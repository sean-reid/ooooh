import type Anthropic from "@anthropic-ai/sdk";
import { anthropicClient, models, textOf, upstreamError } from "../anthropic";
import { HttpError, json, readBody, requireSecret } from "../http";
import { compactState, intervention, interventionKinds, segment, transcriptLines } from "../schema";
import { array, obj, oneOf, optional } from "../validate";

export const wordLimit = 15;

const body = obj({
  kind: oneOf(interventionKinds),
  state: compactState,
  recent: array(segment),
  lastIntervention: optional(intervention),
});
type Input = ReturnType<typeof body>;

const system = `You write the one sentence a quiet thinking companion says to someone thinking aloud. They are not talking to you. They are working something out and you occasionally hand them a question.

Rules, all of them hard:
- One sentence, under ${wordLimit} words.
- A question, or a reflection of the speaker's own words back to them.
- Never advice. Never praise. Never the word "I".
- Plain words the speaker used, not new vocabulary.
- No preamble, no quotes, no markdown. Output the sentence and nothing else.

Kinds:
- clarify: ask which part of the unclear thing they mean.
- deepen: ask what sits under the thing they just said.
- reflect: hand back the phrase they keep returning to.
- decide: ask whether the thing they are weighing is settled.
- summarize: name the two or three threads they have open, as one sentence.
- challenge: ask what would make their claim wrong.`;

export const wordCount = (text: string) => text.trim().split(/\s+/).filter(Boolean).length;

export function truncateToLimit(text: string, limit = wordLimit): string {
  const words = text.trim().split(/\s+/).filter(Boolean);
  const head = words.slice(0, limit);
  for (let i = head.length - 1; i >= 0; i--) {
    if (/[.?!]["')]?$/.test(head[i])) return head.slice(0, i + 1).join(" ");
  }
  return head.join(" ").replace(/[,;:\s]+$/, "") + ".";
}

const userMessage = (input: Input) => {
  const last = input.lastIntervention ?? input.state.lastIntervention;
  const lines = [
    `Kind: ${input.kind}`,
    `Mode: ${input.state.mode}`,
    `Current thread: ${input.state.currentThread || "(none yet)"}`,
    `Open questions: ${input.state.openQuestions.map((q) => q.text).join(" | ") || "none"}`,
    `Main ideas: ${input.state.mainIdeas.map((q) => q.text).join(" | ") || "none"}`,
    `Uncertainties: ${input.state.uncertainties.map((q) => q.text).join(" | ") || "none"}`,
    last ? `Last thing said to them (${last.kind}): ${last.text}` : "Nothing said to them yet.",
    `Recent words:\n${transcriptLines(input.recent)}`,
  ];
  return lines.join("\n");
};

const params = (
  input: Input,
  messages: Anthropic.Beta.BetaMessageParam[],
): Anthropic.Beta.MessageCreateParamsNonStreaming => ({
  model: models.phrase,
  max_tokens: 1024,
  betas: ["server-side-fallback-2026-07-01"],
  fallbacks: "default",
  system,
  output_config: { effort: "low" },
  messages,
});

const refused = (message: Anthropic.Beta.BetaMessage) =>
  new HttpError(502, { error: "anthropic refused", detail: message.stop_details });

async function retryShorter(client: Anthropic, input: Input, first: string): Promise<string> {
  const over = wordCount(first) - wordLimit;
  const response = await client.beta.messages
    .create(
      params(input, [
        { role: "user", content: userMessage(input) },
        { role: "assistant", content: first },
        {
          role: "user",
          content: `That is ${over} ${over === 1 ? "word" : "words"} over the limit of ${wordLimit}. Say it again in under ${wordLimit} words.`,
        },
      ]),
    )
    .catch(upstreamError);
  if (response.stop_reason === "refusal") throw refused(response);
  const text = textOf(response.content).trim();
  return wordCount(text) > wordLimit ? truncateToLimit(text) : text;
}

const finalText = (client: Anthropic, input: Input, first: string) =>
  wordCount(first) > wordLimit ? retryShorter(client, input, first) : Promise.resolve(first);

async function phraseOnce(client: Anthropic, input: Input): Promise<string> {
  const response = await client.beta.messages
    .create(params(input, [{ role: "user", content: userMessage(input) }]))
    .catch(upstreamError);
  if (response.stop_reason === "refusal") throw refused(response);
  return finalText(client, input, textOf(response.content).trim());
}

const sse = (event: string, data: unknown) => `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;

function phraseStream(client: Anthropic, input: Input): Response {
  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const send = (event: string, data: unknown) =>
        controller.enqueue(encoder.encode(sse(event, data)));
      try {
        const upstream = client.beta.messages.stream(
          params(input, [{ role: "user", content: userMessage(input) }]),
        );
        let text = "";
        let forwarding = true;
        for await (const event of upstream) {
          if (event.type !== "content_block_delta" || event.delta.type !== "text_delta") continue;
          text += event.delta.text;
          if (forwarding && wordCount(text) > wordLimit) forwarding = false;
          if (forwarding) send("delta", { text: event.delta.text });
        }
        const message = await upstream.finalMessage();
        if (message.stop_reason === "refusal") throw refused(message);
        send("done", { text: await finalText(client, input, text.trim()) });
      } catch (e) {
        const detail = e instanceof HttpError ? e.body : { error: "stream failed" };
        send("error", detail);
      } finally {
        controller.close();
      }
    },
  });
  return new Response(stream, {
    headers: { "content-type": "text/event-stream", "cache-control": "no-cache" },
  });
}

export async function phrase(request: Request, env: Env): Promise<Response> {
  const input = await readBody(request, body);
  const client = anthropicClient(requireSecret(env.ANTHROPIC_API_KEY, "ANTHROPIC_API_KEY"));
  if (request.headers.get("accept")?.includes("text/event-stream")) {
    return phraseStream(client, input);
  }
  return json({ text: await phraseOnce(client, input) });
}
