# MVP Validation Status

Validation date: 2026-09-19/20
Xcode: 27.0 (27A266a)
Primary simulator: iPhone 18 Pro (`1A931676-E2F0-4DFF-AD3E-01E61E382414`)

| Criterio | Estado | Evidencia | Pendiente |
|---|---|---|---|
| Core app compiles on iPhone Simulator | PASS | Debug `xcodebuild build` succeeded with iOS Simulator 27.0; app installed and launched. | None for build gate. |
| Core test suite | NO VERIFICADO | `scripts/run-tests.sh vreaderTests` compiled the app/tests and began tests, but both 900-second runs ended by watchdog timeout; no assertion failure was reported. | Complete the full suite with a longer execution window or narrower CI lanes. |
| Library on iPhone | NO VERIFICADO | Library state was exercised by reset/seed/open through DebugBridge, but no standalone iPhone library screenshot was captured. | Capture library screen explicitly. |
| EPUB opens | PASS | `mini-epub3` opened through `vreader-debug://open`; screenshot showed `VReader Mini EPUB Fixture`. | None for this fixture. |
| Readium EPUB rendering | PASS | Readium 3.9.0 products resolved and the default EPUB reader rendered the fixture with styled chapters and controls on iPhone. | Add a stronger engine-identity assertion to the runtime snapshot. |
| EPUB navigation | PASS | `vreader-debug://navigate?spine=1&fraction=0.5`; screenshot and chrome changed to `Chapter 2 of 2`. | None for this navigation path. |
| Visual advance updates one durable ReadingPosition | NO VERIFICADO | Navigation changed the visible chapter indicator, but DebugBridge snapshots reported `position: null`; no durable locator assertion was available. | Expose/verify the persisted canonical ReadingPosition through the runtime harness. |
| READ → PLAY starts from visual position | NO VERIFICADO | TTS snapshot reported `ttsState: speaking` and `ttsOffsetUTF16: 84`, but the exact visual-to-audio locator mapping was not independently observable. | Add a runtime assertion linking the visual locator and TTS start offset. |
| TTS chunks correspond to visual position | NO VERIFICADO | No chunk identity was exposed by the runtime snapshot. | Add chunk/locator evidence to the verification harness. |
| Audio progress updates the same ReadingPosition | NO VERIFICADO | No persisted position was exposed in the snapshot after TTS start. | Verify the shared store after audio progress. |
| PAUSE returns reader to reached point | NO VERIFICADO | The TTS control driver (`idb`) is unavailable in this environment, so Pause could not be pressed through the real control. | Install/enable the repository gesture driver and repeat. |
| Resume continues from paused point | NO VERIFICADO | Same limitation as Pause/Resume. | Repeat with real accessibility gesture control. |
| Kill/reopen restores exact position | NO VERIFICADO | Reopen returned to the EPUB with `Chapter 2 of 2`, but exact locator/progression remained `null` in DebugBridge state. | Verify exact href/progression after relaunch. |
| Google Cloud TTS / `es-US-Wavenet-B` | NO VERIFICADO | No Google API key was provided or confirmed in the simulator; observed TTS state was not sufficient to prove Google HTTP usage. | Enter the key manually in HTTP TTS settings and repeat network/audio validation. |
| API key stored in Keychain | NO VERIFICADO | The UI/code path uses Keychain, but no key was entered for this run. | Manually enter a test key and verify only presence/behavior, never its value. |
| MP3 Base64 decode, speed, cache | NO VERIFICADO | No Google response was available in this run. | Repeat after configuring Google Cloud TTS. |
| iPad build | PASS | Debug `xcodebuild build` succeeded for iPad Air 11-inch (M4), UDID `931DA81B-B440-4863-BCA0-17F5D60BF4DF`. | None for build gate. |
| iPad app opens | PASS | App installed/launched; after initialization the library screen rendered. | None. |
| iPad library/layout | PASS | Screenshot showed usable iPad library layout, controls, empty state, and import action. | None for the empty-library surface. |
| iPad reader/TTS controls | NO VERIFICADO | The iPad fixture seed did not produce an imported EPUB file, so reader/control validation was not executed there. | Seed/import an EPUB on iPad and repeat the limited reader check. |

No CloudKit, cross-device sync, Mac, PDF, OpenAI, ElevenLabs, or visual redesign work was implemented.

Checkpoint exception: no executable Git hook or configured `core.hooksPath` was found. The full validation suite had already been run twice and exceeded its 900-second watchdog, documented above as NO VERIFICADO. The checkpoint commit therefore used `--no-verify` after the staged diff passed `git diff --cached --check`; no validation hook was skipped.
