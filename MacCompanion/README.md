# IssueCapture Mac companion

A native SwiftUI macOS app that receives IssueCapture exports, groups them into
explainable candidate requests, and prepares lossless request folders you can
copy or drag into a coding tool.

Version one works offline. It needs no API key and makes no model call.

## Build and run

```bash
cd MacCompanion
swift build -c release
swift run -c release IssueCaptureCompanion
```

Requires macOS 14+ and a Swift 6 toolchain. The package resolves the parent
IssueCapture package by path and links only its Foundation-only
`IssueCaptureSchema` product. It never links the iOS `IssueCapture` target,
which imports UIKit.

The executable sets a regular activation policy at launch, so `swift run`
produces a real window. Running it from a `.app` bundle built with Xcode works
the same way.

## Using it

1. **File ▸ Open Export…**, or drop an export ZIP or expanded export folder
   onto the window. Multiple selections are imported in one pass.
2. The left pane lists candidate requests grouped by project and by exact
   recorded app version and build. Every grouping states the rule that produced
   it.
3. The middle pane shows the issues in the selected candidate request, their
   authored text, screen and build context, evidence warnings, and image
   previews with the attachment decision and its reason. You can toggle
   individual images, pin issues into a named group to split or merge, and add
   request instructions.
4. **Prepare request** writes a versioned folder. The right pane then offers
   **Copy prompt**, **Drag files** and **Reveal folder**, with the exact
   attachment count and byte total.
5. **File ▸ Choose Watched Folder…** opts into watching one folder. Access is
   persisted with a security-scoped bookmark. The companion never claims ZIP
   file associations.

## What a prepared request contains

```text
requests/<request UUID>/
  request.md        # assignment, checklist with full UUIDs, exact authored text
  request.json      # ordered UUIDs/revisions, reasons, rule and template versions,
                    # attachment mappings, hashes and preparation time
  evidence/<issue UUID>/…   # every received file for that issue revision
```

`request.md` reproduces authored description, expected behavior and reproduction
notes exactly, even where the UI preview abbreviates them. Captured events are
labelled as observations, not reproduction steps. Companion-authored
instructions are kept in their own section, and the assignment states that the
host repository's own implementation and validation rules take precedence. It
contains no blanket instruction to run tests.

## Honest limits

- **Drag destinations are not verified.** Drag exposes `request.md` plus the
  chosen images as real file URLs, which is what image attachment requires —
  Markdown links alone do not attach images in chat tools. Whether a particular
  coding tool accepts a multi-file drop, and what it does with the evidence
  folder, has to be checked in that tool. This build claims no verified
  destination and applies no destination size limit; the attachment-count
  advisory in Preferences is a local readability hint only.
- **Prepared, copied or dragged is not delivered, fixed or verified.** Issue and
  request states are local bookkeeping you set by hand. There is no transport,
  so nothing acknowledges receipt.
- **Export images may already be JPEG derivatives** produced by the exporter's
  compression options. They are preserved byte-for-byte, but they are not the
  device's stored original.
- **Grouping is mechanical.** Rules propose candidate requests from recorded
  metadata. They never claim the grouped issues share a root cause. Text
  similarity and model-based clustering are not used.
- **Captured file paths are diagnostic hints.** The companion never selects a
  repository or runs a command from them. Project-to-repository mapping is not
  implemented in this build.
- **Only stored ZIP32 archives are read**, which is what the iOS exporter
  writes. Compressed or ZIP64 archives are reported as unsupported rather than
  partially imported.

## Batching rules

Rule version `batch-rules-1`. The same inputs, rule version and preferences
always produce identical memberships and ordering.

1. Partition by `projectID`, then by exact recorded `appVersion` and `build`.
   Absent values, and the `unavailable` sentinel the capture build writes, count
   as missing and keep their issues in a partition of their own.
2. A single explicit `batch:<name>` tag groups issues within that partition.
   More than one batch tag leaves the issue alone with a conflict explanation.
3. Otherwise a group is proposed only when every issue recorded exactly one leaf
   screen candidate and the documented accepted context status. The key is the
   exact `stableID` when present, otherwise the exact qualified type plus the
   captured source file. Mounted screen UUIDs identify instances, not stable
   screens, and are never used.
4. Ambiguous, unregistered and unrecognized-status issues stay individual.
   Ordinary tags and exact shared event IDs are shown as related items and never
   merge requests, nor chain through a third issue.
5. Issues sort by capture timestamp then full UUID. Rule-derived groups split at
   the configurable cap (default five) in that order. Manual groups are never
   split automatically; they are flagged when over the cap.

Manual decisions are pinned to the exact issue revision you reviewed. When newer
evidence arrives under the same issue identity, the decision stops applying and
is surfaced for review rather than carried silently onto content you never saw.
A manual group that would span projects is not applied.

## Tests

```bash
cd MacCompanion
swift test
```

The suite covers the acceptance scenarios: repeated archive import, edited UUID,
same short ID with different UUIDs, mixed projects and builds, ambiguous
screens, multiple batch tags, compressed image filenames, missing image,
annotated manual attachment, unsafe archive paths, interrupted folder copy,
large batch split, and a prepared request staying unchanged after newer evidence
arrives.
