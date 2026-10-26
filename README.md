# ooooh

An iPhone app for people who think better by talking but dislike speaking into silence. You talk for as long as you need. The app listens, keeps track, and stays quiet, except when it notices you circling, hesitating, or leaving an idea unresolved. Then, once you have been quiet for a second and a half, it asks one short question and goes quiet again; if you pick the thread back up first, it says nothing. When you stop, it turns the session into notes.

Transcription runs on the phone. Jev, a model that returns typed answers, decides when to speak; Claude phrases the question and ElevenLabs says it. A small Cloudflare Worker holds the provider keys and stores, per device, an App Attest public key, its counters, the month's session count, and the verified subscription. iOS 26 or later, iPhone only. Three sessions a month are free; `com.seanreid.ooooh.monthly` is $6.99 and `com.seanreid.ooooh.yearly` is $49.99.

## Development

Xcode 26.4, XcodeGen, and Node 24. The Xcode project is generated and not tracked.

```sh
brew install xcodegen
xcodegen generate                      # writes ooooh.xcodeproj
swift test --package-path Packages     # unit tests, no simulator needed
xcodebuild -scheme ooooh -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

cd worker && npm ci                    # again after any pull that touches the lockfile
npm run types                          # worker-configuration.d.ts, for tsc and the editor
cp .dev.vars.example .dev.vars         # then fill in the three keys
npm test                               # worker tests in the Workers runtime
npm run dev                            # wrangler dev on http://localhost:8787
```

Debug builds talk to `http://localhost:8787`; release builds take `xcodebuild OOOOH_WORKER_URL=https://<your worker> ...` and run listening-only without one. The simulator cannot transcribe, so Start fails there with "Listening isn't available on this device yet." and Debug builds add a Demo button that replays a recorded fixture through the whole pipeline; `-demo 1` taps it at launch, `-onboarding 1` shows the first-run screens again, `-worker-url http://localhost:8788` points the build at another port, `-force-voice 1` speaks prompts on the simulator's otherwise quiet speaker route, `-free-exhausted 1` runs every session as one the Worker refused, with the paywall after End, and `-reset-store 1` and `-seed-history 1` give the UI tests an empty or a one-session history. Every session is saved on the device: the clock button on the home screen opens history with search and swipe to delete, the gear opens Settings with the listener switches, Subscribe, export, and delete, and up to three threads left open by past sessions sit in a card beneath Start. To record a fixture, run a debug build on a phone, tap "Record a fixture", talk, then Stop; the JSON and audio land in the app's Documents folder for `tools/labeler/`.

Snapshot tests compare the screens against PNGs under `Packages/Tests/*/__Snapshots__`, recorded on the iPhone 17 Pro simulator; run them with `-only-testing:DesignTests` and the other snapshot targets on that simulator. To re-record after a visual change, delete the PNGs you changed and run again, then look at the new PNGs before committing them. CI uploads failed comparisons as the `snapshot-failures` artifact. After any change to the orb painter, run `swift run --package-path Packages render-icon` and commit the icons it writes.

`site/` is the landing page, privacy policy, and terms, published to https://ooooh.app/ by `.github/workflows/pages.yml`. The store is on-device until the iCloud capability exists in the developer portal. `App/Resources/Products.storekit` sells the subscriptions on the simulator before App Store Connect has a record; the iOS 26.4 simulator runtime refuses StoreKit test sessions (Apple's FB22774836), so the purchase tests skip there and say so.

## Worker

| Path                     | Provider                       | Returns                                                                                                                        |
| ------------------------ | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| `GET /health`            | none                           | `{ ok, version }`, the id of the Worker version answering                                                                      |
| `GET /v1/config`         | none                           | the governor config, same fields and version as `GovernorConfig.initial`                                                       |
| `POST /v1/decide`        | Jev (`jev-latest`)             | `answers` shaped like `JevAnswers`, `cues`, `questionsVersion`, `usage.jevInputTokens`                                         |
| `POST /v1/compact`       | Claude Haiku                   | `patch` shaped like `StatePatch`, `usage.inputTokens`, `usage.outputTokens`                                                    |
| `POST /v1/phrase`        | Claude Sonnet                  | `{ text }` of at most 15 words, or `delta`, `done`, and `error` events with `Accept: text/event-stream`                        |
| `POST /v1/notes`         | Claude Opus                    | `notes` shaped like `SessionNotes`, `usage.inputTokens`, `usage.outputTokens`                                                  |
| `POST /v1/speak`         | ElevenLabs (`eleven_v4_turbo`) | `audio/mpeg` streamed as it arrives, `x-character-count` in the headers; `{ text }` of 1 to 400 characters                     |
| `GET /v1/challenge`      | none                           | `{ challenge }`, 32 random bytes in base64, good once for five minutes                                                         |
| `POST /v1/attest`        | none                           | 204 once the App Attest attestation checks out, 401 with a `reason` otherwise                                                  |
| `POST /v1/session/start` | none                           | `{ allowed, free, remainingFree, promptMinutes }`, `{ allowed: true, free: false }` when paid, or `{ allowed: false, reason }` |
| `POST /v1/session/end`   | none                           | 204, after `{ minutes }` is added to the month's usage                                                                         |
| `POST /v1/entitlement`   | none                           | `{ entitlement, expiresDate }` once a StoreKit 2 transaction verifies, 401 otherwise                                           |

Bodies are JSON, capped at 256 KiB; a bad field is 422 with the field named. A provider call from a device with no open session and no entitlement is 402 `{ error: "no-session", reason }`, `not-started` or, once the month's free sessions are spent, `free-used`; past `promptMinutes` of a free session `/v1/decide`, `/v1/phrase`, and `/v1/speak` answer `minutes-used`, while `/v1/compact` and `/v1/notes` keep answering so the session gets its notes. A rate-limited provider is 503 with `retryAfter` in seconds, after one or two retries when its `Retry-After` is 2 seconds or less. Any other upstream failure is 502 with `status` and `detail`, a Jev 200 that is not JSON included; a reply the Worker refuses after the model answered, `anthropic refused`, `anthropic truncated`, `bad patch`, or `bad notes`, is 502 too and still counts against the day, and a Jev answer the phone could not decode is 502 `jev answer shape` with the `question`, `field`, and `expected` shape. On the SSE path the same body arrives as an `error` event. A Jev call is abandoned after 5 seconds.

Every provider route runs behind `DEVICE_MINUTE_REQUESTS` requests a minute per device (429) and a daily cap per provider in the `BUDGET` KV namespace (503 until the UTC day rolls over): `JEV_DAILY_TOKENS`, `ANTHROPIC_DAILY_TOKENS`, and `ELEVENLABS_DAILY_CHARACTERS`, 20 million, 700,000, and 20,000 by default. The Anthropic figure counts Opus-equivalent tokens: a Sonnet token weighs 0.5 and a Haiku token 0.025, their list prices over Opus's, and a model outside those three weighs 1, so 700,000 is about $5 of Opus a day at four input tokens per output token. Every var lives twice in `wrangler.jsonc`, top level for local runs and under `env.production`, since wrangler does not pass vars down; a value that is not a positive number keeps the default. The three secrets are set with `wrangler secret put <NAME> --env production` and listed in `.dev.vars.example`; `ANTHROPIC_AUTH_TOKEN` in `.dev.vars` sends a short-lived OAuth token instead and wins over the key. `GET /v1/challenge` and `POST /v1/attest` carry no device to key on, so they take 10 requests a minute per client address between them, 429 past that.

There are no accounts; the device is the identity. A phone attests a key once per install (`GET /v1/challenge`, Apple's attestation over the challenge hash, `POST /v1/attest`), and from then on every provider and session request carries `x-device`, `x-assertion-time` with the unix seconds it was signed, and `x-assertion` over SHA256 of `METHOD\nPATH\nSECONDS\nBODY_HASH_HEX`; the Worker rebuilds that string from the request and checks the chain, the nonce, the RP ID hash against `APP_ATTEST_APP_ID`, the aaguid for `APP_ATTEST_ENVIRONMENT`, that the time is within 300 seconds of its clock, and a counter that only moves forward, answering 401 with the failing check as `reason` (`stale` for an old time). Attesting a known key again keeps its counter. `/health` and `/v1/config` stay open. The simulator cannot attest, so `.dev.vars` sets `REQUIRE_ATTESTATION=false` and the routes take `x-device` as a label. A microphone session posts `/v1/session/start` once the microphone is running and `/v1/session/end` with its wall-clock minutes, and the Demo posts the same pair around its fixture. The Worker opens `session:<keyId>` at start, counting a free one against the month, and closes it at end; a start while one is open answers the same allowance and counts nothing, and the record expires on its own after four hours. A refusal keeps the session listening under "listening only, this month's free sessions are used up" with no prompts, nothing more sent to the Worker, and no notes at the end, a free session stops prompting at `promptMinutes` or when a provider route answers 402 `no-session`, and a session that ends with no free sessions left on an unpaid device brings up the paywall. A paid device skips the free-session count: the app posts each signed StoreKit 2 transaction to `/v1/entitlement`, and the Worker verifies it against the Apple Root CA G3, `APP_BUNDLE_ID`, the two product ids, and `APP_STORE_ENVIRONMENT` (`Sandbox` for TestFlight), then keeps it under `entitlement:<keyId>` until expiry plus 30 days. The transaction has to carry the `appAccountToken` the app sets at purchase, a UUID derived from the device's App Attest key id, so one subscription cannot be posted from another install; the first device to claim an `originalTransactionId` keeps it, and an older `signedDate` never replaces a newer record. A purchase made without the token can never be entitled, so this ships before the first real purchase.

`npm test` runs the shell tests for `bin/rotate-secret` first, then every route against a fake upstream in the Workers runtime and, with keys in `.dev.vars`, five contract tests that call each provider once; the Opus one spends real tokens. `WRITE_FIXTURES=1 npx vitest run --project node` rewrites the fixtures `ProxyTests` decodes, so a shape change on either side fails one of the two suites. `npm run coverage` prints line and branch coverage for the Workers project; CI uploads the summary as the `worker-coverage` artifact.

The Worker runs at `https://api.ooooh.app` as the `production` environment, named `ooooh-production` in Cloudflare. `.github/workflows/deploy.yml` lints, typechecks, tests, deploys, and polls `/health` until the version wrangler printed answers, on every push to `main` that touches `worker/`; it needs `CLOUDFLARE_API_TOKEN` (Edit Cloudflare Workers template, this account and the `ooooh.app` zone) and `CLOUDFLARE_ACCOUNT_ID` as Actions secrets. `npm run deploy:dry` builds the production config without uploading. To rotate a key, run `bin/rotate-secret ELEVENLABS_API_KEY`: it reads the value with echo off, puts it in production, probes `/health`, and prints the revoke and `KEY_ROTATED_AT_<NAME>` reminders; the first prompt from a phone is the check that the new key works.

## Layout

- `App/` is the thin app target; everything it does lives in a package.
- `Packages/` is one Swift package: Audio, Transcription, State, Governor, Notes, Design, Proxy, Session, Persistence, Billing, and Settings.
- `worker/` is the Cloudflare Worker.
- `tools/labeler/` marks good moments in a recorded session; serve it with `python3 -m http.server -d tools/labeler`, load a fixture and its audio, press a letter per utterance, and Export writes `<name>.labels.json`.
- `tools/synth/` turns the scripts in `fixtures/synthetic/scripts/` into fixtures, labels, and audio.

## Eval

A fixture is a recorded session as JSON segments; labels mark the utterances where a prompt would have been welcome and which kind. `eval` replays a fixture through the session loop and reports precision, recall, and lateness per kind. With no `--answers` it uses the oracle, which reads the labels and must score 1.00; `--answers` scores a recorded Jev run and `--config` tries other thresholds. `eval --corpus <dir> --require-perfect` runs a directory and CI runs it over `fixtures/synthetic/estimate` on every push.

The ten scripts in `fixtures/synthetic/scripts/` are a regression benchmark for the governor, not calibration data. `script.schema.json` is their schema and the corpus tests enforce the pacing: speech fills 55 to 75 percent of a session, every intervention label sits before a gap of at least 5 s, and every `leave` before at least 15 s. `synth.mjs --tts say` or `--tts elevenlabs` also renders the audio, under `fixtures/synthetic/audio/`, which is ignored.

```sh
swift run --package-path Packages eval <fixture.json> <labels.json>
node tools/synth/synth.mjs --all fixtures/synthetic/scripts --out fixtures/synthetic/estimate
node --test tools/synth/*.test.mjs tools/labeler/*.test.mjs
```
