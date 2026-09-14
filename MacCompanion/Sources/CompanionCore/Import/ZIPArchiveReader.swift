import Foundation

/// Reads the stored ZIP32 archives produced by the iOS exporter.
///
/// The reader validates structure, paths and checksums before anything is
/// written to disk. Compression methods other than "stored" are reported as
/// unsupported rather than partially imported.
public enum ZIPArchiveReader {
    /// Bounds applied before expansion so a hostile archive cannot exhaust disk.
    public struct Limits: Sendable {
        /// Maximum number of entries accepted.
        public var maximumEntries: Int
        /// Maximum total expanded bytes accepted.
        public var maximumExpandedBytes: Int
        /// Maximum length of a single archive-relative path.
        public var maximumPathLength: Int

        /// Creates limits.
        public init(maximumEntries: Int = 20_000,
                    maximumExpandedBytes: Int = 2 << 30,
                    maximumPathLength: Int = 1_024) {
            self.maximumEntries = maximumEntries
            self.maximumExpandedBytes = maximumExpandedBytes
            self.maximumPathLength = maximumPathLength
        }

        /// Default bounds.
        public static let standard = Limits()
    }

    /// One validated archive member.
    public struct Entry: Sendable {
        /// Archive-relative path, already validated as safe.
        public let path: String
        /// Whether the entry is a directory marker.
        public let isDirectory: Bool
        /// Stored bytes; empty for directories.
        public let data: Data
    }

    private struct CentralEntry {
        let name: String
        let versionMadeBy: UInt16
        let flags: UInt16
        let method: UInt16
        let crc: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let externalAttributes: UInt32
        let localOffset: UInt32
    }

    /// Expands `archive` into `destination`, which must already exist and be empty.
    ///
    /// - Throws: ``ImportFailure`` describing the exact rejection. Nothing is
    ///   written unless every entry passed validation.
    public static func expand(archive: URL, into destination: URL,
                              limits: Limits = .standard) throws {
        let bytes: Data
        do {
            bytes = try Data(contentsOf: archive, options: .mappedIfSafe)
        } catch {
            throw ImportFailure(code: .unreadableSource,
                                detail: "Could not read \(archive.lastPathComponent): \(error.localizedDescription)",
                                isRetryable: true)
        }
        let entries = try read(bytes: bytes, limits: limits)
        let root = destination.standardizedFileURL
        for entry in entries {
            let target = root.appendingPathComponent(entry.path).standardizedFileURL
            guard target.path == root.path || target.path.hasPrefix(root.path + "/") else {
                throw ImportFailure(code: .unsafeArchivePath,
                                    detail: "Entry \"\(entry.path)\" resolves outside the staged import folder.")
            }
            if entry.isDirectory {
                try create(directory: target)
            } else {
                try create(directory: target.deletingLastPathComponent())
                do {
                    try entry.data.write(to: target, options: .atomic)
                } catch {
                    throw ImportFailure(code: .storageFailure,
                                        detail: "Could not stage \"\(entry.path)\": \(error.localizedDescription)",
                                        isRetryable: true)
                }
            }
        }
    }

    /// Validates and decodes every member without writing to disk.
    public static func read(bytes: Data, limits: Limits = .standard) throws -> [Entry] {
        let centralEntries = try readCentralDirectory(bytes: bytes, limits: limits)
        var seen = Set<String>()
        var expanded = 0
        var result: [Entry] = []
        for central in centralEntries {
            let path = try safePath(central.name, limits: limits)
            guard seen.insert(path.normalized).inserted else {
                throw ImportFailure(code: .unsafeArchivePath,
                                    detail: "Archive declares \"\(path.normalized)\" more than once.")
            }
            if isSymlink(central) {
                throw ImportFailure(code: .unsafeArchivePath,
                                    detail: "Entry \"\(path.normalized)\" is a symbolic link, which is not imported.")
            }
            if path.isDirectory {
                result.append(Entry(path: path.normalized, isDirectory: true, data: Data()))
                continue
            }
            guard central.method == 0 else {
                throw ImportFailure(code: .unsupportedCompression,
                                    detail: "Entry \"\(path.normalized)\" uses compression method \(central.method). "
                                          + "This reader supports stored (method 0) entries only and will not partially import.")
            }
            expanded += Int(central.uncompressedSize)
            guard expanded <= limits.maximumExpandedBytes else {
                throw ImportFailure(code: .archiveLimitExceeded,
                                    detail: "Expanded size exceeds the \(limits.maximumExpandedBytes)-byte import limit.")
            }
            let data = try payload(bytes: bytes, central: central, path: path.normalized)
            guard CRC32.checksum(data) == central.crc else {
                throw ImportFailure(code: .checksumMismatch,
                                    detail: "Checksum mismatch for \"\(path.normalized)\"; the archive is damaged or truncated.")
            }
            result.append(Entry(path: path.normalized, isDirectory: false, data: data))
        }
        return result
    }

    private static func payload(bytes: Data, central: CentralEntry, path: String) throws -> Data {
        let cursor = Cursor(bytes)
        try cursor.seek(to: Int(central.localOffset), context: path)
        guard try cursor.u32() == 0x0403_4b50 else {
            throw ImportFailure(code: .notAnExport, detail: "Missing local header for \"\(path)\".")
        }
        try cursor.skip(22, context: path)
        let nameLength = Int(try cursor.u16())
        let extraLength = Int(try cursor.u16())
        try cursor.skip(nameLength + extraLength, context: path)
        return try cursor.read(Int(central.uncompressedSize), context: path)
    }

    private static func readCentralDirectory(bytes: Data, limits: Limits) throws -> [CentralEntry] {
        guard let endOffset = locateEndRecord(bytes) else {
            throw ImportFailure(code: .notAnExport,
                                detail: "No ZIP end-of-central-directory record was found. The file is not a stored ZIP32 export.")
        }
        let cursor = Cursor(bytes)
        try cursor.seek(to: endOffset + 8, context: "end record")
        let entriesOnDisk = try cursor.u16()
        let totalEntries = try cursor.u16()
        _ = try cursor.u32()
        let centralOffset = try cursor.u32()
        guard entriesOnDisk == totalEntries else {
            throw ImportFailure(code: .notAnExport, detail: "Multi-disk archives are not supported.")
        }
        guard totalEntries != UInt16.max, centralOffset != UInt32.max else {
            throw ImportFailure(code: .unsupportedCompression,
                                detail: "The archive uses ZIP64 extensions. The export writer emits stored ZIP32; this file cannot be imported.")
        }
        guard Int(totalEntries) <= limits.maximumEntries else {
            throw ImportFailure(code: .archiveLimitExceeded,
                                detail: "Archive declares \(totalEntries) entries, above the \(limits.maximumEntries) import limit.")
        }
        try cursor.seek(to: Int(centralOffset), context: "central directory")
        var entries: [CentralEntry] = []
        for _ in 0..<Int(totalEntries) {
            guard try cursor.u32() == 0x0201_4b50 else {
                throw ImportFailure(code: .notAnExport, detail: "Damaged central directory header.")
            }
            let versionMadeBy = try cursor.u16()
            _ = try cursor.u16()
            let flags = try cursor.u16()
            let method = try cursor.u16()
            try cursor.skip(4, context: "central directory")
            let crc = try cursor.u32()
            let compressed = try cursor.u32()
            let uncompressed = try cursor.u32()
            let nameLength = Int(try cursor.u16())
            let extraLength = Int(try cursor.u16())
            let commentLength = Int(try cursor.u16())
            try cursor.skip(4, context: "central directory")
            let externalAttributes = try cursor.u32()
            let localOffset = try cursor.u32()
            let nameData = try cursor.read(nameLength, context: "central directory")
            try cursor.skip(extraLength + commentLength, context: "central directory")
            guard compressed != UInt32.max, uncompressed != UInt32.max, localOffset != UInt32.max else {
                throw ImportFailure(code: .unsupportedCompression,
                                    detail: "The archive uses ZIP64 extensions, which this reader does not import.")
            }
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw ImportFailure(code: .unsafeArchivePath, detail: "An entry name is not valid UTF-8.")
            }
            entries.append(CentralEntry(name: name, versionMadeBy: versionMadeBy, flags: flags,
                                        method: method, crc: crc, compressedSize: compressed,
                                        uncompressedSize: uncompressed,
                                        externalAttributes: externalAttributes, localOffset: localOffset))
        }
        return entries
    }

    private static func isSymlink(_ entry: CentralEntry) -> Bool {
        // Unix creators record st_mode in the high half of the external attributes.
        guard entry.versionMadeBy >> 8 == 3 else { return false }
        return (entry.externalAttributes >> 16) & 0xF000 == 0xA000
    }

    private static func safePath(_ raw: String, limits: Limits) throws -> (normalized: String, isDirectory: Bool) {
        func reject(_ reason: String) -> ImportFailure {
            ImportFailure(code: .unsafeArchivePath, detail: "Entry \"\(raw)\" \(reason).")
        }
        guard !raw.isEmpty else { throw reject("has an empty name") }
        guard raw.utf8.count <= limits.maximumPathLength else { throw reject("exceeds the path length limit") }
        guard !raw.contains("\0") else { throw reject("contains a null byte") }
        guard !raw.contains("\\") else { throw reject("contains a backslash separator") }
        guard !raw.hasPrefix("/") else { throw reject("is an absolute path") }
        guard raw.range(of: "^[A-Za-z]:", options: .regularExpression) == nil else {
            throw reject("is an absolute path")
        }
        let isDirectory = raw.hasSuffix("/")
        let components = raw.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let meaningful = isDirectory ? Array(components.dropLast()) : components
        guard !meaningful.isEmpty else { throw reject("has no path components") }
        for component in meaningful {
            guard !component.isEmpty else { throw reject("contains an empty path component") }
            guard component != "..", component != "." else {
                throw reject("contains a relative traversal component")
            }
        }
        let normalized = meaningful.joined(separator: "/")
        return (normalized, isDirectory)
    }

    private static func locateEndRecord(_ bytes: Data) -> Int? {
        let minimum = 22
        guard bytes.count >= minimum else { return nil }
        let window = min(bytes.count, minimum + Int(UInt16.max))
        let lowest = bytes.count - window
        var index = bytes.count - minimum
        while index >= lowest {
            if bytes[bytes.startIndex + index] == 0x50,
               bytes[bytes.startIndex + index + 1] == 0x4b,
               bytes[bytes.startIndex + index + 2] == 0x05,
               bytes[bytes.startIndex + index + 3] == 0x06 {
                return index
            }
            index -= 1
        }
        return nil
    }

    private static func create(directory: URL) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ImportFailure(code: .storageFailure,
                                detail: "Could not create \(directory.lastPathComponent): \(error.localizedDescription)",
                                isRetryable: true)
        }
    }
}

/// Bounds-checked little-endian reader over archive bytes.
private final class Cursor {
    private let bytes: Data
    private var offset = 0

    init(_ bytes: Data) { self.bytes = bytes }

    func seek(to position: Int, context: String) throws {
        guard position >= 0, position <= bytes.count else {
            throw ImportFailure(code: .notAnExport, detail: "Offset out of range while reading \(context).")
        }
        offset = position
    }

    func skip(_ count: Int, context: String) throws { try seek(to: offset + count, context: context) }

    func read(_ count: Int, context: String) throws -> Data {
        guard count >= 0, offset + count <= bytes.count else {
            throw ImportFailure(code: .notAnExport, detail: "Truncated data while reading \(context).")
        }
        let start = bytes.startIndex + offset
        defer { offset += count }
        return bytes.subdata(in: start..<(start + count))
    }

    func u16() throws -> UInt16 {
        let data = try read(2, context: "header")
        return UInt16(data[data.startIndex]) | UInt16(data[data.startIndex + 1]) << 8
    }

    func u32() throws -> UInt32 {
        let data = try read(4, context: "header")
        var value: UInt32 = 0
        for index in (0..<4).reversed() { value = value << 8 | UInt32(data[data.startIndex + index]) }
        return value
    }
}

/// CRC-32 as used by ZIP entry checksums.
public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var remainder = UInt32(value)
        for _ in 0..<8 { remainder = (remainder >> 1) ^ ((remainder & 1) == 1 ? 0xedb8_8320 : 0) }
        return remainder
    }

    /// Computes the checksum of `data`.
    public static func checksum(_ data: Data) -> UInt32 {
        var checksum: UInt32 = 0xffff_ffff
        for byte in data { checksum = (checksum >> 8) ^ table[Int((checksum ^ UInt32(byte)) & 0xff)] }
        return checksum ^ 0xffff_ffff
    }
}
