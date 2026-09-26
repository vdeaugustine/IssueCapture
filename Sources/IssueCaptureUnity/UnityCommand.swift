import Foundation
import IssueCapture

struct UnityCommand: Decodable {
    let operation: String
    let session: String
    var projectID: String?
    var sourceRevision: String?
    var eventLimit: Int?
    var eventByteLimit: Int?
    var screen: UnityScreen?
    var active: Bool?
    var category: String?
    var name: String?
    var result: String?
    var file: String?
    var line: UInt?
}

struct UnityScreen: Decodable {
    let id: UUID
    let parentID: String
    let stableID: String
    let name: String
    let typeName: String
    let file: String
    let line: UInt

    var context: IssueScreenContext {
        .init(id: id, stableID: String(stableID.prefix(200)), name: String(name.prefix(200)),
              typeName: String(typeName.prefix(300)), file: String(file.prefix(300)),
              line: line, parentID: UUID(uuidString: parentID))
    }
}
