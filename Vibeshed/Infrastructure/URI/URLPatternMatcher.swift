import Foundation

enum URLPatternMatcher {
    /// Match a URL against a glob or regex pattern.
    /// Patterns wrapped in `/` are treated as regex; all others use fnmatch glob matching.
    /// Matching is attempted against host+path first, then the full URL string.
    static func matches(url: URL, pattern: String) -> Bool {
        let hostPath = (url.host ?? "") + (url.path.isEmpty ? "" : url.path)
        let fullURL = url.absoluteString

        if isRegexPattern(pattern) {
            let regexStr = String(pattern.dropFirst().dropLast())
            guard let regex = try? NSRegularExpression(pattern: regexStr, options: .caseInsensitive) else {
                return false
            }
            return hasMatch(regex, in: hostPath) || hasMatch(regex, in: fullURL)
        } else {
            return fnmatch(pattern, hostPath, FNM_CASEFOLD) == 0
                || fnmatch(pattern, fullURL, FNM_CASEFOLD) == 0
        }
    }

    /// Validate that a pattern is syntactically valid.
    static func validate(pattern: String) -> ConfigValidationResult {
        if pattern.isEmpty {
            return .invalid(["Pattern cannot be empty"])
        }
        if isRegexPattern(pattern) {
            let regexStr = String(pattern.dropFirst().dropLast())
            do {
                _ = try NSRegularExpression(pattern: regexStr)
            } catch {
                return .invalid(["Invalid regex '\(pattern)': \(error.localizedDescription)"])
            }
        }
        return .valid
    }

    // MARK: - Private

    private static func isRegexPattern(_ pattern: String) -> Bool {
        pattern.hasPrefix("/") && pattern.hasSuffix("/") && pattern.count > 2
    }

    private static func hasMatch(_ regex: NSRegularExpression, in string: String) -> Bool {
        regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }
}
