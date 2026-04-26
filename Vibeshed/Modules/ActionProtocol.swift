import SwiftUI

// MARK: - ActionID

struct ActionID: Hashable, Sendable, Codable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(module: String, name: String) {
        self.rawValue = "\(module)/\(name)"
    }

    var description: String {
        rawValue
    }

    var moduleID: String {
        if let idx = rawValue.firstIndex(of: "/") {
            return String(rawValue[..<idx])
        }
        return rawValue
    }

    /// The action name part after the module separator (e.g. "cycleLeft" from "window/cycleLeft").
    var actionName: String {
        if let idx = rawValue.firstIndex(of: "/") {
            return String(rawValue[rawValue.index(after: idx)...])
        }
        return rawValue
    }
}

// MARK: - Action Protocol

protocol Action: Sendable, Identifiable where ID == ActionID {
    var id: ActionID { get }
    var title: String { get }
    var subtitle: String { get }
    var iconName: String? { get }
    var relevanceScore: Double { get }
    var keywords: [String] { get }
    var parameters: [ActionParameter] { get }

    func run(with values: [String: Any]) async throws -> ActionResult

    /// When true, the picker activates this action on a single mouse click.
    /// Default is false (double-click required) to avoid accidental activation.
    var activatesOnSingleClick: Bool { get }

    @MainActor
    func makeListItemView() -> AnyView?
    @MainActor
    func makePreviewView() -> AnyView?
}

extension Action {
    var iconName: String? {
        nil
    }

    var keywords: [String] {
        []
    }

    var parameters: [ActionParameter] {
        []
    }

    var activatesOnSingleClick: Bool {
        false
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        nil
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        nil
    }
}
