import { HttpError, sleep } from "../http";
import { jevModel, questions, type QuestionName } from "./questions";

export const jevEndpoint = "https://api.typesafe.ai/v1/systemone";

const retryDelaysMs = [250, 500];

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

const retryAfterSeconds = (res: Response, attempt: number) => {
  const header = Number(res.headers.get("retry-after"));
  if (Number.isFinite(header) && header > 0) return Math.min(header, 60);
  return Math.ceil((retryDelaysMs[attempt] ?? 1000) / 1000);
};

export async function askJev(apiKey: string, state: unknown): Promise<JevResponse> {
  const body = JSON.stringify({ model: jevModel, state, questions });
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(jevEndpoint, {
      method: "POST",
      headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
      body,
    });
    if (res.ok) return (await res.json()) as JevResponse;
    if (res.status === 429 || res.status === 529) {
      if (attempt < retryDelaysMs.length) {
        await sleep(retryDelaysMs[attempt]);
        continue;
      }
      throw new HttpError(503, {
        error: "jev unavailable",
        retryAfter: retryAfterSeconds(res, attempt),
      });
    }
    const detail = await res.text();
    throw new HttpError(502, { error: "jev", status: res.status, detail: detail.slice(0, 500) });
  }
}
