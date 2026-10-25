import { HttpError, maxRetryWaitMs, retryAfterFrom, sleep } from "../http";
import { array, num, obj, oneOf, str, ValidationError, type Validator } from "../validate";
import { jevModel, questions, type QuestionName } from "./questions";

export const jevEndpoint = "https://api.typesafe.ai/v1/systemone";

const retryDelaysMs = [250, 500];
/** A decision past this is useless to the phone, which has already moved on. */
export const jevTimeoutMs = 5000;

const noulAnswer = obj({ type: oneOf(["noul"]), noul: num });
const choiceAnswer = <const T extends readonly string[]>(options: T) =>
  obj({ type: oneOf(["choice"]), choice: oneOf(options), confidence: num });
const scoreAnswer = obj({
  type: oneOf(["score"]),
  score: num,
  confidence: num,
  legend: array(str),
});

type Question = (typeof questions)[QuestionName];
type AnswerOf<Q> = Q extends { type: "noul" }
  ? ReturnType<typeof noulAnswer>
  : Q extends { type: "choice"; criteria: infer C }
    ? { type: "choice"; choice: keyof C & string; confidence: number }
    : Q extends { type: "score" }
      ? ReturnType<typeof scoreAnswer>
      : never;

const answerFor = (question: Question): Validator<unknown> => {
  switch (question.type) {
    case "noul":
      return noulAnswer;
    case "choice":
      return choiceAnswer(Object.keys(question.criteria));
    case "score":
      return scoreAnswer;
  }
};

const answers = Object.fromEntries(
  (Object.keys(questions) as QuestionName[]).map((name) => [name, answerFor(questions[name])]),
) as { [K in QuestionName]: Validator<AnswerOf<(typeof questions)[K]>> };

export const jevResponse = obj({ answers: obj(answers), usage: obj({ input_tokens: num }) });
export type JevResponse = ReturnType<typeof jevResponse>;

/** The reply the phone can decode, or a 502 naming the question and field that it cannot. */
export function readJevReply(text: string): JevResponse {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new HttpError(502, { error: "jev", status: 200, detail: "not json" });
  }
  try {
    return jevResponse(parsed, "");
  } catch (e) {
    if (!(e instanceof ValidationError)) throw e;
    const [root, question] = e.field.split(".");
    throw new HttpError(502, {
      error: "jev answer shape",
      question: root === "answers" ? question : undefined,
      field: e.field,
      expected: e.expected,
    });
  }
}

export async function askJev(apiKey: string, state: unknown): Promise<JevResponse> {
  const body = JSON.stringify({ model: jevModel, state, questions });
  for (let attempt = 0; ; attempt++) {
    let res: Response;
    try {
      res = await fetch(jevEndpoint, {
        method: "POST",
        headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
        body,
        signal: AbortSignal.timeout(jevTimeoutMs),
      });
    } catch (e) {
      if (e instanceof DOMException && e.name === "TimeoutError") {
        throw new HttpError(503, { error: "jev unavailable", retryAfter: 1 });
      }
      throw e;
    }
    if (res.ok) return readJevReply(await res.text());
    if (res.status === 429 || res.status === 529) {
      const header = res.headers.get("retry-after");
      const defaultWaitMs = retryDelaysMs[attempt] ?? 1000;
      const waitMs = header ? retryAfterFrom(header) * 1000 : defaultWaitMs;
      if (attempt < retryDelaysMs.length && waitMs <= maxRetryWaitMs) {
        await sleep(waitMs);
        continue;
      }
      throw new HttpError(503, {
        error: "jev unavailable",
        retryAfter: retryAfterFrom(header, Math.ceil(defaultWaitMs / 1000)),
      });
    }
    const detail = await res.text();
    throw new HttpError(502, { error: "jev", status: res.status, detail: detail.slice(0, 500) });
  }
}
