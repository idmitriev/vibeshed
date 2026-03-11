import AppKit
import Foundation

private let zoomBundleID = "us.zoom.xos"

enum ZoomManager {

    // MARK: - URL Building

    static func joinURL(meetingId: String, password: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "zoommtg"
        components.host = "zoom.us"
        components.path = "/join"
        var items = [URLQueryItem(name: "confno", value: meetingId)]
        if let password, !password.isEmpty {
            items.append(URLQueryItem(name: "pwd", value: password))
        }
        components.queryItems = items
        return components.url
    }

    static func startPersonalMeetingURL(meetingId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "zoommtg"
        components.host = "zoom.us"
        components.path = "/start"
        components.queryItems = [URLQueryItem(name: "confno", value: meetingId)]
        return components.url
    }

    // MARK: - Link Parsing

    /// Parses a Zoom meeting link and extracts the meeting ID and optional password.
    /// Supports formats:
    ///   - https://zoom.us/j/123456789?pwd=abc
    ///   - https://us06web.zoom.us/j/123456789?pwd=abc
    ///   - 123456789 (plain meeting ID)
    static func parseMeetingInput(_ input: String) -> (meetingId: String, password: String?)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Plain numeric meeting ID
        let digitsOnly = trimmed.replacingOccurrences(of: " ", with: "")
        if digitsOnly.allSatisfy(\.isNumber), digitsOnly.count >= 9 {
            return (digitsOnly, nil)
        }

        // URL format
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased(),
              host.hasSuffix("zoom.us")
        else {
            return nil
        }

        let pathComponents = url.pathComponents
        guard let jIndex = pathComponents.firstIndex(of: "j"),
              jIndex + 1 < pathComponents.count
        else {
            return nil
        }

        let meetingId = pathComponents[jIndex + 1]
            .replacingOccurrences(of: " ", with: "")
        guard meetingId.allSatisfy(\.isNumber), meetingId.count >= 9 else {
            return nil
        }

        let password = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "pwd" })?
            .value

        return (meetingId, password)
    }

    /// Resolves a config meeting entry to a meeting ID and password.
    static func resolve(_ entry: ZoomMeetingEntry) -> (meetingId: String, password: String?)? {
        if let meetingId = entry.meetingId {
            return (meetingId, entry.password)
        }
        if let link = entry.link {
            return parseMeetingInput(link)
        }
        return nil
    }

    // MARK: - App Control

    static func isZoomRunning() -> Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: zoomBundleID)
            .isEmpty
    }

    static func focusOrLaunchZoom() {
        let apps = NSRunningApplication
            .runningApplications(withBundleIdentifier: zoomBundleID)
        if let app = apps.first {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: zoomBundleID
        ) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    // MARK: - Formatting

    static func formatMeetingId(_ id: String) -> String {
        let digits = id.filter(\.isNumber)
        guard digits.count >= 9 else { return id }

        // Format as XXX XXX XXXX or XXX XXXX XXXX depending on length
        var result = ""
        for (index, char) in digits.enumerated() {
            if index == 3 || index == 6 {
                result.append(" ")
            }
            result.append(char)
        }
        return result
    }
}
