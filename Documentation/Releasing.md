# Releasing IssueCapture

IssueCapture is distributed as a source Swift package from this GitHub repository. Swift Package Manager does not consume this package through GitHub Packages' npm/Maven-style registry; the repository URL and Git tags are the package registry boundary.

## Create a release

1. Update package source and documentation.
2. Commit the change to the default branch.
3. Create and push an annotated semantic-version tag:

   ```sh
   git tag -a 1.0.0 -m "Release 1.0.0"
   git push origin 1.0.0
   ```

4. GitHub Actions validates the package and creates the GitHub Release with generated notes.

Use a patch version for backward-compatible fixes, a minor version for backward-compatible API additions, and a major version for breaking API changes. Never move or reuse a published tag.

## Consume updates

Consumers should use a lower-bound requirement such as:

```swift
.package(url: "https://github.com/vdeaugustine/IssueCapture.git", from: "1.0.0")
```

Xcode records the resolved version and revision in the consumer's `Package.resolved`. To update manually, use **File → Packages → Update to Latest Package Versions**. Consumer teams can use Renovate or their own dependency bot for automated SwiftPM update pull requests; this repository's Dependabot configuration tracks GitHub Actions updates.

## Release checks

The tag workflow checks the manifest and builds the package for the iOS simulator. Physical-device behavior and consuming-app integration remain host-repository responsibilities.
