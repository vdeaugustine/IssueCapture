import Foundation

/// A semantic action or outcome; metadata must contain only explicitly allowed values.
public struct IssueAction: Sendable {
    /// Event category.
    public let category: String
    /// Stable name, such as profile.save.
    public let name: String
    /// Bounded, explicitly supplied diagnostic fields.
    public let metadata: [String: String]

    /// Creates a diagnostic event description.
    public init(category: String, name: String, metadata: [String: String] = [:]) {
        self.category = category
        self.name = name
        self.metadata = metadata
    }
    /// Describes activation of an existing action handler.
    public static func tap(_ name: String) -> Self { .init(category: "action", name: name) }
    /// Describes an observed operation outcome.
    public static func outcome(_ name: String, metadata: [String: String] = [:]) -> Self {
        .init(category: "outcome", name: name, metadata: metadata)
    }
    /// Describes a host navigation change.
    public static func navigation(_ name: String) -> Self { .init(category: "navigation", name: name) }
}

/// An ordered event containing its original scoped screen context.
public struct IssueEvent: Codable, Identifiable, Sendable {
    /// Unique event identifier.
    public let id: UUID
    /// Recorder session identity.
    public let sessionID: UUID
    /// Owning scene identifier.
    public let sceneID: String
    /// Wall-clock timestamp.
    public let timestamp: Date
    /// Monotonic session sequence.
    public let sequence: UInt64
    /// Semantic event category.
    public let category: String
    /// Stable semantic name.
    public let name: String
    /// Explicit bounded metadata.
    public let metadata: [String: String]
    /// Original source scope; nil indicates a coverage gap.
    public let screen: IssueScreenContext?
    /// Recording call site.
    public let file: String
    /// Recording source line.
    public let line: UInt
}
