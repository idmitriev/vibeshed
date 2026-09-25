import Foundation

/// Typed, `Sendable` container for the values collected for an action's parameters.
///
/// Parameter values are string-encoded end to end: `.text`/`.path` keep their raw
/// string, `.number` its decimal string, `.toggle` `"true"`/`"false"`, and
/// `.selection`/`.dynamicSelection` the chosen option's id. Modules read them back
/// through the typed accessors below instead of casting out of `[String: Any]`.
struct ParameterValues: Sendable, Equatable, Codable, ExpressibleByDictionaryLiteral {
    private var storage: [String: String]

    init(_ storage: [String: String] = [:]) {
        self.storage = storage
    }

    init(dictionaryLiteral elements: (String, String)...) {
        storage = Dictionary(elements, uniquingKeysWith: { _, last in last })
    }

    static let empty = ParameterValues()

    var isEmpty: Bool {
        storage.isEmpty
    }

    /// The underlying string-keyed values, e.g. for forwarding to `ActionResult.chain`.
    var raw: [String: String] {
        storage
    }

    subscript(_ id: String) -> String? {
        get { storage[id] }
        set { storage[id] = newValue }
    }

    func contains(_ id: String) -> Bool {
        storage[id] != nil
    }

    // MARK: - Typed accessors

    func string(_ id: String) -> String? {
        storage[id]
    }

    func double(_ id: String) -> Double? {
        storage[id].flatMap(Double.init)
    }

    func int(_ id: String) -> Int? {
        storage[id].flatMap(Int.init)
    }

    /// Only the exact string "true" is true; a missing value reads as false.
    func bool(_ id: String) -> Bool {
        storage[id] == "true"
    }

    mutating func set(_ value: String, for id: String) {
        storage[id] = value
    }
}
