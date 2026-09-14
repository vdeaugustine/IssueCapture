import Foundation
@testable import CompanionCore

/// Minimal stored ZIP32 writer used by tests, matching the shape the iOS
/// exporter produces. It can also emit deliberately hostile archives.
enum StoredZIP {
    struct Member {
        var path: String
        var bytes: Data
        /// Compression method recorded in the headers. 0 is stored.
        var method: UInt16 = 0
        /// Unix mode recorded in the external attributes, when non-nil.
        var unixMode: UInt32?
    }

    /// Archives every regular file under `directory`, sorted by path.
    static func archive(directory: URL, to destination: URL) throws {
        let manager = FileManager.default
        let base = directory.standardizedFileURL.path
        let files = (manager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL } ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.path < $1.path }
        let members = try files.map {
            Member(path: String($0.standardizedFileURL.path.dropFirst(base.count + 1)),
                   bytes: try Data(contentsOf: $0))
        }
        try write(members: members, to: destination)
    }

    /// Writes an archive from explicit members.
    static func write(members: [Member], to destination: URL) throws {
        var output = Data()
        var central = Data()
        var count = 0
        for member in members {
            let name = Data(member.path.utf8)
            let crc = CRC32.checksum(member.bytes)
            let offset = UInt32(output.count)
            output.appendLE(UInt32(0x0403_4b50)); output.appendLE(UInt16(20))
            output.appendLE(UInt16(0x0800)); output.appendLE(member.method)
            output.appendLE(UInt16(0)); output.appendLE(UInt16(33))
            output.appendLE(crc); output.appendLE(UInt32(member.bytes.count))
            output.appendLE(UInt32(member.bytes.count))
            output.appendLE(UInt16(name.count)); output.appendLE(UInt16(0))
            output.append(name); output.append(member.bytes)

            let versionMadeBy: UInt16 = member.unixMode == nil ? 20 : (3 << 8) | 20
            central.appendLE(UInt32(0x0201_4b50)); central.appendLE(versionMadeBy)
            central.appendLE(UInt16(20)); central.appendLE(UInt16(0x0800))
            central.appendLE(member.method); central.appendLE(UInt16(0)); central.appendLE(UInt16(33))
            central.appendLE(crc); central.appendLE(UInt32(member.bytes.count))
            central.appendLE(UInt32(member.bytes.count))
            central.appendLE(UInt16(name.count))
            for _ in 0..<4 { central.appendLE(UInt16(0)) }
            central.appendLE((member.unixMode ?? 0) << 16)
            central.appendLE(offset); central.append(name)
            count += 1
        }
        let centralOffset = UInt32(output.count)
        output.append(central)
        output.appendLE(UInt32(0x0605_4b50))
        output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
        output.appendLE(UInt16(count)); output.appendLE(UInt16(count))
        output.appendLE(UInt32(central.count)); output.appendLE(centralOffset)
        output.appendLE(UInt16(0))
        try output.write(to: destination, options: .atomic)
    }
}

private extension Data {
    mutating func appendLE<Value: FixedWidthInteger>(_ value: Value) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
