# Label

Turns a recorded fixture into the labels file the eval reads, with the first pass proposed by Opus and the final say kept by hand. Record a session on the phone's Debug record screen, share the `.json` to the Mac, and put it under `data/`, which stays out of git. The tool loads the Anthropic SDK from the Worker's install, so run `npm ci` in `worker/` once, and `propose` reads the key from `ANTHROPIC_API_KEY` and nothing else.

```
node tools/label/label.mjs propose data/2026-10-26-213012.json
node tools/label/label.mjs review data/2026-10-26-213012.json
node tools/label/label.mjs fold data/2026-10-26-213012.review.md
```

`propose` sends the transcript, with each utterance's index, times, and the pause after it, to `claude-opus-5-5` with adaptive thinking, and writes two files beside the fixture: `<name>.labels.proposed.json`, the labels format with a one-line reason on each label, and `<name>.review.md`, the transcript with the proposed labels inline and the editing rules at the top. Edit the review: delete a `label:` line to drop it, change the word to re-kind it, add a `label:` line under an utterance to add one. `review` rewrites the review from the proposed file to start the edit over. `fold` reads the edited review and writes `<name>.labels.json` with only utterance, time, and kind, which `swift run --package-path Packages eval <fixture> <labels>` then scores. `--out <dir>` on `propose` and `review` puts the files somewhere other than beside the fixture.
