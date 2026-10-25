# ooooh

An iPhone app for people who think better by talking but dislike speaking into silence. You talk for as long as you need. The app listens, keeps track, and stays quiet, except when it notices you circling, hesitating, or leaving an idea unresolved. Then it asks one short question and goes quiet again. When you stop, it turns the session into notes: ideas, decisions, questions, insights, actions, open threads, and the lines worth keeping.

Transcription runs on the phone. The decision about when to speak is made by Jev, a model that returns typed answers rather than text. Prompts are phrased by Claude and spoken by ElevenLabs. A small Cloudflare Worker holds the provider keys and stores only each device's App Attest public key and its counters.

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

The app reads the Worker base URL from the `OOOOH_WORKER_URL` build setting, which lands in Info.plist as `OoooohWorkerURL`. Debug builds default to `http://localhost:8787`, so `npm run dev` in `worker/` is all a simulator needs. Release builds have no default; pass one on the command line, `xcodebuild OOOOH_WORKER_URL=https://<your worker> ...`. Without a URL the app runs listening only and never prompts.

The home screen has one Start button. Debug builds add a Demo button that replays `fixtures/synthetic/estimate/decision.fixture.json` through the whole pipeline at 1x, which is how the app runs on the simulator; launching with `-demo 1` taps it for you. The session screen is the orb, the elapsed time, and the last prompt. When the Worker is unreachable the session keeps listening and shows one line saying so, and no prompts fire until it is back.

`site/` is the landing page with the privacy policy and terms, plain HTML with no build step, published to https://sean-reid.github.io/ooooh/ by `.github/workflows/pages.yml` on every push to main that touches it.

`site/` is the landing page with the privacy policy and terms, plain HTML with no build step, published to https://ooooh.app/ by `.github/workflows/pages.yml` on every push to main that touches it.

To record a fixture, run a debug build on a phone, tap "Record a fixture" at the bottom of the home screen, then Start. Talk, then Stop. A share sheet offers two files named from the session start, `yyyy-MM-dd-HHmmss.json` with the final segments and `yyyy-MM-dd-HHmmss.caf` with the microphone audio. They also stay in the app's Documents folder under `fixtures/`, visible in the Files app. Load the JSON into `tools/labeler/` to mark the moments, or replay it with `FixtureTranscriber`.

### CloudKit sync

The store has three configurations: `.inMemory` for tests, `.local` for a device without iCloud, and `.cloud`, which syncs through the user's private CloudKit database in the container `iCloud.com.seanreid.ooooh`. The app passes `.local` until the capability exists in the developer portal, since a build with `.cloud` and no entitlement fails on launch. To turn sync on, add the iCloud capability with CloudKit and that container id to the app target in `project.yml`, plus `remote-notification` under `UIBackgroundModes` so the device picks up changes pushed from another one. The schema follows the CloudKit rules: every attribute has a default or is optional, every relationship is optional with an inverse, and nothing is marked unique.

### Worker routes

| Path                     | Provider                       | Returns                                                                           |
| ------------------------ | ------------------------------ | --------------------------------------------------------------------------------- |
| `POST /v1/decide`        | Jev (`jev-latest`)             | `answers` shaped like `JevAnswers`, `questionsVersion`, `usage.jevInputTokens`    |
| `POST /v1/compact`       | Claude Haiku                   | `patch` shaped like `StatePatch`, `usage.inputTokens`, `usage.outputTokens`       |
| `POST /v1/phrase`        | Claude Sonnet                  | `{ text }`, or `delta` and `done` events with `Accept: text/event-stream`         |
| `POST /v1/speak`         | ElevenLabs (`eleven_v4_turbo`) | `audio/mpeg` streamed as it is made, `x-character-count` in the headers           |
| `GET /v1/challenge`      | none                           | `{ challenge }`, 32 random bytes in base64, good once for five minutes            |
| `POST /v1/attest`        | none                           | 204 once the App Attest attestation checks out, 401 with a `reason` otherwise     |
| `POST /v1/session/start` | none                           | `{ allowed, free, remainingFree, promptMinutes }` or `{ allowed: false, reason }` |
| `POST /v1/session/end`   | none                           | 204, after `{ minutes }` is added to the month's usage                            |

Bodies are JSON, capped at 256 KiB. A bad field comes back as 422 with the field named. A rate-limited provider comes back as 503 with `retryAfter` in seconds.

`/v1/speak` takes `{ text }` of 1 to 400 characters and answers with `mp3_44100_64`: 8 KB per second of speech, and the phone starts playing from the first kilobyte, so it costs a sixth of raw PCM for the same start time. The voice is `ELEVENLABS_VOICE_ID` in `wrangler.jsonc` vars, River by default; set another id there or per deployment. The model is v4 Turbo, which starts streaming in about 0.3 s like Flash and costs the same, with v4 voice quality; it ignores the speed setting, so pace comes from the words.

The Worker reads three secrets. Set them once per deployment and put the same names in `worker/.dev.vars` for local runs:

```sh
cd worker
wrangler secret put TYPESAFE_API_KEY
wrangler secret put ANTHROPIC_API_KEY
wrangler secret put ELEVENLABS_API_KEY
```

For local development with a short-lived OAuth token instead of a stored key, set `ANTHROPIC_AUTH_TOKEN` in `.dev.vars`. It is sent as a bearer with the `oauth-2025-04-20` beta, and when both are set the token wins.

`npm test` runs every route against a fake upstream and skips the four contract tests. With the keys in `.dev.vars` or the environment, the contract tests call each provider once with a small state and check the response shape. `WRITE_FIXTURES=1 npx vitest run --project node` rewrites `Packages/Tests/ProxyTests/Fixtures` from the fake upstream; `ProxyTests` decodes those files, so a shape change on either side fails one of the two suites.

When a session ends the app posts the compact state and the whole transcript to `/v1/notes`, about 10,000 tokens for an hour of talking, so nothing is excerpted. Opus returns a title, an optional summary, and seven sections (ideas, decisions, questions, insights, actions, open threads, quotes) as JSON against a schema; every item is one sentence with a span into the transcript, and the Worker trims spans to the transcript's bounds and rejects duplicate ids. A session under about three minutes comes back as a summary paragraph plus open threads. `NotesView` shows the non-empty sections, reveals the transcript words under an item when tapped, and shares the notes as markdown. The Opus contract test spends real tokens, about 4,000 in and 1,400 out, so run it on purpose.

### Caps

Every provider-backed route runs behind two checks before it calls upstream. A per-device limit of `DEVICE_MINUTE_REQUESTS` requests a minute, keyed on the attested key id (or the `x-device` header, else the client IP, when attestation is off), answers 429 with `retry-after`. A daily cap per provider, `JEV_DAILY_TOKENS`, `ANTHROPIC_DAILY_TOKENS`, and `ELEVENLABS_DAILY_CHARACTERS`, counted in the `BUDGET` KV namespace from the usage each response reports, answers 503 with the provider, the count, and seconds until the UTC day rolls over. The defaults in `wrangler.jsonc` are about a dollar a day per provider; change them per deployment, not in code. Create the namespace once with `wrangler kv namespace create BUDGET` and paste the id into `wrangler.jsonc`.

### Authentication

There are no accounts; the device is the identity. A phone proves itself with App Attest once per install: it generates a key, fetches a challenge from `GET /v1/challenge`, asks Apple to attest the key over SHA256 of that challenge, and posts the key id, the attestation, and the challenge to `POST /v1/attest`. The Worker checks the certificate chain against Apple's App Attest root, the nonce, the key id against the certified key, the RP ID hash against `APP_ATTEST_APP_ID`, a zero counter, and the aaguid for `APP_ATTEST_ENVIRONMENT`, then stores the public key in KV under `device:<keyId>` with no expiry. From then on every provider and session request carries `x-device` with the key id and `x-assertion` with an assertion over SHA256 of the body, and the Worker checks the signature, the RP ID hash, and that the counter moved forward, answering 401 with `unknown-device`, `bad-assertion`, or `replay` when one fails. The rate limit above then counts against the verified key id. `/health` and `/v1/config` stay open.

The vars in `wrangler.jsonc`: `REQUIRE_ATTESTATION` (`true`), `APP_ATTEST_APP_ID` (`C6UWR42ZAP.com.seanreid.ooooh`), `APP_ATTEST_ENVIRONMENT` (`production`, or `development` for a development-signed build), `FREE_SESSIONS_PER_MONTH` (3), and `FREE_PROMPT_MINUTES` (20). `APP_ATTEST_ROOT_PEM` replaces Apple's root with another PEM; the tests set it to a root they generate, a deployment leaves it unset.

App Attest does not run on the simulator, so put `REQUIRE_ATTESTATION=false` in `worker/.dev.vars`. The routes then take `x-device` as a plain label and otherwise key on the client address, which is what `npm run dev` plus a simulator build needs. On the Swift side `ProxyClient.attestor(baseURL:session:)` returns `DeviceAttestation` when `DCAppAttestService.isSupported` and `SimulatorAttestor`, which sends nothing, otherwise. `DeviceAttestation` keeps the key id in the keychain, enrols on the first request, and enrols again with a fresh key when Apple reports the old one invalid.

Sessions are free three times a month per device, 20 prompt minutes each, counted by UTC month. `POST /v1/session/start` decides and counts at the start, and `POST /v1/session/end` with `{ minutes }` records what the session used. `entitlement()` in `worker/src/entitlement.ts` answers `free` for every device until the StoreKit check replaces it; a device it reports as `paid` skips the count.

The Worker tests build attestations and assertions in Apple's exact CBOR and X.509 layout from keys they generate, including a P-384 root in Apple's shape, and check that Apple's real root parses and is self-signed. Nothing runs against Apple itself, since the simulator cannot attest; the first end-to-end run is a device build against a deployed Worker.

The Design package has snapshot tests that render the orb and the session screen with ImageRenderer and compare against the PNGs in `Packages/Tests/DesignTests/__Snapshots__`. `NotesSnapshotTests` does the same for the notes screen. They need UIKit, so run them on the simulator: `xcodebuild -scheme ooooh -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DesignTests -only-testing:NotesSnapshotTests test`. Record on the iPhone 17 Pro simulator, since text rendering differs between devices. To re-record after a visual change, delete the PNGs you changed and run again, or run with `SIMCTL_CHILD_SNAPSHOT_TESTING_RECORD=all` in the environment; then look at the new PNGs before committing them. A failed comparison writes the rendered image and a diff to the path in `SIMCTL_CHILD_SNAPSHOT_ARTIFACTS`, which CI uploads as the `snapshot-failures` artifact.

The app icon is rendered from the orb painter, so the icon and the listening indicator cannot drift apart. `swift run --package-path Packages render-icon` writes `App/Resources/Assets.xcassets/AppIcon.appiconset/`: the 1024 px light icon on the night sky, a dark variant of the same orb unmixed onto transparency, a tinted variant as the orb's luminance on transparency, and the Contents.json. Run it after any change to the painter and commit the PNGs.

## Layout

- `App/` is the thin app target. Everything it does lives in a package.
- `Packages/` holds Audio, Transcription, State, Governor, Notes, Design, Proxy, Session, and Persistence as one Swift package.
- `Packages/Sources/Persistence/` is the on-device store. `SessionStore` is a `@ModelActor` over four SwiftData models: a session with its compact state as JSON, its transcript segments, its note items, and the open threads it produced. It saves a `SessionResult`, attaches the notes that arrive after the end, lists history newest first, searches segment and note text, offers unresolved threads for the next session, edits and deletes items, and exports one Markdown file per session. Kept audio stays a file under the app's storage; the store holds only its path. `PersistenceTests` run on the in-memory container with `swift test`, including a timing test that searches 300 sessions.
- `worker/` is the Cloudflare Worker that serves the governor config and proxies the providers.
- `tools/labeler/` is a static page for marking good moments in a recorded session. Open `index.html` in Safari (Chrome blocks module scripts from the file system, so serve the directory with `python3 -m http.server -d tools/labeler` there), then load a fixture and its recording or drop both files on the page; the phone's `.caf` is decoded in the page, `.m4a` and `.wav` play natively. Arrow keys move between utterances and one key labels the current one (c clarify, d deepen, r reflect, e decide, s summarize, h challenge, f finished, l leave, q recall, w wrapUp, x clears), Enter plays it, space plays and pauses the whole recording with a playhead following through the list, and Export writes `<name>.labels.json`. `node --test tools/labeler/*.test.mjs` runs the CAF parser and export tests.
- `tools/synth/` turns the scripts in `fixtures/synthetic/scripts/` into audio, fixtures, and labels.

## Eval

A fixture is a recorded session as JSON segments. Labels mark the utterances where a prompt would have been welcome, and which kind, plus `finished` and `leave`. `eval` replays the fixture through the session loop and reports precision, recall, and median lateness in utterances per kind. With no `--answers` file it uses the oracle provider, which reads the labels and runs with the floor off, and must score 1.00 everywhere; pass `--answers` with one recorded Jev answer per line to score a real run, and `--config` to try other thresholds. `eval --corpus <dir> --require-perfect` runs every fixture and labels pair in a directory and prints one line per session plus a merged report; CI runs it over `fixtures/synthetic/estimate` on every push. Recordings and labels live outside the repo in a data directory.

## Synthetic corpus

Ten scripted sessions in `fixtures/synthetic/scripts/`, three to eight minutes of speech each, written as thinking aloud: fillers, false starts, repeated ideas, hanging questions, and pauses from half a second to forty. Each covers one archetype (a flowing plan, a stuck loop, a decision, a late night, a false ending, a speaker addressing the app, and so on) and carries labels for where a prompt would have been welcome. The corpus is a regression benchmark for the governor: a change that fires on a `leave` or misses a `clarify` here is a regression. It is not calibration data. Calibration still needs real recordings and real labels from the labeler.

A script is JSON with a `name`, a `summary`, and `utterances`, each with `text`, a `pauseAfter` in seconds, and an optional `label` from the intervention kinds plus `finished`, `leave`, `recall`, and `wrapUp`. `script.schema.json` in the same directory is the schema and every script is validated against it. Pacing rules, enforced by the corpus tests: speech fills 55 to 75 percent of a session (late night runs lower), a pause of 4 s or more falls in every two minutes, every intervention label sits before a gap of at least 5 s so a spoken prompt has room to start, and every `leave` sits before at least 15 s.

`tools/synth/synth.mjs` has three modes. `estimate` times each utterance from its word count (2.6 words per second plus 0.3 s) and writes only the fixture and labels, so CI can regenerate them without speech. `say` speaks each utterance with macOS `say`, measures it with `afinfo`, and splices speech and silence with ffmpeg into `<name>.m4a` (AAC, 22.05 kHz mono) and `<name>.wav` (16 kHz mono); the fixture times come from the audio. `elevenlabs` does the same splice with clips from the ElevenLabs API, model `eleven_flash_v2_5`, reading `ELEVENLABS_API_KEY` from the environment and a voice id from `--voice`. The estimate outputs are committed under `fixtures/synthetic/estimate/`; audio and say-timed fixtures go to `fixtures/synthetic/audio/`, which is ignored.

```sh
node tools/synth/synth.mjs --all fixtures/synthetic/scripts --out fixtures/synthetic/estimate
node tools/synth/synth.mjs --all fixtures/synthetic/scripts --out fixtures/synthetic/audio --tts say
node --test tools/synth/*.test.mjs
```
