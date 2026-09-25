import Foundation
import OSLog

/// Runs themes through their targets. All work is serialized through one pipeline so a
/// preview, its revert and a commit can never interleave, and previews are coalesced:
/// arrowing quickly through ten themes applies only the one the highlight rests on.
actor ThemeApplier {
    struct Result: Sendable {
        let target: String
        let outcome: ThemeTargetOutcome
    }

    static let targets: [any ThemeTarget] = [
        AppearanceTarget(), AccentTarget(), FolderColorTarget(), PointerTarget(), WallpaperTarget(),
        ITermTarget(), VSCodeTarget(), ZedTarget(), JetBrainsTarget(), ClaudeCodeTarget(),
        BatTarget(), LsdTarget(), MicroTarget(), BtopTarget(), GitHubWebTarget(), TemplatesTarget(), HooksTarget(),
    ]

    private let log = Log.module("theme")
    private var pipeline: Task<Void, Never>?

    /// State captured before the first preview of a `theme/switch` session.
    private struct PreviewSession {
        var restores: [ThemeRestore] = []
        var captured: Set<ThemeTargetID> = []
        var hasApplied = false
    }

    private var previewSession: PreviewSession?
    private var previewGeneration = 0

    /// What to apply beyond the theme itself.
    struct Options: Sendable {
        var wallpaper: WallpaperChoice
        /// Restrict to these targets (e.g. just the wallpaper); nil = every enabled target.
        var only: Set<ThemeTargetID>?
    }

    // MARK: - Public

    func apply(_ theme: ResolvedTheme, config: ThemeConfig, options: Options) async -> [Result] {
        await serialized { await self.performApply(theme, config: config, options: options) }
    }

    /// Previews `theme`. `isCurrent` means it's what is already applied: until something
    /// else has been previewed, resting on it changes nothing.
    func preview(_ theme: ResolvedTheme, config: ThemeConfig, options: Options, isCurrent: Bool) async {
        previewGeneration += 1
        let generation = previewGeneration
        await serialized {
            await self.performPreview(
                theme, config: config, options: options, isCurrent: isCurrent, generation: generation
            )
        }
    }

    /// Ends a preview session: reverts everything it changed unless `committed`.
    func endPreview(committed: Bool) async {
        previewGeneration += 1
        await serialized { await self.finishPreview(committed: committed) }
    }

    static func enabledTargets(
        for theme: ResolvedTheme,
        config: ThemeConfig,
        only: Set<ThemeTargetID>? = nil
    ) -> [any ThemeTarget] {
        var ids = config.enabledTargets
        // A theme that names a GitHub theme opts into that target unless targets are explicit.
        if config.targets == nil, theme.appOverrides[ThemeTargetID.github.rawValue] != nil {
            ids.insert(.github)
        }
        if let only { ids.formIntersection(only) }
        return targets.filter { ids.contains($0.id) }
    }

    // MARK: - Pipeline

    private func serialized<T: Sendable>(_ operation: @escaping @Sendable () async -> T) async -> T {
        let previous = pipeline
        let task = Task {
            await previous?.value
            return await operation()
        }
        pipeline = Task { _ = await task.value }
        return await task.value
    }

    private func performApply(_ theme: ResolvedTheme, config: ThemeConfig, options: Options) async -> [Result] {
        // A committed preview already left its changes in place; nothing to restore.
        previewSession = nil
        let request = ThemeApplyRequest(theme: theme, config: config, isPreview: false, wallpaper: options.wallpaper)
        let targets = Self.enabledTargets(for: theme, config: config, only: options.only)
        // Hooks go last so they can rely on everything else (e.g. rendered templates).
        var results = await run(request, targets.filter { $0.id != .hooks })
        results += await run(request, targets.filter { $0.id == .hooks })
        await MainActor.run { ActiveTheme.shared.commit(theme.activeInfo) }
        for result in results {
            let line = "\(theme.name) → \(result.target): \(String(describing: result.outcome))"
            log.info("\(line, privacy: .public)")
        }
        return results
    }

    private func performPreview(
        _ theme: ResolvedTheme,
        config: ThemeConfig,
        options: Options,
        isCurrent: Bool,
        generation: Int
    ) async {
        // A newer highlight (or the end of the session) superseded this one.
        guard generation == previewGeneration else { return }
        var session = previewSession ?? PreviewSession()
        // Resting on what's already applied changes nothing — don't touch anything yet.
        if !session.hasApplied, isCurrent {
            previewSession = session
            return
        }

        let targets = Self.enabledTargets(for: theme, config: config, only: options.only).filter(\.supportsPreview)
        let uncaptured = targets.filter { !session.captured.contains($0.id) }
        session.restores += await snapshots(uncaptured, config: config)
        session.captured.formUnion(uncaptured.map(\.id))
        session.hasApplied = true
        previewSession = session

        let request = ThemeApplyRequest(theme: theme, config: config, isPreview: true, wallpaper: options.wallpaper)
        _ = await run(request, targets)
        await MainActor.run { ActiveTheme.shared.preview(theme.activeInfo) }
    }

    private func finishPreview(committed: Bool) async {
        guard let session = previewSession else { return }
        previewSession = nil
        guard !committed else { return }
        if session.hasApplied {
            for restore in session.restores.reversed() {
                await restore()
            }
        }
        await MainActor.run { ActiveTheme.shared.preview(nil) }
    }

    // MARK: - Fan-out

    private func run(_ request: ThemeApplyRequest, _ targets: [any ThemeTarget]) async -> [Result] {
        await withTaskGroup(of: Result.self) { group in
            for target in targets {
                group.addTask {
                    Result(target: target.displayName, outcome: await target.apply(request))
                }
            }
            var results: [Result] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private func snapshots(_ targets: [any ThemeTarget], config: ThemeConfig) async -> [ThemeRestore] {
        await withTaskGroup(of: ThemeRestore?.self) { group in
            for target in targets {
                group.addTask { await target.snapshot(config: config) }
            }
            var restores: [ThemeRestore] = []
            for await restore in group {
                if let restore { restores.append(restore) }
            }
            return restores
        }
    }
}
