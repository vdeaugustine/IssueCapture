import CryptoKit
import Foundation
import IssueCaptureSchema

/// SHA-256 helpers used for identity, deduplication and idempotence.
public enum Digest {
    /// Lowercase hex SHA-256 of `data`.
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Lowercase hex SHA-256 of a file, streamed so large archives are not
    /// held in memory in full.
    public static func sha256(fileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Derives the stable content identity of one issue revision.
///
/// The fingerprint covers canonical decoded report content and the bytes of
/// every received image, and deliberately excludes `exportPreparedAt`, which
/// records local preparation rather than issue content.
public enum ContentFingerprint {
    /// Canonical report bytes with export-preparation history removed.
    public static func canonicalReport(_ report: IssueReport) throws -> Data {
        var canonical = report
        canonical.exportPreparedAt = []
        return try IssueExportSchema.encoder().encode(canonical)
    }

    /// Computes the revision identifier for a report and its image hashes.
    ///
    /// - Parameter imageHashes: kind raw value to SHA-256 of the received bytes.
    public static func revisionID(report: IssueReport, imageHashes: [String: String]) throws -> String {
        var lines = ["report:" + Digest.sha256(try canonicalReport(report))]
        lines += imageHashes.keys.sorted().map { "image:\($0):\(imageHashes[$0] ?? "")" }
        return Digest.sha256(Data(lines.joined(separator: "\n").utf8))
    }
}
