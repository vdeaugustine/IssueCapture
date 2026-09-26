# IssueCapture: agent setup handoff

Read this document when asked to finish adopting IssueCapture into an existing app. Adding the package dependency alone is not completed integration.

## Your assignment

Inspect the consuming app, install an enabled capture host in its approved development builds, register its screens, instrument meaningful actions, and document coverage. Make the changes in the consuming app. Do not stop at explaining how its developer could do them.

Follow the consuming repository's instructions and existing architecture. Do not modify the package merely to avoid following its integration contract. Preserve unrelated work and do not replace the app's navigation or business logic for instrumentation.

Read these package documents first:

1. [Integration.md](Integration.md) — authoritative screen, event, context, and build contracts.
2. [../README.md](../README.md) — actual public APIs and installation examples.
3. [Validation.md](Validation.md) — package checks already performed and remaining platform limitations.

Use the source for the installed version to resolve API details. [Specification.md](Specification.md) is a design reference, not proof that every proposed capability is implemented. The included [example app](../Examples/IssueCaptureDemo) demonstrates a registration wrapper with descendant reporting content.

For Unity consumers, use [UnityIntegration.md](UnityIntegration.md) for installation,
C# registration, frame capture and development-build gating in place of the SwiftUI
host/modifier steps below. Keep the same coverage, privacy and verification duties.

## Step 1: inspect before changing

Locate:

- App targets that link IssueCapture, package version/path, minimum iOS version, and Swift toolchain.
- Each scene root and any existing capture-host installation.
- Navigation destinations, distinct tab destinations, sheets, and full-screen covers.
- Shared button components, routers, and existing action handlers.
- Host Debug, production Release, and any approved internal-testing configurations.
- Repository rules for builds, tests, signing, and changes to AGENTS.md.

The current package requires iOS 15+ and a Swift 6 toolchain; it compiles in Swift 5 language mode. If the app is incompatible, report that concrete mismatch before changing deployment targets or migrating its toolchain.

If integration already exists, inspect and complete it. Do not install duplicate hosts or duplicate events.

## Step 2: wire the host and builds

Link the IssueCapture library product to the intended app target. Attach `.issueCaptureHost(configuration:)` once at each scene root, above the screens that need its environment.

Choose a stable projectID for this app. Enable capture explicitly from the consuming app's compilation conditions. Default production behavior must stay disabled.

```swift
private var issueConfiguration: IssueCaptureConfiguration {
    #if DEBUG || INTERNAL_QA
    .init(isEnabled: true, projectID: "ExistingApp")
    #else
    .init()
    #endif
}

// In the existing scene, preserving its existing modifiers:
WindowGroup {
    RootView()
        .issueCaptureHost(configuration: issueConfiguration)
}
```

Use the app's actual approved condition names. `INTERNAL_QA` above is an example, not a flag automatically supplied by the package. Do not enable all Release builds to make TestFlight reporting work. The package's own DEBUG flag is not the host's enablement policy.

Keep configuration stable during the installed host's lifetime. Document that disabled behavior does not guarantee package code is absent from the binary.

## Step 3: register screen boundaries

Every navigable screen and presented destination in the adoption scope must conform to `IssueReportableScreen` and apply `.issueCaptureScreen(Self.self)`.

The default name comes from the supplied type. Override `issueScreenName` only when a friendlier display label adds value. The package also records qualified type and modifier source location. Optional `id:` can supply a stable identity across renames.

Do not register every label, icon, row, or decorative container. Shared content normally inherits the containing screen's scope.

For retained tabs or other simultaneously mounted surfaces, use `.issueCaptureScreen(Self.self, isActive: ...)` driven by the app's real selection state. Preserve candidate hierarchy instead of pretending appearance order proves which screen is active.

Protocol conformance alone is insufficient: the modifier must also be attached. A modifier compiling successfully does not prove all destinations are covered.

## Step 4: place event recording in the correct scope

Read `@Environment(\.issueReporter)` in a descendant of the registration modifier. Environment flows downward; reading it on the same outer view that applies that modifier gets the parent's scope.

Prefer this shape when an existing screen needs a wrapper:

```swift
struct ProfileEditorView: IssueReportableScreen {
    var body: some View {
        ProfileEditorContent()
            .issueCaptureScreen(Self.self)
    }
}

private struct ProfileEditorContent: View {
    @Environment(\.issueReporter) private var reporter

    var body: some View {
        Button("Save") {
            reporter.record(.tap("profile.save"))
            // Invoke the app's existing Save action here, unchanged.
        }
    }
}
```

Do not use that illustrative comment as a replacement for the app's implementation. Preserve existing state ownership, bindings, environment dependencies, and action behavior when separating wrapper/content views.

Record meaningful actions inside their existing handlers, before the action executes. Prioritize actions affecting navigation, persistence, forms, settings, selection, loading, and error states. Use stable semantic IDs such as `profile.save`.

- Never add an extra tap gesture merely to observe a Button.
- Never replace a control's accessibility activation path.
- Instrument shared handlers once; avoid duplicate call-site events.
- Record navigation changes through existing routing/selection code where useful.
- Record operation outcomes separately. A tap is not proof of success.
- Pass the scoped IssueReporter value into asynchronous work or service callbacks when needed. Retain that original scope for its outcome; do not look up whichever screen is active later.
- Never put user input, credentials, tokens, or request bodies into event names or metadata.

Follow Integration.md for event APIs and metadata limits. Do not add unrestricted log/network collection as part of this assignment.

## Step 5: create a coverage record

Create a small repository-owned document, preferably `Documentation/IssueCaptureCoverage.md` unless the app has another documentation convention. Include:

- Installed package location/version and supported app targets.
- Host installation file/line for each scene.
- Actual enablement conditions and production-disabled configuration.
- Destination coverage table with the following columns.

| Screen/destination | Registration location | Activity/presentation handling | Events covered | Gaps |
|---|---|---|---|---|
| Actual source type | Actual file:line | Router/tab/sheet behavior | Stable event IDs or shared handler | Explicit remaining gaps |

Inventory destinations before filling this table. Include uninstrumented destinations rather than silently omitting them. Mark UIKit-only or third-party screens as unsupported/manual integration where applicable; do not invent SwiftUI protocol conformance for them.

Include validation performed, checks not run, known capture limitations, and any unresolved build or coverage issues. Do not use a percentage unless you have a real inventoried denominator.

## Step 6: verify within repository policy

Build the intended app target when allowed by repository rules. If runtime validation is permitted and available, walk through:

1. Open a registered screen and activate a meaningful action.
2. Open diagnostics and confirm its screen identity and scoped event; check for unscoped/duplicate events.
3. Capture while the issue is visible. Confirm the captured image precedes the reporter UI.
4. Save a description, relaunch, reopen, and edit it.
5. Export selected issues and confirm description/image pairing and source context.
6. Check a presented screen and a retained tab, if the app uses them.
7. Confirm the production configuration leaves capture disabled.

These are verification targets, not authorization to ignore restrictions on tests or device use. Do not run tests when repository/user instructions prohibit them. Mark unavailable or unperformed checks explicitly. Existing package validation is not a substitute for validation in this app.

Do not claim verified screenshot fidelity on physical devices unless actually observed. Keyboard, system windows, protected media, and custom rendering surfaces can require manual attachment.

## Step 7: make the contract persistent

Add a concise reference to the consuming repository's AGENTS.md or its equivalent agent instructions. Preserve the rest of that file.

Use a stable repository-owned path or a documented way to locate the installed package. Do not hardcode a machine-specific DerivedData checkout path. For remote SwiftPM dependencies, record the package identity/version and instruct agents to resolve its checkout from the project when needed.

Suggested entry, substituting actual locations:

> IssueCapture is integrated in this app. Follow the installed package's Documentation/AgentHandoff.md and Documentation/Integration.md when changing screens or actions. Register navigation and presentation boundaries, use descendant scoped reporters, preserve behavior/accessibility, and keep production disabled. Update Documentation/IssueCaptureCoverage.md as coverage changes. Follow this repository's validation policy.

## Definition of done

- Package product is linked to the intended targets.
- Exactly one enabled host exists per intended scene, with documented host-controlled enablement.
- Inventoried in-scope destinations have protocol conformance and registration, or an explicitly reported gap.
- Meaningful actions and useful outcomes use correctly scoped, nonduplicated events.
- Existing behavior, state ownership, navigation, and accessibility are preserved.
- Coverage record and persistent agent instructions are updated.
- Builds/runtime checks allowed by repository policy are recorded honestly.
- No unresolved integration failure is described as completed work.

Finish with a concise report naming changed files, screen/action coverage, checks performed, and remaining gaps. If something is blocked, identify the exact missing requirement and complete independent authorized work first.
