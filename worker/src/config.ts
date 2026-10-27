// Mirrors GovernorConfig in Packages/Sources/Governor. Numbers here are what ships.
export const governorConfig = {
  version: 5,
  floor: { min: 30, max: 120 },
  // Seconds into the session before the first prompt; the finished question and commands are not held.
  warmUp: 45,
  speak: { probability: 0.9, confidence: 0 },
  finished: { probability: 0.6, confidence: 0.7 },
  command: { probability: 0.9, confidence: 0.7 },
  densityWindow: 120,
  endSilence: 30,
  // A pause this long gets the finished question whatever Jev answered at the last check.
  longSilence: 45,
  // Pause lengths in seconds at which the phone asks Jev during silence; after the last, nothing until speech resumes.
  silenceChecks: [5, 11, 20],
  armingDelay: 1.5,
  // Weights from the second recorded Jev run: only the cues that separated labeled checks from unlabeled ones.
  cueWeights: { hangingQuestion: 1.0, trailsOff: 1.38, unnamedDecision: 1.125 },
  cueKinds: { hangingQuestion: "clarify", trailsOff: "deepen", unnamedDecision: "decide" },
} as const;
