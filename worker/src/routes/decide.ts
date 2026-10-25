import { charge } from "../budget";
import { json, readBody, requireSecret, HttpError } from "../http";
import { askJev, type JevAnswer } from "../jev/client";
import { questions, questionsVersion, type QuestionName } from "../jev/questions";
import { compactState, intervention, segment, transcriptLines } from "../schema";
import { array, bool, num, obj, optional } from "../validate";

const body = obj({
  state: compactState,
  recentTranscript: array(segment),
  signals: obj({ pauseLength: num, speechDensity: num, awaitingFinishedReply: bool }),
  lastIntervention: optional(intervention),
});

type Of<T extends JevAnswer["type"]> = Extract<JevAnswer, { type: T }>;

const expect = <T extends JevAnswer["type"]>(
  name: QuestionName,
  a: JevAnswer | undefined,
  type: T,
) => {
  if (!a || a.type !== type) {
    throw new HttpError(502, { error: "jev answer shape", question: name, expected: type });
  }
  return a as Of<T>;
};

const noul = (name: QuestionName, a?: JevAnswer) => ({
  probability: expect(name, a, "noul").noul,
});

const choice = (name: QuestionName, a?: JevAnswer) => {
  const { choice, confidence } = expect(name, a, "choice");
  return { choice, confidence };
};

const score = (name: QuestionName, a?: JevAnswer) => {
  const { score, confidence } = expect(name, a, "score");
  return { score: score + 1, confidence };
};

export async function decide(request: Request, env: Env): Promise<Response> {
  const input = await readBody(request, body);
  const key = requireSecret(env.TYPESAFE_API_KEY, "TYPESAFE_API_KEY");

  const { lastIntervention: stateIntervention, ...state } = input.state;
  const last = input.lastIntervention ?? stateIntervention;
  const jevState = {
    state,
    lastIntervention: last ? { kind: last.kind, text: last.text, at: last.at } : null,
    signals: input.signals,
    recentTranscript: transcriptLines(input.recentTranscript),
  };

  const res = await askJev(key, jevState);
  await charge(env, "jev", res.usage?.input_tokens ?? 0);
  const a = res.answers;
  const answers = {
    goodMoment: noul("goodMoment", a.goodMoment),
    intervention: choice("intervention", a.intervention),
    articulationDifficulty: score("articulationDifficulty", a.articulationDifficulty),
    momentum: score("momentum", a.momentum),
    seemsFinished: noul("seemsFinished", a.seemsFinished),
    addressesApp: choice("addressesApp", a.addressesApp),
  } satisfies Record<keyof typeof questions, unknown>;

  return json({
    answers,
    questionsVersion,
    usage: { jevInputTokens: res.usage?.input_tokens ?? 0 },
  });
}
