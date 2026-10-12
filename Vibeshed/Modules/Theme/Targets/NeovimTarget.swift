import Foundation

/// Neovim: writes the palette as `~/.config/nvim/colors/vibeshed.lua` (select it once with
/// `colorscheme vibeshed`), then asks every running Neovim that uses it to reload it over
/// its RPC socket, so open editors retint live. Editors on another colorscheme are left
/// alone. `apps: { neovim: "<scheme>" }` makes `vibeshed` load one of your installed
/// colorschemes instead.
struct NeovimTarget: ThemeTarget {
    let id = ThemeTargetID.neovim
    let displayName = "Neovim"
    var supportsPreview: Bool { true }

    static let schemeName = "vibeshed"

    static var configDirectory: String {
        "\(CLITools.configHome)/nvim"
    }

    static var schemePath: String {
        "\(configDirectory)/colors/\(schemeName).lua"
    }

    func apply(_ request: ThemeApplyRequest) async -> ThemeTargetOutcome {
        let nvim = CLITools.executable("nvim")
        guard nvim != nil || ThemeFiles.exists(Self.configDirectory) else { return .skipped("not installed") }
        let scheme = request.override(.neovim).map {
            NeovimThemeBuilder.alias($0, mode: request.palette.mode, themeName: request.theme.name)
        } ?? NeovimThemeBuilder.colorscheme(request.palette, themeName: request.theme.name)
        do {
            try ThemeFiles.write(scheme, to: Self.schemePath)
        } catch {
            return .failed(error.localizedDescription)
        }
        if let nvim { await Self.reloadRunning(nvim: nvim) }
        guard !request.isPreview, !Self.configSelectsScheme() else { return .applied() }
        return .applied(note: "add `vim.cmd.colorscheme(\"\(Self.schemeName)\")` to your Neovim config")
    }

    func snapshot(config _: ThemeConfig) async -> ThemeRestore? {
        let files = ThemeFiles.snapshot([Self.schemePath])
        return {
            await files()
            if let nvim = CLITools.executable("nvim") { await Self.reloadRunning(nvim: nvim) }
        }
    }

    // MARK: - Running editors

    /// Vimscript evaluated in each running Neovim: reload the scheme only where it's active.
    static let reloadExpression =
        #"execute("if get(g:, \"colors_name\", \"\") ==# \"\#(schemeName)\" | colorscheme \#(schemeName) | endif")"#

    /// Folders Neovim puts its server sockets in: `stdpath("run")` is `$XDG_RUNTIME_DIR` or
    /// `$TMPDIR/nvim.$USER` (0.10+ adds a random subfolder), and `/tmp/nvim.$USER` for
    /// builds that ignore `$TMPDIR`.
    static var socketDirectories: [String] {
        let user = NSUserName()
        var directories = [
            (NSTemporaryDirectory() as NSString).appendingPathComponent("nvim.\(user)"),
            "/tmp/nvim.\(user)",
        ]
        if let runtime = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] { directories.append(runtime) }
        return directories
    }

    /// Server sockets of running Neovims (`nvim.<pid>.<n>`), up to two folders deep.
    static func serverSockets(in directories: [String] = socketDirectories) -> [String] {
        let manager = FileManager.default
        var sockets: Set<String> = []
        func scan(_ directory: String, depth: Int) {
            for name in (try? manager.contentsOfDirectory(atPath: directory)) ?? [] {
                let path = (directory as NSString).appendingPathComponent(name)
                switch (try? manager.attributesOfItem(atPath: path))?[.type] as? FileAttributeType {
                case .typeSocket where name.hasPrefix("nvim."):
                    sockets.insert(ThemeFiles.resolved(path))
                case .typeDirectory where depth > 0:
                    scan(path, depth: depth - 1)
                default:
                    break
                }
            }
        }
        directories.forEach { scan($0, depth: 1) }
        return sockets.sorted()
    }

    /// One shell command that messages every socket in parallel. Stale sockets (left by a
    /// crashed Neovim) just refuse the connection.
    static func reloadCommand(nvim: String, sockets: [String]) -> String {
        let quote = { (text: String) in "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let calls = sockets.map {
            "\(quote(nvim)) --server \(quote($0)) --remote-expr \(quote(reloadExpression)) >/dev/null 2>&1 &"
        }
        return (calls + ["wait"]).joined(separator: "\n")
    }

    private static func reloadRunning(nvim: String) async {
        let sockets = serverSockets()
        guard !sockets.isEmpty else { return }
        _ = await ShellCommand.run(reloadCommand(nvim: nvim, sockets: sockets), timeout: 5)
    }

    // MARK: - Config

    /// Whether any config file mentions the scheme (`colorscheme vibeshed`, LazyVim's
    /// `opts = { colorscheme = "vibeshed" }`, …), so the setup hint is only shown when needed.
    static func configSelectsScheme(in directory: String = configDirectory) -> Bool {
        let root = URL(fileURLWithPath: ThemeFiles.resolved(directory))
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return false
        }
        var scanned = 0
        for case let url as URL in files {
            if url.lastPathComponent == "colors" || url.lastPathComponent.hasPrefix(".") {
                files.skipDescendants()
                continue
            }
            guard ["lua", "vim"].contains(url.pathExtension), scanned < 500 else { continue }
            scanned += 1
            if let text = ThemeFiles.read(url.path), text.contains(schemeName) { return true }
        }
        return false
    }
}
