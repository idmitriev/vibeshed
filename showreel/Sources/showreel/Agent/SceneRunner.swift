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
    /// Recording time spent paused so far, and when the current pause began.
    private var pausedTotal: TimeInterval = 0
    private var pausedAt: Date?
    /// Recording time the current segment started at.
    private var segmentStart: Double = 0
    /// Windows whose frames the manifest keeps, for crops in outputs.
    private var trackedTargets: [WindowTarget] = [.picker]
    /// The picker's top row when the last typing started, for `waitFor` a fresh result.
    var rowBeforeTyping: String?

    static let videoName = "recording.mov"

    /// A take's video is written in segments, split by `recording: pause`; the host
    /// joins them into `videoName`.
    static func segmentName(_ index: Int) -> String {
        "recording-\(index).mov"
    }

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
                if case .waitForUser = action {} else { try await guardAgainstDialogs() }
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
        manifest.segments = []
        try await startSegment()
        recordingStart = Date()
        try SystemDialogs.ensureNone()
        manifest.video = Self.videoName
        event("recording \(Int(manifest.display.width * scale))×\(Int(manifest.display.height * scale))")
    }

    private func startSegment() async throws {
        let name = Self.segmentName((manifest.segments?.count ?? 0) + 1)
        let url = outputURL.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let current = content.displays.first { $0.displayID == display.displayID } ?? display
        recorder = try await ScreenRecorder.start(display: current, scale: scale, settings: scene.record, to: url)
        segmentStart = elapsed
        manifest.segments?.append(.init(file: name, duration: 0))
    }

    /// Ends the current segment; its duration is the recording time it covered.
    private func finishSegment() async throws {
        guard let recorder else { return }
        self.recorder = nil
        if var segments = manifest.segments, !segments.isEmpty {
            segments[segments.count - 1].duration = ((elapsed - segmentStart) * 1000).rounded() / 1000
            manifest.segments = segments
        }
        try await recorder.stop()
    }

    /// No input goes out while a system dialog is up: the take stops, or with
    /// `record.pauseOnDialogs` its recording pauses until someone answers.
    private func guardAgainstDialogs() async throws {
        guard scene.record.pauseOnDialogs, SystemDialogs.current() != nil else {
            return try SystemDialogs.ensureNone()
        }
        let pausedHere = pausedAt == nil
        if pausedHere { try await pauseRecording() }
        try await waitForUser(900)
        if pausedHere { try await resumeRecording() }
    }

    func pauseRecording() async throws {
        guard pausedAt == nil, recordingStart != nil else { return }
        try await finishSegment()
        pausedAt = Date()
    }

    func resumeRecording() async throws {
        guard let pausedAt else { return }
        pausedTotal += Date().timeIntervalSince(pausedAt)
        self.pausedAt = nil
        if scene.record.video {
            try await startSegment()
            try SystemDialogs.ensureNone()
        }
    }

    private func stopRecording() async throws {
        if let pausedAt {
            // A take that ends paused: its last segment is already finished.
            pausedTotal += Date().timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }
        guard recorder != nil else {
            if manifest.duration == nil { manifest.duration = elapsed }
            return
        }
        manifest.duration = elapsed
        try await finishSegment()
        event("recording stopped")
    }

    /// Recording time: seconds since recording started, less the paused stretches
    /// (it stands still during a pause).
    var elapsed: Double {
        guard let recordingStart else { return 0 }
        let now = pausedAt ?? Date()
        return now.timeIntervalSince(recordingStart) - pausedTotal
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
