# Phrase judge

Measures the one sentence the app says. The corpus is every labeled intervention moment in `fixtures/synthetic/estimate`, 17 of them across six kinds, or in any directory of phone recordings and labels given with `--fixtures`. Each moment becomes the input the phone would have sent `/v1/phrase`: the kind, the transcript up to that moment, the lines produced earlier in the same session as `said`, and an empty compact state, since the fixtures carry no state. The prompt, the word limit, and the model name are imported from `worker/src/phrasing.ts` and `worker/src/models.ts`, so the `shipping` variant is what the route sends today, and `--ref <commit>` runs the prompt from an older commit over the same moments with the window that commit's phone sent.

Install once with `npm ci` in this directory; the model calls read `ANTHROPIC_API_KEY` from the environment through the SDK. Then, from the repo root:

```
node tools/judge/corpus.mjs                 # data/corpus.jsonl, one moment per line
node tools/judge/phrase.mjs shipping        # data/lines.shipping.jsonl: text, latency, tokens
node tools/judge/phrase.mjs shipping --ref origin/main --name old   # the prompt as it was
node tools/judge/phrase.mjs opus            # claude-opus-5-5 with adaptive thinking
node tools/judge/score.mjs shipping         # data/scores.shipping.jsonl from the judge
node tools/judge/report.mjs                 # the table over every variant under data/
node tools/judge/frames.mjs                 # stock frames and named words per variant
```

`--dir` on `phrase.mjs`, `score.mjs`, `report.mjs`, and `frames.mjs` reads and writes somewhere other than `data/`.

`phrase.mjs` records the first sentence the model returns; the route's shorter-retry and truncation are left out so the hard-rule rate shows what the model does on its own. `score.mjs` sends claude-opus-5-5 the kind, the lines said before, the same transcript window for every variant, and the sentence, never the variant name, and reads back 1 to 5 on seven criteria: the speaker's own words, the one thing they were circling, question or reflection rather than advice or praise, fits the kind, welcome at that moment, names something from the last two utterances, and shares neither frame nor opening with the lines said before. `report.mjs` adds the hard rules checked in code (one sentence, at most 15 words, no "I", no quotes or markdown, none of the five forbidden frames), median and p90 latency, and cost from the token counts at list price. `frames.mjs` counts the lines in one of five stock frames and the lines that share a content word with the last two utterances; `--show` prints them, so leave it off over private recordings.

`data/` is ignored by git. `node --test tools/judge/*.test.mjs` runs without a key or a network.
