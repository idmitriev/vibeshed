import AppKit
import SwiftUI

/// The permission setup window. On first launch, right after the initial config is
/// written, it greets the user and walks through every permission the config's
/// modules need, one macOS prompt at a time. After that it opens from the menu bar.
@MainActor
final class PermissionSetup {
    /// Set when the initial config is written, cleared once the user is done here.
    /// macOS offers to quit and reopen Vibeshed after some grants; this brings the
    /// window back afterwards.
    static var isPending: Bool {
        get { UserDefaults.standard.bool(forKey: pendingKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
    }

    private static let pendingKey = "permissionSetup.pending"

    private let permissionsManager: PermissionsManager
    private let moduleRegistry: ModuleRegistry
    private let configManager: ConfigManager
    private var walkthrough: PermissionWalkthrough?
    private var window: NSWindow?
    private var windowDelegate: SetupWindowDelegate?
    private var refreshTask: Task<Void, Never>?

    init(permissionsManager: PermissionsManager, moduleRegistry: ModuleRegistry, configManager: ConfigManager) {
        self.permissionsManager = permissionsManager
        self.moduleRegistry = moduleRegistry
        self.configManager = configManager
    }

    /// Opens the window. `welcome` greets a first launch and names the apps the new
    /// config was set up for; it stays that way until first-launch setup is done.
    /// Call once modules are registered: the plan comes from them.
    func show(welcome: Bool) {
        let walkthrough = currentWalkthrough()
        let view = PermissionSetupView(
            walkthrough: walkthrough,
            context: makeContext(welcome: welcome || Self.isPending, plan: walkthrough.plan),
            openConfig: { [weak self] in self?.openConfig() },
            done: { [weak self] in self?.finish() }
        )
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]

        let window = window ?? makeWindow()
        let wasVisible = window.isVisible
        window.contentViewController = controller
        if !wasVisible {
            window.center()
        }
        self.window = window
        keepRefreshing(walkthrough.plan)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Done or Later: closes the window and ends setup.
    func finish() {
        end()
        window?.close()
    }

    /// Each launch once setup is done: asks again for what Vibeshed asks for at launch
    /// (Accessibility, and Input Monitoring and Full Disk Access when the config needs
    /// them), and about Automation for the apps that are open. Call once modules are
    /// registered.
    func requestAtLaunch() async {
        let plan = makePlan()
        for permission in [Permission.accessibility, .inputMonitoring, .fullDiskAccess]
            where plan.permissions.contains(permission) && !permissionsManager.isGranted(permission)
        {
            await permissionsManager.request(permission)
        }
        let answers = await permissionsManager.requestAutomation(for: plan.automationTargets)
        for bundleID in plan.automationTargets {
            switch answers[bundleID] {
            case .allowed: Log.stderr("  ✓ automation: \(Self.appName(bundleID) ?? bundleID)")
            case .denied: Log.stderr("  ⚠ automation: \(Self.appName(bundleID) ?? bundleID) — denied")
            default: break
            }
        }
    }

    // MARK: - Plan

    /// What the registered modules (and the ones waiting on permissions) need.
    func makePlan() -> PermissionPlan {
        PermissionPlan(
            required: moduleRegistry.requiredPermissions,
            optional: moduleRegistry.optionalPermissions,
            automationTargets: moduleRegistry.automationTargets.filter { Self.appURL($0) != nil },
            usesCapsLock: configManager.config.keybindings.contains(where: \.usesCapsLock)
        )
    }

    /// The running walkthrough, or a new one for the current config.
    private func currentWalkthrough() -> PermissionWalkthrough {
        if let walkthrough, walkthrough.isRunning {
            return walkthrough
        }
        let walkthrough = PermissionWalkthrough(plan: makePlan(), authority: permissionsManager)
        walkthrough.onGrantedInSettings = { [weak self] _ in self?.bringToFront() }
        self.walkthrough = walkthrough
        return walkthrough
    }

    private func makeContext(welcome: Bool, plan: PermissionPlan) -> PermissionSetupView.Context {
        PermissionSetupView.Context(
            isWelcome: welcome,
            hotkey: welcome ? Self.pickerHotkey(in: configManager.config.keybindings) : nil,
            software: welcome ? foundSoftware() : [],
            automationApps: plan.automationTargets.compactMap(Self.appName)
        )
    }

    /// The apps the config's integration modules were enabled for, by name.
    private func foundSoftware() -> [String] {
        let configured = Set(configManager.config.moduleConfigs.keys)
        var names: [String] = []
        for integration in SoftwareIntegration.detect(in: .live) where configured.contains(integration.moduleID) {
            for name in integration.software where !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    /// The picker toggle as a key label: "⌥Space", or "Caps Lock + Space" spelled out,
    /// since Caps Lock as a modifier is new to most people.
    static func pickerHotkey(in keybindings: [KeyBindingEntry]) -> String? {
        guard let entry = keybindings.first(where: { $0.action == "app/togglePicker" && $0.app == nil }),
              let combo = try? KeyComboParser.parse(entry.combo)
        else {
            return nil
        }
        let label = switch combo {
        case let .standard(keyCode, modifiers):
            KeystrokeFormatter.comboLabel(keyCode: keyCode, modifiers: modifiers)
        case let .capsLockModifier(keyCode):
            "Caps Lock + " + KeystrokeFormatter.keyLabel(for: keyCode, characters: "")
        default:
            entry.combo
        }
        return label.replacingOccurrences(of: "␣", with: "Space")
    }

    // MARK: - Window

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Vibeshed Setup"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        let delegate = SetupWindowDelegate { [weak self] in self?.end() }
        window.delegate = delegate
        windowDelegate = delegate
        return window
    }

    /// Back from System Settings after a grant, ready for the next prompt.
    private func bringToFront() {
        guard let window, window.isVisible else { return }
        NSApp.activate()
        window.orderFrontRegardless()
        window.makeKey()
    }

    /// Picks up grants made outside the walkthrough, e.g. straight in System Settings.
    private func keepRefreshing(_ plan: PermissionPlan) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                for permission in plan.permissions {
                    self?.permissionsManager.refresh(permission)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func end() {
        walkthrough?.cancel()
        refreshTask?.cancel()
        refreshTask = nil
        Self.isPending = false
    }

    private func openConfig() {
        NSWorkspace.shared.open(configManager.configFileURL)
    }

    private static func appURL(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private static func appName(_ bundleID: String) -> String? {
        guard let url = appURL(bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// Ends setup when the user closes the window. `windowShouldClose` only fires for the
/// close button, not for `close()` or quitting, so a "Quit & Reopen" from System
/// Settings leaves setup pending.
private final class SetupWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        onClose()
        return true
    }
}
