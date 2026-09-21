# Architecture

- **Core**: configuration and Codable report/screen/annotation models.
- **Context**: screen protocol, constrained registration modifier, environment context and commands.
- **Recording**: thread-safe bounded in-memory event recorder and Sendable scoped sink.
- **Capture**: per-scene host attachment, passthrough overlay, screenshot service and editor session.
- **Storage**: shared actor serializes durable writes inside Application Support/IssueCapture.
- **Export**: Markdown/JSON generation, annotated derivatives, image cards and streaming stored ZIP32 writer.
- **UI**: description editor, markup canvas, inbox, diagnostics and system share sheet.

`Core` model types, `Recording` event types and the export schema live in the
separate Foundation-only `IssueCaptureSchema` target so non-UIKit readers can
decode exports. `IssueCapture` re-exports it, leaving `import IssueCapture`
unchanged for consumers.

## Mac companion

`MacCompanion/` is a separate Swift package holding the macOS companion app. It
depends on this package by path and links only the `IssueCaptureSchema` product,
never the UIKit `IssueCapture` target. Its `CompanionCore` library is split into
Import (archive and folder ingestion, manifest validation, staged commits, folder
watch), Evidence (versioned storage and import provenance), Batching (pure rule
engine with explanations and persistent manual overrides) and Requests (lossless
assembly, attachment policy, snapshot manifests). See
[MacCompanion.md](MacCompanion.md).

## Ownership

An enabled scene root owns CaptureSession. The session owns its recorder and overlay controller. The overlay uses weak references back to the session and host window. SwiftUI dismantling detaches the overlay. Each recorder receives its owning scene ID; no global current-screen variable exists.

Screen registration injects an instance-specific context into descendants. Records copy that context. Registration lifecycle drives candidate tracking; explicit activity state refines it. Entering the reporter suspends its scene recorder, excluding reporter-induced events from the frozen report history.

## Capture

The source app window is rendered before the overlay becomes key and before the editor opens. The capture button belongs to a separate window and is excluded. While the reporter is open, an explicit self-capture action renders the overlay window instead and records an IssueCapture-owned screen context. The overlay becomes key only for reporting and restores the prior key window on close. It passes through touches outside its tab while idle.

The app hierarchy render result is retained as a fidelity status, not a claim that all pixels are correct. Keyboard and system-owned surfaces may be absent. Manual attachment is the fallback.

## Persistence

A new save writes assets plus metadata into a hidden staging directory, then moves it to the UUID destination. An edit stages a complete replacement, copying existing assets when necessary, then uses Foundation directory replacement. Failures leave the editor available for retry. Hidden staging folders are excluded from the inbox.

Reports are never automatically evicted. Export preparation timestamps are appended from the current stored record to avoid overwriting edits. Exported bundles use immutable copies selected at export time. Archives remain in the OS-managed temporary directory for sharing; iOS may purge them. Saved reports are independent of exports.

## Build configuration

Default is disabled. Host compilation conditions select explicit enablement. The package intentionally does not inspect its own DEBUG flag. Swift 5 language mode is selected with a Swift 6 manifest/toolchain; public recorder values are Sendable and UI orchestration is main-actor isolated.
