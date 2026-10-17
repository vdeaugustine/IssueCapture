# IssueCapture Web

An independent Chrome extension with a web inbox for capturing issues, keeping context, and exporting evidence when you're ready. Version **0.1.0**. No Swift package integration, account, server, external libraries, or build dependencies.

## Install in Chrome

1. From the repository root, run `pnpm --dir ChromeExtension build` (Node.js 22+). No dependency installation is needed.
2. Open `chrome://extensions` in Chrome and enable **Developer mode**.
3. Choose **Load unpacked**, then select `ChromeExtension/dist/extension`.
4. Pin **IssueCapture — Web** in the Chrome toolbar.
5. Open an HTTP or HTTPS page. Click the extension and choose **Capture this page**.

The build also creates `ChromeExtension/dist/issuecapture-web-0.1.0.zip` for distribution. Extract this ZIP before choosing Load unpacked. This is an unpacked development extension; it has not been published to the Chrome Web Store. Keep the unpacked folder in a stable location and use the extension's **Reload** button after rebuilding. Repeatedly removing and reinstalling can lose local data; export first.

**Shortcut:** Command+Shift+U on Mac; Ctrl+Shift+U on other platforms. Chrome or another extension can reserve this shortcut. Customize it at `chrome://extensions/shortcuts`.

## Capture → describe → save → export

- **Capture this page** saves the visible viewport as a PNG before opening the editor in a new tab. Captured reports appear as drafts immediately, even if the editor is closed without a title.
- Review the page context: title, full URL, viewport, device pixel ratio, scroll coordinates, language, browser user agent, timezone, and timestamp. This is point-in-time context, not a source-code identity or application-state snapshot.
- Describe the issue, expected behavior, reproduction steps, type (Bug, Improvement, Question), status, and comma-separated tags. Draft edits save locally after a short pause. **Save issue** requires a title and completes the draft.
- Draw optional arrows, boxes, and pen marks on the screenshot. Undo removes the last mark. Pointer drawing is optional; the text workflow uses labeled native keyboard-accessible controls.
- A text-only report can attach one PNG, JPEG, or WebP screenshot up to 20 MB and 40 megapixels. Captured and manually attached original image bytes remain unchanged. Annotations are separate normalized coordinates and render to a separate PNG at export time. To use a different original, create a new report.
- Search titles, notes, IDs, tags, and page metadata; filter by type or status; reopen and edit reports; mark them resolved yourself.
- Select reports to **Copy for agent** (full Markdown and JSON, without image bytes), or **Export ZIP** (notes, JSON, original images, and annotated PNGs). Uncheck **Include screenshot in exports** to omit the original, annotations, and annotation coordinates from a handoff. This does not delete the locally saved image.
- Export preparation is recorded locally. It does not establish download completion, delivery, or resolution. Reports stay saved after export. Individual deletion requires confirmation and is permanent.

Use one editor per issue at a time; simultaneous edits in multiple tabs do not merge.

## Run the web app without the extension

```sh
pnpm --dir ChromeExtension dev
```

Open [the local inbox](http://127.0.0.1:4173). It supports manual text reports, screenshot attachments, annotations, local storage, search, and exports. The server binds to localhost only; set `PORT` to change its port. Stop with Ctrl+C. Serve the same `src` directory on HTTPS to host it elsewhere; there is no backend. The initial entry point is `src/app/app.html`. Clipboard copy requires HTTPS or localhost.

Automatic capture of another web page requires the Chrome extension. Website sandboxing prevents the standalone inbox from inspecting arbitrary tabs. Extension storage and web app storage are separate; they do not synchronize. The web app requires a connection to load its files; once loaded, capture editing and export do not require a remote service. No offline service worker or installable PWA is claimed.

## Storage and permissions

Reports and image data live in IndexedDB within the extension's browser profile (or the web app's origin). There is no telemetry, cloud sync, remote script, or upload. Export files and clipboard contents leave that store only when you request them; clipboard sync is controlled by the OS/browser. Data is not encrypted by this app. Clearing site data or uninstalling the extension can remove reports. ZIP exports are handoffs, not re-importable backups in this initial version.

The extension requests only:

| Permission | Reason |
| --- | --- |
| `activeTab` | Temporary access to the page where you invoke the extension. |
| `scripting` | Read explicit browser/page metadata for that capture. |
| `unlimitedStorage` | Keep local screenshots without the ordinary extension quota. Available disk space still limits saves. |

No persistent host permissions, background page recorder, form/input collection, cookies, network inspection, console recording, or browsing-history permission. No access to page text or the DOM tree beyond document title and language. Full URLs and visible screenshot contents can still contain sensitive information: review them before exporting. Screenshot exclusion is omission, not redaction.

Chrome's API grants `activeTab` on user invocation and supports screenshot capture with that permission. See the official [activeTab documentation](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab), [scripting API](https://developer.chrome.com/docs/extensions/reference/api/scripting), and [tabs API](https://developer.chrome.com/docs/extensions/reference/api/tabs).

## Export format: issuecapture-web v1

```text
README.md
manifest.json
issues/<UUID>/issue.md
issues/<UUID>/issue.json
issues/<UUID>/screenshot-original.png   # .jpg / .webp for those manual originals
issues/<UUID>/screenshot-annotated.png  # when annotations exist
```

The UTF-8 stored ZIP32 archive includes CRC32 checksums. `manifest.json` declares `format: "issuecapture-web"`, `schemaVersion: 1`, ISO 8601 `exportedAt`, and report paths. Each JSON report declares `platform: "web"`, exact authored text, context, normalized annotation paths, asset filenames, draft/status fields, and export preparation history. Images are separate assets, with no base64 image data embedded in report JSON. Dates use ISO 8601 strings. Exported text is never shortened. Readers must check the format and schema version explicitly.

**This format is separate from the iOS export schema and is not supported by the existing Mac companion importer.** Agent instructions identify report text and page metadata as untrusted evidence.

## Limits and validation

- Captures cover the current visible viewport only, not an entire scrolling page, hidden content, browser chrome, or guaranteed protected-media output. The app permits only HTTP/HTTPS capture; Chrome settings, Chrome Web Store pages, and other restricted pages can reject script injection. Use a manual report for those pages.
- Active-tab and URL checks reject obvious tab switches or navigations during capture. Context and pixels are not an atomic snapshot of animations, same-URL state changes, or dynamic page rendering.
- No automatic action breadcrumbs, errors, network requests, application state, source file mapping, PDF export, redaction, report import, or synchronization in this initial release.
- Storage saves can fail when disk or browser policy blocks persistence. Failed edits stay visible and warn before leaving. Keep exports of important evidence.
- Build and JavaScript syntax checks passed. The local server started and the empty inbox rendered in the Codex in-app browser; a root-route asset resolution issue found during that review was corrected.
- The requested end-to-end acceptance check passed in desktop Chrome 155 on October 17, 2026: toolbar capture, notes and annotations, save, inbox reload, reopen, ZIP download, archive integrity, exact Unicode/multiline report text, and separate original/annotated images. See [observed results and remaining coverage](Acceptance.md). Shortcuts, clipboard, and other paths listed there were not exercised. No automated browser suite or iOS tests were run; this does not establish Chrome Web Store approval.

## Release identity

The extension has its own manifest/package version, **0.1.0**, independent of Swift package versions. Repository tag **1.9.0** introduces this standalone tool without changing iOS package APIs or sources. Existing repository release automation still builds the Swift package; it does not publish the extension to the Chrome Web Store.
