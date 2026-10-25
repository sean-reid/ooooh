import { HttpError, maxRetryWaitMs, retryAfterFrom, sleep } from "../http";
import { jevModel, questions, type QuestionName } from "./questions";

export const jevEndpoint = "https://api.typesafe.ai/v1/systemone";

const retryDelaysMs = [250, 500];
/** A decision past this is useless to the phone, which has already moved on. */
export const jevTimeoutMs = 5000;

type NoulAnswer = { type: "noul"; noul: number };
type ChoiceAnswer = {
  type: "choice";
  choice: string;
  confidence: number;
  probabilities: Record<string, number>;
};
type ScoreAnswer = {
  type: "score";
  score: number;
  confidence: number;
  probabilities: number[];
  legend: string[];
};
export type JevAnswer = NoulAnswer | ChoiceAnswer | ScoreAnswer;

export type JevResponse = {
  answers: Record<QuestionName, JevAnswer>;
  usage: { input_tokens: number };
};

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
    if (res.ok) return (await res.json()) as JevResponse;
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
