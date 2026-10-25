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

## Layout

- `App/` is the thin app target. Everything it does lives in a package.
- `Packages/` holds Audio, Transcription, State, Governor, Notes, Design, and Proxy as one Swift package.
- `worker/` is the Cloudflare Worker that serves the governor config and proxies the providers.
- `tools/labeler/` is a static page for marking good moments in a recorded session. Open `index.html` in a browser, load a fixture, export labels.
- `tools/synth/` turns the scripts in `fixtures/synthetic/scripts/` into audio, fixtures, and labels.

## Eval

A fixture is a recorded session as JSON segments. Labels mark the utterances where a prompt would have been welcome, and which kind, plus `finished` and `leave`. `eval` replays the fixture through the session loop and reports precision, recall, and median lateness in utterances per kind. With no `--answers` file it uses the oracle provider, which reads the labels and should score 1.00 everywhere; pass `--answers` with one recorded Jev answer per line to score a real run, and `--config` to try other thresholds. Recordings and labels live outside the repo in a data directory.

## Synthetic corpus

Ten scripted sessions in `fixtures/synthetic/scripts/`, three to eight minutes of speech each, written as thinking aloud: fillers, false starts, repeated ideas, hanging questions, and pauses from half a second to forty. Each covers one archetype (a flowing plan, a stuck loop, a decision, a late night, a false ending, a speaker addressing the app, and so on) and carries labels for where a prompt would have been welcome. The corpus is a regression benchmark for the governor: a change that fires on a `leave` or misses a `clarify` here is a regression. It is not calibration data. Calibration still needs real recordings and real labels from the labeler.

A script is JSON with a `name`, a `summary`, and `utterances`, each with `text`, a `pauseAfter` in seconds, and an optional `label` from the intervention kinds plus `finished`, `leave`, `recall`, and `wrapUp`. `script.schema.json` in the same directory is the schema and every script is validated against it.

`tools/synth/synth.mjs` has three modes. `estimate` times each utterance from its word count (2.6 words per second plus 0.3 s) and writes only the fixture and labels, so CI can regenerate them without speech. `say` speaks each utterance with macOS `say`, measures it with `afinfo`, and splices speech and silence with ffmpeg into `<name>.m4a` (AAC, 22.05 kHz mono) and `<name>.wav` (16 kHz mono); the fixture times come from the audio. `elevenlabs` does the same splice with clips from the ElevenLabs API, model `eleven_flash_v2_5`, reading `ELEVENLABS_API_KEY` from the environment and a voice id from `--voice`. The estimate outputs are committed under `fixtures/synthetic/estimate/`; audio and say-timed fixtures go to `fixtures/synthetic/audio/`, which is ignored.

```sh
node tools/synth/synth.mjs --all fixtures/synthetic/scripts --out fixtures/synthetic/estimate
node tools/synth/synth.mjs --all fixtures/synthetic/scripts --out fixtures/synthetic/audio --tts say
node --test tools/synth/*.test.mjs
```
