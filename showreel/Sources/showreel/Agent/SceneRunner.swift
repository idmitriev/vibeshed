import AppKit
import ScreenCaptureKit
import ShowreelCore

/// Plays one scene inside the VM: applies its setup, records the display
/// while performing its actions, and writes the take's manifest.
@MainActor
final class SceneRunner {
    let scene: Scene
    let sceneURL: URL
    let outputURL: URL
    let display: SCDisplay
    var scale: Double
    var manifest: Manifest
    private var recorder: ScreenRecorder?
    private var recordingStart: Date?
    /// Windows whose frames the manifest keeps, for crops in outputs.
    private var trackedTargets: [WindowTarget] = [.picker]

    static let videoName = "recording.mov"

    init(scene: Scene, sceneURL: URL, outputURL: URL) async throws {
        self.scene = scene
        self.sceneURL = sceneURL
        self.outputURL = outputURL
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mainID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else {
            throw AgentError("no display to record")
        }
        self.display = display
        scale = Double(NSScreen.main?.backingScaleFactor ?? 2)
        manifest = Manifest(
            scene: sceneURL.deletingPathExtension().lastPathComponent,
            display: .init(width: Double(display.width), height: Double(display.height), scale: scale)
        )
        for output in scene.outputs {
            if case let .region(.window(target)) = output.crop, !trackedTargets.contains(target) {
                trackedTargets.append(target)
            }
        }
    }

    func run() async {
        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            try await preflightCapture()
            try await applySetup()
            try await refreshDisplay()
            try await sleep(scene.setup.settle)
            try await startRecording()
            try await sleep(scene.record.leadIn)
            for (index, action) in scene.actions.enumerated() {
                if case .waitForUser = action {} else { try SystemDialogs.ensureNone() }
                CapsLock.turnOff()
                event("[\(index + 1)/\(scene.actions.count)] \(describe(action))")
                try await perform(action)
                trackWindows()
            }
            try await sleep(scene.record.leadOut)
            try await stopRecording()
        } catch {
            manifest.failure = "\(error)"
            Log.warn("failed: \(error)")
            try? await stopRecording()
        }
        do {
            try manifest.write(to: outputURL.appendingPathComponent("manifest.json"))
        } catch {
            Log.warn("couldn't write manifest: \(error)")
        }
    }

    // MARK: - Recording

    /// Captures once before touching anything, so macOS's periodic "bypass
    /// the private window picker" confirmation shows up now, not mid-take.
    private func preflightCapture() async throws {
        try SystemDialogs.ensureNone()
        let probe = FileManager.default.temporaryDirectory.appendingPathComponent("showreel-preflight.png")
        try await Screenshots.capture(
            .region(Rect(x: 0, y: 0, width: 8, height: 8)), display: display, scale: scale, cursor: false, to: probe
        )
        try? FileManager.default.removeItem(at: probe)
        try await Task.sleep(for: .seconds(1))
        try SystemDialogs.ensureNone()
    }

    /// A display mode switch in setup changes the display's size.
    private func refreshDisplay() async throws {
        guard scene.setup.display != nil else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        if let updated = content.displays.first(where: { $0.displayID == display.displayID }) {
            scale = NSScreen.main.map { Double($0.backingScaleFactor) } ?? scale
            manifest.display = .init(width: Double(updated.width), height: Double(updated.height), scale: scale)
        }
    }

    private func startRecording() async throws {
        guard scene.record.video else {
            recordingStart = Date()
            return
        }
        let url = outputURL.appendingPathComponent(Self.videoName)
        try? FileManager.default.removeItem(at: url)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let current = content.displays.first { $0.displayID == display.displayID } ?? display
        recorder = try await ScreenRecorder.start(display: current, scale: scale, settings: scene.record, to: url)
        recordingStart = Date()
        try SystemDialogs.ensureNone()
        manifest.video = Self.videoName
        event("recording \(Int(manifest.display.width * scale))×\(Int(manifest.display.height * scale))")
    }

    private func stopRecording() async throws {
        guard let recorder else {
            if manifest.duration == nil { manifest.duration = elapsed }
            return
        }
        self.recorder = nil
        manifest.duration = elapsed
        try await recorder.stop()
        event("recording stopped")
    }

    var elapsed: Double {
        recordingStart.map { Date().timeIntervalSince($0) } ?? 0
    }

    func event(_ text: String) {
        Log.info(text)
        if recordingStart != nil {
            manifest.events.append(.init(time: (elapsed * 1000).rounded() / 1000, text: text))
        }
    }

    func warn(_ text: String) {
        Log.warn(text)
        manifest.warnings.append(text)
    }

    /// Sleeps while keeping track of where windows are, so a crop to the
    /// picker covers it even if it only showed up during a wait.
    func sleep(_ seconds: Double) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            trackWindows()
            try await Task.sleep(for: .seconds(min(0.1, max(0, deadline.timeIntervalSinceNow))))
        }
    }

    func trackWindows() {
        guard recordingStart != nil else { return }
        for target in trackedTargets {
            guard let frame = Windows.find(target)?.frame else { continue }
            manifest.windows[target.name] = manifest.windows[target.name].map { $0.union(frame) } ?? frame
        }
    }

    func resolve(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded) }
        return URL(fileURLWithPath: expanded, relativeTo: sceneURL.deletingLastPathComponent()).standardizedFileURL
    }
}
