# Changelog

## [0.5.0](https://github.com/sean-reid/ooooh/compare/v0.4.0...v0.5.0) (2026-10-28)


### Features

* accept Sandbox purchases, add the privacy manifest, number builds from git ([#244](https://github.com/sean-reid/ooooh/issues/244)) ([3fa5630](https://github.com/sean-reid/ooooh/commit/3fa5630b6e88bb7d2c0404ff96b2766bf6f517dc))
* **governor:** warm-up floor and a longer arming delay ([#226](https://github.com/sean-reid/ooooh/issues/226)) ([f620ff6](https://github.com/sean-reid/ooooh/commit/f620ff654730bfe9af632617d9d5914d44d2a1f4))
* keep the lines the app said in the transcript with a bad mark ([#239](https://github.com/sean-reid/ooooh/issues/239)) ([deae4ef](https://github.com/sean-reid/ooooh/commit/deae4ef0d693a9948c6d33680fdf4a192626675c))
* **notes:** edit mode for session notes ([#238](https://github.com/sean-reid/ooooh/issues/238)) ([f4e9d46](https://github.com/sean-reid/ooooh/commit/f4e9d46feeaacf369daf3b88387ad57d16da483f))
* pause and resume a session from the media buttons ([#246](https://github.com/sean-reid/ooooh/issues/246)) ([e6f6bb9](https://github.com/sean-reid/ooooh/commit/e6f6bb95127baed76e2956484fc1abf509902cd8))
* start and end a session by Siri, the Action button, and media buttons ([#232](https://github.com/sean-reid/ooooh/issues/232)) ([1064fde](https://github.com/sean-reid/ooooh/commit/1064fdefbb9ee244e04c5e41d84ff2621737034d))
* sync the store to iCloud through CloudKit ([#234](https://github.com/sean-reid/ooooh/issues/234)) ([9d0f1bd](https://github.com/sean-reid/ooooh/commit/9d0f1bd2eb5fef0be33991b51c9984e337b2beda))
* **worker:** cap each device's daily spend per provider ([#236](https://github.com/sean-reid/ooooh/issues/236)) ([f6e4a60](https://github.com/sean-reid/ooooh/commit/f6e4a601c8a9aeb9126ff23c61d3c94f4aec2696))
* **worker:** forbid the why-does-it-matter frame and give deepen five moves ([#242](https://github.com/sean-reid/ooooh/issues/242)) ([33a092a](https://github.com/sean-reid/ooooh/commit/33a092a72ad3e97c094c1165eb8986bb424965a4))


### Bug Fixes

* **app:** build for iPhone only ([#247](https://github.com/sean-reid/ooooh/issues/247)) ([65bc281](https://github.com/sean-reid/ooooh/commit/65bc281eb3c54713617e8d3fbdad10e172cf9932))
* **transcription:** hold a short volatile inside a line until its final ([#241](https://github.com/sean-reid/ooooh/issues/241)) ([6e5c10a](https://github.com/sean-reid/ooooh/commit/6e5c10a09501f54223102f16ae8e496d693ef9bf))
* **worker:** answer 409 on a second notes call for a session ([#233](https://github.com/sean-reid/ooooh/issues/233)) ([21649c5](https://github.com/sean-reid/ooooh/commit/21649c54541591970c1216cec0acd9e0a7d2e09a))

## [0.4.0](https://github.com/sean-reid/ooooh/compare/v0.3.0...v0.4.0) (2026-10-27)


### Features

* **app:** show the speech model download and name each Start failure ([#188](https://github.com/sean-reid/ooooh/issues/188)) ([cdf9b84](https://github.com/sean-reid/ooooh/commit/cdf9b84eee89d22f7b9627e12ee166146b5dbdbf))
* **audio:** log each spoken line's start, cut, finish, and failure ([#197](https://github.com/sean-reid/ooooh/issues/197)) ([ccda4c8](https://github.com/sean-reid/ooooh/commit/ccda4c83fac34643fee6f2f3ab25beaca1f9f97b))
* **eval:** fit the speak policy from per-check feature rows ([#218](https://github.com/sean-reid/ooooh/issues/218)) ([885ab11](https://github.com/sean-reid/ooooh/commit/885ab116646b2089802f4c9a2e80a3770f026d46))
* **eval:** six synthetic voice sessions with Jev's answers ([#228](https://github.com/sean-reid/ooooh/issues/228)) ([7d2cf5d](https://github.com/sean-reid/ooooh/commit/7d2cf5d2e0ffb16f220bf2691fbe91e6fc85e9d8))
* **governor:** ask if finished after 45 seconds of silence ([#196](https://github.com/sean-reid/ooooh/issues/196)) ([a1253d4](https://github.com/sean-reid/ooooh/commit/a1253d4674ae513f57ffe850ad3d1bd408bb2e61))
* name the speaker's words in every line and vary the frame ([#225](https://github.com/sean-reid/ooooh/issues/225)) ([2216b50](https://github.com/sean-reid/ooooh/commit/2216b50e3f7f6a7e3d6c82bdce5897ca80452468))
* **notes:** show and export the session transcript ([#212](https://github.com/sean-reid/ooooh/issues/212)) ([d72a188](https://github.com/sean-reid/ooooh/commit/d72a188091f99b04799d73a43811a6c692b414f6))
* record-to-labels pipeline for real sessions ([#200](https://github.com/sean-reid/ooooh/issues/200)) ([f4063fb](https://github.com/sean-reid/ooooh/commit/f4063fb32ad3687aae162008e916a44aeafd1fc2))
* **session:** compact every 75 seconds or 150 words ([#207](https://github.com/sean-reid/ooooh/issues/207)) ([b0039c1](https://github.com/sean-reid/ooooh/commit/b0039c1e1f45209816038ce442d324126deb5142))
* **session:** send session counts to Jev and sweep the governor over recordings ([#204](https://github.com/sean-reid/ooooh/issues/204)) ([405ce9a](https://github.com/sean-reid/ooooh/commit/405ce9a2f1828ceb606963261c5d5a18a844d91d))
* **tools:** add a judge for the phrase line ([#201](https://github.com/sean-reid/ooooh/issues/201)) ([3a7e7d2](https://github.com/sean-reid/ooooh/commit/3a7e7d2ff2d97b4b8e0557004fef3ced068ccc17))
* **tools:** synthesize voice sessions in my style for Jev calibration ([#223](https://github.com/sean-reid/ooooh/issues/223)) ([f515538](https://github.com/sean-reid/ooooh/commit/f515538f845515017b628d5ec0b94c5a1ad0ab23))
* **worker:** phrase with six example lines in the prompt ([#209](https://github.com/sean-reid/ooooh/issues/209)) ([a1605ef](https://github.com/sean-reid/ooooh/commit/a1605ef69c5e0670d00d7186be0326ef6f0ff09d))


### Bug Fixes

* **app:** keep the microphone's echo of a spoken line from cutting it ([#210](https://github.com/sean-reid/ooooh/issues/210)) ([0cd9b25](https://github.com/sean-reid/ooooh/commit/0cd9b25a3d976ef12033850c1cc93462f0154186))
* **app:** stop re-seeding a carried thread the compactor removed ([#186](https://github.com/sean-reid/ooooh/issues/186)) ([f904b90](https://github.com/sean-reid/ooooh/commit/f904b90b72d744abaae31e192922cf86d7f81b5b))
* **audio:** level spoken prompts toward -16 dBFS ([#202](https://github.com/sean-reid/ooooh/issues/202)) ([de40505](https://github.com/sean-reid/ooooh/commit/de405055ab81898f687863b2db0c51e6c8ccc7a8))
* **audio:** report one start per line and mute test runs ([#211](https://github.com/sean-reid/ooooh/issues/211)) ([bf907ab](https://github.com/sean-reid/ooooh/commit/bf907ab42f184eccc3a55d4a66dfc498240e69c2))
* **design:** wake a paused orb when its level or phase changes ([#190](https://github.com/sean-reid/ooooh/issues/190)) ([453b2ca](https://github.com/sean-reid/ooooh/commit/453b2ca714fb5eeb13da11a2788ced559f18d1f1))
* **persistence:** name each in-memory store so two never share one ([#213](https://github.com/sean-reid/ooooh/issues/213)) ([9f068c8](https://github.com/sean-reid/ooooh/commit/9f068c8a2905651efa648826b333ee06adae2c74))
* **proxy:** replace a stored App Attest key the service refuses ([#187](https://github.com/sean-reid/ooooh/issues/187)) ([1ab419a](https://github.com/sean-reid/ooooh/commit/1ab419aedebe65399ed9927814971ee6995e5f9f))
* **site:** centre the footer and stack the credit on phones ([#208](https://github.com/sean-reid/ooooh/issues/208)) ([1bf52f8](https://github.com/sean-reid/ooooh/commit/1bf52f83f2e5465c41f16ca9a40851ebf278ee21))
* **site:** draw the App Store placeholder as a label ([#221](https://github.com/sean-reid/ooooh/issues/221)) ([7892a03](https://github.com/sean-reid/ooooh/commit/7892a03fae0d2a3064c30ebdf007c5b5278ea1f5))
* **transcription:** drop short fragments and prefix matches during a line ([#220](https://github.com/sean-reid/ooooh/issues/220)) ([f93651b](https://github.com/sean-reid/ooooh/commit/f93651b2d0e90405b0464b1ff44db67b41704ad6))
* **transcription:** finalize dictation after a one second pause ([#192](https://github.com/sean-reid/ooooh/issues/192)) ([4660557](https://github.com/sean-reid/ooooh/commit/4660557d6a764f2fb62a87532507cd771cbee8c3))
* **transcription:** time echo windows on the microphone's clock ([#227](https://github.com/sean-reid/ooooh/issues/227)) ([f9db83a](https://github.com/sean-reid/ooooh/commit/f9db83af141aac43f857327185d869754ee47cba))
* **worker:** log every structured answer the validator rejects ([#198](https://github.com/sean-reid/ooooh/issues/198)) ([9a28537](https://github.com/sean-reid/ooooh/commit/9a285371ebe1bad60e30a8279c69998f5a887390))


### Performance

* **app:** keep launch work off the first frame and build sessions through SessionAssembly ([#215](https://github.com/sean-reid/ooooh/issues/215)) ([7cb5e06](https://github.com/sean-reid/ooooh/commit/7cb5e06d6b249440c92b88b1958585aed17d2af4))
* **design:** cache the orb's halo and halve its frame rate in a flat room ([#214](https://github.com/sean-reid/ooooh/issues/214)) ([e58122d](https://github.com/sean-reid/ooooh/commit/e58122d39d34fc05973c08430ace2424286e0e20))

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
