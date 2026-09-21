# IssueCapture Swift Package Specification

Status: Proposed v1 specification. APIs below describe intended behavior, not an implemented library.

## Purpose

Let a developer using an iPhone app capture an issue at the moment it occurs, including a screenshot, description, screen identity, and recent diagnostic events. Persist reports offline and export a batch for AI coding agents when the developer returns to their computer.

## Product decisions

- Native Swift package embedded in existing SwiftUI apps.
- Proposed minimum deployment target: iOS 17; confirm during implementation planning.
- No account, backend, companion app, or network connection required for v1.
- A movable edge tab opens the reporter over the app's active scene.
- The reporter can explicitly self-capture its current screen for dogfooding and improvement reports.
- Capture the app and freeze context before presenting the reporting interface.
- Require only an issue description; support keyboard dictation through the standard text input system.
- Register screens through a protocol and modifier; record actions explicitly through scoped reporting context.
- Store original screenshots and editable report text separately. Generate combined image cards for sharing.
- Export Markdown, JSON, and images together in a ZIP archive.
- Enable explicitly in approved development/internal builds; disabled by default.

## Scope

### Required for v1

1. Package installation and explicit host configuration.
2. Scene-aware floating capture control, including access over sheets and full-screen app presentations.
3. Screenshot capture before reporter presentation.
4. Description editor with screenshot preview.
5. Arrow, rectangle, and freehand annotations with undo and reset.
6. Screen identity protocol, source location, and scoped event recording.
7. Bounded recent event history frozen per report.
8. Persistent local report inbox, editing, deletion, and batch selection.
9. ZIP export and optional per-issue PNG cards through the system share sheet.
10. Diagnostics panel showing registered context, recent events, and missing-context warnings.
11. Package integration contract for agents and host AGENTS.md reference text.

### Deferred

- Automatic cloud sync and a shared cross-app inbox.
- Dedicated Mac app, PDF export, screen recording, and voice recording/transcription service.
- Automatic semantic discovery of arbitrary SwiftUI actions or source view names.
- Automatic network interception, unrestricted log ingestion, or app-state replay.
- Automatic issue fixing, uploads, or agent execution.
- Mandatory migration to package-owned navigation, buttons, or screen architecture.

## Capture workflow

1. Developer taps the edge tab while the issue is visible.
2. Recorder reserves an issue UUID and freezes timestamp, active screen stack, metadata, and recent events.
3. For a host capture, the capture service excludes its own UI and snapshots the relevant app scene before opening the editor or changing keyboard focus. An explicit reporter self-capture snapshots the visible reporter window instead.
4. Editor presents the screenshot and focuses the description field.
5. Developer describes the problem and optionally annotates the screenshot or adds expected behavior and reproduction notes.
6. Save durably persists the report and assets, then closes the reporter.
7. Developer resumes testing. The capture flow does not navigate the host app.

Cancel discards a new draft only after confirming when user-authored content would be lost. Capture failure must still allow a text-only report or manual image attachment. Repeated capture taps must not create overlapping editors.

Original screenshot is immutable. Annotations remain editable and render into a separate derivative. Annotations never overwrite original evidence.

## Capture control

- Default: small edge tab that can move vertically and switch sides.
- Respect safe areas and persist position per scene configuration.
- Provide an accessible label and adequate touch target.
- Do not intercept touches outside the control or reporter.
- Host may hide the tab and invoke capture programmatically.
- Include access to the issue inbox and diagnostics panel.
- Reporter must work over host sheets/full-screen covers without dismissing them.
- The implementation must scope any overlay window to its owning UIWindowScene and restore focus after dismissal.
- Permission dialogs and other system-owned surfaces are outside the guaranteed capture/control scope.

## Proposed public API

These signatures establish intent; implementation may refine naming while preserving the contract.

```swift
/// A screen that exposes an identity for issue reporting.
public protocol IssueReportableScreen: View {
    static var issueScreenName: String { get }
}

public extension IssueReportableScreen {
    static var issueScreenName: String {
        String(describing: Self.self)
    }
}
```

The package stores both the display name and a qualified type name derived from the supplied type. A display-name override does not replace source identity. Type names are diagnostic labels, not stable database keys across refactors.

```swift
struct ProfileEditorView: IssueReportableScreen {
    var body: some View {
        ProfileEditorContent()
            .issueCaptureScreen(Self.self)
    }
}
```

`issueCaptureScreen` accepts only `IssueReportableScreen.Type` through a generic constraint. Default `#fileID` and `#line` arguments record the modifier call site. Optional explicit stable screen ID supports hosts that need identity across renames.

The modifier injects reporting context into its descendants:

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

Environment values flow downward. A property wrapper on the same outer view that applies the modifier does not automatically receive that modifier's injected value. Documentation must demonstrate descendant content as above and provide an explicit scoped reporter for handlers owned outside that subtree.

Host installation attaches once per scene root:

```swift
WindowGroup {
    RootView()
        .issueCaptureHost(configuration: captureConfiguration)
}
```

Configuration includes enabled state, project identifier, allowed metadata provider, history limits, and retention limits. The default configuration is disabled. Configuration must not rely solely on the package target's own `DEBUG` compilation condition.

## Screen context semantics

- Register navigable screens, tabs when they represent distinct destinations, sheets, and full-screen destinations.
- Do not require registration on every row, icon, or layout component.
- Each mounted registration has a unique instance ID, optional stable screen ID, display name, type name, source location, scene ID, and parent context.
- Action events receive context from the reporter used at the action site.
- Maintain scene-local presentation/navigation context; do not use a global last-onAppear string.
- Hosts may supply explicit route/selection updates for navigation or tabs whose active state cannot be inferred reliably from lifecycle callbacks.
- If capture-time context is ambiguous, retain the candidate hierarchy and flag uncertainty. Do not invent an active screen.
- Multiple windows must not mix event histories or active-screen state.
- Conformance constrains registration arguments; it does not prove registration exists on every screen.

## Event recording

Supported event categories: screen entry/exit, navigation, user action, operation outcome, and diagnostic error.

Each event contains an ID, session ID, scene ID, wall-clock timestamp, monotonic ordering value, category, stable event name, screen context, optional source location, and bounded typed metadata.

- Default history: last 50 events per scene, also bounded by bytes; proposed byte limit 256 KiB.
- Record actions inside existing handlers before invoking their behavior.
- Record outcomes separately; a tap does not prove an operation succeeded.
- Navigation adapters and shared controls should avoid duplicate events.
- Preserve source context explicitly for asynchronous outcomes even if navigation changes before completion.
- Recording must be concurrency-safe and perform no synchronous disk or network I/O on the interaction path.
- Freeze a copy at capture time; reporter interactions must not enter the captured history.
- Events without context remain visible and are flagged as unscoped.
- Breadcrumbs are observed history, not validated reproduction instructions.

Metadata accepts explicitly allowed scalar values and small collections with size limits. Do not record passwords, tokens, freeform field contents, or complete request/response bodies by default. No automatic scanning of input controls.

## Screenshot implementation requirements

Capture the rendered app scene rather than constructing a fresh SwiftUI view tree. Prototype UIKit window capture and evaluate sheets, full-screen covers, keyboard-visible forms, scrolling, and common embedded UIKit content.

SwiftUI ImageRenderer alone is insufficient for arbitrary app screenshots: Apple documents exclusions for UIKit-backed views such as web views and media players.

The package cannot promise capture of system-owned windows, protected media, or every custom rendering surface. Capture output must expose success, partial/unsupported, or failure status. Where incomplete output can be detected, show it in the editor and preserve that status in exports; never label unknown fidelity as verified.

Support manual attachment when the captured image misses relevant content. A screenshot capture must not silently dismiss the keyboard before obtaining the image. If that cannot be achieved on a supported configuration, document the limitation and provide the manual path.

## Report model

| Field | Meaning |
|---|---|
| schemaVersion | Version of serialized report format |
| id | UUID used for durable identity and file pairing |
| displayID | Human-readable local issue number |
| projectID | Host-configured app/project identifier |
| capturedAt | Original capture timestamp with timezone context |
| updatedAt | Most recent report edit |
| description | Required user-authored problem description |
| expectedBehavior | Optional user-authored expectation |
| reproductionNotes | Optional user-authored steps |
| screenContext | Screen identity, source, hierarchy, and confidence status |
| environment | App/build, OS, device model, orientation, appearance, locale, Dynamic Type |
| events | Frozen recent event history |
| assets | Original, annotations, optional manual images, capture status |
| exportHistory | Export preparation and share completion observations |

Metadata must distinguish unavailable values from empty or zero values. Record build/source revision only when supplied by the host; do not guess it. Do not use a persistent device identifier.

## Persistence and inbox

- Store reports in the host app's Application Support container.
- Use an atomic commit or recoverable transaction so interrupted writes do not create apparently complete reports with missing images.
- Save works offline. Surface disk failures and allow retry without losing the current draft.
- Retain saved reports until explicit deletion in v1. Warn about storage consumption; do not silently evict reports.
- Inbox supports project/date filtering, multi-selection, description editing, annotation editing, deletion, and export.
- Export history does not mean an agent received or fixed an issue.
- Deleting the host app can remove its local reports; mention this in retention/help UI where relevant.
- A package inside one app cannot automatically read another app's private report store.

## AI export contract

```text
IssueCapture-export-<date>/
  README.md
  manifest.json
  issues/
    <uuid>/
      issue.md
      issue.json
      screenshot-original.png
      screenshot-annotated.png
      issue-card.png
```

Optional derivatives are omitted when not requested or not applicable. Manifest lists relative paths, schema version, export timestamp, and included report IDs. Markdown references images with relative links. JSON retains structured metadata and events. Export is packaged as a ZIP for the share sheet, Files, or AirDrop.

Each issue Markdown file contains the user's exact description, screen/source context, environment, recent events, and attachment links. Label missing context explicitly. Do not rewrite the description into inferred facts.

An issue card places text outside the screenshot, preserves aspect ratio, and includes the issue ID. Long descriptions must wrap and expand the layout without silent truncation. Full-resolution originals remain available in the bundle.

README includes a suggested agent prompt: inspect each report and linked image, locate relevant code, preserve issue IDs in responses, distinguish uncertain expectations, and follow the host repository's instructions for implementation and validation. Export itself never starts agents or sends reports to a remote service.

## Build controls

- Host explicitly enables capture using its compilation conditions, such as DEBUG or a dedicated INTERNAL_QA flag.
- Ordinary production configuration stays disabled and installs no capture UI or recorders.
- Disabled reporter calls must be safe no-ops and create no report files.
- Release-configured internal/TestFlight builds may opt in intentionally.
- Shipping no active behavior is distinct from removing package code from the binary. Hosts requiring binary exclusion need compile-time guards or target/dependency separation.
- CI/documentation must describe the host build-setting responsibility; runtime configuration alone does not prove production exclusion.

## Package organization

Keep public models, context tracking, event recording, capture services, persistence, export, and UI in focused directories and files. Hard limit: 500 lines per file. Public APIs require documentation comments.

Suggested products: one IssueCapture library for v1; avoid separate products until consumers need them. Internally separate Core, Context, Recording, Capture, Storage, Export, and UI responsibilities. Keep cloud transport out of the core design.

## Agent adoption contract

The package ships Integration.md and an AGENTS.md snippet linking to it. Adoption requires:

1. Add the package and configure enabled builds explicitly.
2. Install a host once per app scene.
3. Inventory navigation destinations, tabs, sheets, and full-screen presentations.
4. Add protocol conformance and screen modifiers to those destinations.
5. Instrument meaningful existing action handlers, centralizing shared control coverage where practical.
6. Add navigation/selection hooks where lifecycle tracking is insufficient.
7. Pass scoped reporters into non-view handlers where needed.
8. Do not alter gestures, accessibility semantics, navigation behavior, or business logic to collect events.
9. Record outcomes where they add diagnostic value; avoid duplicate and sensitive events.
10. List coverage gaps explicitly. Never claim compiler-enforced whole-app coverage.
11. Keep instrumentation current when adding or changing screens and actions.
12. Follow repository-specific validation rules, including restrictions on running tests.

Suggested host AGENTS.md text:

> Follow IssueCapture's Integration.md when changing UI. Register navigable and presented screens with IssueReportableScreen and issueCaptureScreen. Record meaningful actions through scoped reporters inside existing handlers. Preserve behavior and accessibility, avoid sensitive data, and document coverage gaps. Keep production configuration disabled unless explicitly authorized otherwise.

## Acceptance criteria

These define implementation completion; this specification does not execute tests.

- A physical iPhone can save five reports offline, relaunch the app, and export all five with correctly paired text and images.
- Capture excludes reporter controls and occurs before opening the editor.
- Capture handles supported sheets/full-screen covers and documents keyboard/rendering limitations based on device verification.
- Original and annotated assets remain distinct, and edits survive relaunch.
- Screen type/source and action context match explicitly registered destinations.
- Modal, tab, asynchronous outcome, and multiple-scene cases do not silently assign unrelated screen context.
- Missing context appears as a diagnosable gap.
- Existing button, gesture, and accessibility behavior remains intact.
- Export preserves descriptions and uses valid relative attachment paths and consistent UUIDs.
- Interrupted storage/export and screenshot failure produce recoverable user-visible states.
- Disabled production configuration creates no overlay, recordings, or report files.
- Event memory usage remains bounded and recording performs no blocking I/O on the UI interaction path.

## Implementation sequence

1. Build a feasibility sample: overlay presentation, capture timing, keyboard behavior, screen/environment propagation, and physical-device export.
2. Implement models, scoped recording, and local persistence.
3. Implement reporter editor, annotations, and inbox.
4. Implement bundle/card exports and disabled-build behavior.
5. Write integration documentation and adopt in one existing app to refine the contract before wider rollout.

## Reference basis

- [Apple: ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer) — limitations of rendering UIKit-backed content.
- [Apple: UIView.drawHierarchy](https://developer.apple.com/documentation/uikit/uiview/drawhierarchy(in:afterscreenupdates:)) — candidate live hierarchy capture API.
- [Apple: Configuring app groups](https://developer.apple.com/documentation/xcode/configuring-app-groups) — explicit configuration required when sharing containers across related apps/extensions.

The API and architecture above are proposed design decisions. Platform capture fidelity and overlay behavior require implementation-time verification; they are not claimed as demonstrated capabilities.
