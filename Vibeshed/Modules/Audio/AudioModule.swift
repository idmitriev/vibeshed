import CoreAudio
import Foundation
import OSLog

actor AudioModule: ModuleConfigurable {
    let id = "audio"
    let displayName = "Audio"
    let iconName = "speaker.wave.2"
    var isEnabled = true

    typealias Config = AudioConfig
    static var defaultConfig: Config? { .init() }

    private var config: AudioConfig = .init()
    private var context: ModuleContext?
    private let log = Log.module("audio")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        log.info("Audio module initialized")
    }

    func configDidUpdate(_ config: AudioConfig) async {
        self.config = config
        log.debug("Config updated")
    }

    static func validate(_ config: AudioConfig) -> ConfigValidationResult {
        var errors: [String] = []
        for step in config.volumeSteps {
            if step < 0 || step > 100 {
                errors.append("volumeSteps value \(step) must be between 0 and 100")
            }
        }
        if Set(config.volumeSteps).count != config.volumeSteps.count {
            errors.append("volumeSteps contains duplicate values")
        }
        if config.volumeStep < 1 || config.volumeStep > 50 {
            errors.append("volumeStep must be between 1 and 50")
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        let actions = buildActions(config: config)

        guard !query.isEmpty else { return actions }
        let lowered = query.lowercased()
        return actions.filter { action in
            action.title.lowercased().contains(lowered)
                || action.subtitle.lowercased().contains(lowered)
                || action.keywords.contains { $0.contains(lowered) }
        }
    }

    func provideParameterOptions(
        for parameterID: String,
        in actionID: ActionID,
        query: String
    ) async -> [ParameterOption] {
        guard parameterID == "device" else { return [] }

        let raw = actionID.rawValue
        let isInput = raw.hasSuffix("selectInput")

        let devices: [AudioManager.AudioDevice]
        let currentID: AudioDeviceID

        if isInput {
            devices = AudioManager.inputDevices()
            currentID = AudioManager.defaultInputDeviceID()
        } else {
            devices = AudioManager.outputDevices()
            currentID = AudioManager.defaultOutputDeviceID()
        }

        let options = devices.map { device in
            let label = device.id == currentID
                ? "\(device.name) (current)"
                : device.name
            return ParameterOption(
                id: String(device.id),
                label: label,
                iconName: isInput ? "mic" : "speaker.wave.2"
            )
        }

        guard !query.isEmpty else { return options }
        let lowered = query.lowercased()
        return options.filter { $0.label.lowercased().contains(lowered) }
    }

    // MARK: - Build Actions

    private func buildActions(config: AudioConfig) -> [AudioAction] {
        let enabled = config.enabledActions
        var actions: [AudioAction] = []

        actions.append(contentsOf: buildMuteActions())
        actions.append(contentsOf: buildVolumeActions(config: config))
        actions.append(contentsOf: buildMediaActions())
        actions.append(contentsOf: buildDeviceActions())

        if let enabled {
            return actions.filter { enabled.contains(actionName($0.id)) }
        }
        return actions
    }

    private func actionName(_ id: ActionID) -> String {
        let raw = id.rawValue
        guard let dotIndex = raw.firstIndex(of: ".") else { return raw }
        return String(raw[raw.index(after: dotIndex)...])
    }

    // MARK: - Mute Actions

    private func buildMuteActions() -> [AudioAction] {
        let outputMuted = AudioManager.isOutputMuted()
        let inputMuted = AudioManager.isInputMuted()

        return [
            AudioAction(
                id: ActionID(module: "audio", name: "mute"),
                title: "Toggle Mute",
                subtitle: outputMuted ? "Currently muted" : "Currently unmuted",
                iconName: outputMuted ? "speaker.slash" : "speaker.wave.2",
                relevanceScore: 0.9,
                keywords: ["mute", "unmute", "sound", "audio", "speaker", "silent"]
            ) { _ in
                AudioManager.toggleOutputMute()
                return .dismiss
            },
            AudioAction(
                id: ActionID(module: "audio", name: "micMute"),
                title: "Toggle Mic Mute",
                subtitle: inputMuted ? "Mic currently muted" : "Mic currently unmuted",
                iconName: inputMuted ? "mic.slash" : "mic",
                relevanceScore: 0.85,
                keywords: ["mic", "microphone", "mute", "unmute", "input", "audio"]
            ) { _ in
                let success = AudioManager.toggleInputMute()
                if success {
                    return .dismiss
                }
                return .showResult(
                    title: "Mic Mute",
                    body: "Current input device does not support mute"
                )
            },
        ]
    }

    // MARK: - Volume Actions

    private func buildVolumeActions(config: AudioConfig) -> [AudioAction] {
        let currentVolume = Int(AudioManager.getOutputVolume() * 100)
        let step = config.volumeStep

        var actions: [AudioAction] = [
            AudioAction(
                id: ActionID(module: "audio", name: "volumeUp"),
                title: "Volume Up",
                subtitle: "Increase by \(step)% (current: \(currentVolume)%)",
                iconName: "speaker.plus",
                relevanceScore: 0.85,
                keywords: ["volume", "up", "increase", "louder", "audio", "sound"]
            ) { _ in
                let current = AudioManager.getOutputVolume()
                AudioManager.setOutputVolume(current + Float(step) / 100.0)
                return .dismiss
            },
            AudioAction(
                id: ActionID(module: "audio", name: "volumeDown"),
                title: "Volume Down",
                subtitle: "Decrease by \(step)% (current: \(currentVolume)%)",
                iconName: "speaker.minus",
                relevanceScore: 0.85,
                keywords: ["volume", "down", "decrease", "quieter", "audio", "sound"]
            ) { _ in
                let current = AudioManager.getOutputVolume()
                AudioManager.setOutputVolume(current - Float(step) / 100.0)
                return .dismiss
            },
        ]

        for pct in config.volumeSteps.sorted() {
            actions.append(AudioAction(
                id: ActionID(module: "audio", name: "volume\(pct)"),
                title: "Volume \(pct)%",
                subtitle: "Set volume to \(pct)% (current: \(currentVolume)%)",
                iconName: pct == 0 ? "speaker" : "speaker.wave.1",
                relevanceScore: 0.8,
                keywords: ["volume", "set", "\(pct)", "audio", "sound"]
            ) { _ in
                AudioManager.setOutputVolume(Float(pct) / 100.0)
                return .dismiss
            })
        }

        return actions
    }

    // MARK: - Media Actions

    private func buildMediaActions() -> [AudioAction] {
        [
            AudioAction(
                id: ActionID(module: "audio", name: "playPause"),
                title: "Play / Pause",
                subtitle: "Toggle media playback",
                iconName: "playpause",
                relevanceScore: 0.9,
                keywords: ["play", "pause", "music", "media", "audio", "track"]
            ) { _ in
                AudioManager.playPause()
                return .dismiss
            },
            AudioAction(
                id: ActionID(module: "audio", name: "nextTrack"),
                title: "Next Track",
                subtitle: "Skip to next track",
                iconName: "forward.end",
                relevanceScore: 0.8,
                keywords: ["next", "skip", "forward", "track", "music", "media", "audio"]
            ) { _ in
                AudioManager.nextTrack()
                return .dismiss
            },
            AudioAction(
                id: ActionID(module: "audio", name: "previousTrack"),
                title: "Previous Track",
                subtitle: "Go to previous track",
                iconName: "backward.end",
                relevanceScore: 0.8,
                keywords: ["previous", "back", "rewind", "track", "music", "media", "audio"]
            ) { _ in
                AudioManager.previousTrack()
                return .dismiss
            },
        ]
    }

    // MARK: - Device Actions

    private func buildDeviceActions() -> [AudioAction] {
        let outputName = AudioManager.defaultOutputDeviceName()
        let inputName = AudioManager.defaultInputDeviceName()

        return [
            AudioAction(
                id: ActionID(module: "audio", name: "selectOutput"),
                title: "Select Output Device",
                subtitle: "Current: \(outputName)",
                iconName: "hifispeaker",
                relevanceScore: 0.75,
                keywords: ["output", "device", "speaker", "headphones", "audio", "switch"],
                parameters: [
                    ActionParameter(
                        id: "device",
                        label: "Output Device",
                        type: .dynamicSelection(hint: "device"),
                        isRequired: true
                    ),
                ]
            ) { values in
                guard let deviceStr = values["device"] as? String,
                      let deviceID = UInt32(deviceStr)
                else {
                    return .showResult(title: "Error", body: "No device selected")
                }
                AudioManager.setDefaultOutputDevice(deviceID)
                let name = AudioManager.defaultOutputDeviceName()
                return .showResult(title: "Output Device", body: "Switched to \(name)")
            },
            AudioAction(
                id: ActionID(module: "audio", name: "selectInput"),
                title: "Select Input Device",
                subtitle: "Current: \(inputName)",
                iconName: "mic.badge.plus",
                relevanceScore: 0.75,
                keywords: ["input", "device", "microphone", "mic", "audio", "switch"],
                parameters: [
                    ActionParameter(
                        id: "device",
                        label: "Input Device",
                        type: .dynamicSelection(hint: "device"),
                        isRequired: true
                    ),
                ]
            ) { values in
                guard let deviceStr = values["device"] as? String,
                      let deviceID = UInt32(deviceStr)
                else {
                    return .showResult(title: "Error", body: "No device selected")
                }
                AudioManager.setDefaultInputDevice(deviceID)
                let name = AudioManager.defaultInputDeviceName()
                return .showResult(title: "Input Device", body: "Switched to \(name)")
            },
        ]
    }
}
