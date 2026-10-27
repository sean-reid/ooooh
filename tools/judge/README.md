# Phrase judge

Measures the one sentence the app says. The corpus is every labeled intervention moment in `fixtures/synthetic/estimate`, 17 of them across six kinds. Each moment becomes the input the phone would have sent `/v1/phrase`: the kind, the last 6 finals, and an empty compact state, since the fixtures carry no state. The prompt, the word limit, and the model name are imported from `worker/src/phrasing.ts` and `worker/src/models.ts`, so the `shipping` variant is what the route sends today.

Install once with `npm ci` in this directory; the model calls read `ANTHROPIC_API_KEY` from the environment through the SDK. Then, from the repo root:

```
node tools/judge/corpus.mjs                 # data/corpus.jsonl, one moment per line
node tools/judge/phrase.mjs shipping        # data/lines.shipping.jsonl: text, latency, tokens
node tools/judge/phrase.mjs exemplars       # the same prompt plus one example line per kind
node tools/judge/phrase.mjs opus            # claude-opus-5-5 with adaptive thinking
node tools/judge/score.mjs shipping         # data/scores.shipping.jsonl from the judge
node tools/judge/report.mjs                 # the table over every variant under data/
```

`phrase.mjs` records the first sentence the model returns; the route's shorter-retry and truncation are left out so the hard-rule rate shows what the model does on its own. `score.mjs` sends claude-opus-5-5 the kind, the same 6 lines, and the sentence, never the variant name, and reads back 1 to 5 on five criteria: the speaker's own words, the one thing they were circling, question or reflection rather than advice or praise, fits the kind, welcome at that moment. `report.mjs` adds the hard rules checked in code (one sentence, at most 15 words, no "I", no quotes or markdown), median and p90 latency, and cost from the token counts at list price.

`data/` is ignored by git. `node --test tools/judge/*.test.mjs` runs without a key or a network.
