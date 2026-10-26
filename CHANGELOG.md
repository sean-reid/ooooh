# Changelog

## [0.3.0](https://github.com/sean-reid/ooooh/compare/v0.2.0...v0.3.0) (2026-10-26)


### Features

* **app:** attest in production from development builds ([#114](https://github.com/sean-reid/ooooh/issues/114)) ([9211082](https://github.com/sean-reid/ooooh/commit/9211082cc2a509b423f0485d44315240ec8cd481))
* **app:** session gating through the Worker and the paywall after the last free session ([#72](https://github.com/sean-reid/ooooh/issues/72)) ([be69b64](https://github.com/sean-reid/ooooh/commit/be69b64d88e150ac015e1380d4f7c2e560b75cee))
* **app:** settings from the home screen, signed purchases, and refused sessions off the Worker ([#81](https://github.com/sean-reid/ooooh/issues/81)) ([c41a668](https://github.com/sean-reid/ooooh/commit/c41a6684b972c132206e3a6d1eb338cc32d98c51))
* **billing:** post each verified transaction to the Worker ([#151](https://github.com/sean-reid/ooooh/issues/151)) ([0e4a918](https://github.com/sean-reid/ooooh/commit/0e4a918dbda2c88abcf9713a972ddf0ac4808e5d))
* **store:** render the product-page header and search artwork ([#110](https://github.com/sean-reid/ooooh/issues/110)) ([504475e](https://github.com/sean-reid/ooooh/commit/504475e05f819956c75421326a8af8b0e747e251))
* **tools:** render the App Store screenshots and cut the preview ([#89](https://github.com/sean-reid/ooooh/issues/89)) ([cb1d202](https://github.com/sean-reid/ooooh/commit/cb1d202891c78cfc9458c1ed6dbb20821c4e5b77))
* **tools:** seed the store stand-in from one real run ([#102](https://github.com/sean-reid/ooooh/issues/102)) ([928b4c7](https://github.com/sean-reid/ooooh/commit/928b4c7962cf8834aec4ad4c46c870ecf2fbf223))
* transcribe on phones that lack SpeechTranscriber ([#153](https://github.com/sean-reid/ooooh/issues/153)) ([121751c](https://github.com/sean-reid/ooooh/commit/121751c703da638745746b8cb81801b722de0dcb))
* **transcription:** log the engine probe, the tap, and the first result ([#178](https://github.com/sean-reid/ooooh/issues/178)) ([25c87ad](https://github.com/sean-reid/ooooh/commit/25c87adf3c4e70193a7ebbbaa7ef68b3d9ffbe6f))
* **worker:** gate provider routes on an open session and weight the Anthropic cap ([#77](https://github.com/sean-reid/ooooh/issues/77)) ([82b3b6d](https://github.com/sean-reid/ooooh/commit/82b3b6d836ecd4565ddf10e679ee221f063b9e0e))


### Bug Fixes

* 44 pt tap targets, 3:1 component edges, VoiceOver prompts, one amber style ([#165](https://github.com/sean-reid/ooooh/issues/165)) ([e286b76](https://github.com/sean-reid/ooooh/commit/e286b76b3fce6a0a7c8e93bb76041a32b4811f51))
* accent token for the paywall text and the history tint ([#112](https://github.com/sean-reid/ooooh/issues/112)) ([95e210e](https://github.com/sean-reid/ooooh/commit/95e210e7d364a97ab3d56822c3893fd25b235d01))
* **app:** bill and show the same session minutes, wall clock from start to End ([#184](https://github.com/sean-reid/ooooh/issues/184)) ([69705bf](https://github.com/sean-reid/ooooh/commit/69705bffd09400881337b11842d15d20aadc9c00))
* **app:** bundle the one decision fixture from the eval corpus ([#162](https://github.com/sean-reid/ooooh/issues/162)) ([c4d0312](https://github.com/sean-reid/ooooh/commit/c4d0312281910301a8148ed683c927a5960a0e72))
* **app:** declare local network use so a Debug build can reach a Mac Worker ([#175](https://github.com/sean-reid/ooooh/issues/175)) ([e8d17eb](https://github.com/sean-reid/ooooh/commit/e8d17eb3aee3807bbd362cd2d3b11a230eb38c61))
* **app:** draw the pending notes Done label in ink on amber ([#116](https://github.com/sean-reid/ooooh/issues/116)) ([01af27a](https://github.com/sean-reid/ooooh/commit/01af27a285476a892b6a755c93200769e4a98b47))
* **app:** no audio engine at session start, and UI tests that wait on conditions ([#159](https://github.com/sean-reid/ooooh/issues/159)) ([a55640e](https://github.com/sean-reid/ooooh/commit/a55640e3acbb0af80351d47ef51f5288f6bf2ce2))
* **app:** one cancellation path for End, barge-in, and a cancelled arm ([#181](https://github.com/sean-reid/ooooh/issues/181)) ([4213b89](https://github.com/sean-reid/ooooh/commit/4213b894db345d704bbb508f969cafe7c1591ed7))
* **app:** open a Worker session for the demo too ([#94](https://github.com/sean-reid/ooooh/issues/94)) ([b03af8a](https://github.com/sean-reid/ooooh/commit/b03af8ab27643eb5167663f7103964d5b6bdb84e))
* **app:** read phone microphone levels and log why the Worker went offline ([#182](https://github.com/sean-reid/ooooh/issues/182)) ([b5cf7f1](https://github.com/sean-reid/ooooh/commit/b5cf7f13393eab337047bff7846cf2f4b65b4107))
* bind a StoreKit transaction to the install that posts it ([#69](https://github.com/sean-reid/ooooh/issues/69)) ([0adc822](https://github.com/sean-reid/ooooh/commit/0adc82271e2d9303ea7a2d22aa9326a64bce3bd2))
* bind assertions to the route and time, and keep the counter on re-attest ([#68](https://github.com/sean-reid/ooooh/issues/68)) ([4d31bbe](https://github.com/sean-reid/ooooh/commit/4d31bbe97575c735c9358cea6c5764c123000520))
* **eval:** open a session and honor the rate limit in live recording ([#113](https://github.com/sean-reid/ooooh/issues/113)) ([32090e0](https://github.com/sean-reid/ooooh/commit/32090e099add6ba0c83851afb4b2524a944af819))
* learn the Worker's clock from a stale 401 and stop promising notes ([#173](https://github.com/sean-reid/ooooh/issues/173)) ([28d5023](https://github.com/sean-reid/ooooh/commit/28d5023f8ee0b6031b1623de1b7cf93f5221c637))
* paywall empty state and the in-app policy's server records ([#105](https://github.com/sean-reid/ooooh/issues/105)) ([eb5c9c6](https://github.com/sean-reid/ooooh/commit/eb5c9c6bfa0d951df66691f822f1479cd9bbfe10))
* **proxy:** check the attest key id write and fetch the challenge before the key ([#172](https://github.com/sean-reid/ooooh/issues/172)) ([18db971](https://github.com/sean-reid/ooooh/commit/18db971516c81defdd4631f082876d8582d55fc4))
* seed the demo history from one bundled notes JSON ([#171](https://github.com/sean-reid/ooooh/issues/171)) ([744e405](https://github.com/sean-reid/ooooh/commit/744e405684370cccee55c5e2831592f676528827))
* **session:** keep the last sentence on End, compact once, and check with recent words ([#179](https://github.com/sean-reid/ooooh/issues/179)) ([95a605a](https://github.com/sean-reid/ooooh/commit/95a605a542d1fa4d74754689872190957c582ebf))
* **settings:** wire the Challenge prompts and Quiet mode switches ([#180](https://github.com/sean-reid/ooooh/issues/180)) ([1be44af](https://github.com/sean-reid/ooooh/commit/1be44af277d2fd3c133cb116cf16953c46d9200d))
* **site:** set each section on a centred 48ch measure ([#96](https://github.com/sean-reid/ooooh/issues/96)) ([dff9514](https://github.com/sean-reid/ooooh/commit/dff9514b6903d5e58092831c99a14cd28dba1ec9))
* **worker:** Anthropic body deadlines and fixed 502 detail ([#97](https://github.com/sean-reid/ooooh/issues/97)) ([dbb33eb](https://github.com/sean-reid/ooooh/commit/dbb33eb6b9ff38b888b3a79e0c2f0b41d4ed7a6a))
* **worker:** count free sessions once the phone starts and move the counters into Durable Objects ([#169](https://github.com/sean-reid/ooooh/issues/169)) ([952b44e](https://github.com/sean-reid/ooooh/commit/952b44ee483b97cf41a8252b7ab277b71bd7cb3e))
* **worker:** move a subscription claim to the key that posts it after the old key goes quiet ([#183](https://github.com/sean-reid/ooooh/issues/183)) ([f186e0d](https://github.com/sean-reid/ooooh/commit/f186e0d2e237682131145220df9c501414c84284))
* **worker:** rate-limit challenge and attest per client address ([#79](https://github.com/sean-reid/ooooh/issues/79)) ([2c822d3](https://github.com/sean-reid/ooooh/commit/2c822d34b60647682d3885bf4943d91115794bfb))
* **worker:** run charges on one budget key in order ([#111](https://github.com/sean-reid/ooooh/issues/111)) ([5d137b5](https://github.com/sean-reid/ooooh/commit/5d137b50da1174d3f998a395583ffbf5c00c5a0e))
* **worker:** take Jev's legend as the object it sends ([#90](https://github.com/sean-reid/ooooh/issues/90)) ([0fdd7f5](https://github.com/sean-reid/ooooh/commit/0fdd7f503c24fabbc3fdbc7a05c35be8e07b69c4))
* **worker:** the audit's quick wins, and a README a third the size ([#66](https://github.com/sean-reid/ooooh/issues/66)) ([284fca7](https://github.com/sean-reid/ooooh/commit/284fca7d8a7d3c997c8b8511e797fc789cf2d079))
* **worker:** validate the whole Jev reply before it reaches the phone ([#73](https://github.com/sean-reid/ooooh/issues/73)) ([ae7d630](https://github.com/sean-reid/ooooh/commit/ae7d63020c61dfe0be86dd3b034429554d436601))


### Performance

* **design:** pause the orb timeline once it rests ([#166](https://github.com/sean-reid/ooooh/issues/166)) ([733f9fb](https://github.com/sean-reid/ooooh/commit/733f9fbe2cc1b5d61329142f86190892f4c27008))
* **governor:** check on a silence schedule instead of every 3 s ([#160](https://github.com/sean-reid/ooooh/issues/160)) ([90182a3](https://github.com/sean-reid/ooooh/commit/90182a3c19d1a94a66d0e8f223c1b1554bbd2acd))
* **history:** bound the history queries and surface a failed delete ([#163](https://github.com/sean-reid/ooooh/issues/163)) ([65fe68b](https://github.com/sean-reid/ooooh/commit/65fe68b36fc0e748d884b59a7a7d0ce24e6b6c09))
* **site:** pause the orb out of view, shrink the screenshot, fix link rows ([#164](https://github.com/sean-reid/ooooh/issues/164)) ([3029f1b](https://github.com/sean-reid/ooooh/commit/3029f1bf7487c801e40b116e8d6034cd2a88fef3))
* **worker:** call ElevenLabs with fetch and put a deadline on the audio body ([#75](https://github.com/sean-reid/ooooh/issues/75)) ([bad5d81](https://github.com/sean-reid/ooooh/commit/bad5d81fcc0c5a1b7b0539ccd6ca88fcf9fe655f))
* **worker:** take KV writes off the hot path and move the assertion counter into a Durable Object ([#100](https://github.com/sean-reid/ooooh/issues/100)) ([7833bbc](https://github.com/sean-reid/ooooh/commit/7833bbcfb22b07406e0e6bcff2bc64e352b5bc15))

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
