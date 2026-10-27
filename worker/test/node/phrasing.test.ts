import { describe, expect, it } from "vitest";
import {
  exemplars,
  forbiddenFrames,
  kindGuide,
  phraseRules,
  phraseSystem,
  phraseUserMessage,
  saidLines,
  saidWindow,
  stockFrame,
  wordCount,
  wordLimit,
  type PhraseInput,
} from "../../src/phrasing";
import { interventionKinds, type Intervention } from "../../src/schema";
import { phraseBody, saidLines as said, segments, state } from "../upstream";

const input = (over: Record<string, unknown> = {}): PhraseInput =>
  ({ ...phraseBody, ...over }) as unknown as PhraseInput;

const line = (kind: Intervention["kind"], text: string, at: number): Intervention => ({
  kind,
  text,
  at,
  takenUp: undefined,
});

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

  it("gives deepen five moves, connect among them, and tells the model to skip the one already said", () => {
    for (const move of [/cost/, /instance/, /first time/, /turned out false/, /connect it/]) {
      expect(kindGuide.deepen).toMatch(move);
    }
    expect(kindGuide.deepen).toMatch(/not one already used in the lines said/);
    expect(kindGuide.deepen).not.toMatch(/\breason\b|\bwhy\b|\bmatter/);
    for (const kind of ["clarify", "challenge"] as const) {
      expect(kindGuide[kind], kind).toMatch(/, then ask .*, or /);
    }
    for (const kind of ["deepen", "challenge"] as const) {
      expect(kindGuide[kind], kind).toMatch(/open question, main idea, or uncertainty/);
    }
    expect(phraseRules).toMatch(
      /names one thing the speaker said in their last two utterances.*a connect line names that thing and one open question, main idea, or uncertainty/,
    );
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
      "Why does Friday matter?",
      "Why does it matter that the build is slow?",
      "Why would the small team matter more than the big one?",
      "What makes the small team matter here?",
      "Why is the Friday deadline important?",
      "Why does Friday count, and not the Monday after?",
      "Why Friday counts more than the Monday after?",
      "Does the retry queue matter more than the sync layer?",
      "Friday slips, so what?",
      "So what if the build takes an hour?",
    ]) {
      expect(line).toMatch(stockFrame);
    }
    for (const line of [
      "Slow as in the build, or slow as in the review queue?",
      "Is the cost the money or the time it sits in review?",
      "Earlier the cheaper path was the safe one, now it is the risk?",
      "Why Friday, and not the Monday after?",
      "Why does the build take an hour on Fridays?",
      "Why did the small team come up again?",
      "Is it a matter of money or of time?",
      "The last time Friday slipped, what happened?",
      "When did the retry queue first come up?",
      "What would change if Friday were not fixed?",
      "What does Friday cost that the Monday after would not?",
    ]) {
      expect(line).not.toMatch(stockFrame);
    }
  });

  it("ships exemplars per kind, two for deepen and challenge, each within 12 words, the hard rules, and the frame rule", () => {
    expect(Object.keys(exemplars)).toEqual([...interventionKinds]);
    expect(phraseRules).toContain(`under ${wordLimit} words, the named thing counted in`);
    for (const [kind, lines] of Object.entries(exemplars)) {
      expect(lines.length, kind).toBe(kind === "deepen" || kind === "challenge" ? 2 : 1);
      for (const line of lines) {
        expect(sentences(line), kind).toBe(1);
        expect(wordCount(line), kind).toBeLessThanOrEqual(12);
        expect(line, kind).not.toMatch(/\bI\b/);
        expect(line, kind).not.toMatch(/["*_#`>]/);
        expect(line, kind).not.toMatch(stockFrame);
        expect(phraseSystem).toContain(`- ${kind}: ${line}`);
      }
    }
    for (const line of exemplars.deepen) expect(line).not.toMatch(/\bwhy\b/i);
    expect(exemplars.deepen[0].split(" ")[0]).not.toBe(exemplars.deepen[1].split(" ")[0]);
    expect(exemplars.challenge[1]).toMatch(/\bopen\b.*\bFriday\b/);
    expect(phraseSystem).toMatch(/one per kind and two for deepen and challenge/);
    expect(phraseSystem).toMatch(/show the standard, not a template/);
    expect(phraseSystem.startsWith(phraseRules)).toBe(true);
  });

  it("renders the last three lines said, oldest first, under the instruction not to echo them", () => {
    const four = [
      ...said,
      line("reflect", "Back and forth, twice now.", 110),
      line("decide", "The queue or the sync layer, which is it?", 125),
    ];
    expect(saidWindow).toBe(3);
    expect(saidLines(input({ said: four }))).toEqual(four.slice(1));
    const message = phraseUserMessage(input({ said: four }));
    expect(message).toContain(
      "Said to them this session, oldest first. Do not open with the same words or reuse the shape of any of them:\n" +
        "- (deepen) Why does the retry queue matter more than the sync layer?\n" +
        "- (reflect) Back and forth, twice now.\n" +
        "- (decide) The queue or the sync layer, which is it?\n",
    );
    expect(message).not.toContain(four[0].text);
    expect(message.indexOf("Said to them")).toBeLessThan(message.indexOf("Recent words"));
  });

  it("falls back to the one line it has when a phone sends no said list", () => {
    const last = line("clarify", "Which part feels least clear?", 60);
    expect(saidLines(input({ said: [], lastIntervention: last }))).toEqual([last]);
    const inState = { ...state, lastIntervention: last };
    expect(saidLines(input({ said: undefined, state: inState }))).toEqual([last]);
    const bare = input({ said: [], lastIntervention: undefined, state });
    expect(saidLines(bare)).toEqual([]);
    expect(phraseUserMessage(bare)).toContain("Nothing said to them yet.\nRecent words");
    expect(phraseUserMessage(bare).split("\n").at(-1)).toBe(
      `[${segments[1].start}s] ${segments[1].text}`,
    );
  });
});
