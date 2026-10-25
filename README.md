# ooooh

An iPhone app for people who think better by talking but dislike speaking into silence. You talk for as long as you need. The app listens, keeps track, and stays quiet, except when it notices you circling, hesitating, or leaving an idea unresolved. Then it asks one short question and goes quiet again. When you stop, it turns the session into notes: ideas, decisions, questions, insights, actions, open threads, and the lines worth keeping.

Transcription runs on the phone. The decision about when to speak is made by Jev, a model that returns typed answers rather than text. Prompts are phrased by Claude and spoken by ElevenLabs. A small Cloudflare Worker holds the keys and stores nothing.

iOS 26 or later, iPhone only.

## Development

Xcode 26.4, XcodeGen, and Node 24. The Xcode project is generated and not tracked.

```sh
brew install xcodegen
xcodegen generate                      # writes ooooh.xcodeproj
swift test --package-path Packages     # unit tests, no simulator needed
xcodebuild -scheme ooooh -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

swift run --package-path Packages eval <fixture.json> <labels.json>  # governor eval

cd worker && npm install
npm test                               # worker tests in the Workers runtime
npm run dev                            # wrangler dev on http://localhost:8787
```

To record a fixture, run a debug build on a phone, tap "Record a fixture" at the bottom of the home screen, then Start. Talk, then Stop. A share sheet offers two files named from the session start, `yyyy-MM-dd-HHmmss.json` with the final segments and `yyyy-MM-dd-HHmmss.caf` with the microphone audio. They also stay in the app's Documents folder under `fixtures/`, visible in the Files app. Load the JSON into `tools/labeler/` to mark the moments, or replay it with `FixtureTranscriber`.

### Worker routes

| Path               | Provider           | Returns                                                                        |
| ------------------ | ------------------ | ------------------------------------------------------------------------------ |
| `POST /v1/decide`  | Jev (`jev-latest`) | `answers` shaped like `JevAnswers`, `questionsVersion`, `usage.jevInputTokens` |
| `POST /v1/compact` | Claude Haiku       | `patch` shaped like `StatePatch`, `usage.inputTokens`, `usage.outputTokens`    |
| `POST /v1/phrase`  | Claude Sonnet      | `{ text }`, or `delta` and `done` events with `Accept: text/event-stream`      |
| `POST /v1/notes`   | Claude Opus        | `notes` shaped like `SessionNotes`, `usage.inputTokens`, `usage.outputTokens`  |

Bodies are JSON, capped at 256 KiB. A bad field comes back as 422 with the field named. A rate-limited provider comes back as 503 with `retryAfter` in seconds.

The Worker reads two secrets. Set them once per deployment and put the same names in `worker/.dev.vars` for local runs:

```sh
cd worker
wrangler secret put TYPESAFE_API_KEY
wrangler secret put ANTHROPIC_API_KEY
```

For local development with a short-lived OAuth token instead of a stored key, set `ANTHROPIC_AUTH_TOKEN` in `.dev.vars`. It is sent as a bearer with the `oauth-2025-04-20` beta, and when both are set the token wins.

`npm test` runs every route against a fake upstream and skips the four contract tests. With the keys in `.dev.vars` or the environment, the contract tests call each provider once with a small state and check the response shape. `WRITE_FIXTURES=1 npx vitest run --project node` rewrites `Packages/Tests/ProxyTests/Fixtures` from the fake upstream; `ProxyTests` decodes those files, so a shape change on either side fails one of the two suites.

When a session ends the app posts the compact state and the whole transcript to `/v1/notes`, about 10,000 tokens for an hour of talking, so nothing is excerpted. Opus returns a title, an optional summary, and seven sections (ideas, decisions, questions, insights, actions, open threads, quotes) as JSON against a schema; every item is one sentence with a span into the transcript, and the Worker trims spans to the transcript's bounds and rejects duplicate ids. A session under about three minutes comes back as a summary paragraph plus open threads. `NotesView` shows the non-empty sections, reveals the transcript words under an item when tapped, and shares the notes as markdown. The Opus contract test spends real tokens, about 4,000 in and 1,400 out, so run it on purpose.

### Caps

Every provider-backed route runs behind two checks before it calls upstream. A per-device limit of `DEVICE_MINUTE_REQUESTS` requests a minute, keyed on the `x-device` header or the client IP, answers 429 with `retry-after`. A daily cap per provider, `JEV_DAILY_TOKENS`, `ANTHROPIC_DAILY_TOKENS`, and `ELEVENLABS_DAILY_CHARACTERS`, counted in the `BUDGET` KV namespace from the usage each response reports, answers 503 with the provider, the count, and seconds until the UTC day rolls over. The defaults in `wrangler.jsonc` are about a dollar a day per provider; change them per deployment, not in code. Create the namespace once with `wrangler kv namespace create BUDGET` and paste the id into `wrangler.jsonc`.

The Design package has snapshot tests that render the orb and the session screen with ImageRenderer and compare against the PNGs in `Packages/Tests/DesignTests/__Snapshots__`. `NotesSnapshotTests` does the same for the notes screen. They need UIKit, so run them on the simulator: `xcodebuild -scheme ooooh -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DesignTests -only-testing:NotesSnapshotTests test`. Record on the iPhone 17 Pro simulator, since text rendering differs between devices. To re-record after a visual change, delete the PNGs you changed and run again, or run with `SIMCTL_CHILD_SNAPSHOT_TESTING_RECORD=all` in the environment; then look at the new PNGs before committing them. A failed comparison writes the rendered image and a diff to the path in `SIMCTL_CHILD_SNAPSHOT_ARTIFACTS`, which CI uploads as the `snapshot-failures` artifact.

The app icon is rendered from the orb painter, so the icon and the listening indicator cannot drift apart. `swift run --package-path Packages render-icon` writes `App/Resources/Assets.xcassets/AppIcon.appiconset/`: the 1024 px light icon on the night sky, a dark variant of the same orb unmixed onto transparency, a tinted variant as the orb's luminance on transparency, and the Contents.json. Run it after any change to the painter and commit the PNGs.

## Layout

- `App/` is the thin app target. Everything it does lives in a package.
- `Packages/` holds Audio, Transcription, State, Governor, Notes, Design, and Proxy as one Swift package.
- `worker/` is the Cloudflare Worker that serves the governor config and proxies the providers.
- `tools/labeler/` is a static page for marking good moments in a recorded session. Open `index.html` in a browser, load a fixture, export labels.
- `tools/synth/` turns the scripts in `fixtures/synthetic/scripts/` into audio, fixtures, and labels.

## Eval

A fixture is a recorded session as JSON segments. Labels mark the utterances where a prompt would have been welcome, and which kind, plus `finished` and `leave`. `eval` replays the fixture through the session loop and reports precision, recall, and median lateness in utterances per kind. With no `--answers` file it uses the oracle provider, which reads the labels and runs with the floor off, and must score 1.00 everywhere; pass `--answers` with one recorded Jev answer per line to score a real run, and `--config` to try other thresholds. `eval --corpus <dir> --require-perfect` runs every fixture and labels pair in a directory and prints one line per session plus a merged report; CI runs it over `fixtures/synthetic/estimate` on every push. Recordings and labels live outside the repo in a data directory.

## Synthetic corpus

Ten scripted sessions in `fixtures/synthetic/scripts/`, three to eight minutes of speech each, written as thinking aloud: fillers, false starts, repeated ideas, hanging questions, and pauses from half a second to forty. Each covers one archetype (a flowing plan, a stuck loop, a decision, a late night, a false ending, a speaker addressing the app, and so on) and carries labels for where a prompt would have been welcome. The corpus is a regression benchmark for the governor: a change that fires on a `leave` or misses a `clarify` here is a regression. It is not calibration data. Calibration still needs real recordings and real labels from the labeler.

A script is JSON with a `name`, a `summary`, and `utterances`, each with `text`, a `pauseAfter` in seconds, and an optional `label` from the intervention kinds plus `finished`, `leave`, `recall`, and `wrapUp`. `script.schema.json` in the same directory is the schema and every script is validated against it.

`tools/synth/synth.mjs` has three modes. `estimate` times each utterance from its word count (2.6 words per second plus 0.3 s) and writes only the fixture and labels, so CI can regenerate them without speech. `say` speaks each utterance with macOS `say`, measures it with `afinfo`, and splices speech and silence with ffmpeg into `<name>.m4a` (AAC, 22.05 kHz mono) and `<name>.wav` (16 kHz mono); the fixture times come from the audio. `elevenlabs` does the same splice with clips from the ElevenLabs API, model `eleven_flash_v2_5`, reading `ELEVENLABS_API_KEY` from the environment and a voice id from `--voice`. The estimate outputs are committed under `fixtures/synthetic/estimate/`; audio and say-timed fixtures go to `fixtures/synthetic/audio/`, which is ignored.

```sh
node tools/synth/synth.mjs --all fixtures/synthetic/scripts --out fixtures/synthetic/estimate
node tools/synth/synth.mjs --all fixtures/synthetic/scripts --out fixtures/synthetic/audio --tts say
node --test tools/synth/*.test.mjs
```
