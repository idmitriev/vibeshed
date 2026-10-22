import Foundation
import Yams

public enum SceneError: Error, CustomStringConvertible, Equatable {
    case invalid(String)

    public var description: String {
        switch self {
        case let .invalid(message): message
        }
    }
}

/// A scene script: the state the VM starts in, the actions played while
/// recording, and the files cut from the recording afterwards.
///
/// Every field but `actions` has a default, decoded with `decodeIfPresent`
/// so a scene only spells out what it changes.
public struct Scene: Decodable, Sendable {
    public var title: String?
    /// `fresh` runs the scene on a new clone of the VM, deleted after the take.
    public var machine: Machine
    public var setup: Setup
    public var record: RecordSettings
    public var actions: [SceneAction]
    public var outputs: [OutputSpec]

    public enum Machine: String, Decodable, Sendable {
        case current, fresh
    }

    enum CodingKeys: String, CodingKey {
        case title, machine, setup, record, actions, outputs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        machine = try container.decodeIfPresent(Machine.self, forKey: .machine) ?? .current
        setup = try container.decodeIfPresent(Setup.self, forKey: .setup) ?? Setup()
        record = try container.decodeIfPresent(RecordSettings.self, forKey: .record) ?? RecordSettings()
        actions = try container.decodeIfPresent([SceneAction].self, forKey: .actions) ?? []
        outputs = try container.decodeIfPresent([OutputSpec].self, forKey: .outputs) ?? []
    }

    public static func load(from url: URL) throws -> Scene {
        let text = try String(contentsOf: url, encoding: .utf8)
        do {
            return try YAMLDecoder().decode(Scene.self, from: text)
        } catch let error as DecodingError {
            throw SceneError.invalid("\(url.lastPathComponent): \(describe(error))")
        }
    }

    /// Files the scene reads, relative to the scene file, so the host can copy
    /// them into the VM next to it.
    public var referencedFiles: [String] {
        var files: [String] = []
        if let wallpaper = setup.wallpaper, !wallpaper.hasPrefix("#") { files.append(wallpaper) }
        files.append(contentsOf: setup.vibeshed.config)
        files.append(contentsOf: setup.sync)
        files.append(contentsOf: setup.vibeshed.files.values.sorted())
        // Documents apps open, unless they're URLs or paths in the VM.
        files.append(contentsOf: setup.apps.compactMap(\.open).filter {
            !$0.contains("://") && !$0.hasPrefix("/") && !$0.hasPrefix("~")
        })
        return files
    }

    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        }
        switch error {
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            return "\(path(context)): \(context.debugDescription)"
        case let .keyNotFound(key, context):
            return "\(path(context)): missing '\(key.stringValue)'"
        @unknown default:
            return "\(error)"
        }
    }
}

public enum Appearance: String, Codable, Sendable {
    case dark
    case light
}

public enum Visibility: String, Codable, Sendable {
    case shown
    case hidden
}

public struct Setup: Decodable, Sendable {
    /// Display mode to switch to, in points. Best effort: the VM's virtual
    /// display only offers the modes UTM configured.
    public var display: DisplaySize?
    public var appearance: Appearance?
    /// Image file, relative to the scene file, or a solid `#rrggbb` color.
    public var wallpaper: String?
    /// `hidden` turns on Dock autohide.
    public var dock: Visibility?
    /// `hidden` turns on menu bar autohide: no clock or status icons on camera.
    public var menuBar: Visibility?
    public var desktopIcons: Visibility?
    /// Widgets on the desktop (calendar, weather…).
    public var desktopWidgets: Visibility?
    /// Region format (`en_US`), for how apps write numbers and dates. Set
    /// before Vibeshed and the apps launch, so they pick it up.
    public var locale: String?
    /// Quit every regular app (Finder stays) before opening `apps`.
    public var quitApps = true
    public var apps: [AppSetup] = []
    /// App to bring to the front once everything is open.
    public var focus: String?
    public var clipboard: String?
    public var cursor: Point?
    /// zsh script run in the guest before the apps open (after quitting the others).
    public var prepare: String?
    /// zsh script run in the guest after the apps open.
    public var shell: String?
    public var vibeshed = VibeshedSetup()
    /// Seconds to let animations finish before recording starts.
    public var settle = 1.0
    /// Actions played after everything else, before recording: off-camera
    /// prep like moving the caret or clearing an app.
    public var actions: [SceneAction] = []
    /// More files to copy into the VM, e.g. scripts `shell` runs (it gets the
    /// scene's folder in the VM as `$SCENE_DIR`).
    public var sync: [String] = []
    /// Calendar events created (fresh) in a local "Showreel" calendar; `[]`
    /// empties it, and leaving it out keeps what an earlier scene put there.
    public var events: [EventSetup]?

    enum CodingKeys: String, CodingKey {
        case display, appearance, wallpaper, dock, menuBar, desktopIcons, desktopWidgets, locale, quitApps, apps, focus
        case clipboard, cursor, prepare, shell, vibeshed, settle, actions, sync, events
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        display = try container.decodeIfPresent(DisplaySize.self, forKey: .display)
        appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance)
        wallpaper = try container.decodeIfPresent(String.self, forKey: .wallpaper)
        dock = try container.decodeIfPresent(Visibility.self, forKey: .dock)
        menuBar = try container.decodeIfPresent(Visibility.self, forKey: .menuBar)
        desktopIcons = try container.decodeIfPresent(Visibility.self, forKey: .desktopIcons)
        desktopWidgets = try container.decodeIfPresent(Visibility.self, forKey: .desktopWidgets)
        locale = try container.decodeIfPresent(String.self, forKey: .locale)
        quitApps = try container.decodeIfPresent(Bool.self, forKey: .quitApps) ?? quitApps
        apps = try container.decodeIfPresent([AppSetup].self, forKey: .apps) ?? []
        focus = try container.decodeIfPresent(String.self, forKey: .focus)
        clipboard = try container.decodeIfPresent(String.self, forKey: .clipboard)
        cursor = try container.decodeIfPresent(Point.self, forKey: .cursor)
        prepare = try container.decodeIfPresent(String.self, forKey: .prepare)
        shell = try container.decodeIfPresent(String.self, forKey: .shell)
        vibeshed = try container.decodeIfPresent(VibeshedSetup.self, forKey: .vibeshed) ?? vibeshed
        settle = try container.decodeIfPresent(Double.self, forKey: .settle) ?? settle
        actions = try container.decodeIfPresent([SceneAction].self, forKey: .actions) ?? []
        sync = try container.decodeIfPresent([String].self, forKey: .sync) ?? []
        events = try container.decodeIfPresent([EventSetup].self, forKey: .events)
    }
}

/// An app to open before recording, e.g.
/// `{ app: Safari, open: https://example.com, frame: [80, 60, 1200, 760] }`.
public struct AppSetup: Decodable, Sendable, Equatable {
    /// App name ("Safari") or bundle identifier ("com.apple.Safari").
    public var app: String
    /// URL or file path to open in it.
    public var open: String?
    /// Command-line arguments for the launch (apps are quit first, so they apply),
    /// e.g. Chrome's `--no-default-browser-check`.
    public var args: [String] = []
    /// Frame of its front window.
    public var frame: Rect?

    enum CodingKeys: String, CodingKey { case app, open, args, frame }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        app = try container.decode(String.self, forKey: .app)
        open = try container.decodeIfPresent(String.self, forKey: .open)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        frame = try container.decodeIfPresent(Rect.self, forKey: .frame)
    }
}

/// `{ title: Standup, in: 10, minutes: 15, url: "https://zoom.us/j/…" }`:
/// starts `in` minutes from setup (negative for one already running).
public struct EventSetup: Decodable, Sendable, Equatable {
    public var title: String
    public var startsIn: Double
    public var minutes: Double
    public var url: String?
    public var location: String?
    public var notes: String?

    enum CodingKeys: String, CodingKey {
        case title, startsIn = "in", minutes, url, location, notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        startsIn = try container.decodeIfPresent(Double.self, forKey: .startsIn) ?? 0
        minutes = try container.decodeIfPresent(Double.self, forKey: .minutes) ?? 30
        url = try container.decodeIfPresent(String.self, forKey: .url)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

public struct VibeshedSetup: Decodable, Sendable {
    /// Config files merged (later ones win, key by key) and written to
    /// ~/.config/vibeshed/config.yaml, relative to the scene. `${NAME}` and
    /// `${NAME:-default}` are filled from tools/showreel/.vm/secrets.env.
    public var config: [String] = []
    /// Extra files for ~/.config/vibeshed, e.g. `usage.json: ../fixtures/usage.json`.
    public var files: [String: String] = [:]
    /// Delete usage history, clipboard history, timers and the applied palette
    /// theme so ranking, history views and colors start the same on every take.
    public var reset = true
    /// Relaunch Vibeshed so it starts from the config above.
    public var launch = true
    /// Open and close the picker once before recording, so its first
    /// appearance on camera isn't the empty panel of a cold catalog.
    public var warmUp = true
    /// Turn on the keystroke visualizer once it is running.
    public var keystrokes = false
    public var app = "/Applications/Vibeshed.app"

    enum CodingKeys: String, CodingKey {
        case config, files, reset, launch, warmUp, keystrokes, app
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let one = try? container.decode(String.self, forKey: .config) {
            config = [one]
        } else {
            config = try container.decodeIfPresent([String].self, forKey: .config) ?? []
        }
        files = try container.decodeIfPresent([String: String].self, forKey: .files) ?? [:]
        reset = try container.decodeIfPresent(Bool.self, forKey: .reset) ?? reset
        launch = try container.decodeIfPresent(Bool.self, forKey: .launch) ?? launch
        warmUp = try container.decodeIfPresent(Bool.self, forKey: .warmUp) ?? warmUp
        keystrokes = try container.decodeIfPresent(Bool.self, forKey: .keystrokes) ?? keystrokes
        app = try container.decodeIfPresent(String.self, forKey: .app) ?? app
    }
}

public struct RecordSettings: Decodable, Sendable {
    /// Record a video of the display; off for screenshot-only scenes.
    public var video = true
    public var fps = 60
    public var cursor = false
    public var codec = VideoCodec.hevc
    /// Seconds recorded before the first action and after the last.
    public var leadIn = 0.5
    public var leadOut = 1.0
    /// A system dialog that comes up mid-take pauses the recording until it's answered
    /// (and banners are cleared), so it becomes a cut instead of failing the take.
    public var pauseOnDialogs = false

    enum CodingKeys: String, CodingKey {
        case video, fps, cursor, codec, leadIn, leadOut, pauseOnDialogs
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        video = try container.decodeIfPresent(Bool.self, forKey: .video) ?? video
        fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? fps
        cursor = try container.decodeIfPresent(Bool.self, forKey: .cursor) ?? cursor
        codec = try container.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? codec
        leadIn = try container.decodeIfPresent(Double.self, forKey: .leadIn) ?? leadIn
        leadOut = try container.decodeIfPresent(Double.self, forKey: .leadOut) ?? leadOut
        pauseOnDialogs = try container.decodeIfPresent(Bool.self, forKey: .pauseOnDialogs) ?? pauseOnDialogs
    }
}

public enum VideoCodec: String, Codable, Sendable {
    case h264
    case hevc
}
