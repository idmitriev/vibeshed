import SwiftUI

// MARK: - ActionID

struct ActionID: Hashable, Sendable, Codable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(module: String, name: String) {
        self.rawValue = "\(module).\(name)"
    }

    var description: String {
        rawValue
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

    @MainActor
    func makeListItemView() -> AnyView? {
        nil
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        nil
    }
}
