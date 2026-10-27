import {
  anthropicClient,
  credential,
  models,
  structured,
  upstreamError,
  within,
} from "../anthropic";
import { json, readBody } from "../http";
import { transcriptLines } from "../phrasing";
import { compactState, existingIds, listNames, modes, segment } from "../schema";
import { array, obj, oneOf, optional, str, ValidationError } from "../validate";

const body = obj({ state: compactState, transcript: array(segment) });

const patch = obj({
  currentThread: optional(str),
  mode: optional(oneOf(modes)),
  recentTopics: optional(array(str)),
  add: array(obj({ list: oneOf(listNames), id: str, text: str })),
  resolve: array(str),
  remove: array(str),
});
export type StatePatch = ReturnType<typeof patch>;

export const patchSchema = {
  type: "object",
  properties: {
    currentThread: { type: ["string", "null"] },
    mode: { anyOf: [{ type: "string", enum: [...modes] }, { type: "null" }] },
    recentTopics: { type: ["array", "null"], items: { type: "string" } },
    add: {
      type: "array",
      items: {
        type: "object",
        properties: {
          list: { type: "string", enum: [...listNames] },
          id: { type: "string" },
          text: { type: "string" },
        },
        required: ["list", "id", "text"],
        additionalProperties: false,
      },
    },
    resolve: { type: "array", items: { type: "string" } },
    remove: { type: "array", items: { type: "string" } },
  },
  required: ["currentThread", "mode", "recentTopics", "add", "resolve", "remove"],
  additionalProperties: false,
};

const system = `You maintain a compact state for someone thinking aloud. You read the current state and the transcript since the last update, and you return a patch.

The state has four lists: mainIdeas, openQuestions, uncertainties, decisions. Each item has a short id and one sentence of text in the speaker's own terms.

Rules for the patch:
- add: new items only. Invent a short lowercase slug id of 2 to 4 words joined by hyphens. Never reuse an id from the existing list.
- resolve: ids of existing items the speaker has settled. remove: ids that turned out to be noise.
- currentThread: one or two sentences on what the speaker is working on right now, or null to keep it.
- mode: exploring, converging, stuck, or finishing, or null to keep it.
- recentTopics: up to six short topic labels, newest last, or null to keep it.
- Keep lists short. Prefer resolving or merging over adding. Leave out anything the transcript does not support.`;

const checkIds = (p: StatePatch, existing: string[]) => {
  const taken = new Set(existing);
  for (const addition of p.add) {
    if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(addition.id)) {
      throw new ValidationError(`add.${addition.id}`, "slug id");
    }
    if (taken.has(addition.id)) throw new ValidationError(`add.${addition.id}`, "unused id");
    taken.add(addition.id);
    if (!addition.text.trim()) throw new ValidationError(`add.${addition.id}`, "text");
  }
  for (const id of [...p.resolve, ...p.remove]) {
    if (!existing.includes(id)) throw new ValidationError(id, "existing id");
  }
};

const compactMaxTokens = 4096;

/** Haiku patches a few minutes of transcript in seconds; the call runs between turns, so 30 s is the cap. */
export const compactDeadlineMs = 30_000;

export const compactWith =
  (deadlineMs: number) =>
  async (request: Request, env: Env): Promise<Response> => {
    const input = await readBody(request, body);
    const client = anthropicClient(credential(env));
    const ids = existingIds(input.state);

    const user = [
      `Existing ids (never reuse): ${ids.length ? ids.join(", ") : "none"}`,
      `Current state:\n${JSON.stringify(input.state, null, 1)}`,
      `Transcript since the last update:\n${transcriptLines(input.transcript)}`,
    ].join("\n\n");

    const response = await within(deadlineMs, (signal) =>
      client.messages.create(
        {
          model: models.compact,
          max_tokens: compactMaxTokens,
          system,
          messages: [{ role: "user", content: user }],
          output_config: { effort: "low", format: { type: "json_schema", schema: patchSchema } },
        },
        { signal },
      ),
    ).catch(upstreamError);
    const { value, usage } = await structured(env, response, compactMaxTokens, "bad patch", (p) => {
      const result = patch(p, "");
      checkIds(result, ids);
      return result;
    });
    return json({ patch: value, usage });
  };

export const compact = compactWith(compactDeadlineMs);
