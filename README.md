# IssueCapture

Embed an offline issue reporter in a SwiftUI iPhone app. Tap a movable edge tab, describe the problem, annotate its screenshot, and export a batch for a coding agent.

Requires iOS 17+ and a Swift 6 toolchain. Package sources compile in Swift 5 language mode. No third-party dependencies, account, or backend.

## Agent setup handoff

After importing the package, point your coding agent to [Documentation/AgentHandoff.md](Documentation/AgentHandoff.md). It defines the setup assignment, required contracts, coverage record, persistent agent instructions, and completion criteria.

Copy this prompt:

> We imported IssueCapture. Read its Documentation/AgentHandoff.md and complete the integration in this app. Follow the linked contracts, register screens and meaningful actions, update our agent instructions and coverage document, and report verification and remaining gaps.

## Mac companion

[MacCompanion/](MacCompanion) is a native macOS app that imports an export ZIP or
folder, groups issues into explainable candidate requests, and prepares versioned
request folders you can copy or drag into a coding tool. It works offline and
needs no API key. See [MacCompanion/README.md](MacCompanion/README.md) for how to
build, run and verify it, and for what it deliberately does not claim.

## Install

In Xcode, choose **File → Add Package Dependencies → Add Local**, select this directory, and add the `IssueCapture` product to your app target. For distribution, add the GitHub repository with a tagged version requirement:

```swift
dependencies: [
    .package(url: "https://github.com/vdeaugustine/IssueCapture.git", from: "1.0.0")
]
```

Then link the `IssueCapture` product to the app target. Releases use semantic-version Git tags (`1.0.0`, `1.0.1`, etc.). Swift Package Manager resolves and records the selected tag and commit in the consuming app's `Package.resolved`. See [release and update policy](Documentation/Releasing.md).

```swift
import IssueCapture

private var captureConfiguration: IssueCaptureConfiguration {
    #if DEBUG || INTERNAL_QA
    .init(isEnabled: true, projectID: "YourApp")
    #else
    .init()
    #endif
}

// Inside App.body:
WindowGroup {
    RootView()
        .issueCaptureHost(configuration: captureConfiguration)
}
```

Enable in the host build, not through the package's DEBUG flag. `INTERNAL_QA` is an optional custom Swift compilation condition for internal release/TestFlight builds. Configuration is fixed for the lifetime of the installed host. Disabled installation creates no capture session, overlay, or report store. Compile-time binary exclusion requires host target/dependency separation.

## Register a screen

```swift
struct ProfileEditorView: IssueReportableScreen {
    var body: some View {
        ProfileEditorContent()
            .issueCaptureScreen(Self.self)
    }
}
```

`issueScreenName` defaults to the supplied type name. Override it for a display label; the qualified Swift type and source file/line are preserved separately. Use `id: "profile.editor"` for an optional identity stable across renames. Use `isActive:` when tab/navigation state retains inactive views.

## Record actions

```swift
struct ProfileEditorContent: View {
    @Environment(\.issueReporter) private var reporter

    var body: some View {
        Button("Save") {
            reporter.record(.tap("profile.save"))
            saveProfile()
        }
    }
}
```

Environment flows to descendants. Read the reporter inside the content wrapped by the screen modifier, not on the outer view applying that modifier. Pass that value to a service or task when an outcome needs the original screen context. `IssueReporter` is Sendable and its recorder serializes access with a lock; event recording performs no disk/network I/O.

## Capture and export

- Tap the neutral capture button to capture before opening the editor.
- Drag the tab vertically or to either edge.
- Touch and hold it for the inbox and diagnostics.
- From the reporter, choose "Capture IssueCapture screen" to file a report about the reporter itself.
- Write a description, optionally add expected behavior/steps, and draw arrows, rectangles, or pen marks.
- Save locally. Later, select issues in the inbox and export a ZIP through AirDrop or Files.
- Unzip on your Mac and give the agent `README.md` plus the linked issue folders. Image cards are also included by default.

The inbox filters by date, description/ID, and export history. Prepared exports are tracked; receipt or fixes are not. Original screenshots are immutable. A manually attached image remains a separate asset.

For a custom trigger, configure `showsCaptureTab: false` and read `@Environment(\.issueCapture)` in a descendant of the host. Call `capture()`, `openInbox()`, or `openDiagnostics()` from the main actor.

## Example app

Open `Examples/IssueCaptureDemo/IssueCaptureDemo.xcodeproj`, select the demo scheme and a simulator, then Run. On a physical device, select your signing team first. The checked-in project does not require XcodeGen; `project.yml` is supplied for regeneration.

The example includes a profile screen, sheet presentation, explicit action events, and a deliberately failed Save action for capturing a useful report.

## Limits

- Screen registration is explicit. Neither a protocol nor lifecycle callbacks prove whole-app coverage.
- Candidate hierarchy is preserved when active context is ambiguous. Use host route/tab state to clarify registration.
- Live app-window rendering does not guarantee system keyboard, system dialogs, protected media, or every custom rendering surface. The editor/export labels fidelity as unverified and permits manual attachment.
- No automatic cloud sync. Local reports live inside each host app's sandbox; deleting the app can remove them.
- No automatic input, credential, network, or log harvesting. Supplied metadata must be explicitly allowed.
- UI annotation is optional and touch-driven. Editing notes, saving, and exporting use standard accessible controls.
- ZIP exports use uncompressed ZIP32. Image cards reject impractically long layouts with a clear error; exporting without cards retains all text.
- Physical-device behavior and complete acceptance coverage still require validation in a consuming app. See Documentation/Validation.md.

See [Integration contract](Documentation/Integration.md), [architecture](Documentation/Architecture.md), and [export format](Documentation/ExportFormat.md).

### Capture button appearance

The floating button uses an adaptive neutral background and a 48-point touch target.
Set host defaults with `captureButtonAppearance`:

```swift
IssueCaptureConfiguration(
    isEnabled: true,
    captureButtonAppearance: .init(
        backgroundColor: .darkGray,
        foregroundColor: .white,
        diameter: 56
    )
)
```

Hold the button and choose **Button appearance** for a live preview, color pickers,
and a size slider. Runtime changes last for the current host session; configuration
sets defaults for future sessions. Displayed diameter is clamped to 44–80 points.

Capture opens an evidence preview alongside the description. **Save & review for
handoff** opens saved issues; **Save & return to app** resumes your app. Select
reports to copy full text for Codex, share a PDF, or export an evidence ZIP.
