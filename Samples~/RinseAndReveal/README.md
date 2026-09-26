# Rinse & Reveal reference example

This is a minimal uGUI demonstration, not the Rinse & Reveal game source.
Import this sample from Package Manager, then select **Tools → IssueCapture →
Create sample Boardwalk and Clean**. It creates new scenes under
`Assets/IssueCaptureExampleScenes` and adds them to Build Settings. Existing files
are never overwritten. Use a separate sample project if your game already has
scenes named Boardwalk or Clean. Install uGUI (`com.unity.ugui` 2.0.0 for Unity 6)
and select **Active Input Handling: Input Manager (Old)** or **Both** for this
sample's StandaloneInputModule. Real game integrations retain their input system.

Build Boardwalk and Clean for iOS 15+ with **Development Build** enabled and export
to a fresh folder. The buttons demonstrate explicit scene instances, a retained
Play/Inventory pair, a child Pause overlay, a delayed operation, capture, inbox,
and diagnostics. Start an async operation and switch scenes before it finishes:
the outcome must retain Boardwalk as its origin when Clean is active.

The editor and production builds still show the example controls for navigation,
but show no reporting controls and perform no native recording. The example's
timer stands in for a real async operation. In a consumer, put `Action` before the
existing handler's operation and pass its `Reporter` to the real completion path.
Do not replace existing Buttons, listeners, navigation, or accessibility.

See `Documentation/UnityIntegration.md` in the package repository for the full
installation, activity, privacy, capture and build contracts.
