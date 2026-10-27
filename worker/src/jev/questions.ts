import { interventionKinds } from "../schema";

export const questionsVersion = 3;

export const jevModel = "jev-latest";

type Noul = { type: "noul"; instructions?: string; criteria?: { true: string; false: string } };
type Choice = { type: "choice"; criteria: Record<string, string> };
type Score = { type: "score"; criteria: string[] };

export const interventionDescriptions: Record<(typeof interventionKinds)[number], string> = {
  clarify:
    "The speaker is vague or tangled on one point and a question would help them pin it down.",
  deepen:
    "The speaker has stated something worth going further into and a question would open it up.",
  reflect:
    "The speaker has said something notable and hearing it back in their own words would help.",
  decide: "The speaker is weighing options and is close to a decision a question could land.",
  summarize: "The speaker has covered a lot and a short recap of their own threads would help.",
  challenge: "The speaker has made a claim or assumption that deserves a gentle test.",
};

/// Atomic cues about the last few utterances. Each is one yes/no judgment; the
/// governor combines them with weights from the remote config.
export const cueQuestions = {
  hangingQuestion: {
    type: "noul",
    instructions:
      "In the recent lines, did the speaker ask themselves a question and then stop or move on without answering it?",
    criteria: {
      true: "A question to themselves is left open at or near the end of the recent lines.",
      false: "No self-question, or they answered it and kept going.",
    },
  } satisfies Noul,
  repeatsPoint: {
    type: "noul",
    instructions:
      "In the recent lines, is the speaker saying again, in different words, a point they already made earlier in these lines or in the state?",
    criteria: {
      true: "The same point appears at least twice without a new angle on it.",
      false: "Each point is new, or a repeat adds a new angle.",
    },
  } satisfies Noul,
  trailsOff: {
    type: "noul",
    instructions:
      "Does the most recent line give out rather than pause: the speaker loses the thread, runs out of words, or gives up on the sentence with a 'so maybe', an 'I don't know', or a shrug? A clause break is not a trail-off. The transcriber cuts a line after one second of silence, so a line that stops at 'and', 'but', 'so', 'because', or 'which' while the sentence is still going is a breath, and the next line will finish it. A short opening line that only names the topic is not a trail-off either.",
    criteria: {
      true: "The thought is abandoned or dissolves into uncertainty, and nothing in the line points to how it would continue.",
      false:
        "The line is a complete thought, or it stops at a clause boundary with the sentence still in motion, or it is a short opening line that sets up what follows.",
    },
  } satisfies Noul,
  contradictsEarlier: {
    type: "noul",
    instructions:
      "Does something in the recent lines contradict a claim the speaker made earlier in these lines or in the state's ideas or decisions?",
    criteria: {
      true: "A recent claim and an earlier one cannot both hold.",
      false: "No contradiction, or the speaker noticed and resolved it.",
    },
  } satisfies Noul,
  unnamedDecision: {
    type: "noul",
    instructions:
      "In the recent lines, did the speaker land on a choice between options they were weighing, without calling it a decision?",
    criteria: {
      true: "They stated which option they are going with, in passing.",
      false: "They are still weighing, or they explicitly marked the decision.",
    },
  } satisfies Noul,
} as const;

export type CueName = keyof typeof cueQuestions;

export const questions = {
  goodMoment: {
    type: "noul",
    instructions:
      "Is this a good moment for the app to say one short sentence to the speaker? Judge from the recent lines, the pause, and the signals: secondsSinceStart, wordsSoFar, promptsSoFar, and secondsSincePrompt. Answer no when the speaker is mid-thought, between two clauses of one sentence, partway through a list or a sequence of steps, in the first sentences of the session before they have laid out what they are thinking about, or has just answered their own question and is carrying on. Answer yes only when the speaker has closed a thought, not just a sentence, and a question from outside would land rather than interrupt.",
    criteria: {
      true: "The speaker has finished a thought and paused on it. The session is past its opening, the last prompt is well behind, and a short question would be welcome now.",
      false:
        "The speaker is mid-thought; or taking a breath between clauses; or working through a list that is not done; or in the first sentences of the session; or has just answered their own question; or just heard a prompt and should be left alone.",
    },
  } satisfies Noul,
  intervention: {
    type: "choice",
    criteria: interventionDescriptions,
  } satisfies Choice,
  articulationDifficulty: {
    type: "score",
    criteria: [
      "Fluent: ideas arrive in full sentences with little repair.",
      "Mostly fluent: an occasional restart or search for a word.",
      "Mixed: frequent restarts, fillers, or half-finished sentences.",
      "Laboured: the speaker circles a point several times without landing it.",
      "Struggling: fragments, long pauses, or stated frustration at not finding the words.",
    ],
  } satisfies Score,
  momentum: {
    type: "score",
    criteria: [
      "Stalled: no new content, repetition, or silence.",
      "Slowing: new content is sparse and the speaker is winding down a thread.",
      "Steady: the speaker is moving through a thread at an even pace.",
      "Gaining: new ideas or connections are arriving and building on each other.",
      "Building: the speaker is clearly energised and the thread is developing fast.",
    ],
  } satisfies Score,
  seemsFinished: {
    type: "noul",
    instructions:
      "Does the speaker seem finished with the whole session, not just the current thread?",
    criteria: {
      true: "The speaker has wrapped up, summarised, or signalled they are done thinking for now.",
      false: "The speaker is still working, between threads, or pausing to think.",
    },
  } satisfies Noul,
  addressesApp: {
    type: "choice",
    criteria: {
      none: "The speaker is thinking aloud and not talking to the app.",
      recall: "The speaker asks the app to repeat or remind them of something said earlier.",
      wrapUp: "The speaker tells the app to finish, stop, or produce the notes.",
    },
  } satisfies Choice,
  ...cueQuestions,
} as const;

export type QuestionName = keyof typeof questions;
