# Chrome acceptance check — October 17, 2026

The user explicitly requested installing the extension in Chrome and verifying the full capture, save, and export flow. Installation of this unpacked local extension was separately approved. No product defect was observed in this acceptance flow; no implementation changes were needed.

## Environment

- Google Chrome 155.0.0.0 on macOS, existing desktop profile.
- IssueCapture Web 0.1.0, unpacked from `ChromeExtension/dist/extension`, built from repository commit `d1d3fed`.
- Synthetic local HTTP checkout fixture at `http://127.0.0.1:4187/`, titled `IssueCapture acceptance — checkout fixture`. It deliberately clips the Continue button and contains no personal page content.
- Captured viewport: 1728 × 997 CSS pixels, device pixel ratio 2. Exported PNGs: 3456 × 1994 pixels.

## Observed results

| Step | Result |
| --- | --- |
| Load unpacked extension | Installed, enabled, and available in Chrome's toolbar. |
| Invoke toolbar capture | Screenshot saved before editor opens; draft editor opened in its own extension tab. |
| Page context | Correct fixture URL and title, viewport, scroll coordinates, browser user agent, language, timezone, and timestamp displayed and exported. |
| Author notes | Title, observed behavior, expected behavior, multiline reproduction steps, and three tags entered. |
| Literal and Unicode text | `café → ✓` and literal `<script>alert("evidence")</script>` preserved as authored evidence; no script execution observed. |
| Annotate | Arrow and rectangle drawn over the clipped button. A pen stroke was added and undone. |
| Save | Report appeared as Open; draft count returned to zero. |
| Persist and reopen | Reloaded inbox, reopened report, and observed notes, tags, context, arrow, and rectangle intact. |
| Export ZIP | Selected saved report and clicked Export ZIP. Chrome showed the download as Done; saved report remained in the inbox. |
| Archive integrity | Python `zipfile.testzip()` passed for every entry; PNG chunk CRC checks also passed. |
| Report content | Exact authored title, description, expected behavior, multiline steps, tags, saved state, page context, and ZIP export history matched assertions against downloaded JSON and Markdown. |
| Image evidence | Original and annotated PNGs are separate, valid images of the expected dimensions. Visual inspection confirms the original has no marks and the annotated copy contains the arrow and box. JSON contains exactly those two normalized annotation paths; the undone pen stroke is absent. |

## Evidence

- Issue ID: `a00434ce-a9b4-413f-82ac-dd8bce5dd957`.
- Download: `IssueCapture-Web-2026-10-17T23-15-46-066Z.zip` (420,066 bytes) in the local Downloads folder.
- Archive entries: root README and manifest; per-issue Markdown, JSON, original PNG, and annotated PNG.
- Original PNG SHA-256: `af3fed73628a0da9837d09a4830f453302ca2ebf4b42e3cdb826310919da7c0a`.
- Annotated PNG SHA-256: `8774f7149a9b70718dbb8e7fd9ac1e2451e5bc6eb7327b804279fbd8a7fdccdc`.
- Reopened editor screenshot and local archive assertion output were retained in the task's visualization/scratch directories. Generated user evidence is not committed to the repository.

The extension and synthetic saved issue were left installed in Chrome. The temporary fixture server was stopped after verification.

## Scope

This verifies one real desktop Chrome toolbar capture → notes/annotations → save → reload → reopen → downloaded ZIP flow. It does not establish behavior across all websites, protected media, restricted Chrome pages, storage failures, other browser versions, or Chrome Web Store publication. Keyboard shortcuts, clipboard handoff, batch selection of multiple reports, screenshot exclusion, manual attachments, status changes, and deletion were not exercised in this run. No automated browser suite or iOS tests were run.
