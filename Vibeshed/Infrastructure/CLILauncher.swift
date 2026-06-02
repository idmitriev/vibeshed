import AppKit
import Foundation
import OSLog

/// Opens a path in an editor/IDE via its command-line tool, falling back to launching
/// the `.app` through `NSWorkspace` when no CLI is available. Shared by the editor
/// managers (VS Code, Zed) which previously each carried this resolve-then-launch dance.
enum CLILauncher {
    /// Resolves the CLI to use: an explicit `customPath` if executable, otherwise the
    /// first executable entry in `candidates`. Returns `nil` if none resolve.
    static func resolveCLI(
        customPath: String?,
        candidates: [String],
        log: Logger
    ) -> String? {
        if let custom = customPath {
            if FileManager.default.isExecutableFile(atPath: custom) {
                return custom
            }
            log.warning("Custom CLI path not executable: \(custom, privacy: .public)")
            return nil
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Opens `path` by running the resolved CLI in the background; if no CLI resolves,
    /// falls back to opening `path` with the app at `fallbackAppPath` via `NSWorkspace`.
    static func open(
        path: String,
        customPath: String?,
        candidates: [String],
        fallbackAppPath: String,
        log: Logger
    ) {
        guard let cli = resolveCLI(customPath: customPath, candidates: candidates, log: log) else {
            log.debug("No CLI found, falling back to NSWorkspace.open")
            let url = URL(fileURLWithPath: path)
            DispatchQueue.main.async {
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: URL(fileURLWithPath: fallbackAppPath),
                    configuration: .init()
                )
            }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cli)
            process.arguments = [path]
            do {
                try process.run()
            } catch {
                log.warning("CLI launch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
