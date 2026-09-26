# Unity integration validation — 2026-09-25

These checks apply to the new Unity integration, not the published 1.7.1 release.
No XCTest, Unity Test Framework, or repository test suites were run. Builds,
package resolution, assembly inspection and interactive simulator checks were
performed during implementation, in accordance with repository policy.

## Passed

- `swift package dump-package` resolves the manifest with iOS 15 and the new
  `IssueCaptureUnity` library product.
- Xcode 27 / Swift 6 toolchain: `IssueCaptureUnity` built for generic iOS device
  (arm64) and simulator with iOS 15 deployment minimum, signing disabled.
  The existing SwiftUI `IssueCapture` package also compiled during the change.
- Unity **6000.2.13f1** batch-mode import of a temporary project with this local UPM
  dependency compiled `VinWare.IssueCapture`, its editor assembly, and the imported
  Boardwalk/Clean sample. No sample compilation errors were reported.
- Unity's bundled Roslyn compiler separately compiled the runtime with
  `UNITY_IOS,DEVELOPMENT_BUILD`, `UNITY_IOS`, and `UNITY_EDITOR`. The actual iOS
  postprocessor compiled against Unity 6.2's `UnityEditor.iOS.Extensions.Xcode.dll`.
- Managed assembly import-table inspection found **five** native imports in the
  development assembly and **zero** in the production assembly.
- The actual postprocessor's source-copy and PBX configuration methods ran against
  an XcodeGen fixture with Unity-iPhone and UnityFramework targets. Xcode resolved
  `IssueCaptureSupport/Package` locally, without fetching another native version.
  This caught and corrected the nested PBX requirement-object replacement before
  successful resolution/build.
- The Objective-C++ adapter and Swift C ABI linked through UnityFramework into the
  app. The native fixture launched on an **iPhone 16 / iOS 18.4 simulator**.
- Native initialization, scoped diagnostics and PNG capture opened the actual
  IssueCapture editor. The supplied image preview contained the fixture app before
  reporter presentation. The fixture supplies a UIKit PNG, not Unity Metal pixels.
- A background outcome recorded after Boardwalk disposal and Clean activation
  retained Boardwalk's original context. Saved/exported report context named Clean;
  `boardwalk.load_complete` still named Boardwalk.
- Entered a description, saved, reopened, edited, and saved again through native
  UI. The stored description reflected the edit. SHA-256 of the saved original
  screenshot remained unchanged after editing and exporting.
- Prepared a ZIP from the native inbox. Visual inspection confirmed the system
  share sheet with Copy / Save to Files. Read the generated archive and verified
  manifest, Markdown, JSON, image manifest, original PNG and image card entries;
  exported description equaled stored text and screen/event origins matched.
- `git diff --check` passed. New/changed code files remain below 500 lines.

## Remaining gaps

- The installed Unity editor has **no iOS Build Support module**. No full Unity
  IL2CPP player, Unity-export callback invocation, signed app/archive, or production
  Unity player was built. The postprocessor's underlying methods and API signatures
  were exercised separately; that is not a full Unity build.
- Unity 6000.0 is the declared minimum, but only 6000.2.13f1 assemblies/editor were
  available. Validate other Unity 6 and Xcode 16+ versions in the consumer's CI.
- No iOS 15/16 runtime or physical device was available for this check. Availability
  was compiler-checked at iOS 15, but fallback navigation, TextEditor, legacy
  UIWindow-without-scene attachment, orientation and keyboard behavior need device
  or matching simulator validation. The iOS 18.4 fixture window had a windowScene.
- Actual Metal/uGUI end-of-frame fidelity, transient GPU/PNG memory pressure,
  IL2CPP byte-array marshaling, app pause/resume, background timeout, input/audio
  restoration and native overlays are not proven by a UIKit fixture.
- Retained panels, additive scenes, overlay precedence/ambiguity, surface limits,
  queue saturation and repeated shutdown/reinitialization are implemented but have
  not received full runtime acceptance coverage.
- Annotation gestures, Photos selection, PDF/clipboard delivery, VoiceOver and
  dynamic type remain consumer acceptance checks. ZIP generation and share-sheet
  presentation were observed; no AirDrop/Files delivery to another app was made.
- No Rinse & Reveal source was changed. Its actual controllers, canvases, routes,
  build settings, visibility transitions and sensitive screens still need the
  coverage inventory described in UnityIntegration.md.

## Repeating the checks

Use the repository's current validation policy. Native build commands:

```sh
swift package dump-package
xcodebuild -scheme IssueCaptureUnity -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -scheme IssueCaptureUnity -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

The native fixture lives under `Unity/Native~/Fixture` so Unity never imports it
into a consumer. Its README describes generation. For actual adoption, import the
UPM sample into a Unity 6 project with iOS Build Support, then:

1. Export a fresh development project; resolve and build both UnityFramework and
   Unity-iPhone. Confirm no hand edits are necessary after a second fresh export.
2. Visit Boardwalk, retained Play/Inventory, Pause overlay and Clean; inspect
   diagnostics and verify each explicit activity transition and async origin.
3. Capture representative Metal/uGUI screens in both orientations. Save, relaunch,
   edit, annotate, attach, export, and inspect text/image pairing on iOS 15 and a
   current iOS device. Confirm original screenshot hashes do not change.
4. Export a fresh non-development player. Confirm no IssueCaptureSupport directory,
   package reference or native imports; no capture controls, runner, frame readback,
   overlay, recording or report-storage creation at runtime.
5. Attempt reuse of a development export for production and confirm the build
   rejects it, requiring a clean export. Keep Development Build disabled for
   production even if Xcode's archive configuration is Release.
