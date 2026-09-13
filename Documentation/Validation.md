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
