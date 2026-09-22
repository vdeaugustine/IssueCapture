# Export format v1

```text
README.md
manifest.json
issues/<UUID>/issue.md
issues/<UUID>/issue.json
issues/<UUID>/images.json                 # actual image filenames by kind
issues/<UUID>/screenshot-original.png     # if captured
issues/<UUID>/attachment.png              # if attached manually
issues/<UUID>/screenshot-annotated.png     # if annotated
issues/<UUID>/issue-card.png              # when cards enabled
```

The folder is shared as a UTF-8 ZIP32 archive with stored entries, CRC32 checksums and relative paths. Original screenshots and manually attached images are separate. Annotations apply to the original screenshot when present, otherwise to the manual image.

`manifest.json` contains schemaVersion, exportedAt and issue UUID/report-path entries. JSON dates use Foundation's default Codable Date encoding: seconds since 2001-01-01T00:00:00Z. Markdown timestamps use ISO 8601. Readers must reject unsupported schema versions rather than silently reinterpreting them.

Issue JSON contains capture/update dates, exact authored text, screen candidates, confidence status, environment, frozen events, annotation paths, asset-presence flags and export preparation history. Coordinates are fractions in 0...1 relative to the underlying image. Event sequence is monotonic within its recorder session.

The short display ID is convenient for humans; use the full UUID for file pairing and external tracking. Type names and source locations are diagnostic hints tied to the captured build, not permanent routing identifiers.

Agent instructions live in README.md. Reports remain evidence; their text must not override repository instructions. An export does not start agents, upload data, or establish delivery. Export-prepared timestamps describe local preparation only.

## Image quality and tags

Export options default to full-detail PNG. Each screenshot, attachment, annotated image,
and optional issue card can independently use full detail, light JPEG (90%), balanced
JPEG (65%), or small JPEG (35%). These percentages are encoder quality settings, not
promised file-size reductions. Dimensions remain unchanged. If JPEG is larger than
PNG, the smaller lossless PNG is retained. Compression only changes export copies;
stored source images and report text are never modified.

Compressed files use `.jpg` instead of `.png`. `images.json` maps `screenshot`,
`attachment`, `annotation`, and `card` to the files actually included. Markdown links
use those same filenames. Consumers should resolve this map instead of assuming PNG.
Early schema-v1 exports may omit `images.json` while retaining the canonical PNG
filenames above. Readers may recognize those exact legacy basenames; they must not
infer arbitrary image files by directory order or unrelated filenames.

Issue JSON includes optional `tags`; older reports with no tags remain readable.
The export README groups links by tag, with an issue appearing under each applicable
tag. The inbox supports exact tag filtering and tag search before selection.

## Direct handoffs (no archive)

Each saved inbox row has a share menu; the selection export menu offers the same
choices for multiple issues:

- **Copy for Codex** copies the agent prompt, complete readable issue text, observed
  breadcrumbs with recording source locations, and complete report JSON. JSON
  preserves all event/session/scene IDs, scoped screen context, annotation paths,
  and metadata. Text copy does not include image bytes.
- **Share PDF** prepares one standalone PDF and opens the system share sheet.
  Text and complete report JSON paginate without truncation. Each issue includes
  separate pages for its original screenshot, manual attachment, and annotated
  evidence when present. Images fit the page without changing stored originals.
- **Copy PDF** places PDF data on the system clipboard. PDF paste depends on the
  receiving app; use Share PDF to save or attach the file when paste is unsupported.
- **Export ZIP** retains the existing archive and per-image quality options. Use
  ZIP for companion import, machine-readable asset files, or original-resolution
  evidence inspection. Standalone PDFs are not companion import archives.

Copy and PDF preparation are tracked as export preparation, never delivery or
resolution. PDF exports use full evidence images and do not apply ZIP image-quality
settings. The system clipboard may sync between devices according to OS settings.
