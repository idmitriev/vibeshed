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
            try await Windows.bringToFront(Apps.open(app, activate: true))
        case let .window(placement):
            try place(placement)
        case let .select(title):
            try await selectRow(title)
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
        case let .type(typing):
            rowBeforeTyping = PickerResults.topRow()
            try await Keyboard.type(typing)
        case let .click(click): try await Mouse.click(resolved(click))
        case let .move(move): try await Mouse.move(to: move.to, duration: move.duration)
        case let .drag(drag): try await Mouse.drag(drag)
        case let .scroll(scroll): try await Mouse.scroll(scroll)
        default: return false
        }
        return true
    }

    private func place(_ placement: WindowPlacement) throws {
        guard let app = Apps.running(placement.app) else { throw AgentError("\(placement.app) isn't running") }
        try Windows.place(app, frame: placement.frame)
    }

    /// A click on a window lands in its middle.
    private func resolved(_ click: Click) throws -> Click {
        guard let target = click.window else { return click }
        guard let frame = Windows.find(target)?.frame else { throw AgentError("no \(target.name) window to click") }
        var click = click
        click.at = Point(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
        return click
    }

    func describe(_ action: SceneAction) -> String {
        switch action {
        case let .press(press): "press \(press.chord)" + (press.times > 1 ? " ×\(press.times)" : "")
        case let .type(typing): "type \"\(typing.text)\""
        case let .click(click): "click \(click.window?.name ?? click.at.map { "\($0.x),\($0.y)" } ?? "here")"
        case let .move(move): "move to \(move.to.x),\(move.to.y)"
        case let .drag(drag): "drag \(drag.from.x),\(drag.from.y) → \(drag.to.x),\(drag.to.y)"
        case let .scroll(scroll): "scroll \(scroll.dy)"
        case let .recording(control): "\(control.rawValue) recording"
        case let .select(title): "select the row “\(title)”"
        default: describeOther(action)
        }
    }

    private func describeOther(_ action: SceneAction) -> String {
        switch action {
        case let .wait(seconds): "wait \(seconds)s"
        case let .open(target): "open \(target)"
        case let .screenshot(shot): "screenshot \(shot.name)"
        case let .waitFor(condition):
            "wait for \(condition.name)" + (condition.gone ? " to close" : condition.fresh ? " from this search" : "")
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
                lastSeen = PickerResults.topTitle()
                let changed = !condition.fresh || PickerResults.topRow() != rowBeforeTyping
                if changed, topResult(lastSeen, startsWith: text) { return }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        switch condition.target {
        case let .window(window):
            let state = condition.gone ? "close" : "appear"
            let titled = condition.title.map { " titled “\($0)” (last title: “\(lastSeen ?? "")”)" } ?? ""
            throw AgentError("\(window.name)\(titled) didn't \(state) within \(condition.timeout)s")
        case let .result(text):
            if condition.fresh, topResult(lastSeen, startsWith: text) {
                // The search may simply have the same first result as the list before it.
                return warn("the picker's top result stayed “\(rowBeforeTyping ?? "")” after typing")
            }
            throw AgentError("the picker's top result is “\(lastSeen ?? "nothing")”, not “\(text)”")
        }
    }

    /// A prefix, not a substring: "Search Google for “design review”" must not pass
    /// for the event "Design review".
    private func topResult(_ title: String?, startsWith text: String) -> Bool {
        title.map { $0.lowercased().hasPrefix(text.lowercased()) } ?? false
    }

    /// Presses ↓ from the top row down to the first one titled `title` (a prefix), once
    /// the list has settled: two readings 0.35 s apart agree, so a re-ranking can't move
    /// the row between reading and pressing.
    private func selectRow(_ title: String, timeout: Double = 6) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var titles: [String] = []
        var previous: [String]?
        while Date() < deadline {
            titles = PickerResults.rowTitles()
            defer { previous = titles }
            if titles == previous, let index = titles.firstIndex(where: { topResult($0, startsWith: title) }) {
                if index > 0 {
                    try await Keyboard.press(KeyPress(chord: .parse("down"), times: index, interval: 0.12))
                }
                try await confirmPreview(title)
                return
            }
            try await Task.sleep(for: .milliseconds(350))
        }
        Log.info("picker list:\n" + PickerResults.treeSummary())
        throw AgentError("no picker row “\(title)” (rows: \(titles.prefix(8).joined(separator: " | ")))")
    }

    /// Waits for the preview pane to show `title`: proof the highlight is on that row
    /// (a list that refreshes, like a meeting's countdown, puts it back on the top row).
    private func confirmPreview(_ title: String, timeout: Double = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if PickerResults.previewTexts().contains(where: { topResult($0, startsWith: title) }) { return }
            try await Task.sleep(for: .milliseconds(150))
        }
        throw AgentError("the preview doesn't show “\(title)”: the highlight isn't on that row")
    }

    func waitForUser(_ seconds: Double) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        try await Task.sleep(for: .seconds(1.5))   // a prompt the last step triggered may still be coming
        var announced: Set<String> = []
        var clearSince: Date?
        while Date() < deadline {
            // Notification banners too: someone at the VM can clear them while the take waits.
            guard let dialog = SystemDialogs.current() ?? SystemDialogs.banner() else {
                // Clear for a moment, not an instant: answering one prompt can open
                // another (an "Open System Settings" button, then its password sheet).
                let since = clearSince ?? Date()
                clearSince = since
                if Date().timeIntervalSince(since) >= 2.5 { return }
                try await Task.sleep(for: .milliseconds(250))
                continue
            }
            clearSince = nil
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
