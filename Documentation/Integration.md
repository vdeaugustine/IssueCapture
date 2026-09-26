# Agent integration contract

For the complete setup assignment and completion criteria, start with [AgentHandoff.md](AgentHandoff.md). This document defines the underlying instrumentation contracts.

Unity iOS consumers follow [UnityIntegration.md](UnityIntegration.md) for the UPM
package, explicit C# surfaces, native report bridge, and generated-project setup.
The SwiftUI adoption steps below remain valid for SwiftUI applications.

## Required adoption work

1. Add the local or remote package dependency and link the IssueCapture library product.
2. Install `.issueCaptureHost(configuration:)` once per scene root. Enable only via the host's explicit Debug/internal build configuration.
3. Inventory navigable screens, tabs, sheets, and full-screen destinations. Keep a short coverage table in the host repository.
4. Adopt `IssueReportableScreen` and apply `.issueCaptureScreen(Self.self)` on those screens. Do not register every decorative component or row.
5. Read `issueReporter` in descendants of the screen modifier. Existing outer views may be split into a small registration wrapper and focused content view where necessary.
6. Record semantic actions inside their existing handlers, before executing business logic. Never add an extra gesture just to observe a button.
7. Instrument shared control handlers centrally when possible. Avoid recording the same activation both centrally and at its call site.
8. Record useful outcomes separately. Pass a captured `IssueReporter` value to asynchronous work so results retain the original scope.
9. Use `isActive:` for retained tabs or navigation surfaces. Record route changes from the host router where applicable.
10. Preserve accessibility, gestures, navigation, and business behavior.
11. Keep production disabled. A runtime no-op does not mean package code is absent from the binary.
12. List coverage gaps and follow host validation rules. Do not claim automatic whole-app coverage.

## Naming

- Screen label defaults to `String(describing: Self.self)`.
- Optional override: `static let issueScreenName = "Edit Profile"`.
- Qualified type and `#fileID`/`#line` remain available independently.
- Optional stable registration ID: `id: "profile.editor"`.
- Event names are stable semantic identifiers such as `profile.save`, not localized labels or user text.

## Events

```swift
reporter.record(.tap("profile.save"))
reporter.record(.navigation("profile.open"))
reporter.record(.outcome("profile.save_failed", metadata: ["reason": "offline"]))
reporter.record(IssueAction(category: "error", name: "profile.decode_failed"))
```

Metadata is bounded to 16 fields, keys to 100 characters, values to 512 characters. Oversized event records are rejected by the byte budget. Events are retained in a count/byte bounded ring-like queue. Defaults: 50 events and 256 KiB per scene.

Never supply passwords, access tokens, freeform field contents, personal identifiers, or request bodies. Breadcrumbs describe observations; they do not establish validated reproduction instructions.

## Context pitfalls

Environment injection only flows downward. Reading the reporter in the same outer view that applies the screen modifier reads its parent's scope. Prefer a wrapper screen with descendant content, as demonstrated in the example.

The package preserves multiple active registration candidates and reports uncertainty. It does not infer the source hierarchy from UIKit internals or treat the latest `onAppear` as definitive. A screen may remain mounted beneath a presentation or in a retained tab. Explicit `isActive:` state is the host's escape hatch.

## Suggested host AGENTS.md entry

> Follow IssueCapture/Documentation/Integration.md for UI changes. Register navigable and presented screens with IssueReportableScreen and issueCaptureScreen. Record meaningful events through scoped reporters inside existing handlers, preserving original context for asynchronous outcomes. Keep instrumentation out of sensitive data and production behavior. Preserve existing gestures/accessibility and document coverage gaps. Follow this repository's validation policy.

## Adoption prompt

> Adopt IssueCapture in this app. Read its integration contract, add the dependency and development-only scene host, inventory destinations, register screens, and instrument meaningful existing action handlers. Use inherited reporter context correctly. Add the contract reference to AGENTS.md and document uninstrumented surfaces. Preserve app behavior and follow repository validation instructions.

## Floating button styling

Pass `captureButtonAppearance: CaptureButtonAppearance(...)` in the host
configuration to set `backgroundColor`, `foregroundColor`, and `diameter`.
UIKit dynamic colors support light and dark appearances. Defaults use
`secondarySystemBackground`, `label`, and 48 points. Sizes are constrained to
44–80 points; nonfinite values fall back to 48. `showsCaptureTab: false` and
disabled-host behavior remain unchanged.

Reporters can hold the floating button and open **Button appearance**, or find it
in the saved-issues toolbar menu. These live changes apply only to that host
session. Use configuration for persistent app defaults.
