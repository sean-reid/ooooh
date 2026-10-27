import { charge } from "../budget";
import { json, readBody, requireSecret } from "../http";
import { askJev, type JevResponse } from "../jev/client";
import { cueQuestions, questionsVersion } from "../jev/questions";
import { compactState, intervention, segment, transcriptLines } from "../schema";
import { array, bool, num, obj, optional } from "../validate";

/// Jev reads the last few utterances verbatim; everything older lives in the compact state.
const recentWindow = 6;

const body = obj({
  state: compactState,
  recentTranscript: array(segment),
  signals: obj({
    pauseLength: num,
    speechDensity: num,
    awaitingFinishedReply: bool,
    secondsSinceStart: num,
    wordsSoFar: num,
    promptsSoFar: num,
    secondsSincePrompt: optional(num),
  }),
  lastIntervention: optional(intervention),
});

type Answers = JevResponse["answers"];

const noul = (a: { noul: number }) => ({ probability: a.noul });

const choice = <T extends string>(a: { choice: T; confidence: number }) => ({
  choice: a.choice,
  confidence: a.confidence,
});

const score = (a: { score: number; confidence: number }) => ({
  score: a.score + 1,
  confidence: a.confidence,
});

const cues = (a: Answers) =>
  Object.fromEntries(
    (Object.keys(cueQuestions) as (keyof typeof cueQuestions)[]).map((name) => [
      name,
      a[name].noul,
    ]),
  );

export async function decide(request: Request, env: Env): Promise<Response> {
  const input = await readBody(request, body);
  const key = requireSecret(env.TYPESAFE_API_KEY, "TYPESAFE_API_KEY");

  const { lastIntervention: stateIntervention, ...state } = input.state;
  const last = input.lastIntervention ?? stateIntervention;
  const jevState = {
    state,
    lastIntervention: last ? { kind: last.kind, text: last.text, at: last.at } : null,
    // Sent as null rather than dropped, so Jev sees that nothing has been asked yet.
    signals: { ...input.signals, secondsSincePrompt: input.signals.secondsSincePrompt ?? null },
    recentTranscript: transcriptLines(input.recentTranscript.slice(-recentWindow)),
    earlierLinesInWindow: Math.max(0, input.recentTranscript.length - recentWindow),
  };

  const res = await askJev(key, jevState);
  await charge(env, "jev", res.usage.input_tokens);
  const a = res.answers;
  const answers = {
    goodMoment: noul(a.goodMoment),
    intervention: choice(a.intervention),
    articulationDifficulty: score(a.articulationDifficulty),
    momentum: score(a.momentum),
    seemsFinished: noul(a.seemsFinished),
    addressesApp: choice(a.addressesApp),
    cues: cues(a),
  };

  return json({ answers, questionsVersion, usage: { jevInputTokens: res.usage.input_tokens } });
}
