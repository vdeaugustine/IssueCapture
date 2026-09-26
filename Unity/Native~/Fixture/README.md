# Native linking / report-flow fixture

This UIKit app models the Unity-iPhone → UnityFramework → IssueCaptureUnity link.
Its `UnityGetMainWindow` is an explicit stand-in, not the Unity engine. It exercises
C ABI initialization, screen registration, a late background outcome, supplied PNG
capture, and the real editor, inbox and export UI. It cannot prove Metal rendering,
IL2CPP marshaling, Unity pause/resume, or an actual Unity iOS export.

Generate into a new temporary folder using the installed Unity 6 compiler/PBX
assembly and XcodeGen:

```sh
python3 script/prepare_unity_fixture.py --unity /path/to/Unity.app --output /tmp/IssueCaptureFixture
xcodebuild -resolvePackageDependencies -project /tmp/IssueCaptureFixture/UnityBridgeHost.xcodeproj -scheme UnityBridgeHost
xcodebuild -project /tmp/IssueCaptureFixture/UnityBridgeHost.xcodeproj -scheme UnityBridgeHost -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

The preparation script calls the actual postprocessor's source-copy and PBX
configuration methods. It does not simulate Unity's complete build callback or run
tests. Open the generated project to launch and interact with the reporter. No
fixture or generated project is included in a consumer because this directory is
inside Unity's ignored `Native~` folder. The fixture has no XCTest targets.

For normal installation, use the UPM package; do not copy this app into a game.
