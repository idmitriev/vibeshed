import Foundation
@testable import ShowreelCore
import Testing
import Yams

struct SceneTests {
    private func decode(_ yaml: String) throws -> Scene {
        try YAMLDecoder().decode(Scene.self, from: yaml)
    }

    @Test func machineDefaultsToTheCurrentVM() throws {
        #expect(try decode("title: Here").machine == .current)
        #expect(try decode("machine: fresh").machine == .fresh)
    }

    @Test func defaultsApplyToAnEmptyScene() throws {
        let scene = try decode("title: Empty")
        #expect(scene.setup.quitApps)
        #expect(scene.setup.vibeshed.launch)
        #expect(scene.setup.vibeshed.reset)
        #expect(scene.record.video)
        #expect(scene.record.fps == 60)
        #expect(!scene.record.pauseOnDialogs)
        #expect(scene.actions.isEmpty)
    }

    @Test func anEmptyEventListDiffersFromNone() throws {
        #expect(try decode("title: Untouched").setup.events == nil)
        #expect(try decode("setup:\n  events: []").setup.events == [])
        let events = try decode("setup:\n  events:\n    - { title: Standup, in: 5, minutes: 15 }").setup.events
        #expect(events?.map(\.title) == ["Standup"])
    }

    @Test func actionsDecodeFromShorthandAndMappings() throws {
        let scene = try decode("""
        actions:
          - wait: 0.5
          - press: capslock+space
          - press: { keys: down, times: 3, interval: 0.2 }
          - type: safari
          - type: { text: "Hello", cps: 20 }
          - click: [100, 200]
          - click: { at: [10, 20], button: right, glide: 0 }
          - click: { window: Ghostty }
          - screenshot: results
          - screenshot: { name: panel, window: picker }
          - screenshot: { name: around, region: picker, padding: 40 }
          - screenshot: { name: corner, region: [0, 0, 400, 300] }
          - waitFor: picker
          - waitFor: { window: picker, gone: true, timeout: 2 }
          - waitFor: { result: Safari }
          - waitFor: { result: "", fresh: true, timeout: 30 }
          - waitFor: { window: Google Chrome, title: Hacker News, timeout: 10 }
          - marker: picked
          - open: vibeshed://picker?q=theme
          - window: { app: Safari, frame: [80, 60, 1200, 760] }
          - recording: pause
          - recording: resume
        """)
        let expected: [SceneAction] = try [
            .wait(0.5),
            .press(KeyPress(chord: .parse("capslock+space"))),
            .press(KeyPress(chord: .parse("down"), times: 3, interval: 0.2)),
            .type(TypeText(text: "safari")),
            .type(TypeText(text: "Hello", cps: 20)),
            .click(Click(at: Point(x: 100, y: 200))),
            .click(Click(at: Point(x: 10, y: 20), button: .right, glide: 0)),
            .click(Click(at: nil, window: .app("Ghostty"))),
            .screenshot(Screenshot(name: "results")),
            .screenshot(Screenshot(name: "panel", window: .picker)),
            .screenshot(Screenshot(name: "around", region: .window(.picker), padding: 40)),
            .screenshot(Screenshot(name: "corner", region: .rect(Rect(x: 0, y: 0, width: 400, height: 300)))),
            .waitFor(WaitCondition(window: .picker)),
            .waitFor(WaitCondition(window: .picker, gone: true, timeout: 2)),
            .waitFor(WaitCondition(result: "Safari")),
            .waitFor(WaitCondition(result: "", fresh: true, timeout: 30)),
            .waitFor(WaitCondition(window: .app("Google Chrome"), title: "Hacker News", timeout: 10)),
            .marker("picked"),
            .open("vibeshed://picker?q=theme"),
            .window(WindowPlacement(app: "Safari", frame: Rect(x: 80, y: 60, width: 1200, height: 760))),
            .recording(.pause),
            .recording(.resume),
        ]
        #expect(scene.actions == expected)
    }

    @Test func unknownActionsAreRejected() {
        #expect(throws: DecodingError.self) {
            try decode("actions:\n  - jump: 3")
        }
        #expect(throws: DecodingError.self) {
            try decode("actions:\n  - { wait: 1, press: return }")
        }
    }

    @Test func referencedFilesCoverSetup() throws {
        let scene = try decode("""
        setup:
          wallpaper: ../../docs/wallpapers/a.jpg
          vibeshed:
            config: ../configs/demo.yaml
            files: { usage.json: ../fixtures/usage.json }
          apps:
            - { app: TextEdit, open: ../fixtures/notes.txt }
            - { app: Finder, open: /Applications }
            - { app: Safari, open: "https://example.com" }
        """)
        #expect(scene.referencedFiles == [
            "../../docs/wallpapers/a.jpg", "../configs/demo.yaml", "../fixtures/usage.json", "../fixtures/notes.txt",
        ])
    }

    @Test func beforeAfterOpensOnTheFirstFramesLeftAndTheLastFramesRight() throws {
        let scene = try decode("""
        outputs:
          - { name: clip, from: start, to: end, beforeAfter: 2 }
        """)
        let output = try #require(scene.outputs.first)
        #expect(output.beforeAfter == 2)
        let args = FFmpegPlan.beforeAfterArguments(for: output, seconds: 2, clip: "in.mp4", destination: "out.mp4")
        let graph = try #require(args.firstIndex(of: "-filter_complex").map { args[$0 + 1] })
        #expect(args.contains("-sseof"))
        #expect(graph.contains("[0:v]trim=end_frame=1,setpts=PTS-STARTPTS,crop=iw/2:ih:0:0"))
        #expect(graph.contains("[1:v]trim=end_frame=1,setpts=PTS-STARTPTS,crop=iw/2:ih:iw/2:0"))
        #expect(graph.contains("tpad=stop_mode=clone:stop_duration=2.0"))
        #expect(graph.hasSuffix("[intro][clip]concat=n=2:v=1:a=0[out]"))
        #expect(args.last == "out.mp4")
    }

    @Test func outputsDecodeCropsAndSizes() throws {
        let scene = try decode("""
        outputs:
          - name: web
          - name: square
            crop: picker
            size: 1080x1080
            background: blur
            from: opened-0.5
          - name: corner
            crop: [0, 0, 640, 400]
            format: gif
          - name: poster
            format: png
            at: picked
        """)
        #expect(scene.outputs[0].crop == .display)
        #expect(scene.outputs[1].crop == .region(.window(.picker)))
        #expect(scene.outputs[1].size == PixelSize(width: 1080, height: 1080))
        #expect(scene.outputs[1].from == TimeRef(anchor: .marker("opened"), offset: -0.5))
        #expect(scene.outputs[2].crop == .region(.rect(Rect(x: 0, y: 0, width: 640, height: 400))))
        #expect(scene.outputs[3].fileName == "poster.png")
        #expect(throws: DecodingError.self) {
            try decode("outputs:\n  - { name: still, format: png }")
        }
    }
}

struct KeyChordTests {
    @Test func parsesModifiersInPressOrder() throws {
        let chord = try KeyChord.parse("shift+cmd+capslock+k")
        #expect(chord.modifiers == [.capsLock, .shift, .command])
        #expect(chord.keyCode == 40)
    }

    @Test func parsesNamedKeysAndSymbols() throws {
        #expect(try KeyChord.parse("return").keyCode == 36)
        #expect(try KeyChord.parse("⌘+/").keyCode == 44)
        #expect(try KeyChord.parse("Down").keyCode == 125)
    }

    @Test func rejectsUnknownParts() {
        #expect(throws: SceneError.self) { try KeyChord.parse("hyper+k") }
        #expect(throws: SceneError.self) { try KeyChord.parse("cmd+") }
        #expect(throws: SceneError.self) { try KeyChord.parse("cmd+nope") }
    }

    @Test func capsLockIsHeldAsF18() throws {
        #expect(try KeyChord.parse("capslock+space").modifiers.map(\.keyCode) == [KeyCodes.f18])
    }
}

struct TimeRefTests {
    private var manifest: Manifest {
        var manifest = Manifest(scene: "test", display: .init(width: 1440, height: 900, scale: 2))
        manifest.duration = 10
        manifest.markers = ["opened": 2, "intro-end": 4]
        return manifest
    }

    @Test func resolvesMarkersOffsetsAndBounds() throws {
        #expect(try manifest.resolve(.parse("opened+0.5")) == 2.5)
        #expect(try manifest.resolve(.parse("intro-end")) == 4)
        #expect(try manifest.resolve(.parse("intro-end-1")) == 3)
        #expect(try manifest.resolve(.parse("end-1")) == 9)
        #expect(try manifest.resolve(.parse("start-3")) == 0)
        #expect(throws: SceneError.self) { try manifest.resolve(.parse("missing")) }
    }
}

struct FFmpegPlanTests {
    private var manifest: Manifest {
        var manifest = Manifest(scene: "test", display: .init(width: 1440, height: 900, scale: 2))
        manifest.video = "recording.mov"
        manifest.duration = 8
        manifest.markers = ["opened": 1.25]
        manifest.windows = ["picker": Rect(x: 370, y: 214, width: 700, height: 472)]
        return manifest
    }

    private func output(_ yaml: String) throws -> OutputSpec {
        try YAMLDecoder().decode(OutputSpec.self, from: yaml)
    }

    @Test func cropsToTheWindowWithPaddingInPixels() throws {
        let crop = try FFmpegPlan.cropPixels(for: output("{ name: a, crop: picker, padding: 50 }"), manifest: manifest)
        #expect(crop == Rect(x: 640, y: 328, width: 1600, height: 1144))
    }

    @Test func clampsCropsToTheDisplay() throws {
        let crop = try FFmpegPlan.cropPixels(for: output("{ name: a, crop: picker, padding: 400 }"), manifest: manifest)
        #expect(crop == Rect(x: 0, y: 0, width: 2880, height: 1800))
    }

    @Test func failsWhenTheWindowNeverAppeared() throws {
        let spec = try output("{ name: a, crop: Safari }")
        #expect(throws: SceneError.self) { try FFmpegPlan.cropPixels(for: spec, manifest: manifest) }
    }

    @Test func buildsAnMP4WithTrimAndPadding() throws {
        let spec = try output("{ name: sq, crop: picker, size: 1080x1080, background: '#101018', from: opened-0.25 }")
        let args = try FFmpegPlan.arguments(for: spec, manifest: manifest, input: "in.mov", destination: "sq.mp4")
        #expect(args.starts(with: ["-hide_banner", "-loglevel", "error", "-y", "-i", "in.mov"]))
        let graph = try #require(args.firstIndex(of: "-filter_complex").map { args[$0 + 1] })
        #expect(graph.hasPrefix(
            "[0:v]tpad=stop_mode=clone:stop_duration=60,trim=start=1.000:end=8.000,setpts=PTS-STARTPTS,"
                + "crop=1400:944:740:428,fps=60[clip];"
        ))
        #expect(graph.contains("pad=1080:1080:(ow-iw)/2:(oh-ih)/2:color=#101018"))
        #expect(args.contains("libx264"))
        #expect(args.last == "sq.mp4")
    }

    @Test func crossfadesALoopBackIntoItsStart() throws {
        let spec = try output("{ name: l, crop: picker, from: opened, to: 5.25, loop: 0.5 }")
        let args = try FFmpegPlan.arguments(for: spec, manifest: manifest, input: "in.mov", destination: "l.mp4")
        let graph = try #require(args.firstIndex(of: "-filter_complex").map { args[$0 + 1] })
        // 1.25…5.25 is 4s; the output starts 0.5s in and fades back from 3.0s.
        #expect(graph.contains("[clip]split[body][head]"))
        #expect(graph.contains("xfade=transition=fade:duration=0.500:offset=3.000[looped]"))
        #expect(graph.contains("[looped]null[out]"))
        let short = try output("{ name: s, from: opened, to: 2.0, loop: 0.5 }")
        #expect(throws: SceneError.self) {
            try FFmpegPlan.arguments(for: short, manifest: manifest, input: "in.mov", destination: "s.mp4")
        }
    }

    @Test func skipsAStretchAndShortensTheLoop() throws {
        let spec = try output("{ name: s, from: opened, to: 7.25, skip: [[opened+1, opened+3]], loop: 0.5 }")
        let args = try FFmpegPlan.arguments(for: spec, manifest: manifest, input: "in.mov", destination: "s.mp4")
        let graph = try #require(args.firstIndex(of: "-filter_complex").map { args[$0 + 1] })
        #expect(graph.contains("select='not(between(t,1.000,3.000))',setpts=N/(60*TB)"))
        // 6s clip − 2s skipped = 4s; the loop fades from 3.0s.
        #expect(graph.contains("offset=3.000[looped]"))
    }

    @Test func buildsAGifWithAPalette() throws {
        let spec = try output("{ name: g, format: gif, width: 801 }")
        let args = try FFmpegPlan.arguments(for: spec, manifest: manifest, input: "in.mov", destination: "g.gif")
        let graph = try #require(args.firstIndex(of: "-filter_complex").map { args[$0 + 1] })
        #expect(graph.contains("fps=15"))
        #expect(graph.contains("scale=800:-2"))
        #expect(graph.contains("palettegen"))
    }

    @Test func buildsAPosterFrame() throws {
        let spec = try output("{ name: p, format: png, at: opened+1 }")
        let args = try FFmpegPlan.arguments(for: spec, manifest: manifest, input: "in.mov", destination: "p.png")
        let graph = try #require(args.firstIndex(of: "-filter_complex").map { args[$0 + 1] })
        #expect(graph.contains("trim=start=2.250,"))
        #expect(args.contains("-frames:v"))
    }
}
