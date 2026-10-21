import AppKit
import ScreenCaptureKit
import ShowreelCore

/// The guest side: runs inside the VM as ShowreelAgent.app, launched by the
/// host with `open -g -W … --args agent <command>` so it lives in the logged-in
/// GUI session and holds its own Accessibility and Screen Recording grants.
@MainActor
enum Agent {
    static func main(_ arguments: [String]) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            let status = await run(arguments)
            exit(status)
        }
        app.run()
        exit(0)
    }

    private static func run(_ arguments: [String]) async -> Int32 {
        var positional: [String] = []
        var options: [String: String] = [:]
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument.hasPrefix("--") {
                options[String(argument.dropFirst(2))] = iterator.next() ?? ""
            } else if !argument.hasPrefix("-") {
                positional.append(argument)
            }
        }
        // LaunchServices starts apps in `/`, so relative paths mean the home folder.
        func path(_ text: String) -> URL {
            URL(fileURLWithPath: text, relativeTo: FileManager.default.homeDirectoryForCurrentUser).standardizedFileURL
        }
        let output = path(options["out"] ?? NSTemporaryDirectory() + "showreel")
        switch positional.first ?? "doctor" {
        case "run":
            guard positional.count == 2 else {
                Log.warn("usage: agent run <scene.yaml> --out <dir>")
                return 2
            }
            return await runScene(at: path(positional[1]), output: output)
        case "doctor":
            return await Doctor.run(vibeshedApp: options["vibeshed"] ?? VibeshedSetup().app)
        case "inspect":
            return await inspect(output: output)
        default:
            Log.warn("unknown agent command \(positional[0])")
            return 2
        }
    }

    private static func runScene(at url: URL, output: URL) async -> Int32 {
        do {
            let scene = try Scene.load(from: url)
            Log.info("scene \(scene.title ?? url.lastPathComponent)")
            let runner = try await SceneRunner(scene: scene, sceneURL: url, outputURL: output)
            await runner.run()
            return runner.manifest.failure == nil ? 0 : 1
        } catch {
            Log.warn("\(error)")
            var manifest = Manifest(scene: url.deletingPathExtension().lastPathComponent, display: .init(
                width: 0, height: 0, scale: 1
            ))
            manifest.failure = "\(error)"
            try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try? manifest.write(to: output.appendingPathComponent("manifest.json"))
            return 1
        }
    }

    /// A screenshot and the on-screen windows' frames, for writing scenes.
    private static func inspect(output: URL) async -> Int32 {
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
                throw AgentError("no main display")
            }
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            try await Screenshots.capture(
                .display, display: display, scale: scale, cursor: true, to: output.appendingPathComponent("screen.png")
            )
            Log.info("display \(display.width)×\(display.height) pt @\(scale)x, pointer at \(Mouse.position)")
            var lines: [String] = []
            for window in WindowInfo.onScreen() where window.frame.width > 1 {
                let frame = window.frame
                let rect = "[\(Int(frame.x)), \(Int(frame.y)), \(Int(frame.width)), \(Int(frame.height))]"
                let title = window.title.isEmpty ? "" : " “\(window.title)”"
                lines.append("layer \(window.layer)\t\(rect)\t\(window.owner)\(title)")
            }
            let text = lines.joined(separator: "\n")
            try text.write(to: output.appendingPathComponent("windows.txt"), atomically: true, encoding: .utf8)
            Log.info("on-screen windows, front to back:\n\(text)")
            return 0
        } catch {
            Log.warn("\(error)")
            return 1
        }
    }
}
