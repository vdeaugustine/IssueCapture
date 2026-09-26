import Foundation
import ImageIO
import UIKit

private func decodeCommand(_ bytes: UnsafePointer<UInt8>?, _ length: Int32) -> UnityCommand? {
    guard let bytes, length > 0, length <= 65_536 else { return nil }
    return try? JSONDecoder().decode(UnityCommand.self, from: Data(bytes: bytes, count: Int(length)))
}

/// C ABI installation, called by the Unity Objective-C++ adapter with its explicit app window.
/// Returns 1 when installed, 0 for invalid input or a window not yet attached to a scene.
@_cdecl("ICNativeInitialize")
public func issueCaptureUnityInitialize(_ window: UnsafeRawPointer?, _ bytes: UnsafePointer<UInt8>?,
                                        _ length: Int32) -> Int32 {
    guard Thread.isMainThread, let window, let command = decodeCommand(bytes, length) else { return 0 }
    return MainActor.assumeIsolated {
        let window = Unmanaged<UIWindow>.fromOpaque(window).takeUnretainedValue()
        return UnityRuntime.shared.initialize(window: window, command: command) ? 1 : 0
    }
}

/// Copies a bounded UTF-8 command before returning. Background outcomes are delivered on the main queue.
@_cdecl("ICNativeCommand")
public func issueCaptureUnityCommand(_ bytes: UnsafePointer<UInt8>?, _ length: Int32) {
    guard let command = decodeCommand(bytes, length) else { return }
    if Thread.isMainThread {
        MainActor.assumeIsolated { UnityRuntime.shared.apply(command) }
    } else {
        UnityCommandQueue.shared.enqueue(command)
    }
}

/// Main-thread capture handshake: 1 accepts the request and freezes context, 0 does nothing.
@_cdecl("ICNativeBeginCapture")
public func issueCaptureUnityBeginCapture() -> Int32 {
    guard Thread.isMainThread else { return 0 }
    return MainActor.assumeIsolated { UnityRuntime.shared.beginCapture() ? 1 : 0 }
}

/// Copies and validates a PNG before opening the editor. Invalid data opens a text-only report.
@_cdecl("ICNativeFinishCapture")
public func issueCaptureUnityFinishCapture(_ bytes: UnsafePointer<UInt8>?, _ length: Int32) {
    guard Thread.isMainThread else { return }
    var image: UIImage?
    if let bytes, length > 0, length <= 33_554_432 {
        let data = Data(bytes: bytes, count: Int(length))
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           CGImageSourceGetType(source) as String? == "public.png",
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           width > 0, height > 0, width <= 16_000_000 / height {
            image = UIImage(data: data)
        }
    }
    MainActor.assumeIsolated { UnityRuntime.shared.finishCapture(image) }
}

/// Returns 1 while native reporting owns presentation or awaits a frame; main thread only.
@_cdecl("ICNativeIsPresenting")
public func issueCaptureUnityIsPresenting() -> Int32 {
    guard Thread.isMainThread else { return 0 }
    return MainActor.assumeIsolated { UnityRuntime.shared.isPresenting ? 1 : 0 }
}
