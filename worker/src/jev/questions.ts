import { interventionKinds } from "../schema";

export const questionsVersion = 1;

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

export const questions = {
  goodMoment: {
    type: "noul",
    instructions:
      "Is this a good moment for the app to say one short sentence to the speaker? Judge from the pause, the shape of the recent transcript, and the time since the last intervention.",
    criteria: {
      true: "The speaker has reached a natural break and a short question would be welcome now.",
      false:
        "The speaker is mid-thought, flowing, or just heard an intervention and should be left alone.",
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
} as const;

export type QuestionName = keyof typeof questions;
