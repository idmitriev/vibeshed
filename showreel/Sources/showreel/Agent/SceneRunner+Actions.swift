import AppKit
import ShowreelCore

extension SceneRunner {
    func perform(_ action: SceneAction) async throws {
        if try await performInput(action) { return }
        switch action {
        case let .open(target):
            try await open(target)
        case let .screenshot(shot):
            try await screenshot(shot)
        case let .waitFor(condition):
            try await waitFor(condition)
        case let .marker(name):
            manifest.markers[name] = (elapsed * 1000).rounded() / 1000
        case let .shell(script):
            try runShell(script)
        case let .focus(app):
            _ = try await Apps.open(app, activate: true)
        case let .window(placement):
            guard let app = Apps.running(placement.app) else { throw AgentError("\(placement.app) isn't running") }
            try Windows.place(app, frame: placement.frame)
        default:
            break
        }
    }

    /// Keyboard, pointer, wait and recording actions; false for the rest.
    private func performInput(_ action: SceneAction) async throws -> Bool {
        switch action {
        case let .wait(seconds): try await sleep(seconds)
        case let .recording(control): try await control == .pause ? pauseRecording() : resumeRecording()
        case let .waitForUser(seconds): try await waitForUser(seconds)
        case let .press(press): try await Keyboard.press(press)
        case let .type(typing): try await Keyboard.type(typing)
        case let .click(click): try await Mouse.click(click)
        case let .move(move): try await Mouse.move(to: move.to, duration: move.duration)
        case let .drag(drag): try await Mouse.drag(drag)
        case let .scroll(scroll): try await Mouse.scroll(scroll)
        default: return false
        }
        return true
    }

    func describe(_ action: SceneAction) -> String {
        switch action {
        case let .press(press): "press \(press.chord)" + (press.times > 1 ? " ×\(press.times)" : "")
        case let .type(typing): "type \"\(typing.text)\""
        case let .click(click): "click \(click.at.map { "\($0.x),\($0.y)" } ?? "here")"
        case let .move(move): "move to \(move.to.x),\(move.to.y)"
        case let .drag(drag): "drag \(drag.from.x),\(drag.from.y) → \(drag.to.x),\(drag.to.y)"
        case let .scroll(scroll): "scroll \(scroll.dy)"
        case let .recording(control): "\(control.rawValue) recording"
        default: describeOther(action)
        }
    }

    private func describeOther(_ action: SceneAction) -> String {
        switch action {
        case let .wait(seconds): "wait \(seconds)s"
        case let .open(target): "open \(target)"
        case let .screenshot(shot): "screenshot \(shot.name)"
        case let .waitFor(condition): "wait for \(condition.name)" + (condition.gone ? " to close" : "")
        case let .marker(name): "marker \(name)"
        case let .waitForUser(seconds): "wait up to \(Int(seconds))s for dialogs to be answered"
        case .shell: "shell"
        case let .focus(app): "focus \(app)"
        case let .window(placement): "place \(placement.app)"
        default: ""
        }
    }

    /// `vibeshed://` URLs go to the scene's Vibeshed (not whichever copy
    /// LaunchServices prefers), other URLs to their default app, anything
    /// else is an app to open.
    func open(_ target: String) async throws {
        if target.hasPrefix("vibeshed://") {
            guard let url = URL(string: target) else { throw AgentError("bad URL '\(target)'") }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try await NSWorkspace.shared.open(
                [url], withApplicationAt: scene.setup.vibeshed.appURL, configuration: configuration
            )
        } else if target.contains("://"), let url = URL(string: target) {
            NSWorkspace.shared.open(url)
        } else {
            _ = try await Apps.open(target, activate: true)
        }
    }

    func screenshot(_ shot: Screenshot) async throws {
        let url = outputURL.appendingPathComponent("\(shot.name).png")
        var target = Screenshots.Target.display
        if let window = shot.window {
            guard let found = Windows.find(window) else { throw AgentError("\(window.name) isn't on screen") }
            target = .window(found.id)
        } else if let region = shot.region {
            var rect: Rect
            switch region {
            case let .rect(fixed):
                rect = fixed
            case let .window(window):
                guard let found = Windows.find(window) else { throw AgentError("\(window.name) isn't on screen") }
                rect = found.frame
            }
            target = .region(rect.insetBy(-shot.padding).clamped(to: manifest.display.bounds))
        }
        try await Screenshots.capture(target, display: display, scale: scale, cursor: scene.record.cursor, to: url)
        manifest.screenshots.append(url.lastPathComponent)
    }

    func waitFor(_ condition: WaitCondition) async throws {
        let deadline = Date().addingTimeInterval(condition.timeout)
        var lastSeen: String?
        while Date() < deadline {
            switch condition.target {
            case let .window(window):
                let found = Windows.find(window)
                lastSeen = found?.title
                let matches = found.map { info in
                    condition.title.map { info.title.localizedCaseInsensitiveContains($0) } ?? true
                } ?? false
                if matches != condition.gone {
                    trackWindows()
                    return
                }
            case let .result(text):
                // A prefix, not a substring: "Search Google for “design review”"
                // must not pass for the event "Design review".
                lastSeen = PickerResults.topTitle()
                if let lastSeen, lastSeen.lowercased().hasPrefix(text.lowercased()) { return }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        switch condition.target {
        case let .window(window):
            let state = condition.gone ? "close" : "appear"
            let titled = condition.title.map { " titled “\($0)” (last title: “\(lastSeen ?? "")”)" } ?? ""
            throw AgentError("\(window.name)\(titled) didn't \(state) within \(condition.timeout)s")
        case let .result(text):
            throw AgentError("the picker's top result is “\(lastSeen ?? "nothing")”, not “\(text)”")
        }
    }

    func waitForUser(_ seconds: Double) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        try await Task.sleep(for: .seconds(1.5))   // a prompt the last step triggered may still be coming
        var announced: Set<String> = []
        while Date() < deadline {
            // Notification banners too: someone at the VM can clear them while the take waits.
            guard let dialog = SystemDialogs.current() ?? SystemDialogs.banner() else { return }
            if announced.insert(dialog.owner).inserted {
                let ask = dialog.owner == "Notification Center"
                    ? "clear the notifications in the VM's top-right corner…"
                    : "answer the \(dialog.owner) dialog in the VM…"
                Log.info(ask)
            }
            try await Task.sleep(for: .milliseconds(300))
        }
        try SystemDialogs.ensureNone()
    }

    func runShell(_ script: String) throws {
        let sceneDir = sceneURL.deletingLastPathComponent().path
        let output = try Shell.capture(["/bin/zsh", "-lc", script], environment: ["SCENE_DIR": sceneDir])
        if !output.isEmpty {
            Log.info(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
