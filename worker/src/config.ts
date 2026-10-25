// Mirrors GovernorConfig in Packages/Sources/Governor. Numbers here are what ships.
export const governorConfig = {
  version: 1,
  floor: { min: 30, max: 120 },
  speak: { probability: 0.75, confidence: 0.6 },
  finished: { probability: 0.9, confidence: 0.7 },
  command: { probability: 0.9, confidence: 0.7 },
  densityWindow: 120,
  endSilence: 30,
  checkPause: 2,
  minCheckInterval: 3,
} as const;
