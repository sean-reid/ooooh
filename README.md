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

## Layout

- `App/` is the thin app target. Everything it does lives in a package.
- `Packages/` holds Audio, Transcription, State, Governor, Notes, Design, and Proxy as one Swift package.
- `worker/` is the Cloudflare Worker that serves the governor config and proxies the providers.
- `tools/labeler/` is a static page for marking good moments in a recorded session. Open `index.html` in a browser, load a fixture, export labels.

## Eval

A fixture is a recorded session as JSON segments. Labels mark the utterances where a prompt would have been welcome, and which kind, plus `finished` and `leave`. `eval` replays the fixture through the session loop and reports precision, recall, and median lateness in utterances per kind. With no `--answers` file it uses the oracle provider, which reads the labels and should score 1.00 everywhere; pass `--answers` with one recorded Jev answer per line to score a real run, and `--config` to try other thresholds. Recordings and labels live outside the repo in a data directory.
