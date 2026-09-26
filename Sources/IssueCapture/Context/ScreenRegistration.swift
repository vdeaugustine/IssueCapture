import SwiftUI

/// Adopt on navigable and presented screens to supply diagnostic identity.
public protocol IssueReportableScreen: View {
    /// Human-readable screen label; defaults to the concrete Swift type name.
    static var issueScreenName: String { get }
}

public extension IssueReportableScreen {
    /// Default screen label derived from the explicitly supplied type.
    static var issueScreenName: String { String(describing: Self.self) }
}

private struct ReporterKey: EnvironmentKey {
    static let defaultValue = IssueReporter(recorder: nil, screen: nil)
}
private struct SessionKey: EnvironmentKey {
    static let defaultValue: CaptureSession? = nil
}

public extension EnvironmentValues {
    /// Reporting context inherited from the nearest registered ancestor screen.
    var issueReporter: IssueReporter {
        get { self[ReporterKey.self] }
        set { self[ReporterKey.self] = newValue }
    }
}

extension EnvironmentValues {
    var captureSession: CaptureSession? {
        get { self[SessionKey.self] }
        set { self[SessionKey.self] = newValue }
    }
}

public extension View {
    /// Registers a screen and injects its event sink into descendant views.
    /// Set isActive explicitly when host navigation keeps inactive screens mounted.
    func issueCaptureScreen<Screen: IssueReportableScreen>(
        _ screen: Screen.Type, id: String? = nil, isActive: Bool = true,
        file: String = #fileID, line: UInt = #line
    ) -> some View {
        modifier(ScreenRegistration(name: Screen.issueScreenName,
            typeName: String(reflecting: Screen.self), stableID: id,
            isActive: isActive, file: file, line: line))
    }
}

private struct ScreenRegistration: ViewModifier {
    @Environment(\.captureSession) private var session
    @Environment(\.issueReporter) private var parent
    @State private var instanceID = UUID()
    @State private var appeared = false
    let name: String
    let typeName: String
    let stableID: String?
    let isActive: Bool
    let file: String
    let line: UInt

    private var context: IssueScreenContext {
        .init(id: instanceID, stableID: stableID, name: name, typeName: typeName,
              file: file, line: line, parentID: parent.screen?.id)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.issueReporter, IssueReporter(recorder: session?.recorder, screen: context))
            .onAppear { appeared = true; update() }
            .onDisappear { appeared = false; session?.unregister(instanceID) }
            .onChange(of: isActive) { _ in update() }
            .onChange(of: session?.identity) { _ in update() }
    }

    private func update() {
        if appeared && isActive { session?.register(context) }
        else { session?.unregister(instanceID) }
    }
}
