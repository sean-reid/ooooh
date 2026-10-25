// Mirrors GovernorConfig in Packages/Sources/Governor. Numbers here are what ships.
export const governorConfig = {
  version: 4,
  floor: { min: 30, max: 120 },
  speak: { probability: 0.9, confidence: 0 },
  finished: { probability: 0.6, confidence: 0.7 },
  command: { probability: 0.9, confidence: 0.7 },
  densityWindow: 120,
  endSilence: 30,
  checkPause: 2,
  minCheckInterval: 3,
  armingDelay: 1.5,
  // Weights from the second recorded Jev run: only the cues that separated labeled checks from unlabeled ones.
  cueWeights: { hangingQuestion: 1.0, trailsOff: 1.38, unnamedDecision: 1.125 },
  cueKinds: { hangingQuestion: "clarify", trailsOff: "deepen", unnamedDecision: "decide" },
} as const;
