import { describe, expect, it } from "vitest";
import { governorConfig } from "../src/config";
import { cueQuestions, questions, questionsVersion } from "../src/jev/questions";
import { interventionKinds } from "../src/schema";

describe("Jev questions", () => {
  it("is version 3 with the six fixed questions and the five cues", () => {
    expect(questionsVersion).toBe(3);
    const fixed = Object.keys(questions).filter((name) => !(name in cueQuestions));
    expect(fixed.sort()).toEqual([
      "addressesApp",
      "articulationDifficulty",
      "goodMoment",
      "intervention",
      "momentum",
      "seemsFinished",
    ]);
    expect(Object.keys(cueQuestions).sort()).toEqual([
      "contradictsEarlier",
      "hangingQuestion",
      "repeatsPoint",
      "trailsOff",
      "unnamedDecision",
    ]);
  });

  it("gives every yes/no question instructions and both criteria", () => {
    for (const [name, question] of Object.entries(questions)) {
      if (question.type !== "noul") continue;
      expect(question.instructions, name).toMatch(/\?/);
      expect(question.criteria.true, name).toMatch(/\S/);
      expect(question.criteria.false, name).toMatch(/\S/);
    }
  });

  it("names every signal the decide route sends in the goodMoment instructions", () => {
    for (const signal of [
      "secondsSinceStart",
      "wordsSoFar",
      "promptsSoFar",
      "secondsSincePrompt",
    ]) {
      expect(questions.goodMoment.instructions).toContain(signal);
    }
  });

  it("weights only cues Jev is asked, and maps each to a real kind", () => {
    for (const name of Object.keys(governorConfig.cueWeights)) {
      expect(Object.keys(cueQuestions), name).toContain(name);
    }
    expect(Object.keys(governorConfig.cueKinds).sort()).toEqual(
      Object.keys(governorConfig.cueWeights).sort(),
    );
    for (const kind of Object.values(governorConfig.cueKinds)) {
      expect(interventionKinds).toContain(kind);
    }
  });
});
