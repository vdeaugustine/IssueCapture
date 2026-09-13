import Foundation

/// Minimal ZIP32 writer using uncompressed entries and UTF-8 filenames.
/// Files are streamed to avoid duplicating an entire screenshot batch in memory.
struct StoredZIPWriter {
    private struct Entry {
        let name: Data
        let checksum: UInt32
        let size: UInt32
        let offset: UInt32
    }

    static func archive(directory: URL, destination: URL) throws {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw CocoaError(.fileReadUnknown)
        }
        let files = try enumerator.compactMap { $0 as? URL }.filter {
            try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }.sorted { $0.path < $1.path }
        guard files.count <= Int(UInt16.max) else { throw NSError(domain: "IssueCapture.ZIP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Export exceeds ZIP32 limits."]) }
        guard manager.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var entries: [Entry] = []
        for file in files { entries.append(try append(file: file, root: directory, to: handle)) }
        let centralOffset = try checkedOffset(handle)
        for entry in entries { try handle.write(contentsOf: centralHeader(entry)) }
        let centralSize = try checkedOffset(handle) - centralOffset
        var end = Data()
        end.appendLE(UInt32(0x06054b50))
        end.appendLE(UInt16(0)); end.appendLE(UInt16(0))
        end.appendLE(UInt16(entries.count)); end.appendLE(UInt16(entries.count))
        end.appendLE(centralSize); end.appendLE(centralOffset); end.appendLE(UInt16(0))
        try handle.write(contentsOf: end)
        try handle.synchronize()
    }

    private static func append(file: URL, root: URL, to handle: FileHandle) throws -> Entry {
        let bytes = try Data(contentsOf: file, options: .mappedIfSafe)
        let name = Data(file.path.dropFirst(root.path.count + 1).utf8)
        guard bytes.count < Int(UInt32.max), name.count <= Int(UInt16.max) else {
            throw NSError(domain: "IssueCapture.ZIP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Export exceeds ZIP32 limits."])
        }
        let entry = Entry(name: name, checksum: crc32(bytes), size: UInt32(bytes.count), offset: try checkedOffset(handle))
        var header = Data()
        header.appendLE(UInt32(0x04034b50)); header.appendLE(UInt16(20)); header.appendLE(UInt16(0x0800))
        header.appendLE(UInt16(0)); header.appendLE(UInt16(0)); header.appendLE(UInt16(33))
        header.appendLE(entry.checksum); header.appendLE(entry.size); header.appendLE(entry.size)
        header.appendLE(UInt16(name.count)); header.appendLE(UInt16(0)); header.append(name)
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: bytes)
        _ = try checkedOffset(handle)
        return entry
    }

    private static func centralHeader(_ entry: Entry) -> Data {
        var data = Data()
        data.appendLE(UInt32(0x02014b50)); data.appendLE(UInt16(20)); data.appendLE(UInt16(20))
        data.appendLE(UInt16(0x0800)); data.appendLE(UInt16(0)); data.appendLE(UInt16(0)); data.appendLE(UInt16(33))
        data.appendLE(entry.checksum); data.appendLE(entry.size); data.appendLE(entry.size)
        data.appendLE(UInt16(entry.name.count))
        for _ in 0..<4 { data.appendLE(UInt16(0)) }
        data.appendLE(UInt32(0)); data.appendLE(entry.offset); data.append(entry.name)
        return data
    }

    private static func checkedOffset(_ handle: FileHandle) throws -> UInt32 {
        let offset = try handle.offset()
        guard offset < UInt64(UInt32.max) else { throw NSError(domain: "IssueCapture.ZIP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Export exceeds ZIP32 limits."]) }
        return UInt32(offset)
    }

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var remainder = UInt32(value)
        for _ in 0..<8 { remainder = (remainder >> 1) ^ ((remainder & 1) == 1 ? 0xedb88320 : 0) }
        return remainder
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var checksum: UInt32 = 0xffffffff
        for byte in data { checksum = (checksum >> 8) ^ crcTable[Int((checksum ^ UInt32(byte)) & 0xff)] }
        return checksum ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendLE<Value: FixedWidthInteger>(_ value: Value) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
