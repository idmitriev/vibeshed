import Foundation

/// One step of a scene. Each is a single-key mapping, with a short scalar form
/// for the common case and a mapping for options:
///
/// ```yaml
/// - press: capslock+space
/// - press: { keys: down, times: 3 }
/// - type: safari
/// - screenshot: { name: results, region: picker, padding: 60 }
/// ```
public enum SceneAction: Sendable, Equatable {
    /// Pause, in seconds.
    case wait(Double)
    case press(KeyPress)
    case type(TypeText)
    /// Open a URL (`vibeshed://picker?q=theme`, `https://…`) or an app.
    case open(String)
    case click(Click)
    case move(Move)
    case drag(Drag)
    case scroll(Scroll)
    case screenshot(Screenshot)
    case waitFor(WaitCondition)
    /// Name the current moment, for `from`/`to`/`at` in outputs.
    case marker(String)
    /// Wait up to this many seconds while someone answers system dialogs in
    /// the VM (permission prompts a step just brought up); goes on once none
    /// are open. The only step that runs while a dialog is up.
    case waitForUser(Double)
    /// zsh script run in the guest.
    case shell(String)
    /// Bring an app to the front.
    case focus(String)
    case window(WindowPlacement)
    /// `recording: pause` stops capturing until `recording: resume`, for long
    /// waits: the paused stretch isn't in the take at all, and markers set
    /// during it land on the cut.
    case recording(RecordingControl)
}

public enum RecordingControl: String, Decodable, Sendable {
    case pause, resume
}

extension SceneAction: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "an action is a single-key mapping such as `press: return`"
            ))
        }
        guard let decode = Self.decoders[key.stringValue] else {
            let known = Self.decoders.keys.sorted().joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                forKey: key, in: container, debugDescription: "unknown action '\(key.stringValue)' (known: \(known))"
            )
        }
        self = try decode(container, key)
    }

    private typealias Decode = @Sendable (KeyedDecodingContainer<AnyKey>, AnyKey) throws -> SceneAction

    private static let decoders: [String: Decode] = [
        "wait": { try .wait($0.decode(Double.self, forKey: $1)) },
        "press": { try .press($0.decode(KeyPress.self, forKey: $1)) },
        "type": { try .type($0.decode(TypeText.self, forKey: $1)) },
        "open": { try .open($0.decode(String.self, forKey: $1)) },
        "click": { try .click($0.decode(Click.self, forKey: $1)) },
        "move": { try .move($0.decode(Move.self, forKey: $1)) },
        "drag": { try .drag($0.decode(Drag.self, forKey: $1)) },
        "scroll": { try .scroll($0.decode(Scroll.self, forKey: $1)) },
        "screenshot": { try .screenshot($0.decode(Screenshot.self, forKey: $1)) },
        "waitFor": { try .waitFor($0.decode(WaitCondition.self, forKey: $1)) },
        "marker": { try .marker($0.decode(String.self, forKey: $1)) },
        "waitForUser": { try .waitForUser($0.decode(Double.self, forKey: $1)) },
        "shell": { try .shell($0.decode(String.self, forKey: $1)) },
        "focus": { try .focus($0.decode(String.self, forKey: $1)) },
        "window": { try .window($0.decode(WindowPlacement.self, forKey: $1)) },
        "recording": { try .recording($0.decode(RecordingControl.self, forKey: $1)) },
    ]
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}

/// Decodes `Value` from its scalar shorthand, or from a mapping otherwise.
func decodeShorthand<Value: Decodable, Result>(
    _ decoder: Decoder,
    _ type: Value.Type,
    scalar: (Value) throws -> Result,
    mapping: (Decoder) throws -> Result
) throws -> Result {
    if let container = try? decoder.singleValueContainer(), let value = try? container.decode(type) {
        return try scalar(value)
    }
    return try mapping(decoder)
}

public struct KeyPress: Decodable, Sendable, Equatable {
    public var chord: KeyChord
    public var times = 1
    /// Seconds between repeats.
    public var interval = 0.15

    enum CodingKeys: String, CodingKey { case keys, times, interval }

    public init(chord: KeyChord, times: Int = 1, interval: Double = 0.15) {
        self.chord = chord
        self.times = times
        self.interval = interval
    }

    public init(from decoder: Decoder) throws {
        self = try decodeShorthand(decoder, String.self) { try KeyPress(chord: .parse($0)) } mapping: { decoder in
            let container = try decoder.container(keyedBy: CodingKeys.self)
            return try KeyPress(
                chord: .parse(container.decode(String.self, forKey: .keys)),
                times: container.decodeIfPresent(Int.self, forKey: .times) ?? 1,
                interval: container.decodeIfPresent(Double.self, forKey: .interval) ?? 0.15
            )
        }
    }
}

public struct TypeText: Decodable, Sendable, Equatable {
    public var text: String
    /// Characters per second.
    public var cps = 12.0
    /// How much each keystroke's delay varies, as a fraction of the average.
    /// Seeded, so every take types with the same rhythm.
    public var jitter = 0.4

    enum CodingKeys: String, CodingKey { case text, cps, jitter }

    public init(text: String, cps: Double = 12, jitter: Double = 0.4) {
        self.text = text
        self.cps = cps
        self.jitter = jitter
    }

    public init(from decoder: Decoder) throws {
        self = try decodeShorthand(decoder, String.self) { TypeText(text: $0) } mapping: { decoder in
            let container = try decoder.container(keyedBy: CodingKeys.self)
            return try TypeText(
                text: container.decode(String.self, forKey: .text),
                cps: container.decodeIfPresent(Double.self, forKey: .cps) ?? 12,
                jitter: container.decodeIfPresent(Double.self, forKey: .jitter) ?? 0.4
            )
        }
    }
}

public enum MouseButton: String, Codable, Sendable {
    case left
    case right
}

public struct Click: Decodable, Sendable, Equatable {
    /// Where to click; the current pointer position when omitted.
    public var at: Point?
    public var button = MouseButton.left
    public var count = 1
    /// Seconds the pointer takes to glide to `at`; 0 jumps there.
    public var glide = 0.4

    enum CodingKeys: String, CodingKey { case at, button, count, glide }

    public init(at: Point?, button: MouseButton = .left, count: Int = 1, glide: Double = 0.4) {
        self.at = at
        self.button = button
        self.count = count
        self.glide = glide
    }

    public init(from decoder: Decoder) throws {
        self = try decodeShorthand(decoder, Point.self) { Click(at: $0) } mapping: { decoder in
            let container = try decoder.container(keyedBy: CodingKeys.self)
            return try Click(
                at: container.decodeIfPresent(Point.self, forKey: .at),
                button: container.decodeIfPresent(MouseButton.self, forKey: .button) ?? .left,
                count: container.decodeIfPresent(Int.self, forKey: .count) ?? 1,
                glide: container.decodeIfPresent(Double.self, forKey: .glide) ?? 0.4
            )
        }
    }
}

public struct Move: Decodable, Sendable, Equatable {
    public var to: Point
    public var duration = 0.5

    enum CodingKeys: String, CodingKey { case to, duration }

    public init(to: Point, duration: Double = 0.5) {
        self.to = to
        self.duration = duration
    }

    public init(from decoder: Decoder) throws {
        self = try decodeShorthand(decoder, Point.self) { Move(to: $0) } mapping: { decoder in
            let container = try decoder.container(keyedBy: CodingKeys.self)
            return try Move(
                to: container.decode(Point.self, forKey: .to),
                duration: container.decodeIfPresent(Double.self, forKey: .duration) ?? 0.5
            )
        }
    }
}

public struct Drag: Decodable, Sendable, Equatable {
    public var from: Point
    public var to: Point
    public var duration = 0.6
}

public struct Scroll: Decodable, Sendable, Equatable {
    /// Where to scroll; the current pointer position when omitted.
    public var at: Point?
    /// Lines to scroll; positive moves the content up, like scrolling down a page.
    public var dy = 0.0
    public var dx = 0.0
    public var duration = 0.4

    enum CodingKeys: String, CodingKey { case at, dy, dx, duration }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        at = try container.decodeIfPresent(Point.self, forKey: .at)
        dy = try container.decodeIfPresent(Double.self, forKey: .dy) ?? 0
        dx = try container.decodeIfPresent(Double.self, forKey: .dx) ?? 0
        duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0.4
    }
}

/// A window a step targets: the Vibeshed picker, or an app's front window by
/// app name or bundle identifier.
public enum WindowTarget: Sendable, Equatable {
    case picker
    case app(String)

    init(_ text: String) {
        self = text == "picker" ? .picker : .app(text)
    }

    public var name: String {
        switch self {
        case .picker: "picker"
        case let .app(app): app
        }
    }
}

/// A part of the display: a fixed rectangle, or wherever a window is when the
/// step runs.
public enum RegionTarget: Sendable, Equatable {
    case rect(Rect)
    case window(WindowTarget)
}

public struct Screenshot: Decodable, Sendable, Equatable {
    public var name: String
    /// Capture just this window, with its shadow on a transparent background.
    public var window: WindowTarget?
    /// Capture this part of the display, wallpaper and all.
    public var region: RegionTarget?
    /// Points added around `region`.
    public var padding = 0.0

    enum CodingKeys: String, CodingKey { case name, window, region, padding }

    public init(name: String, window: WindowTarget? = nil, region: RegionTarget? = nil, padding: Double = 0) {
        self.name = name
        self.window = window
        self.region = region
        self.padding = padding
    }

    public init(from decoder: Decoder) throws {
        self = try decodeShorthand(decoder, String.self) { Screenshot(name: $0) } mapping: { decoder in
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var region: RegionTarget?
            if let rect = try? container.decode(Rect.self, forKey: .region) {
                region = .rect(rect)
            } else if let name = try container.decodeIfPresent(String.self, forKey: .region) {
                region = .window(WindowTarget(name))
            }
            return try Screenshot(
                name: container.decode(String.self, forKey: .name),
                window: container.decodeIfPresent(String.self, forKey: .window).map(WindowTarget.init),
                region: region,
                padding: container.decodeIfPresent(Double.self, forKey: .padding) ?? 0
            )
        }
    }
}

public struct WaitCondition: Decodable, Sendable, Equatable {
    public enum Target: Sendable, Equatable {
        /// A window appearing (or closing, with `gone`).
        case window(WindowTarget)
        /// The picker's top result starting with this text (any case). Check it
        /// before pressing Return: right after the picker opens, the list can
        /// still show results for an earlier query.
        case result(String)
    }

    public var target: Target
    /// Wait for the window to close instead.
    public var gone = false
    /// Wait until the window's title contains this, e.g. a page that loaded.
    public var title: String?
    public var timeout = 5.0

    enum CodingKeys: String, CodingKey { case window, result, gone, title, timeout }

    public init(window: WindowTarget, gone: Bool = false, title: String? = nil, timeout: Double = 5) {
        target = .window(window)
        self.gone = gone
        self.title = title
        self.timeout = timeout
    }

    public init(result: String, timeout: Double = 3) {
        target = .result(result)
        self.timeout = timeout
    }

    public var name: String {
        switch target {
        case let .window(window): window.name
        case let .result(text): "top result “\(text)”"
        }
    }

    public init(from decoder: Decoder) throws {
        self = try decodeShorthand(decoder, String.self) { WaitCondition(window: WindowTarget($0)) } mapping: {
            let container = try $0.container(keyedBy: CodingKeys.self)
            let timeout = try container.decodeIfPresent(Double.self, forKey: .timeout)
            if let result = try container.decodeIfPresent(String.self, forKey: .result) {
                return WaitCondition(result: result, timeout: timeout ?? 3)
            }
            return try WaitCondition(
                window: WindowTarget(container.decode(String.self, forKey: .window)),
                gone: container.decodeIfPresent(Bool.self, forKey: .gone) ?? false,
                title: container.decodeIfPresent(String.self, forKey: .title),
                timeout: timeout ?? 5
            )
        }
    }
}

public struct WindowPlacement: Decodable, Sendable, Equatable {
    public var app: String
    public var frame: Rect
}
