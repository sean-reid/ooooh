import {
  anthropicClient,
  credential,
  models,
  refused,
  textOf,
  upstreamError,
  within,
} from "../anthropic";
import { chargeModel } from "../budget";
import { HttpError, json, readBody } from "../http";
import { compactState, segment, type Segment } from "../schema";
import { array, num, obj, optional, str, ValidationError } from "../validate";

const body = obj({ state: compactState, transcript: array(segment) });

export const sectionNames = [
  "ideas",
  "decisions",
  "questions",
  "insights",
  "actions",
  "openThreads",
  "quotes",
] as const;

const span = obj({ start: num, end: num });
const item = obj({ id: str, text: str, span: optional(span) });
type Item = ReturnType<typeof item>;

const notes = obj({
  title: str,
  summary: optional(str),
  ideas: array(item),
  decisions: array(item),
  questions: array(item),
  insights: array(item),
  actions: array(item),
  openThreads: array(item),
  quotes: array(item),
});
export type Notes = ReturnType<typeof notes>;

const itemSchema = {
  type: "object",
  properties: {
    id: { type: "string" },
    text: { type: "string" },
    span: {
      anyOf: [
        {
          type: "object",
          properties: { start: { type: "number" }, end: { type: "number" } },
          required: ["start", "end"],
          additionalProperties: false,
        },
        { type: "null" },
      ],
    },
  },
  required: ["id", "text", "span"],
  additionalProperties: false,
};

export const notesSchema = {
  type: "object",
  properties: {
    title: { type: "string" },
    summary: { anyOf: [{ type: "string" }, { type: "null" }] },
    ...Object.fromEntries(sectionNames.map((name) => [name, { type: "array", items: itemSchema }])),
  },
  required: ["title", "summary", ...sectionNames],
  additionalProperties: false,
};

const system = `You turn one session of someone thinking aloud into their notes. You read the compact state the session kept and the full transcript, and you return the notes as JSON.

The notes have a title, an optional summary, and seven sections: ideas, decisions, questions, insights, actions, openThreads, quotes. Every item is one sentence in the speaker's own words where possible, with a short lowercase slug id of 2 to 4 words joined by hyphens, unique across all sections, and a span giving the start and end time in seconds of the transcript lines it came from. Use the times printed on the lines. Use null for a span only when no lines support the item.

Rules:
- Title: a few plain words naming what the session was about, not a slogan.
- ideas: things the speaker proposed or considered. decisions: things they settled. questions: things they asked and left open. insights: things they noticed or realised. actions: things they said they would do. openThreads: threads they started and left unresolved. quotes: lines worth keeping, verbatim from the transcript.
- No praise, no advice, no interpretation the transcript does not support. Leave a section empty rather than pad it.
- A short session, under about three minutes or a dozen lines, gets a summary of one paragraph plus openThreads, and the other sections stay empty. A longer session gets the sections and a summary only when the sections alone would not carry it; otherwise summary is null.`;

const transcriptLines = (segments: Segment[]) =>
  segments.map((s, i) => `${i + 1}. [${s.start.toFixed(0)}s to ${s.end.toFixed(0)}s] ${s.text}`);

const slug = /^[a-z0-9]+(-[a-z0-9]+)*$/;

// Keeps a span that overlaps the transcript, trimmed to its bounds; drops one that does not.
const fitSpan = (
  s: Item["span"],
  bounds: { start: number; end: number } | undefined,
): Item["span"] => {
  if (!s || !bounds || s.start > s.end || s.end < bounds.start || s.start > bounds.end) {
    return undefined;
  }
  return { start: Math.max(s.start, bounds.start), end: Math.min(s.end, bounds.end) };
};

export const checkNotes = (n: Notes, transcript: Segment[]): Notes => {
  const bounds = transcript.length
    ? {
        start: Math.min(...transcript.map((s) => s.start)),
        end: Math.max(...transcript.map((s) => s.end)),
      }
    : undefined;
  if (!n.title.trim()) throw new ValidationError("title", "text");
  const seen = new Set<string>();
  const out = { ...n, summary: n.summary?.trim() || undefined };
  for (const name of sectionNames) {
    out[name] = n[name].map((entry) => {
      const field = `${name}.${entry.id}`;
      if (!slug.test(entry.id)) throw new ValidationError(field, "slug id");
      if (seen.has(entry.id)) throw new ValidationError(field, "unique id");
      seen.add(entry.id);
      if (!entry.text.trim()) throw new ValidationError(field, "text");
      return { ...entry, span: fitSpan(entry.span, bounds) };
    });
  }
  return out;
};

/** Thinking counts against this too, so a long session can run out before the JSON closes. */
const notesMaxTokens = 16_000;
/** Opus thinks through the whole session before the JSON starts, and the notes screen waits for it. */
const notesDeadlineMs = 180_000;

export async function notesRoute(request: Request, env: Env): Promise<Response> {
  const input = await readBody(request, body);
  const cred = credential(env);
  const client = anthropicClient(cred, { timeout: notesDeadlineMs });

  const user = [
    `Compact state at the end of the session:\n${JSON.stringify(input.state, null, 1)}`,
    `Transcript, one line per utterance with its times:\n${transcriptLines(input.transcript).join("\n")}`,
  ].join("\n\n");

  const response = await within(notesDeadlineMs, (signal) =>
    client.beta.messages.create(
      {
        model: models.notes,
        max_tokens: notesMaxTokens,
        betas: ["server-side-fallback-2026-07-01", ...cred.betas],
        fallbacks: "default",
        thinking: { type: "adaptive" },
        system,
        messages: [{ role: "user", content: user }],
        output_config: { effort: "high", format: { type: "json_schema", schema: notesSchema } },
      },
      { signal },
    ),
  ).catch(upstreamError);
  await chargeModel(env, response.model, response.usage);

  if (response.stop_reason === "max_tokens") {
    throw new HttpError(502, { error: "anthropic truncated", maxTokens: notesMaxTokens });
  }
  if (response.stop_reason === "refusal") throw refused(response);
  let parsed: unknown;
  try {
    parsed = JSON.parse(textOf(response.content));
  } catch {
    throw new HttpError(502, { error: "bad notes", field: "", expected: "json" });
  }
  let result: Notes;
  try {
    result = checkNotes(notes(parsed, ""), input.transcript);
  } catch (e) {
    if (e instanceof ValidationError) {
      throw new HttpError(502, { error: "bad notes", field: e.field, expected: e.expected });
    }
    throw e;
  }

  return json({
    notes: result,
    usage: {
      inputTokens: response.usage.input_tokens,
      outputTokens: response.usage.output_tokens,
    },
  });
}
