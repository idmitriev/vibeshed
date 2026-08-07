import Foundation
import Yams

final class MutableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) {
        self.value = value
    }
}

struct ModuleConfigDecoder: Sendable {
    let validate: @Sendable (Data?) throws -> Void
    let apply: @Sendable (Data?) async throws -> Void

    static func make<M: ModuleConfigurable>(
        for module: M,
        moduleID: String
    ) -> ModuleConfigDecoder {
        let lastConfig = MutableBox<M.Config?>(nil)

        return ModuleConfigDecoder(
            validate: { yamlData in
                let config = try Self.decode(M.self, from: yamlData, moduleID: moduleID)
                let result = M.validate(config)
                if !result.isValid {
                    throw ModuleConfigError.validationFailed(
                        moduleID: moduleID,
                        reasons: result.errors
                    )
                }
            },
            apply: { yamlData in
                let config = try Self.decode(M.self, from: yamlData, moduleID: moduleID)
                let result = M.validate(config)
                guard result.isValid else {
                    throw ModuleConfigError.validationFailed(
                        moduleID: moduleID,
                        reasons: result.errors
                    )
                }
                guard lastConfig.value != config else { return }
                lastConfig.value = config
                await module.configDidUpdate(config)
            }
        )
    }

    private static func decode<M: ModuleConfigurable>(
        _: M.Type,
        from yamlData: Data?,
        moduleID: String
    ) throws -> M.Config {
        if let yamlData {
            // A section with no keys (or only comments) serializes to a null
            // scalar — that means "enable with defaults", not a decode error.
            let text = String(data: yamlData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let text, text.isEmpty || text == "null" || text == "~",
               let defaultConfig = M.defaultConfig
            {
                return defaultConfig
            }
            do {
                return try YAMLDecoder().decode(M.Config.self, from: yamlData)
            } catch {
                // Fall back to defaultConfig when available; otherwise surface
                // the decode error.
                if let defaultConfig = M.defaultConfig {
                    let reason = String(describing: error)
                    Log.config.error(
                        "Module '\(moduleID, privacy: .public)' config failed to decode, falling back to defaults: \(reason, privacy: .public)"
                    )
                    return defaultConfig
                }
                throw ModuleConfigError.decodingFailed(
                    moduleID: moduleID,
                    underlying: error
                )
            }
        } else if let defaultConfig = M.defaultConfig {
            return defaultConfig
        } else {
            throw ModuleConfigError.missingRequired(moduleID: moduleID)
        }
    }
}
