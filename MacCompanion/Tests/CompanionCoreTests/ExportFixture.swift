import Foundation
import IssueCaptureSchema
@testable import CompanionCore

/// Builds export folders and stored ZIP32 archives shaped exactly like the
/// iOS exporter's output, so tests exercise the real reader path.
enum ExportFixture {
    struct IssueSpec {
        var id = UUID()
        var projectID = "demo.project"
        var capturedAt = Date(timeIntervalSinceReferenceDate: 700_000)
        var description = "Save button does nothing"
        var expectedBehavior = "The profile saves"
        var reproductionNotes = "Tapped save twice"
        var screens: [IssueScreenContext] = [ExportFixture.screen(name: "Profile")]
        var contextStatus = IssueContextStatus.accepted
        var environment: [String: String] = ["appVersion": "1.2.0", "build": "44",
                                             "systemVersion": "17.4", "deviceModel": "iPhone"]
        var events: [IssueEvent] = []
        var captureStatus = "rendered from host window"
        var annotations: [IssueAnnotation] = []
        var tags: [String]? = nil
        var hasScreenshot = true
        var hasAttachment = false
        /// Image kind raw value to declared filename and bytes.
        var images: [String: (name: String, bytes: Data)] = [
            "screenshot": ("screenshot-original.png", Data("screenshot-bytes".utf8))
        ]
        /// Filenames declared in images.json but deliberately not written.
        var omittedFiles: Set<String> = []

        var report: IssueReport {
            IssueReport(id: id, projectID: projectID, capturedAt: capturedAt, updatedAt: capturedAt,
                        description: description, expectedBehavior: expectedBehavior,
                        reproductionNotes: reproductionNotes, screens: screens,
                        contextStatus: contextStatus, environment: environment, events: events,
                        captureStatus: captureStatus, annotations: annotations,
                        hasScreenshot: hasScreenshot, hasAttachment: hasAttachment, tags: tags)
        }
    }

    static func screen(name: String, stableID: String? = nil, typeName: String? = nil,
                       file: String = "Demo/ProfileScreen.swift", line: UInt = 12,
                       id: UUID = UUID(), parentID: UUID? = nil) -> IssueScreenContext {
        IssueScreenContext(id: id, stableID: stableID, name: name,
                           typeName: typeName ?? "DemoApp.\(name)Screen",
                           file: file, line: line, parentID: parentID)
    }

    static func event(id: UUID = UUID(), name: String = "profile.save",
                      screen: IssueScreenContext? = nil, sequence: UInt64 = 1) -> IssueEvent {
        IssueEvent(id: id, sessionID: UUID(), sceneID: "scene",
                   timestamp: Date(timeIntervalSinceReferenceDate: 690_000), sequence: sequence,
                   category: "action", name: name, metadata: [:], screen: screen,
                   file: "Demo/ProfileScreen.swift", line: 30)
    }

    /// Writes an export folder and returns its root.
    @discardableResult
    static func writeFolder(issues: [IssueSpec], at root: URL,
                            exportedAt: Date = Date(timeIntervalSinceReferenceDate: 700_100),
                            manifestOverrides: [UUID: UUID] = [:],
                            manifestPaths: [UUID: String] = [:],
                            manifestSchemaVersion: Int = 1,
                            duplicateFirstEntry: Bool = false) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        var items: [IssueExportManifest.Item] = []
        for spec in issues {
            let folder = root.appendingPathComponent("issues").appendingPathComponent(spec.id.uuidString)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            var declared: [String: String] = [:]
            for (kind, image) in spec.images {
                declared[kind] = image.name
                guard !spec.omittedFiles.contains(image.name) else { continue }
                try image.bytes.write(to: folder.appendingPathComponent(image.name))
            }
            try IssueExportSchema.encoder().encode(declared)
                .write(to: folder.appendingPathComponent("images.json"))
            try IssueExportSchema.encoder().encode(spec.report)
                .write(to: folder.appendingPathComponent("issue.json"))
            try "# \(spec.report.displayID)\n".write(to: folder.appendingPathComponent("issue.md"),
                                                     atomically: true, encoding: .utf8)
            let declaredID = manifestOverrides[spec.id] ?? spec.id
            let path = manifestPaths[spec.id] ?? "issues/\(spec.id.uuidString)/issue.json"
            items.append(.init(id: declaredID, report: path))
        }
        if duplicateFirstEntry, let first = items.first { items.append(first) }
        let manifest = IssueExportManifest(schemaVersion: manifestSchemaVersion,
                                           exportedAt: exportedAt, issues: items)
        try IssueExportSchema.encoder().encode(manifest)
            .write(to: root.appendingPathComponent("manifest.json"))
        try "# IssueCapture export\n".write(to: root.appendingPathComponent("README.md"),
                                            atomically: true, encoding: .utf8)
        return root
    }

    /// Writes an export archive and returns its URL.
    @discardableResult
    static func writeArchive(issues: [IssueSpec], at url: URL, workspace: URL,
                             exportedAt: Date = Date(timeIntervalSinceReferenceDate: 700_100),
                             manifestOverrides: [UUID: UUID] = [:],
                             manifestSchemaVersion: Int = 1) throws -> URL {
        let staging = workspace.appendingPathComponent("stage-" + UUID().uuidString)
        try writeFolder(issues: issues, at: staging, exportedAt: exportedAt,
                        manifestOverrides: manifestOverrides,
                        manifestSchemaVersion: manifestSchemaVersion)
        try StoredZIP.archive(directory: staging, to: url)
        try FileManager.default.removeItem(at: staging)
        return url
    }
}
