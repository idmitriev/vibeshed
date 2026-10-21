import AppKit
import ScreenCaptureKit
import ShowreelCore
import UniformTypeIdentifiers

/// Records the main display to a file with ScreenCaptureKit.
final class ScreenRecorder: NSObject, @unchecked Sendable {
    private let stream: SCStream
    private let output: SCRecordingOutput
    private let lock = NSLock()
    private var started: CheckedContinuation<Void, Error>?
    private var finished: CheckedContinuation<Void, Error>?
    private var finishError: Error?
    private var didFinish = false

    private init(stream: SCStream, configuration: SCRecordingOutputConfiguration) {
        self.stream = stream
        output = SCRecordingOutput(configuration: configuration, delegate: ScreenRecorderDelegateProxy.shared)
        super.init()
        ScreenRecorderDelegateProxy.shared.recorder = self
    }

    @MainActor
    static func start(display: SCDisplay, scale: Double, settings: RecordSettings, to url: URL) async throws
        -> ScreenRecorder
    {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(Double(display.width) * scale)
        configuration.height = Int(Double(display.height) * scale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.fps))
        configuration.showsCursor = settings.cursor
        configuration.queueDepth = 8
        configuration.capturesAudio = false
        let stream = SCStream(
            filter: SCContentFilter(display: display, excludingWindows: []),
            configuration: configuration,
            delegate: nil
        )
        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = url
        outputConfiguration.outputFileType = .mov
        outputConfiguration.videoCodecType = settings.codec == .hevc ? .hevc : .h264
        let recorder = ScreenRecorder(stream: stream, configuration: outputConfiguration)
        try stream.addRecordingOutput(recorder.output)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recorder.lock.withLock { recorder.started = continuation }
            stream.startCapture { error in
                if let error { recorder.resumeStarted(with: error) }
            }
        }
        return recorder
    }

    func stop() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let done = lock.withLock { () -> Bool in
                if didFinish { return true }
                finished = continuation
                return false
            }
            if done {
                continuation.resume()
                return
            }
            stream.stopCapture { [weak self] error in
                if let error { self?.resumeFinished(with: error) }
            }
        }
        if let finishError { throw finishError }
    }

    fileprivate func didStart() {
        resumeStarted(with: nil)
    }

    fileprivate func didEnd(with error: Error?) {
        lock.withLock {
            didFinish = true
            finishError = error
        }
        resumeStarted(with: error ?? AgentError("recording ended before it started"))
        resumeFinished(with: error)
    }

    private func resumeStarted(with error: Error?) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { started = nil }
            return started
        }
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }

    private func resumeFinished(with error: Error?) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { finished = nil }
            return finished
        }
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
}

/// SCRecordingOutput holds its delegate weakly and is created before the
/// recorder finishes initializing, so a long-lived proxy forwards the calls.
private final class ScreenRecorderDelegateProxy: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    static let shared = ScreenRecorderDelegateProxy()
    weak var recorder: ScreenRecorder?

    func recordingOutputDidStartRecording(_: SCRecordingOutput) {
        recorder?.didStart()
    }

    func recordingOutput(_: SCRecordingOutput, didFailWithError error: Error) {
        recorder?.didEnd(with: error)
    }

    func recordingOutputDidFinishRecording(_: SCRecordingOutput) {
        recorder?.didEnd(with: nil)
    }
}

/// Still captures: the whole display, part of it, or one window with its
/// shadow on a transparent background.
@MainActor
enum Screenshots {
    enum Target {
        case display
        case region(Rect)
        case window(CGWindowID)
    }

    static func capture(_ target: Target, display: SCDisplay, scale: Double, cursor: Bool, to url: URL) async throws {
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = cursor
        configuration.captureResolution = .best
        let filter: SCContentFilter
        var rect: Rect?
        if case let .region(region) = target { rect = region }
        if case let .window(windowID) = target {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw AgentError("window \(windowID) is no longer on screen")
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            configuration.ignoreShadowsSingleWindow = false
            configuration.shouldBeOpaque = false
            configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
            configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
            let area = rect ?? Rect(x: 0, y: 0, width: Double(display.width), height: Double(display.height))
            configuration.sourceRect = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)
            configuration.width = Int(area.width * scale)
            configuration.height = Int(area.height * scale)
        }
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try writePNG(image, to: url)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw AgentError("can't write \(url.path)") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw AgentError("can't write \(url.path)") }
    }
}
