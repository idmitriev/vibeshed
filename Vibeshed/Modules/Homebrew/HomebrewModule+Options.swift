import SwiftUI

/// Short-lived `brew info` results, so refining a search or filtering the installed
/// list doesn't re-run brew on every keystroke. Dropped after commands that change
/// what's installed.
struct HomebrewPackageCache {
    struct Key: Hashable {
        let name: String
        let isCask: Bool
    }

    static let lifetime: Duration = .seconds(30)

    var searched: [Key: (package: HomebrewPackage, fetchedAt: ContinuousClock.Instant)] = [:]
    var installed: [Bool: (task: Task<[HomebrewPackage], any Error>, startedAt: ContinuousClock.Instant)] = [:]
}

extension HomebrewModule {
    /// Search hits offered per query: plenty to pick from, few enough for one quick `brew info`.
    static let searchLimit = 20

    func searchOptions(query: String, isCask: Bool, brewPath: String) async -> [ParameterOption] {
        guard query.count >= 2 else { return [] }
        let names: [String]
        do {
            names = try await Array(HomebrewManager.search(query, isCask: isCask, brewPath: brewPath)
                .prefix(Self.searchLimit))
        } catch {
            log.warning("Search failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        let packages = await searchedPackages(names, isCask: isCask, brewPath: brewPath)
        return names.map { name in
            guard let package = packages[name] else {
                return ParameterOption(id: name, label: name, iconName: isCask ? "app" : "shippingbox")
            }
            return Self.option(for: package, id: name, marksInstalled: true)
        }
    }

    func installedOptions(isCask: Bool, brewPath: String) async -> [ParameterOption] {
        do {
            return try await installedPackages(isCask: isCask, brewPath: brewPath).map { package in
                Self.option(for: package, id: package.token, marksInstalled: false)
            }
        } catch {
            log.warning("List installed failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func invalidatePackageCache() {
        packageCache = HomebrewPackageCache()
    }

    /// `marksInstalled` checks off installed packages, which only tells something in search results.
    private static func option(for package: HomebrewPackage, id: String, marksInstalled: Bool) -> ParameterOption {
        ParameterOption(
            id: id,
            label: id,
            subtitle: package.description ?? package.installedVersion,
            iconName: package.isCask ? "app" : "shippingbox",
            iconURL: package.existingAppPath.map { URL(fileURLWithPath: $0) },
            isCurrent: marksInstalled && package.isInstalled,
            makePreview: { AnyView(HomebrewPackagePreview(package: package)) }
        )
    }

    // MARK: - Cached lookups

    /// Details for search hits by name. Only names not looked up recently cost a brew run;
    /// if that run fails, those names come back without details.
    private func searchedPackages(
        _ names: [String],
        isCask: Bool,
        brewPath: String
    ) async -> [String: HomebrewPackage] {
        func cached(_ name: String) -> HomebrewPackage? {
            guard let entry = packageCache.searched[.init(name: name, isCask: isCask)],
                  entry.fetchedAt.duration(to: .now) < HomebrewPackageCache.lifetime
            else { return nil }
            return entry.package
        }

        let missing = names.filter { cached($0) == nil }
        if !missing.isEmpty {
            do {
                let fetched = try await HomebrewManager.packages(missing, isCask: isCask, brewPath: brewPath)
                // Search prints tap-qualified names for third-party taps; info reports both forms.
                var byName: [String: HomebrewPackage] = [:]
                for package in fetched {
                    byName[package.token] = package
                    byName[package.fullToken] = package
                }
                let now = ContinuousClock.now
                for name in missing {
                    guard let package = byName[name] else { continue }
                    packageCache.searched[.init(name: name, isCask: isCask)] = (package, now)
                }
            } catch {
                log.warning("Package info failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return names.reduce(into: [:]) { result, name in result[name] = cached(name) }
    }

    /// Every installed formula or cask. Callers within the cache lifetime share one brew run.
    private func installedPackages(isCask: Bool, brewPath: String) async throws -> [HomebrewPackage] {
        if let load = packageCache.installed[isCask],
           load.startedAt.duration(to: .now) < HomebrewPackageCache.lifetime
        {
            return try await load.task.value
        }
        let task = Task { try await HomebrewManager.installedPackages(isCask: isCask, brewPath: brewPath) }
        packageCache.installed[isCask] = (task, .now)
        do {
            return try await task.value
        } catch {
            // Let the next keystroke retry rather than serve the failure until it expires.
            if packageCache.installed[isCask]?.task == task {
                packageCache.installed[isCask] = nil
            }
            throw error
        }
    }
}
