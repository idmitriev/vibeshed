import AppKit
import ShowreelCore

extension SceneRunner {
    /// Puts the VM into the scene's starting state. Steps that would restart
    /// Dock or Finder only run when the setting actually changes.
    func applySetup() async throws {
        let setup = scene.setup
        CapsLock.turnOff()
        if setup.quitApps { await quitApps() }
        if let script = setup.prepare { try runShell(script) }
        try applyDesktop(setup)
        if !setup.events.isEmpty { try await CalendarFixtures.replace(with: setup.events) }
        try await setUpVibeshed(setup.vibeshed)
        for app in setup.apps {
            try await openApp(app)
        }
        if let text = setup.clipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        if let script = setup.shell { try runShell(script) }
        if let focus = setup.focus { try await Windows.bringToFront(Apps.open(focus, activate: true)) }
        if let cursor = setup.cursor { Mouse.warp(to: cursor) }
        for action in setup.actions {
            try SystemDialogs.ensureNone()
            Log.info("setup: \(describe(action))")
            try await perform(action)
        }
    }

    private func applyDesktop(_ setup: Setup) throws {
        if let size = setup.display { switchDisplayMode(to: size) }
        if let appearance = setup.appearance { try setAppearance(appearance) }
        if let wallpaper = setup.wallpaper {
            try setWallpaper(wallpaper.hasPrefix("#") ? solidImage(wallpaper) : resolve(wallpaper))
        }
        if let dock = setup.dock {
            try setDefault(domain: "com.apple.dock", key: "autohide", to: dock == .hidden, restart: "Dock")
        }
        if let menuBar = setup.menuBar {
            try setMenuBarAutohide(menuBar == .hidden)
        }
        if let icons = setup.desktopIcons {
            try setDefault(domain: "com.apple.finder", key: "CreateDesktop", to: icons == .shown, restart: "Finder")
        }
        if let locale = setup.locale {
            let current = try Shell.capture(["/usr/bin/defaults", "read", "-g", "AppleLocale"], check: false)
            if current.trimmingCharacters(in: .whitespacesAndNewlines) != locale {
                try Shell.capture(["/usr/bin/defaults", "write", "-g", "AppleLocale", locale])
                Log.info("region format \(locale)")
            }
        }
        if let widgets = setup.desktopWidgets {
            try setDefault(
                domain: "com.apple.WindowManager", key: "StandardHideWidgets", to: widgets == .hidden,
                restart: "WindowManager"
            )
        }
    }

    private func quitApps() async {
        let keep: Set<String> = ["com.apple.finder", Bundle.main.bundleIdentifier ?? "", Windows.vibeshedBundleID]
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !keep.contains($0.bundleIdentifier ?? "")
        }
        for app in apps {
            Log.info("quitting \(app.localizedName ?? app.bundleIdentifier ?? "app")")
            await Apps.quit(app)
        }
        // Finder stays running, but its windows from an earlier scene go.
        if let finder = Apps.running("com.apple.finder") {
            let closed = Windows.closeAll(of: finder)
            if closed > 0 { Log.info("closed \(closed) Finder window(s)") }
        }
    }

    private func switchDisplayMode(to size: DisplaySize) {
        let display = CGMainDisplayID()
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
        let matches = modes.filter { $0.width == size.width && $0.height == size.height }
        // Prefer the HiDPI variant: twice the pixels for the same points.
        guard let mode = matches.max(by: { $0.pixelWidth < $1.pixelWidth }) else {
            let available = Set(modes.map { "\($0.width)x\($0.height)" }).sorted().joined(separator: ", ")
            warn("no \(size.width)x\(size.height) display mode; available: \(available)")
            return
        }
        if let current = CGDisplayCopyDisplayMode(display), current.width == mode.width,
           current.height == mode.height, current.pixelWidth == mode.pixelWidth
        {
            return
        }
        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
        let result = CGCompleteDisplayConfiguration(config, .permanently)
        if result == .success {
            Log.info("display mode \(mode.width)x\(mode.height) (\(mode.pixelWidth)x\(mode.pixelHeight) px)")
        } else {
            warn("couldn't switch the display mode: CGError \(result.rawValue)")
        }
    }

    private func setAppearance(_ appearance: Appearance) throws {
        let dark = appearance == .dark
        guard (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) != dark else { return }
        let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            throw AgentError("couldn't set the appearance (allow Automation of System Events): \(error)")
        }
    }

    /// A one-color sRGB image for `wallpaper: "#rrggbb"`, so clips sit on a
    /// background a web page can match.
    private func solidImage(_ hex: String) throws -> URL {
        guard hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else {
            throw AgentError("wallpaper color '\(hex)' isn't #rrggbb")
        }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Showreel/cache/solid-\(hex.dropFirst().lowercased()).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { throw AgentError("can't draw a solid wallpaper") }
        let channel = { (shift: UInt32) in CGFloat((value >> shift) & 0xFF) / 255 }
        context.setFillColor(CGColor(srgbRed: channel(16), green: channel(8), blue: channel(0), alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        guard let image = context.makeImage() else { throw AgentError("can't draw a solid wallpaper") }
        try Screenshots.writePNG(image, to: url)
        return url
    }

    private func setWallpaper(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw AgentError("no wallpaper at \(url.path)") }
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    /// The global `_HIHideMenuBar` default, then the notification System Settings posts so
    /// the running session picks it up (no System Events, which would need Automation).
    private func setMenuBarAutohide(_ hidden: Bool) throws {
        let current = try Shell.capture(["/usr/bin/defaults", "read", "-g", "_HIHideMenuBar"], check: false)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["1", "true"].contains(current) != hidden else { return }
        try Shell.capture(["/usr/bin/defaults", "write", "-g", "_HIHideMenuBar", "-bool", hidden ? "true" : "false"])
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("AppleInterfaceMenuBarHidingChangedNotification"), object: nil,
            userInfo: nil, deliverImmediately: true
        )
        Log.info("menu bar autohide = \(hidden)")
    }

    private func setDefault(domain: String, key: String, to value: Bool, restart process: String) throws {
        let current = try Shell.capture(["/usr/bin/defaults", "read", domain, key], check: false)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A missing key means the default: desktop icons on, Dock always shown.
        let missing = current.contains("does not exist")
        let isOn = ["1", "true", "yes"].contains(current) || (missing && key == "CreateDesktop")
        guard isOn != value else { return }
        try Shell.capture(["/usr/bin/defaults", "write", domain, key, "-bool", value ? "true" : "false"])
        try Shell.capture(["/usr/bin/killall", process], check: false)
        Log.info("\(domain) \(key) = \(value)")
    }

    private func openApp(_ setup: AppSetup) async throws {
        Log.info("opening \(setup.app)")
        let document = setup.open.map { $0.contains("://") ? $0 : resolve($0).path }
        let app = try await Apps.open(setup.app, document: document, arguments: setup.args, activate: true)
        guard let frame = setup.frame else { return }
        guard await Windows.waitForWindow(of: app, timeout: 10) else {
            throw AgentError("\(setup.app) opened no window")
        }
        try Windows.place(app, frame: frame)
    }
}
