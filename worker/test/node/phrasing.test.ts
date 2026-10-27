import { describe, expect, it } from "vitest";
import {
  exemplars,
  forbiddenFrames,
  kindGuide,
  phraseRules,
  phraseSystem,
  stockFrame,
  wordCount,
  wordLimit,
} from "../../src/phrasing";
import { interventionKinds } from "../../src/schema";

const sentences = (text: string) =>
  text.split(/[.?!]+(?=\s|$)/).filter((part) => part.trim()).length;

describe("the phrase prompt", () => {
  it("names a guide for every kind and keeps the forbidden frames out of them", () => {
    expect(Object.keys(kindGuide)).toEqual([...interventionKinds]);
    for (const [kind, guide] of Object.entries(kindGuide)) {
      expect(guide, kind).not.toMatch(stockFrame);
      expect(guide, kind).toMatch(/\bnamed?\b|word for word/);
    }
  });

  it("lists each forbidden frame once, in the rule that forbids it", () => {
    for (const frame of forbiddenFrames) {
      expect(frame).toMatch(stockFrame);
      expect(phraseRules.split(`"${frame}"`)).toHaveLength(2);
      expect(phraseRules).toMatch(new RegExp(`Never these frames.*"${frame}"`));
    }
  });

  it("catches the frames in the shapes the model produces and passes a named line", () => {
    for (const line of [
      "How does that sit with you?",
      "How does the Friday deadline sit with you right now?",
      "What makes Friday so important?",
      "What makes the small team important here?",
      "What sits underneath the worry about cost?",
      "What sits under that?",
    ]) {
      expect(line).toMatch(stockFrame);
    }
    for (const line of [
      "Slow as in the build, or slow as in the review queue?",
      "Why does Friday count, and not the Monday after?",
      "Is the cost the money or the time it sits in review?",
      "Earlier the cheaper path was the safe one, now it is the risk?",
    ]) {
      expect(line).not.toMatch(stockFrame);
    }
  });

  it("ships one exemplar per kind, each within 12 words, the hard rules, and the frame rule", () => {
    expect(Object.keys(exemplars)).toEqual([...interventionKinds]);
    expect(phraseRules).toContain(`under ${wordLimit} words, the named thing counted in`);
    for (const [kind, line] of Object.entries(exemplars)) {
      expect(sentences(line), kind).toBe(1);
      expect(wordCount(line), kind).toBeLessThanOrEqual(12);
      expect(line, kind).not.toMatch(/\bI\b/);
      expect(line, kind).not.toMatch(/["*_#`>]/);
      expect(line, kind).not.toMatch(stockFrame);
      expect(phraseSystem).toContain(`- ${kind}: ${line}`);
    }
    expect(phraseSystem).toMatch(/show the standard, not a template/);
    expect(phraseSystem.startsWith(phraseRules)).toBe(true);
  });
});
