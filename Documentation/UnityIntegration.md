# Unity iOS integration

IssueCapture's Unity integration targets **Unity 6 (6000.0+)**, IL2CPP, **iOS 15+**,
and an Xcode toolchain with Swift 6 (Xcode 16+). Unity 6000.2.13f1 C# compilation
and Xcode 27 native builds have been checked; this is not a claim that every
Unity/Xcode combination or an iOS 15 device has been exercised. See
[UnityValidation.md](UnityValidation.md) for actual evidence and gaps.

This integration is new after 1.7.1. **Do not resolve the native library at 1.7.1**;
it lacks these APIs and requires iOS 17. The UPM package version and first Git
release tag containing this integration are both `1.8.0`.

## Install once in the Unity source project

1. Install iOS Build Support for the Unity editor and set iOS deployment target
   to 15.0 or higher in Player Settings. Keep IL2CPP enabled.
2. In Package Manager, **Add package from disk**, select this repository's root
   `package.json`. For a shared/CI setup, add `https://github.com/vdeaugustine/IssueCapture.git#1.8.0`,
   or vendor that tagged checkout and use a relative
   `file:` dependency. Commit Unity's `Packages/manifest.json` and
   `Packages/packages-lock.json`. Avoid an unpinned branch dependency.
3. Add initialization in the game's persistent bootstrap, on the Unity main
   thread after its window is visible. `Initialize` returns false when unavailable;
   retry from a later frame on an enabled iOS development player if launch is early.
4. Register explicit surfaces and record actions as below. Add uGUI development
   buttons that call `Capture()`, `OpenInbox()` and `OpenDiagnostics()`. Show them
   only when `IsEnabled`. The native floating tab is deliberately hidden because
   Unity must supply the game frame.
5. Export iOS with **Development Build** enabled into a **fresh output folder**.
   The package's `IPostprocessBuildWithReport` runs automatically. Open the exported
   Xcode project, select your signing team, resolve packages, and build normally.

No manual edits to generated Xcode output are the integration source of truth.
The postprocessor copies `Package.swift`, `Sources`, and the Objective-C++ adapter
from the installed UPM version into `IssueCaptureSupport`. It adds a local SwiftPM
reference, links `IssueCaptureUnity` to **UnityFramework**, and enables Swift runtime
embedding on **Unity-iPhone**. There is no second remote version to drift from UPM.
A local source snapshot needs no `Package.resolved` pin; UPM locks its origin.

Unity 6's PBX API lacks local-package creation. The postprocessor uses its product
linking API, then replaces only the newly created, GUID-matched remote-reference
object with Xcode's `XCLocalSwiftPackageReference`. Unexpected serialization fails
the build. Keep this callback last among callbacks that rewrite Swift package
references. Custom target layouts and Unity as a Library require host-specific
adaptation; they are not covered by the standalone exporter.

**Append exports are rejected** when IssueCapture output/references already exist.
Use Unity's Replace export or a new folder. This also prevents a production export
from accidentally inheriting a development binary or package reference.

## C# API

```csharp
using Capture = VinWare.IssueCapture.IssueCapture;
using VinWare.IssueCapture;

// Main-thread bootstrap; do not use the Swift package's DEBUG flag.
Capture.Initialize("rinse-and-reveal", sourceRevision: "build-revision");

// BoardwalkController owns these handles; explicitly supply identity.
var boardwalk = Capture.RegisterScreen(
    "scene.boardwalk", "Boardwalk", "RinseReveal.BoardwalkController");
var play = Capture.RegisterScreen(
    "boardwalk.play", "Boardwalk play", "RinseReveal.BoardwalkHUD", boardwalk);
var inventory = Capture.RegisterScreen(
    "boardwalk.inventory", "Inventory", "RinseReveal.InventoryPanel",
    boardwalk, active: false);

// Inside the existing handler, before its existing operation:
var origin = play.Reporter;
origin.Action("boardwalk.enter_clean");
// Pass origin into the real async operation; even after scene unload:
origin.Outcome("boardwalk.load_complete", IssueOutcome.Success);
```

`RegisterScreen` captures caller file/line. Paths inside Assets are project-relative;
other paths are reduced to a filename, excluding workstation usernames. Supply an
explicit project-relative `file:` if package source identity needs more detail.
`typeName` is a supplied C# type name, not a guessed Unity object hierarchy.

| API | Contract |
| --- | --- |
| `Initialize(projectID, sourceRevision, eventLimit, eventByteLimit)` | Main thread, once per persistent host; explicit development opt-in |
| `RegisterScreen(stableID, name, typeName, parent, active, file, line)` | New instance UUID; optional stable semantic ID and parent |
| `IssueScreen.SetActive(bool)` | Main thread; activity follows the actual router/tab/presentation state |
| `IssueScreen.Dispose()` | Main thread; unregisters instance and native descendants |
| `IssueScreen.Reporter` | Immutable origin; retain across asynchronous operations and disposal |
| `Reporter.Action`, `.Navigation`, `.Outcome` | Stable semantic name; thread-safe dispatch; outcome enum only |
| `Capture()` | Freeze context/events, acquire next end-of-frame PNG, open native editor |
| `OpenInbox()` / `OpenDiagnostics()` | Native saved reports/export and coverage UI |
| `IsPresenting` | Main-thread poll; includes pending frame acquisition |
| `Shutdown()` | Detach native UI, suspend recording, destroy capture runner |

Use `IssueOutcome.Success`, `Failure`, or `Cancelled`. Background results are
copied and queued to the iOS main thread; preserve normal operation ordering and
never block the Unity main thread waiting for a worker. Old-session commands are
ignored after shutdown/reinitialization. An outcome arriving while the reporter is
open is excluded, matching SwiftUI recorder suspension.

## Scene, retained surface and overlay activity

- **Scenes:** register Boardwalk/Clean when their controllers are ready, dispose on
  unload/destruction. Additive scene loads need explicit activity from the router;
  Unity's active-scene setting does not prove which UI is visible. Do not subscribe
  blindly to every loaded scene or infer identity from GameObject names.
- **Retained uGUI panels:** register once per instance, with the containing scene as
  parent. Drive `SetActive` from the same selection state that shows/hides the panel.
  A mounted but hidden Canvas is inactive even if `OnDisable` never fires.
- **Presented overlays:** register a distinct child of the presenting surface on
  show and dispose on hide (or retain and toggle). Its parent can remain active;
  the deepest active leaf is the context candidate. Unrelated visible leaves are
  retained as ambiguous, never resolved by last-registration order.
- An inactive/missing parent suppresses descendants. Disposing a parent removes its
  registered subtree; dispose the corresponding C# child handles too and create
  fresh handles when reconstructing that UI. Repeated activation/disposal is safe.
- Call initialization before registrations. Handles obtained while disabled remain
  no-ops; they do not attach retroactively. One persistent host survives scene loads.

Use `OnEnable`/`OnDisable` only when they match real visibility; otherwise call from
routing/presentation code. The package does not pause `Time.timeScale`, audio,
networking or gameplay. Native UI intercepts touch and hides host accessibility
while reporting; use `IsPresenting` to gate the game's own polling input as needed.
The frame must render before a game loop is paused. Unity orientation/input/audio
restoration remains a consumer validation responsibility.

## Capture, edit and export

The C# coroutine calls `ScreenCapture.CaptureScreenshotAsTexture()` after
`WaitForEndOfFrame`, PNG-encodes once, passes copied bytes to native, and destroys
the temporary texture. Context and history are frozen at the request, before the
reporter opens. Avoid scene transitions between that request and the next frame;
the image represents the next rendered frame, not an earlier synchronous state.
This follows Unity's [end-of-frame capture guidance](https://docs.unity.com/en-us/engine/6000.7/script-reference/unityengine/waitforendofframe).

UIKit hierarchy capture is not used for the game framebuffer. Engine PNGs exclude
native keyboards, system windows and other UIKit overlays. Fidelity on a device
is explicitly unverified. Missing, invalid, oversized or timed-out images still
produce an editable text-only report with an honest status and manual attachment.
Application pause cancels a pending request; a five-second foreground timeout
prevents the reporter from remaining stuck awaiting a frame.

The same native editor, annotations, attachment picker, local inbox, tags, JSON,
Markdown, cards, PDF, clipboard and ZIP sharing are used for SwiftUI and Unity.
Original saved screenshots remain immutable; annotations/export encodings create
derivatives. Report descriptions are not truncated. No automatic upload occurs.
`OpenInbox()` is the C# export entry point; the human selects reports and format
in native UI. There is no automatic C# file-export callback in this version.

## Limits and privacy

- Defaults remain 50 retained events / 256 KiB. Configuration clamps to 1–1,000
  events and 1 KiB–1 MiB; oversized events are rejected, oldest events evicted.
- Existing native event limits remain 16 metadata fields, 100-character keys,
  512-character values, 80-character categories and 200-character names.
- Unity adds 64 KiB UTF-8 command, 256 registered surface, 128 pending background
  command, 32 MiB PNG and 16-megapixel decoded-image limits. Excess registrations
  and queued commands are dropped; diagnostics exposes accepted registrations.
- Unity metadata is **only** `result=success|failure|cancelled`. There is no freeform
  dictionary, input-field, network, exception-message or log collection API.
- Names, stable IDs, labels, source revision and caller-supplied source locations
  must be static allowlisted developer values. Length bounds are not redaction.
  Never pass names/emails, save data, player identifiers, credentials or user text.
- Screenshots can contain sensitive pixels. The reporter can exclude the captured
  image; do not capture sensitive gameplay/account surfaces without a host policy.

## Production behavior

The runtime bridge calls and native imports compile only under
`UNITY_IOS && !UNITY_EDITOR && DEVELOPMENT_BUILD`. `Initialize` returns false in
editor, other platforms and production; lifecycle calls and disabled reporters do
nothing. No runner, texture, native session, overlay or report store is created.
The postprocessor skips package/native linking for a fresh non-development export.
Managed no-op API types may remain in a build until Unity strips them.

Xcode Debug/Release does **not** decide this policy: a Unity Development Build
export still enables reporting when archived as Xcode Release. Do not ship that
export to production. Internal TestFlight reporting requires an explicitly approved
Unity Development Build. A custom internal Release define is not supported here.

## iOS 15 compatibility

The previous blockers were Observation (`@Observable`/`@Bindable`, iOS 17), newer
navigation (iOS 16), PhotosPicker/Transferable (iOS 16), multiline TextField (iOS 16),
and toolbar/layout/empty-state APIs. Capture, storage and export themselves did not
require iOS 17. Session observation now uses `ObservableObject`/`@Published`, with
all consuming views observing it explicitly and SwiftUI hosts using `@StateObject`.

On newer iOS, NavigationStack, multiline TextField and modern layout/empty states
remain. iOS 15 uses stack-style NavigationView, multiline TextEditor with visible
labels, standard section spacing and trailing toolbar controls. All versions use
PHPicker for single-image attachment without full photo-library permission.
iOS 15 retains the keyboard Done control; interactive scroll dismissal is iOS 16+.
These are explicit presentation differences; report contents, capture uncertainty,
limits, disabled behavior and lossless export contracts are unchanged.

Swift/UIKit consumers can use `IssueCaptureNativeHost(window:configuration:)`,
explicit `IssueScreenContext`, and `reporter(for:)`. Disabled native hosts create no
session. Call `shutdown()` before releasing the host. Both UIWindowScene and legacy
UIApplication windows are supported; the adapter obtains Unity's window through
`UnityGetMainWindow()`, not UIKit hierarchy inference.

## Consumer coverage record

For Rinse & Reveal, inventory real Boardwalk/Clean controllers, retained shop or
inventory panels, pause/results/settings overlays, and transitions before adoption.
The supplied sample is illustrative; this task did not edit the game's repository.
Record actual source locations, activity owners, semantic handlers, enablement,
version pin, checks and gaps in its `Documentation/IssueCaptureCoverage.md`.
Add a reference to this contract in its AGENTS.md. Preserve existing uGUI controls
and accessibility. Import the [minimal sample](../Samples~/RinseAndReveal) from
Package Manager for a two-scene demonstration.
