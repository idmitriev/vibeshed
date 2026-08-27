import Foundation

/// Newline-delimited JSON reading shared by the vendor session readers. Both Claude
/// Code and Codex record history and session state as `.jsonl`, one object per line.
enum AIJSONL {
    /// Parses every well-formed JSON object in the file at `path`, skipping blank and
    /// malformed lines. Returns an empty array when the file is missing or unreadable —
    /// a vendor simply not being installed is the common case, not an error.
    static func objects(atPath path: String) -> [[String: Any]] {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8)
        else {
            return []
        }
        return objects(in: content)
    }

    /// Parses the leading `limit` JSON objects of a file, stopping early. Used for
    /// session-header records that appear at the top of large transcript files.
    static func headObjects(atPath path: String, limit: Int) -> [[String: Any]] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        // Session headers sit in the first few lines; reading a bounded prefix keeps
        // a scan over hundreds of multi-megabyte transcripts cheap.
        let chunk = (try? handle.read(upToCount: 256 * 1024)) ?? Data()
        // Drop the trailing partial line: the read boundary can fall inside a
        // multi-byte character, and decoding a split character yields nil for the
        // whole chunk. Cutting at the last newline leaves only complete lines,
        // which are always valid UTF-8.
        guard let lastNewline = chunk.lastIndex(of: UInt8(ascii: "\n")) else {
            return []
        }
        let complete = chunk[..<lastNewline]
        guard let content = String(data: complete, encoding: .utf8) else {
            return []
        }
        return Array(objects(in: content).prefix(limit))
    }

    private static func objects(in content: String) -> [[String: Any]] {
        content.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data)
                  as? [String: Any]
            else { return nil }
            return json
        }
    }

    /// Reads and parses a single JSON object file (not JSONL).
    static func object(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data)
              as? [String: Any]
        else { return nil }
        return json
    }
}

extension String {
    /// Truncates to `limit` characters for use as a session title, trimming first.
    func asSessionTitle(limit: Int = 80) -> String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(limit))
    }
}
