import { KINDS } from "../labeler/labels.mjs";
import { kindNames, pauseText, timeSpan } from "./proposal.mjs";

const HEADER = /^## (\d+)\b/;
const FIXTURE = /^fixture:\s*(\S+)\s*$/;
const LABEL = /^label:\s*(\S*)\s*$/i;

const instructions = (reviewFile) =>
  `Each utterance below has its index, its times, and the pause after it. A \`label:\` line under an utterance marks the pause after it as a moment for one short sentence of that kind, a pause to stay out of (leave), or the end of the session (finished).

To accept a label, leave it. To remove one, delete its \`label:\` line. To change its kind, change the word after \`label:\`. To add one, write a \`label:\` line under the utterance. The \`reason:\` lines are the proposer's notes and are dropped on fold.

When done: node tools/label/label.mjs fold ${reviewFile}

Kinds:
${KINDS.map(({ kind, meaning }) => `- ${kind}: ${meaning}`).join("\n")}`;

// The file the owner edits: instructions, then one block per utterance with
// its proposed label and reason inline.
export function renderReview({
  name,
  fixtureFile,
  reviewFile,
  finals,
  labels,
}) {
  const byUtterance = new Map(labels.map((label) => [label.utterance, label]));
  const blocks = finals.map((segment, index) => {
    const lines = [
      `## ${index}  ${timeSpan(segment)}  ${pauseText(finals, index)}`,
      segment.text,
    ];
    const label = byUtterance.get(index);
    if (label) {
      lines.push(`label: ${label.kind}`);
      if (label.reason) lines.push(`reason: ${label.reason}`);
    }
    return lines.join("\n");
  });
  return (
    [
      `# ${name}`,
      `fixture: ${fixtureFile}`,
      instructions(reviewFile),
      ...blocks,
    ].join("\n\n") + "\n"
  );
}

// Reads the edited review back: the fixture file it names and one kind per
// labeled utterance. Errors name the line.
export function parseReview(text) {
  const lines = text.split("\n");
  let fixtureFile = null;
  let current = null;
  const labels = new Map();
  lines.forEach((line, i) => {
    const number = i + 1;
    const header = line.match(HEADER);
    if (header) {
      current = Number(header[1]);
      return;
    }
    const fixture = line.match(FIXTURE);
    if (fixture && current == null) {
      fixtureFile = fixture[1];
      return;
    }
    const label = line.match(LABEL);
    if (!label) return;
    if (current == null)
      throw new Error(`line ${number}: a label before the first utterance`);
    const kind = label[1];
    if (!kindNames.includes(kind))
      throw new Error(
        `line ${number}: unknown kind "${kind}", expected one of ${kindNames.join(", ")}`,
      );
    if (labels.has(current))
      throw new Error(`line ${number}: utterance ${current} has two labels`);
    labels.set(current, kind);
  });
  if (!fixtureFile) throw new Error("the review has no fixture: line");
  return { fixtureFile, labels };
}
