import AppKit
import CompanionCore
import SwiftUI
import UniformTypeIdentifiers

/// The IssueCapture Mac companion.
///
/// Version one works entirely offline. It needs no API key and makes no model
/// calls.
@main
struct CompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel?
    @State private var startupFailure: String?

    var body: some Scene {
        WindowGroup("IssueCapture Companion") {
            Group {
                if let model {
                    InboxView(model: model)
                } else if let startupFailure {
                    ContentUnavailableView("Storage unavailable", systemImage: "externaldrive.badge.xmark",
                                           description: Text(startupFailure))
                } else {
                    ProgressView().task { start() }
                }
            }
            .frame(minWidth: 1_080, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Export…") { openExport() }
                    .keyboardShortcut("o")
                    .disabled(model == nil)
                Button("Choose Watched Folder…") { chooseWatchedFolder() }
                    .disabled(model == nil)
            }
        }
    }

    private func start() {
        do { model = try AppModel() } catch { startupFailure = error.localizedDescription }
    }

    /// Opens an export ZIP or an expanded export folder.
    ///
    /// The companion never registers itself as the handler for all ZIP files.
    private func openExport() {
        guard let model else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip, .folder]
        panel.message = "Choose an IssueCapture export ZIP or an expanded export folder."
        panel.prompt = "Import"
        guard panel.runModal() == .OK else { return }
        model.importSources(panel.urls)
    }

    private func chooseWatchedFolder() {
        guard let model else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a folder to watch for finished export archives."
        panel.prompt = "Watch"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.setWatchedFolder(url)
    }
}

/// Gives the executable a regular application presence and a usable window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
