# Changelog

## [0.2.0](https://github.com/sean-reid/ooooh/compare/v0.1.0...v0.2.0) (2026-10-25)


### Features

* App Attest on the Worker and a free-session counter ([#35](https://github.com/sean-reid/ooooh/issues/35)) ([78474ca](https://github.com/sean-reid/ooooh/commit/78474ca95fa3509f37cfdd108dfa485b5e20928e))
* arm prompt decisions and speak once the pause holds ([#47](https://github.com/sean-reid/ooooh/issues/47)) ([4375d14](https://github.com/sean-reid/ooooh/commit/4375d14b0278a8474715bbaa7695a96542db6703))
* atomic Jev cues, calibrated governor defaults, and live eval recording ([#25](https://github.com/sean-reid/ooooh/issues/25)) ([e3bf1cc](https://github.com/sean-reid/ooooh/commit/e3bf1cc43d93f48946c5de4c8bab70976ad0765c))
* billing package on StoreKit 2 with the paywall ([#34](https://github.com/sean-reid/ooooh/issues/34)) ([4007709](https://github.com/sean-reid/ooooh/commit/4007709e4a6bbcccf570e07c940b0d04ee452f20))
* first-run onboarding with permission recovery ([#42](https://github.com/sean-reid/ooooh/issues/42)) ([ca0b727](https://github.com/sean-reid/ooooh/commit/ca0b72795de55bbb004618c606751c7309c2bc95))
* **governor:** finished threshold 0.6, config version 3 ([#39](https://github.com/sean-reid/ooooh/issues/39)) ([9179b0b](https://github.com/sean-reid/ooooh/commit/9179b0b7243a03d7a595780ca82c2cbcaec3cb1f))
* labeler plays the recording and labels from the keyboard ([#20](https://github.com/sean-reid/ooooh/issues/20)) ([c9c7f40](https://github.com/sean-reid/ooooh/commit/c9c7f40ca3f51eab80529fde7f427206c7ffa19b))
* landing page with the breathing orb, privacy policy, and terms ([#23](https://github.com/sean-reid/ooooh/issues/23)) ([6e91e30](https://github.com/sean-reid/ooooh/commit/6e91e30168dde83d618032b9237c2d8b7fdb617e))
* live session wiring, session screen, and a demo mode ([#24](https://github.com/sean-reid/ooooh/issues/24)) ([b4ee832](https://github.com/sean-reid/ooooh/commit/b4ee832318e887a48761bb1a29752d9aa7df0f44))
* notes route on Opus with the notes view ([#15](https://github.com/sean-reid/ooooh/issues/15)) ([b2d9491](https://github.com/sean-reid/ooooh/commit/b2d94915098343367ce0730cb61f6a2419986d69))
* persistence package on SwiftData with CloudKit-ready models ([#19](https://github.com/sean-reid/ooooh/issues/19)) ([5e0b4f7](https://github.com/sean-reid/ooooh/commit/5e0b4f70716ea7b4c505a1b75e8454b04c114866))
* settings with data controls, export, and the in-app privacy page ([#33](https://github.com/sean-reid/ooooh/issues/33)) ([40428a4](https://github.com/sean-reid/ooooh/commit/40428a4c1337d6b5ce01d99f1c5e5866997255a8))
* **site:** favicon, touch icon, and manifest from the app icon ([#31](https://github.com/sean-reid/ooooh/issues/31)) ([7eaf689](https://github.com/sean-reid/ooooh/commit/7eaf6895b8ecf06d1d6ba3e7a2c7b23e4d5887e1))
* **site:** share card and Open Graph tags ([#38](https://github.com/sean-reid/ooooh/issues/38)) ([8d1e4bd](https://github.com/sean-reid/ooooh/commit/8d1e4bd882cde5b95c119184d1111dd89a5b100f))
* speech route on ElevenLabs with a barge-in player ([#18](https://github.com/sean-reid/ooooh/issues/18)) ([d74dd98](https://github.com/sean-reid/ooooh/commit/d74dd98cef331485316ccf2dfbe277c3639d0132))
* spoken prompts, real notes, history, and carryover in the session ([#43](https://github.com/sean-reid/ooooh/issues/43)) ([dba12ce](https://github.com/sean-reid/ooooh/commit/dba12ce9225ffd6b5ba68dd8b46f3e912257dd9a))
* verify App Store transactions for the paid entitlement ([#40](https://github.com/sean-reid/ooooh/issues/40)) ([cf89377](https://github.com/sean-reid/ooooh/commit/cf893777b4b035218c63016af5aa87aca6669070))


### Bug Fixes

* accent token for amber text and an orb halo that ends inside its frame ([#32](https://github.com/sean-reid/ooooh/issues/32)) ([0cb0765](https://github.com/sean-reid/ooooh/commit/0cb07652faa213d6aa2c90327b6d871b6c0808fc))
* **app:** declare portrait as the only orientation in Info.plist ([#37](https://github.com/sean-reid/ooooh/issues/37)) ([364d2f8](https://github.com/sean-reid/ooooh/commit/364d2f88f7073d8a7d2f7ebaea065e98a8dda2f4))
* **app:** injected dependencies are not an offline session ([#41](https://github.com/sean-reid/ooooh/issues/41)) ([1748b14](https://github.com/sean-reid/ooooh/commit/1748b146075f3f3485bf060c0f4678ba73bc67bd))
* **persistence:** keep the session summary in the store ([#45](https://github.com/sean-reid/ooooh/issues/45)) ([c364243](https://github.com/sean-reid/ooooh/commit/c3642431c54c4667650760f70740e19b77a69d99))
* **site:** the heading says one question at a time, not one per session ([#36](https://github.com/sean-reid/ooooh/issues/36)) ([42cf24f](https://github.com/sean-reid/ooooh/commit/42cf24ffb3c4d0d293c33f04e8f7dbf51fbc0fa5))
* **synth:** pace the scripts like thinking aloud and label only speakable gaps ([#21](https://github.com/sean-reid/ooooh/issues/21)) ([c1134ef](https://github.com/sean-reid/ooooh/commit/c1134ef00be98ef407dc270ff88aa58889c72d26))
* two package tests that were flaky on CI ([#27](https://github.com/sean-reid/ooooh/issues/27)) ([2fc0916](https://github.com/sean-reid/ooooh/commit/2fc091660f0327081a3ea9bd5528625df32e5356))

## 0.1.0 (2026-10-25)


### Features

* app skeleton, core packages, worker, and labeling tool ([101f779](https://github.com/sean-reid/ooooh/commit/101f779dd4711738521f4fc7e9f0593fc6d0a6dd))
* **design:** app icon rendered from the orb ([#14](https://github.com/sean-reid/ooooh/issues/14)) ([999810d](https://github.com/sean-reid/ooooh/commit/999810da8911b4a34d3883124d415ba990756be3))
* eval corpus mode, command labels, and the oracle check in CI ([#10](https://github.com/sean-reid/ooooh/issues/10)) ([40c5e76](https://github.com/sean-reid/ooooh/commit/40c5e764679ea2791f2baeb90c345780c5da58af))
* live transcription and fixture recording ([#7](https://github.com/sean-reid/ooooh/issues/7)) ([898b02d](https://github.com/sean-reid/ooooh/commit/898b02dbce7c14c17b77db3415132bae5a603054))
* orb, adaptive palette, type scale, and snapshot tests ([#8](https://github.com/sean-reid/ooooh/issues/8)) ([3f181e2](https://github.com/sean-reid/ooooh/commit/3f181e2d8f4e62da0551ba62b560ac5749ac484d))
* session loop on fixtures with an eval ([#6](https://github.com/sean-reid/ooooh/issues/6)) ([54eb850](https://github.com/sean-reid/ooooh/commit/54eb850cc0a8224fe5d5d50ec1b98545bf2b66b8))
* synthetic benchmark corpus and generator ([#9](https://github.com/sean-reid/ooooh/issues/9)) ([1ac601f](https://github.com/sean-reid/ooooh/commit/1ac601f15b531ac83d162e80ce6e9e2a151bc10a))
* worker routes for Jev, Haiku, and Sonnet with Swift clients ([#11](https://github.com/sean-reid/ooooh/issues/11)) ([4f054f9](https://github.com/sean-reid/ooooh/commit/4f054f9394792e891caccdfd99969f4da0cc9910))
* **worker:** daily provider caps and a per-device minute limit ([#12](https://github.com/sean-reid/ooooh/issues/12)) ([7ad2cfd](https://github.com/sean-reid/ooooh/commit/7ad2cfd9a43b6138cff7de17770cae804dd897c7))


### Bug Fixes

* green CI on main ([#5](https://github.com/sean-reid/ooooh/issues/5)) ([ffa0ebd](https://github.com/sean-reid/ooooh/commit/ffa0ebd2713d0319e5f1fba62aa4689c286efb7b))
