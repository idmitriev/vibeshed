import AppKit
import Foundation

@MainActor
@Observable
final class URIManager {
    private(set) var routingErrors: [String: String] = [:]

    private let eventBus: EventBus
    private let configManager: ConfigManager
    private let moduleRegistry: ModuleRegistry
    private let showPicker: (String?) -> Void
    private let togglePicker: () -> Void

    private var currentConfig: URLRoutingConfig = .init()
    private var previousDefaultBrowser: String?

    init(
        eventBus: EventBus,
        configManager: ConfigManager,
        moduleRegistry: ModuleRegistry,
        showPicker: @escaping (String?) -> Void,
        togglePicker: @escaping () -> Void
    ) {
        self.eventBus = eventBus
        self.configManager = configManager
        self.moduleRegistry = moduleRegistry
        self.showPicker = showPicker
        self.togglePicker = togglePicker
    }

    // MARK: - Public

    func start() {
        previousDefaultBrowser = BrowserRegistry.systemDefaultBundleID()
        currentConfig = configManager.config.urlRouting
        validateRules()

        if currentConfig.registerAsDefaultBrowser {
            registerAsDefaultBrowser()
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let (_, stream) = await eventBus.subscribe()
            for await event in stream {
                switch event {
                case .configReloaded:
                    self.handleConfigReloaded()
                default:
                    break
                }
            }
        }

        Log.uri.info("URIManager started with \(self.currentConfig.rules.count, privacy: .public) routing rule(s)")
    }

    func handleURLs(_ urls: [URL]) {
        for url in urls {
            handleURL(url)
        }
    }

    // MARK: - URL Dispatch

    private func handleURL(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""

        switch scheme {
        case "vibeshed":
            handleVibeshedURI(url)
        case "http", "https":
            handleWebURL(url)
        default:
            Log.uri.warning("Unsupported URL scheme: \(scheme, privacy: .public)")
            Task { await eventBus.publish(.uriError(url: url.absoluteString, message: "Unsupported scheme: \(scheme)")) }
        }
    }

    // MARK: - vibeshed:// URI

    private func handleVibeshedURI(_ url: URL) {
        guard let host = url.host else {
            Log.uri.error("Invalid vibeshed URI: no host in \(url, privacy: .public)")
            Task { await eventBus.publish(.uriError(url: url.absoluteString, message: "No host component")) }
            return
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        // vibeshed://picker?q=term
        if host == "picker" {
            let searchQuery = queryItems.first { $0.name == "q" }?.value
            showPicker(searchQuery)
            if let searchQuery {
                Log.uri.info("Opened picker via URI with query '\(searchQuery, privacy: .public)'")
            } else {
                Log.uri.info("Opened picker via URI")
            }
            return
        }

        // vibeshed://{module}/{action}?params
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard let actionName = pathComponents.first else {
            Log.uri.error("Invalid vibeshed URI: no action in \(url, privacy: .public)")
            Task { await eventBus.publish(.uriError(url: url.absoluteString, message: "No action specified")) }
            return
        }

        let actionID = ActionID(module: host, name: actionName)
        var values: [String: Any] = [:]
        for item in queryItems {
            values[item.name] = item.value ?? ""
        }

        Task {
            await Self.executeAction(actionID, values: values, moduleRegistry: moduleRegistry, eventBus: eventBus)
        }
    }

    // MARK: - HTTP/HTTPS Routing

    private func handleWebURL(_ url: URL) {
        for rule in currentConfig.rules {
            if URLPatternMatcher.matches(url: url, pattern: rule.pattern) {
                applyRule(rule, for: url)
                return
            }
        }
        openInDefaultBrowser(url)
    }

    private func applyRule(_ rule: URLRoutingRule, for url: URL) {
        if rule.action == "picker" {
            showPicker(url.absoluteString)
            Log.uri.info("Routed \(url, privacy: .public) to picker")
            Task { await eventBus.publish(.uriRouted(url: url.absoluteString, destination: "picker")) }
            return
        }

        if let actionStr = rule.action, actionStr != "picker" {
            let actionID = ActionID(actionStr)
            Task {
                await Self.executeAction(
                    actionID,
                    values: ["url": url.absoluteString],
                    moduleRegistry: moduleRegistry,
                    eventBus: eventBus
                )
            }
            return
        }

        if let browser = rule.browser {
            do {
                try BrowserRegistry.open(url: url, browser: browser, profile: rule.profile)
                let dest = browser + (rule.profile.map { "/\($0)" } ?? "")
                Log.uri.info("Routed \(url, privacy: .public) to \(dest, privacy: .public)")
                Task { await eventBus.publish(.uriRouted(url: url.absoluteString, destination: dest)) }
            } catch {
                let desc = error.localizedDescription
                Log.uri.error(
                    "Failed to open \(url, privacy: .public) in \(browser, privacy: .public): \(desc, privacy: .public)"
                )
                Task { await eventBus.publish(.uriError(url: url.absoluteString, message: error.localizedDescription)) }
                openInDefaultBrowser(url)
            }
            return
        }

        Log.uri.warning("Rule '\(rule.pattern, privacy: .public)' has no browser or action, using default")
        openInDefaultBrowser(url)
    }

    private func openInDefaultBrowser(_ url: URL) {
        if let defaultBrowser = currentConfig.defaultBrowser {
            do {
                try BrowserRegistry.open(url: url, browser: defaultBrowser, profile: currentConfig.defaultProfile)
                Log.uri.info("Routed \(url, privacy: .public) to default browser \(defaultBrowser, privacy: .public)")
                Task { await eventBus.publish(.uriRouted(url: url.absoluteString, destination: defaultBrowser)) }
            } catch {
                Log.uri.error("Default browser failed: \(error.localizedDescription, privacy: .public)")
                fallbackOpen(url)
            }
        } else {
            fallbackOpen(url)
        }
    }

    private func fallbackOpen(_ url: URL) {
        // Use the browser that was default before we registered, skipping ourselves
        if let prevBrowser = previousDefaultBrowser,
           prevBrowser != Bundle.main.bundleIdentifier
        {
            do {
                try BrowserRegistry.open(url: url, browser: prevBrowser, profile: nil)
                Log.uri.info("Routed \(url, privacy: .public) to previous default browser \(prevBrowser, privacy: .public)")
                return
            } catch {
                Log.uri.warning("Previous default browser failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // Last resort: Safari
        do {
            try BrowserRegistry.open(url: url, browser: "safari", profile: nil)
        } catch {
            Log.uri.error("Cannot open URL \(url, privacy: .public): no browser available")
        }
    }

    // MARK: - Config Reload

    private func handleConfigReloaded() {
        let newConfig = configManager.config.urlRouting
        guard newConfig != currentConfig else { return }
        currentConfig = newConfig
        routingErrors = [:]
        validateRules()

        if currentConfig.registerAsDefaultBrowser {
            registerAsDefaultBrowser()
        }

        Log.uri.info("URL routing config reloaded with \(self.currentConfig.rules.count, privacy: .public) rule(s)")
    }

    // MARK: - Validation

    private func validateRules() {
        routingErrors = [:]
        for (index, rule) in currentConfig.rules.enumerated() {
            let key = "\(index):\(rule.pattern)"

            let patternResult = URLPatternMatcher.validate(pattern: rule.pattern)
            if !patternResult.isValid {
                let message = patternResult.errors.joined(separator: "; ")
                routingErrors[key] = message
                Log.uri.error("Invalid routing rule #\(index, privacy: .public): \(message, privacy: .public)")
                Task { await eventBus.publish(.uriError(url: rule.pattern, message: message)) }
                continue
            }

            if rule.browser == nil, rule.action == nil {
                let message = "Rule must specify either 'browser' or 'action'"
                routingErrors[key] = message
                Log.uri.error("Invalid routing rule #\(index, privacy: .public) '\(rule.pattern, privacy: .public)': \(message, privacy: .public)")
                Task { await eventBus.publish(.uriError(url: rule.pattern, message: message)) }
                continue
            }

            if let browser = rule.browser {
                let bundleID = BrowserRegistry.resolveBundleID(browser)
                if !BrowserRegistry.isInstalled(bundleID) {
                    let pat = rule.pattern
                    Log.uri.warning(
                        "Browser '\(browser, privacy: .public)' (bundle: \(bundleID, privacy: .public)) not found for rule '\(pat, privacy: .public)'"
                    )
                }
            }

            if let action = rule.action, action != "picker" {
                let actionID = ActionID(action)
                Task { [weak self] in
                    guard let self else { return }
                    if await moduleRegistry.findAction(id: actionID) == nil {
                        Log.uri.warning("Action '\(action, privacy: .public)' for rule '\(rule.pattern, privacy: .public)' not currently available")
                    }
                }
            }
        }
    }

    // MARK: - Default Browser Registration

    private func registerAsDefaultBrowser() {
        if previousDefaultBrowser == nil {
            previousDefaultBrowser = BrowserRegistry.systemDefaultBundleID()
        }
        Log.uri.info("App configured as http/https handler. User will be prompted to confirm.")
    }

    // MARK: - Action Execution

    private static func executeAction(
        _ actionID: ActionID,
        values: [String: Any],
        moduleRegistry: ModuleRegistry,
        eventBus: EventBus
    ) async {
        guard let action = await moduleRegistry.findAction(id: actionID) else {
            Log.uri.error("Action not found: \(actionID, privacy: .public)")
            await eventBus.publish(.actionFailed(actionID, message: "Action not found"))
            return
        }

        let moduleID = String(actionID.rawValue.prefix(while: { $0 != "." }))
        do {
            _ = try await action.run(with: values)
            await eventBus.publish(.actionExecuted(actionID, moduleID: moduleID))
        } catch {
            Log.uri.error("Action \(actionID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            await eventBus.publish(.actionFailed(actionID, message: error.localizedDescription))
        }
    }
}
