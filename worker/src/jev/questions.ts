export const questionsVersion = 3;

export const jevModel = "jev-latest";

type Noul = { type: "noul"; instructions?: string; criteria?: { true: string; false: string } };
type Choice = { type: "choice"; criteria: Record<string, string> };
type Score = { type: "score"; criteria: string[] };

/// Atomic cues about the last few utterances, one per intervention kind. Each is one
/// yes/no judgment; the governor weights them from the remote config and asks the kind
/// of the strongest.
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
  trailsOff: {
    type: "noul",
    instructions:
      "Does the most recent line end unfinished: a sentence that stops partway, a 'so maybe', an 'I don't know', or a fragment?",
    criteria: {
      true: "The last line is incomplete or ends in uncertainty.",
      false: "The last line is a complete thought.",
    },
  } satisfies Noul,
  realisation: {
    type: "noul",
    instructions:
      "In the last line or two, did the speaker mark a landing themselves: turning against what they had just said ('I keep saying that', 'okay, maybe a little'), or naming the thing under the circling ('that is the actual thing', 'so it feels like confessing')?",
    criteria: {
      true: "The speaker has just contradicted or corrected their own earlier line, or named in plain words the feeling or reason the earlier lines circled, and has not moved on from it.",
      false:
        "A diagnosis, fix, plan, or conclusion about the work; a feeling mentioned in passing while reasoning; or the speaker already carrying on past it.",
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
  threadShift: {
    type: "noul",
    instructions:
      "In the last line or two, did the speaker either switch to a different open thread ('hang on', 'back to', 'where was I', 'the other thing') or land a result they had just reworked over several lines (a new total, a new order)?",
    criteria: {
      true: "The last line or two jumps to another thread, or states a reworked total or order whose parts sit across the earlier lines.",
      false:
        "The speaker is still inside the rework, or is laying one thing out in order for the first time.",
    },
  } satisfies Noul,
  untestedClaim: {
    type: "noul",
    instructions:
      "In the recent lines, did the speaker state a conclusion, or what someone else thinks or wants, as settled, without a reason beyond their own say-so?",
    criteria: {
      true: "A recent line asserts how something works or what another person thinks as a fact, with no evidence given in these lines or the state.",
      false:
        "Claims are hedged, backed by something said earlier, or the speaker is still weighing them.",
    },
  } satisfies Noul,
} as const;

export type CueName = keyof typeof cueQuestions;

export const questions = {
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
