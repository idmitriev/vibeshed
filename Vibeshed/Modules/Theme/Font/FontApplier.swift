import Foundation
import OSLog

/// Runs fonts through their targets, the way `ThemeApplier` runs themes: one serialized
/// pipeline, coalesced previews, and a cancelled preview session put back as it was.
actor FontApplier {
    static let targets: [any FontTarget] = [
        ITermFontTarget(), GhosttyFontTarget(), TerminalFontTarget(), VSCodeFontTarget(), ZedFontTarget(),
        JetBrainsFontTarget(),
    ]

    private let log = Log.module("theme")
    private var pipeline: Task<Void, Never>?

    private struct PreviewSession {
        var restores: [ThemeRestore] = []
        var captured: Set<ThemeTargetID> = []
        var hasApplied = false
    }

    private var previewSession: PreviewSession?
    private var previewGeneration = 0

    /// The font targets `config` has on (its `targets:` list covers fonts too).
    static func enabledTargets(config: ThemeConfig) -> [any FontTarget] {
        let ids = config.enabledTargets
        return targets.filter { ids.contains($0.id) }
    }

    // MARK: - Public

    func apply(_ font: ResolvedFont, config: ThemeConfig) async -> [ThemeApplier.Result] {
        await serialized { await self.performApply(font, config: config) }
    }

    /// Previews `font`. `isCurrent` means it's what is already applied: until something
    /// else has been previewed, resting on it changes nothing.
    func preview(_ font: ResolvedFont, config: ThemeConfig, isCurrent: Bool) async {
        previewGeneration += 1
        let generation = previewGeneration
        await serialized {
            await self.performPreview(font, config: config, isCurrent: isCurrent, generation: generation)
        }
    }

    /// Ends a preview session: reverts everything it changed unless `committed`.
    func endPreview(committed: Bool) async {
        previewGeneration += 1
        await serialized { await self.finishPreview(committed: committed) }
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

    private func performApply(_ font: ResolvedFont, config: ThemeConfig) async -> [ThemeApplier.Result] {
        previewSession = nil
        // First, so profiles the theme rebuilds meanwhile already carry the new font.
        CommittedFont.save(font)
        let request = FontApplyRequest(font: font, config: config, isPreview: false)
        let results = await run(request, Self.enabledTargets(config: config))
        for result in results {
            let line = "Font \(font.name) → \(result.target): \(String(describing: result.outcome))"
            log.info("\(line, privacy: .public)")
        }
        return results
    }

    private func performPreview(_ font: ResolvedFont, config: ThemeConfig, isCurrent: Bool, generation: Int) async {
        // A newer highlight (or the end of the session) superseded this one.
        guard generation == previewGeneration else { return }
        var session = previewSession ?? PreviewSession()
        if !session.hasApplied, isCurrent {
            previewSession = session
            return
        }

        let targets = Self.enabledTargets(config: config).filter(\.supportsPreview)
        let uncaptured = targets.filter { !session.captured.contains($0.id) }
        session.restores += await snapshots(uncaptured, config: config)
        session.captured.formUnion(uncaptured.map(\.id))
        session.hasApplied = true
        previewSession = session

        _ = await run(FontApplyRequest(font: font, config: config, isPreview: true), targets)
    }

    private func finishPreview(committed: Bool) async {
        guard let session = previewSession else { return }
        previewSession = nil
        guard !committed, session.hasApplied else { return }
        for restore in session.restores.reversed() {
            await restore()
        }
    }

    // MARK: - Fan-out

    private func run(_ request: FontApplyRequest, _ targets: [any FontTarget]) async -> [ThemeApplier.Result] {
        await withTaskGroup(of: ThemeApplier.Result.self) { group in
            for target in targets {
                group.addTask {
                    ThemeApplier.Result(target: target.displayName, outcome: await target.apply(request))
                }
            }
            var results: [ThemeApplier.Result] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private func snapshots(_ targets: [any FontTarget], config: ThemeConfig) async -> [ThemeRestore] {
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
