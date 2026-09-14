# IssueCapture Mac companion proposal

Status: implemented. This document remains the product and implementation
contract; see [MacCompanion/README.md](../MacCompanion/README.md) for how to
build, run and verify the app, and for the limits this build does not claim past.

Delivered in this repository: steps 1-3 of the delivery order (import and
evidence, explainable batching with persistent manual adjustments and lossless
request folders, optional watched-folder import and preferences). Step 4 —
direct transfer and explicit coding-tool integrations — is deliberately not
implemented, and no destination's drag behavior has been verified.

## Intended experience

Capture on iPhone, share the export to Mac, open it in IssueCapture, then drag a
prepared request into an AI coding tool. No manual extraction, Markdown hunting,
image pairing, or repetitive prompt writing.

The Mac app owns a persistent inbox. Three panes show batches, their issues, and
the prepared request with attachment previews. Every grouping explains its rule.
Users can split, merge, exclude an image, or edit request instructions without
changing captured evidence. Primary action: **Prepare request**. The resulting
request offers **Copy prompt**, **Drag files**, and **Reveal folder**.

Version one removes work after receipt. AirDrop remains a transfer step. Optional
watching of a user-selected import folder removes the open step. Direct phone-to-Mac
delivery is a later feature requiring changes on both platforms.

## Import and evidence

- Accept an export ZIP or an already expanded export folder through Open or drop.
  Offer an optional watched folder through a system folder picker; persist access
  with security-scoped bookmarks. Never take over all ZIP file associations.
- Wait for watched files to finish copying; stage and validate before committing
  an import. Show actionable failures and allow retry. Do not move source files.
- Read `manifest.json`, then the referenced issue JSON and each `images.json`.
  Pair by full UUID and declared paths, never filename order, short ID, or Markdown
  parsing. Validate manifest identity against report identity.
- Support current schema v1 and Foundation reference-date timestamps. Reject
  unsupported manifest/report versions. Absent tags mean no tags.
- Validate archive checksums and paths before extraction. Reject traversal,
  absolute paths, symlinks, duplicate entry paths, and paths escaping the staged
  root. Bound archive entry counts and expanded bytes. Current writer emits stored
  ZIP32; explicitly report unsupported compression rather than partially importing.
- Preserve received JSON, Markdown, and images byte-for-byte in an immutable import
  store. Export images may already be JPEG derivatives; never claim they reproduce
  the device's stored original. Keep annotations distinct from their source image.
- Missing declared evidence appears as an issue-level warning. Never silently
  present incomplete evidence as complete. Malformed identity or unsafe paths
  reject the import. Unknown safe files remain in the source archive.
- Archive SHA-256 makes exact repeat imports idempotent. Issue identity is
  `(projectID, full UUID)`. Compare canonical decoded report content excluding
  `exportPreparedAt`, plus image-kind/content hashes, to identify unchanged issues.
  Retain all received artifacts and import provenance even when content matches.
- Changed content under an existing issue identity creates a revision. Do not
  overwrite evidence or silently swap a revision already used in a request.

## Deterministic batching

Rules create candidate requests, not claims that issues share a root cause.
Same inputs, rule version, and preferences must yield identical memberships and
ordering. Store rule version and reasons with each proposed batch.

1. Partition by `projectID`; never automatically mix projects. Partition further
   by exact recorded app version/build values. Missing build metadata stays in its
   own partition; choose actual environment keys from the capture implementation.
2. An explicit user-assigned `batch:<name>` tag groups issues within that partition.
   Multiple batch tags leave the issue unbatched with a conflict explanation.
3. Otherwise suggest a batch only when each issue has exactly one screen candidate
   and an accepted, documented context status. Use exact `stableID` when present;
   otherwise exact qualified type plus captured source file. Do not use mounted
   screen UUIDs, which identify instances rather than stable screens.
4. Ambiguous/unregistered screens stay individual. Ordinary tags and exact shared
   event IDs can explain related-item suggestions but never merge requests by
   themselves. No transitive grouping through overlapping tags.
5. Sort issues by capture timestamp, then full UUID. Default cap: five issues per
   candidate request; split larger groups in that order. Make cap configurable.

Manual split/merge decisions persist against explicit issue revisions. New imports
do not rearrange prepared requests. Text similarity and model-based clustering are
optional future suggestions requiring review, never part of deterministic pairing.

## Image policy

Default to including available visual evidence. Avoid asking users to guess
whether a screenshot matters before an agent sees it.

- Include annotated image when available; otherwise captured screenshot.
- Include manual attachment as separate evidence unless its bytes already match
  an included image. When annotation uses the manual attachment because no
  screenshot exists, retain that attachment too.
- Keep the unannotated capture in the evidence bundle even when the annotated
  version is the default external attachment. Allow including both explicitly.
- Omit issue cards from default attachments because they repeat report text.
- Deduplicate identical attachment bytes while retaining all UUID-to-image links.
- Show exact attachment count and bytes before dragging. Apply only documented
  destination limits. Split oversized requests or let users change attachment
  choices; never silently truncate text or recompress evidence.

## Prepared request contract

Create a persistent, versioned folder containing `request.md`, `request.json`, and
an `evidence/` directory with the selected issue revisions and their received files.
The JSON records request ID, project, ordered UUIDs/revisions, grouping reasons,
rule/template versions, attachment mappings and hashes, and preparation time.

`request.md` contains a short implementation assignment, an issue checklist with
full UUIDs, exact authored descriptions/expected behavior/reproduction notes,
screen and build context, observed events, and relative evidence links. Label
captured events as observations, not inferred reproduction steps. Keep report
content separate from companion-authored instructions; repository policy retains
precedence. Preserve complete source text even when UI previews are abbreviated.

The assignment asks the agent to inspect relevant source, assess whether fixes
belong together, implement within repository rules, and report outcomes per UUID.
Never insert a blanket instruction to run tests against repository policy.

Copy places prompt text on the clipboard. Drag exposes request Markdown plus the
chosen images as actual file URLs. Markdown links alone do not attach images to
chat tools. The full folder is available for tools that can read local evidence.
Show destination-specific instructions only after verifying that tool's supported
handoff behavior; do not promise universal one-drop compatibility.

Prepared, copied, or dragged does not mean delivered, fixed, or verified. Track
local states separately: inbox, prepared, user-marked sent, user-marked resolved.
Automatic delivery requires a supported integration and explicit user action.

## Implementation boundaries

Use a native SwiftUI macOS app with Foundation services and small focused files:

- `Import`: ZIP/folder ingestion, manifest validation, staged commits, folder watch.
- `Evidence`: versioned archive/report/image storage and import provenance.
- `Batching`: pure rule engine, explanations, persistent manual overrides.
- `Requests`: lossless assembly, attachment policy, snapshot manifests, file drag.
- `UI`: inbox, batch editor, evidence preview, prepared-request panel.

The existing package target imports UIKit and currently declares iOS 17 only.
Do not make the Mac app depend on that target directly. Extract genuinely shared
Foundation-only schema types into a dedicated target while preserving the public
iOS API, or introduce a focused versioned import DTO layer first. Leave capture
hosting, recording, and disabled-host behavior unchanged.

Keep project-to-local-repository mapping optional and explicit. Captured file paths
are diagnostic hints, not authority to select repositories or execute commands.
Version one works offline and does not need an API key or model call.

## Delivery order and acceptance

1. Import ZIP/folder, persist evidence, deduplicate repeated imports, show an inbox
   with correctly paired images and visible import failures.
2. Add explainable batching and persistent manual adjustments; prepare lossless
   request folders with image previews, copy, and file drag.
3. Add optional watched-folder import and project preferences.
4. Evaluate direct transfer and explicit coding-tool integrations after the local
   workflow proves useful. Transport must acknowledge receipt before claiming it.

Acceptance scenarios for implementation: repeated archive import; edited UUID;
same short ID with different UUIDs; mixed projects/builds; ambiguous screens;
multiple batch tags; compressed image filenames; missing image; annotated manual
attachment; unsafe archive paths; interrupted folder copy; large batch; unchanged
prepared request after newer evidence arrives. Verify real drag behavior in each
supported destination before claiming it works.

This contract was grounded in the current report model, exporter, Markdown renderer,
and export documentation.

## Implementation record

Shared schema types (`IssueReport`, `IssueScreenContext`, `IssuePoint`,
`IssueAnnotation`, `IssueEvent`, `IssueAction`) moved into a Foundation-only
`IssueCaptureSchema` target alongside a new `IssueExportManifest`,
`IssueExportImageKind`, `IssueExportSchema` and `IssueContextStatus`. The iOS
`IssueCapture` target re-exports that module, so `import IssueCapture` still
resolves every previously public name. Public memberwise initializers were added
to the moved types so Foundation-only readers and writers can construct them;
nothing was removed or renamed. Capture hosting, recording and disabled-host
behavior are unchanged.

The Mac app lives in `MacCompanion/` as its own Swift package depending on the
root package by path and linking only the `IssueCaptureSchema` product, never the
UIKit target. Its `CompanionCore` library holds Import, Evidence, Batching and
Requests; `IssueCaptureCompanion` holds the SwiftUI UI.

Verification performed: `xcodebuild -scheme IssueCapture -destination
'generic/platform=iOS Simulator'` succeeds after the extraction; `swift build`
and `swift test` in `MacCompanion` succeed with 65 passing tests covering the
acceptance scenarios above; an end-to-end pass over a generated five-issue export
produced the expected four candidate requests, deduplicated attachments and a
prepared request folder whose drag URLs all exist on disk. The app was launched
and confirmed to open a live 1080x692 window, but its rendered interface was not
visually inspected, and drag-and-drop into any coding tool was not exercised.
