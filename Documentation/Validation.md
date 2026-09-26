# Validation record

Built September 12, 2026 with Xcode 26.5 (17F42), using iOS 26.5 SDK and an iPhone 17 simulator.

## Completed during implementation

- IssueCapture library build for generic iOS Simulator: succeeded.
- IssueCapture library build for generic iOS device: succeeded, signing disabled.
- Example app Debug build and launch on iPhone 17 simulator: succeeded.
- Example app Release build for generic iOS device: succeeded, signing disabled.
- Navigated to the example profile screen and activated its intentionally failing Save action.
- Captured a report using the floating tab, entered a description, and saved.
- Inspected stored metadata: DemoProfileScreen type/source context and profile.save/profile.save_failed events were paired correctly.
- Exported the saved report with Markdown, JSON, original screenshot, manifest, README and image card. Read every ZIP entry successfully, including CRC verification.
- Inspected the image card visually: description readable, correct error screenshot, no capture tab in the captured image.
- Relaunched the demo, reopened the stored report, edited expected behavior, and saved successfully.
- Corrected underlying host accessibility exposure during reporter presentation; a subsequent runtime snapshot contained reporter controls without the host controls.
- Source files remain focused and below the 500-line limit.

No XCTest or other test suite was run. Simulator walkthrough and archive inspection were development checks performed before completion.

## Remaining validation in a consuming app

- Physical-device capture fidelity, keyboard-visible forms, rotation and system/embedded rendering surfaces.
- Sheet/full-screen capture across the host's own presentation structure.
- Dragging, annotation tools, manual photo attachment and accessibility on physical hardware.
- Five-report batch export, multiple scenes, retained tabs and asynchronous outcomes under real app navigation.
- Forced disk failure/interrupted writes and very large reports/images.
- Runtime confirmation of disabled production builds, including the host's own build configuration.
- Actual AirDrop/Files handoff between a physical phone and Mac.

These unverified cases are not claimed as passed. Capture status explicitly describes rendering fidelity as unverified; manual image attachment is available when the app-window snapshot is incomplete.

## Reporting and export polish — 2026-09-14

- iOS Simulator package build passed using `xcodebuild -scheme IssueCapture
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`.
- Added optional tag decoding for older records; export links use the filenames
  produced by per-image encoding, including PNG fallback when JPEG is larger.
- Tests were not run, per repository instructions. Interactive device validation
  remains pending for annotation gestures, Photos selection, VoiceOver, and sharing.

## 2026-09-22 — Direct issue handoffs

- iOS Simulator build passed using the IssueCapture scheme, generic simulator
  destination, and code signing disabled (arm64 and x86_64).
- `git diff --check` passed. Changed source files remain below 500 lines.
- Tests not run, per repository instructions.
- Runtime PDF pagination, image appearance, clipboard acceptance in Codex, and
  system share-sheet delivery have not been manually verified. Clipboard PDF
  support depends on the receiving app; Share PDF provides a file fallback.

## 2026-09-23 — Capture and handoff UI polish

- iOS demo and package dependency compiled for generic iOS Simulator with code
  signing disabled using the IssueCaptureDemo scheme.
- Mac companion compiled with `swift build --package-path MacCompanion`.
- Simulator launch and screenshots confirmed adaptive neutral capture control
  and the evidence-first editor. Automated text entry did not change the field,
  so save/review navigation and interactive appearance controls are not claimed
  as runtime verified. Latest compact preview adjustment was build-verified.
- `git diff --check` passed; changed Swift source files stay below 500 lines.
- Tests not run, per repository instructions. Physical-device checks, VoiceOver,
  accessibility text sizes, color contrast for custom colors, and end-to-end
  copy/PDF/ZIP delivery remain release validation items.

## 2026-09-25 — Unity iOS / iOS 15 support

See [UnityValidation.md](UnityValidation.md) for package and native builds, Unity
C# compilation, production import-table checks, and simulator capture/edit/ZIP
verification. Full Unity IL2CPP/device and iOS 15 runtime acceptance remain open;
no test suites were run.
