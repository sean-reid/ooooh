# ooooh

An iPhone app for people who think better by talking but dislike speaking into silence. You talk for as long as you need. The app listens, keeps track, and stays quiet, except when it notices you circling, hesitating, or leaving an idea unresolved. Then, once you have been quiet for a second and a half, it asks one short question and goes quiet again; if you pick the thread back up first, it says nothing. When you stop, it turns the session into notes.

Transcription runs on the phone. Jev, a model that returns typed answers, decides when to speak; Claude phrases the question and ElevenLabs says it. A small Cloudflare Worker holds the provider keys and knows each device only by its App Attest key, its session count for the month, and its subscription. iOS 26 or later, iPhone only. Three sessions a month are free; `com.seanreid.ooooh.monthly` is $6.99 and `com.seanreid.ooooh.yearly` is $49.99.

## Development

Xcode 26.4, XcodeGen, and Node 24. The Xcode project is generated and not tracked.

```sh
brew install xcodegen
xcodegen generate                      # writes ooooh.xcodeproj
swift test --package-path Packages     # unit tests, no simulator needed

cd worker && npm ci
cp .dev.vars.example .dev.vars         # keys are optional; only the five contract tests use them
npm run types                          # worker-configuration.d.ts, for tsc and the editor
npm test                               # worker tests in the Workers runtime
npm run dev                            # wrangler dev on http://localhost:8787, which the UI tests need

cd .. && xcodebuild -scheme ooooh -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
npm --prefix worker run format && swift format format -i -r Packages App   # what CI's lint jobs check
```

Debug builds talk to `http://localhost:8787`; release builds take `xcodebuild OOOOH_WORKER_URL=https://<your worker> ...`. The simulator cannot transcribe, so Debug builds add a Demo button that replays a synthetic fixture through the whole pipeline. Launch arguments for the simulator and the UI tests:

| Argument                            | Effect                                       |
| ----------------------------------- | -------------------------------------------- |
| `-demo 1`                           | taps Demo at launch                          |
| `-onboarding 1`                     | shows the first-run screens again            |
| `-onboardingComplete 1`             | skips the first-run screens                  |
| `-ui-color-scheme dark`             | forces a colour scheme                       |
| `-worker-url <url>`                 | points the build at another Worker           |
| `-force-voice 1`                    | speaks prompts on the simulator's speaker    |
| `-free-exhausted 1`                 | runs every session as one the Worker refused |
| `-reset-store 1`, `-seed-history 1` | an empty or a one-session history            |
| `-hide-debug 1`                     | hides the Demo row for the store captures    |

To record a fixture, run a debug build on a phone, tap "Record a fixture", talk, then Stop; the JSON and audio land in the app's Documents folder for `tools/labeler/`.

Snapshot tests compare the screens against PNGs under `Packages/Tests/*/__Snapshots__` and `App/BillingTests/__Snapshots__`, recorded on the iPhone 17 Pro simulator; to re-record, delete the PNGs you changed, run again, and look at the new ones before committing them. `AudioTests` gates on the player's frame clock and prints the start and stop latencies, which are checked against their budgets on a phone before a release. After a change to the orb painter, run `swift run --package-path Packages render-icon` and commit the icons. `site/` is the landing page, privacy policy, and terms at https://ooooh.app/, published by `.github/workflows/pages.yml`.

## Worker

| Path                     | Provider      | Returns                                                              |
| ------------------------ | ------------- | -------------------------------------------------------------------- |
| `GET /health`            | none          | `{ ok, version }`                                                    |
| `GET /v1/config`         | none          | the governor config                                                  |
| `POST /v1/decide`        | Jev           | `answers` (with `cues`), `questionsVersion`, `usage`                 |
| `POST /v1/compact`       | Claude Haiku  | `{ patch, usage }`                                                   |
| `POST /v1/phrase`        | Claude Sonnet | `{ text }` of at most 15 words, or an SSE stream                     |
| `POST /v1/notes`         | Claude Opus   | `{ notes, usage }`                                                   |
| `POST /v1/speak`         | ElevenLabs    | `audio/mpeg`, streamed, for up to 400 characters                     |
| `GET /v1/challenge`      | none          | a one-time challenge for attestation                                 |
| `POST /v1/attest`        | none          | 204 once the App Attest attestation checks out                       |
| `POST /v1/session/start` | none          | `{ allowed, free, remainingFree, promptMinutes }`                    |
| `POST /v1/session/end`   | none          | 204 after `{ minutes }` is added to the month                        |
| `POST /v1/entitlement`   | none          | `{ entitlement, expiresDate }` for a verified StoreKit 2 transaction |

A bad field is 422 with the field named, a device with no open session and no subscription gets 402 `no-session`, a rate-limited or slow provider is 503 with `retryAfter`, and any other upstream failure is 502 with the provider's reply in the Worker log and not in the body. Each device gets `DEVICE_MINUTE_REQUESTS` a minute, and each provider a daily cap: `JEV_DAILY_TOKENS`, `ANTHROPIC_DAILY_TOKENS` in Opus-equivalent tokens, and `ELEVENLABS_DAILY_CHARACTERS`. Vars live in `wrangler.jsonc` twice, top level for local runs and under `env.production`; the three secrets are listed in `.dev.vars.example` and set with `wrangler secret put <NAME> --env production`.

There are no accounts; the device is the identity. A phone attests an App Attest key once per install, and every later request carries an assertion the Worker checks against `APP_ATTEST_APP_ID`, `APP_ATTEST_ENVIRONMENT`, a 300 second clock window, and a forward-only counter, answering 401 with the failing check as `reason`. The simulator cannot attest, so `.dev.vars` sets `REQUIRE_ATTESTATION=false`. A free session counts against the month and stops prompting at `promptMinutes`; a subscription is a StoreKit 2 transaction posted to `/v1/entitlement`, checked against `APP_BUNDLE_ID` and `APP_STORE_ENVIRONMENT` (`Sandbox` for TestFlight), and bound to the device through its `appAccountToken`.

`npm test` runs every route against a fake upstream and, with keys in `.dev.vars`, five contract tests that call each provider once; `.github/workflows/contract.yml` runs those five daily with `TYPESAFE_API_KEY`, `ANTHROPIC_API_KEY`, and `ELEVENLABS_API_KEY` as Actions secrets. `WRITE_FIXTURES=1 npx vitest run --project node` rewrites the fixtures `ProxyTests` decodes and `WRITE_REQUEST_FIXTURES=1 swift test --package-path Packages` rewrites the request bodies the node project validates, so a shape change on either side fails one of the two suites. The Worker runs at `https://api.ooooh.app` as the `production` environment; `.github/workflows/deploy.yml` tests, deploys, and probes `/health` on every push to `main` that touches `worker/`, with `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` as Actions secrets. `npm run deploy:dry` builds the production config without uploading and `bin/rotate-secret <NAME>` rotates a provider key.

## Layout

- `App/` is the thin app target; everything it does lives in a package.
- `Packages/` is one Swift package: Audio, Transcription, State, Governor, Notes, Design, Proxy, Session, Persistence, Billing, and Settings.
- `worker/` is the Cloudflare Worker.
- `tools/labeler/` marks good moments in a recorded session (serve it with `python3 -m http.server -d tools/labeler`); `tools/synth/` turns the scripts in `fixtures/synthetic/scripts/` into fixtures, labels, and audio; `tools/store/` renders the App Store screenshots and preview.

## Eval

A fixture is a recorded session as JSON segments; labels mark the utterances where a prompt would have been welcome and which kind. `eval` replays a fixture through the session loop and reports precision, recall, and lateness per kind; `--answers` scores a recorded Jev run and `--config` tries other thresholds. The ten synthetic scripts are a regression benchmark for the governor, not calibration data, and CI runs them with `--require-perfect` on every push.

```sh
swift run --package-path Packages eval <fixture.json> <labels.json>
node tools/synth/synth.mjs --all fixtures/synthetic/scripts --out fixtures/synthetic/estimate
node --test tools/synth/*.test.mjs tools/labeler/*.test.mjs
```
