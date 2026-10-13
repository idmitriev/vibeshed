import Foundation

/// Newline-delimited JSON reading shared by the vendor session readers. Both Claude
/// Code and Codex record history and session state as `.jsonl`, one object per line.
///
/// Lines are located with `memchr` and parsed one at a time from the raw bytes, so the
/// cost tracks the number of lines parsed rather than the bytes read — which matters
/// for transcripts whose single records run to megabytes.
enum AIJSONL {
    /// Parses every well-formed JSON object in the file at `path`, skipping blank and
    /// malformed lines. Returns an empty array when the file is missing or unreadable —
    /// a vendor simply not being installed is the common case, not an error.
    static func objects(atPath path: String) -> [[String: Any]] {
        guard let data = FileManager.default.contents(atPath: path) else {
            return []
        }
        return data.withUnsafeBytes { bytes in
            lineRanges(in: bytes).compactMap { object(in: bytes, range: $0) }
        }
    }

    /// Parses the leading `limit` JSON objects of a file, stopping early. Used for
    /// session-header records that appear at the top of large transcript files.
    static func headObjects(atPath path: String, limit: Int) -> [[String: Any]] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        // Session headers sit in the first few lines; reading a bounded prefix keeps
        // a scan over hundreds of multi-megabyte transcripts cheap.
        let chunk = (try? handle.read(upToCount: 256 * 1024)) ?? Data()
        return chunk.withUnsafeBytes { bytes in
            // Drop the trailing partial line: the read boundary can fall inside a
            // record, or inside a multi-byte character within it.
            let complete = lineRanges(in: bytes).dropLast()
            return Array(
                complete.lazy.compactMap { object(in: bytes, range: $0) }
                    .prefix(limit)
            )
        }
    }

    /// Visits a file's JSON objects newest-first, from the last line backwards, until
    /// `visit` returns `true`. The tail is read in growing chunks, so a value near the
    /// end of a multi-hundred-megabyte transcript costs a read of its last few
    /// kilobytes; `maxBytes` bounds the search for a value that never appears.
    ///
    /// When `needles` is non-empty, lines containing none of them are skipped without
    /// being parsed: a byte search is far cheaper than parsing the tool output and
    /// reasoning records that pile up between the records a caller wants.
    static func scanTail(
        atPath path: String,
        containing needles: [String] = [],
        maxBytes: Int = 4 * 1024 * 1024,
        visit: ([String: Any]) -> Bool
    ) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return }
        let needles = needles.map { Data($0.utf8) }
        let floor = size - min(size, UInt64(maxBytes))
        var end = size
        var chunkSize: UInt64 = 64 * 1024
        // The leading fragment of the previous chunk: the tail end of a line whose
        // start lies further back, completed by the next chunk.
        var carry = Data()
        while end > floor {
            let start = end - min(end - floor, chunkSize)
            guard (try? handle.seek(toOffset: start)) != nil,
                  let chunk = try? handle.read(upToCount: Int(end - start)),
                  !chunk.isEmpty
            else { return }
            let buffer = chunk + carry
            let done = buffer.withUnsafeBytes { bytes in
                var lines = lineRanges(in: bytes)
                // Unless the chunk starts the file, its first line is cut off.
                let fragment = start > 0 ? lines.removeFirst() : 0 ..< 0
                carry = data(in: bytes, range: fragment)
                for range in lines.reversed() {
                    guard needles.isEmpty
                        || needles.contains(where: { contains($0, in: bytes, range: range) }),
                        let json = object(in: bytes, range: range)
                    else { continue }
                    if visit(json) { return true }
                }
                return false
            }
            if done { return }
            end = start
            chunkSize = min(chunkSize * 2, 1024 * 1024)
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

    // MARK: - Lines

    /// The byte ranges between newlines, like `split(omittingEmptySubsequences:
    /// false)`: the last range is whatever follows the final newline, often empty.
    private static func lineRanges(in bytes: UnsafeRawBufferPointer) -> [Range<Int>] {
        guard let base = bytes.baseAddress else { return [0 ..< 0] }
        var ranges: [Range<Int>] = []
        var start = 0
        while let hit = memchr(base + start, Int32(UInt8(ascii: "\n")), bytes.count - start) {
            let end = base.distance(to: UnsafeRawPointer(hit))
            ranges.append(start ..< end)
            start = end + 1
        }
        ranges.append(start ..< bytes.count)
        return ranges
    }

    private static func contains(
        _ needle: Data,
        in bytes: UnsafeRawBufferPointer,
        range: Range<Int>
    ) -> Bool {
        guard let base = bytes.baseAddress, !range.isEmpty else { return false }
        return needle.withUnsafeBytes { needleBytes in
            memmem(
                base + range.lowerBound, range.count,
                needleBytes.baseAddress, needleBytes.count
            ) != nil
        }
    }

    /// Parses one line, skipping blank and malformed ones. Surrounding whitespace,
    /// including a Windows line ending's `\r`, is valid JSON padding.
    private static func object(
        in bytes: UnsafeRawBufferPointer,
        range: Range<Int>
    ) -> [String: Any]? {
        guard !range.isEmpty else { return nil }
        let line = data(in: bytes, range: range)
        return try? JSONSerialization.jsonObject(with: line) as? [String: Any]
    }

    private static func data(
        in bytes: UnsafeRawBufferPointer,
        range: Range<Int>
    ) -> Data {
        guard let base = bytes.baseAddress, !range.isEmpty else { return Data() }
        return Data(bytes: base + range.lowerBound, count: range.count)
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
