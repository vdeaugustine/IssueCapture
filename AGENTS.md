# Package development

- Keep each source file focused and below 500 lines.
- Document public declarations and preserve disabled-host no-op behavior.
- Use explicit screen context; do not infer source identity from UIKit internals.
- Preserve existing controls and accessibility when instrumenting examples.
- Keep original screenshots immutable and exported text lossless.
- Record validation honestly. Do not run tests on finished tasks unless explicitly requested.
- Consumer setup assignment: Documentation/AgentHandoff.md.
- Consumer adoption rules: Documentation/Integration.md.
