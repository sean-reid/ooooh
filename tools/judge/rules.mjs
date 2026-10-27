import { stockFrame, wordCount, wordLimit } from "../../worker/src/phrasing.ts";

const sentenceCount = (text) =>
  text.split(/[.?!]+(?=\s|$)/).filter((part) => part.trim()).length;

/** The prompt's hard rules, checked in code. `underLimit` is the route's own test: it retries past `wordLimit`. */
export const hardRules = (text) => {
  const line = text.trim();
  const checks = {
    oneSentence: sentenceCount(line) === 1,
    underLimit: line.length > 0 && wordCount(line) <= wordLimit,
    noI: !/\bI\b/.test(line),
    plain: !/["*_#`>]|\p{Pi}|\p{Pf}/u.test(line) && !/^[-•]/.test(line),
    noStockFrame: !stockFrame.test(line),
  };
  return { ...checks, pass: Object.values(checks).every(Boolean) };
};

export const ruleNames = [
  "oneSentence",
  "underLimit",
  "noI",
  "plain",
  "noStockFrame",
];
