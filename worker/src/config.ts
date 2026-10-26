import type { CueName } from "./jev/questions";
import type { InterventionKind } from "./schema";

// Mirrors GovernorConfig in Packages/Sources/Governor. Numbers here are what ships.
export const governorConfig = {
  version: 6,
  floor: { min: 30, max: 120 },
  speak: { probability: 0.9, confidence: 0 },
  finished: { probability: 0.6, confidence: 0.7 },
  command: { probability: 0.9, confidence: 0.7 },
  densityWindow: 120,
  endSilence: 30,
  // Pause lengths in seconds at which the phone asks Jev during silence; after the last, nothing until speech resumes.
  silenceChecks: [5, 11, 20],
  armingDelay: 1.5,
  // The three weights from the second recorded Jev run; untestedClaim's from the questionsVersion 3 run.
  cueWeights: {
    hangingQuestion: 1.0,
    trailsOff: 1.38,
    unnamedDecision: 1.125,
    realisation: 1.0,
    threadShift: 1.0,
    untestedClaim: 1.125,
  } satisfies Record<CueName, number>,
  cueKinds: {
    hangingQuestion: "clarify",
    trailsOff: "deepen",
    unnamedDecision: "decide",
    realisation: "reflect",
    threadShift: "summarize",
    untestedClaim: "challenge",
  } satisfies Record<CueName, InterventionKind>,
} as const;
