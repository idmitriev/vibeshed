import Foundation
import ShowreelCore

/// Records scenes in the VM and cuts their outputs on the host.
struct Takes {
    let repo: URL
    let vm: VirtualMachine

    var scenesDirectory: URL { repo.appendingPathComponent("showreel/scenes") }
    var outDirectory: URL { repo.appendingPathComponent("showreel/out") }
    var agentBundle: URL { repo.appendingPathComponent("showreel/.build/ShowreelAgent.app") }

    /// `picker-tour`, `picker-tour.yaml` or a path.
    func sceneURL(_ name: String) throws -> URL {
        let candidates = [
            URL(fileURLWithPath: name),
            scenesDirectory.appendingPathComponent(name),
            scenesDirectory.appendingPathComponent("\(name).yaml"),
        ]
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw HostError("no scene '\(name)' (looked in \(scenesDirectory.path))")
        }
        return url.standardizedFileURL
    }

    func takeDirectory(for sceneURL: URL) -> URL {
        outDirectory.appendingPathComponent(sceneURL.deletingPathExtension().lastPathComponent)
    }

    func deployAgent(host: String) throws {
        guard FileManager.default.fileExists(atPath: agentBundle.path) else {
            throw HostError("no \(agentBundle.path) — build it with `make showreel`")
        }
        try vm.runScript(host: host, "mkdir -p ~/Applications ~/Showreel/bin ~/Showreel/repo ~/Showreel/takes")
        // Checksums, not mtimes: the launcher bundle holds the VM's privacy
        // grants, which a replaced binary loses.
        try vm.rsync(
            host: host, [agentBundle.path + "/"], to: VirtualMachine.agentPath + "/",
            extra: ["--checksum", "--delete"]
        )
        // The agent itself runs as the launcher's child, so it can change freely.
        let binary = repo.appendingPathComponent("showreel/.build/release/showreel")
        try vm.rsync(host: host, [binary.path], to: "Showreel/bin/showreel", extra: ["--checksum"])
    }

    /// Runs `agent <command>` in the VM's GUI session and streams its log.
    /// Paths are relative to the guest's home; the agent resolves them there.
    func runAgent(host: String, _ arguments: [String], output: String) throws {
        let script = """
        out="$HOME/$1"; shift
        rm -rf "$out" && mkdir -p "$out" && : > "$out/agent.log" || exit 1
        open -g -W -n -a "$HOME/\(VirtualMachine.agentPath)" \\
            --stdout "$out/agent.log" --stderr "$out/agent.log" --args agent "$@" &
        app=$!
        tail -n +1 -f "$out/agent.log" &
        tailer=$!
        wait $app; result=$?
        sleep 0.5; kill $tailer 2>/dev/null
        exit $result
        """
        try vm.runScript(host: host, script, arguments: [output] + arguments)
    }

    func record(_ names: [String], postProcess: Bool) throws {
        let host = try vm.ensureReady()
        try deployAgent(host: host)
        for name in names {
            let url = try sceneURL(name)
            let scene = try Scene.load(from: url)
            print("\n🎬 \(scene.title ?? url.lastPathComponent)")
            let guestScene = try syncSceneFiles(url, scene: scene, host: host)
            let sceneName = url.deletingPathExtension().lastPathComponent
            let guestTake = "Showreel/takes/\(sceneName)"
            try runAgent(host: host, ["run", guestScene, "--out", guestTake], output: guestTake)
            let take = takeDirectory(for: url)
            try? FileManager.default.removeItem(at: take)
            try FileManager.default.createDirectory(at: take, withIntermediateDirectories: true)
            try vm.fetch(host: host, guestTake + "/", to: take.path + "/")
            let manifest = try Manifest.load(from: take.appendingPathComponent("manifest.json"))
            if let failure = manifest.failure {
                throw HostError("\(sceneName) failed in the VM: \(failure)\n  log: \(take.path)/agent.log")
            }
            if postProcess {
                try cutOutputs(scene: scene, manifest: manifest, take: take)
            }
            summarize(take)
        }
    }

    /// Copies the scene and the files it references into the VM, keeping
    /// their paths relative to the repo so relative references still resolve.
    /// Returns the scene's path in the VM, relative to its home.
    private func syncSceneFiles(_ url: URL, scene: Scene, host: String) throws -> String {
        let directory = url.deletingLastPathComponent()
        let files = [url] + scene.referencedFiles.map {
            URL(fileURLWithPath: $0, relativeTo: directory).standardizedFileURL
        }
        let root = repo.standardizedFileURL.path + "/"
        var sources: [String] = []
        for file in files {
            guard file.path.hasPrefix(root) else {
                throw HostError("\(file.path) is outside the repo; scenes can only use files inside it")
            }
            guard FileManager.default.fileExists(atPath: file.path) else { throw HostError("missing \(file.path)") }
            sources.append(String(file.path.dropFirst(root.count)))
        }
        // Run from the repo root: macOS's openrsync ignores the `/./` marker.
        try vm.rsync(host: host, sources, to: "Showreel/repo/", extra: ["--relative"], from: repo)
        let secrets = vm.stateDirectory.appendingPathComponent("secrets.env")
        if FileManager.default.fileExists(atPath: secrets.path) {
            // `-a` carries the mode over (openrsync has no --chmod), so make it owner-only here.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secrets.path)
            try vm.rsync(host: host, [secrets.path], to: "Showreel/secrets.env")
        }
        return "Showreel/repo/" + url.path.dropFirst(root.count)
    }

    func postProcess(_ names: [String]) throws {
        for name in names {
            let url = try sceneURL(name)
            let take = takeDirectory(for: url)
            let manifest = try Manifest.load(from: take.appendingPathComponent("manifest.json"))
            try cutOutputs(scene: Scene.load(from: url), manifest: manifest, take: take)
            summarize(take)
        }
    }

    private func cutOutputs(scene: Scene, manifest: Manifest, take: URL) throws {
        for warning in manifest.warnings {
            print("⚠️  \(warning)")
        }
        guard !scene.outputs.isEmpty else { return }
        guard let video = manifest.video else {
            throw HostError("the take has no video to cut outputs from (record.video is off)")
        }
        guard let ffmpeg = Shell.which("ffmpeg") else { throw HostError("ffmpeg not found — brew install ffmpeg") }
        for output in scene.outputs {
            print("✂️  \(output.fileName)")
            let args = try FFmpegPlan.arguments(
                for: output, manifest: manifest,
                input: take.appendingPathComponent(video).path,
                destination: take.appendingPathComponent(output.fileName).path
            )
            try Shell.run([ffmpeg] + args)
            if output.format.isVideo, output.format != .gif,
               let color = cornerColor(of: take.appendingPathComponent(output.fileName), ffmpeg: ffmpeg)
            {
                print("   top-left pixel \(color) — a page behind the clip should use this color")
            }
        }
    }

    /// The first frame's top-left color as a browser decodes it.
    private func cornerColor(of file: URL, ffmpeg: String) -> String? {
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent("showreel-corner.rgb")
        let filter = "crop=2:2:4:4,scale=1:1:in_color_matrix=bt709:in_range=tv,format=rgb24"
        let command = [
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", file.path,
            "-frames:v", "1", "-vf", filter, "-f", "rawvideo", raw.path,
        ]
        guard (try? Shell.capture(command)) != nil, let data = try? Data(contentsOf: raw), data.count >= 3 else {
            return nil
        }
        return String(format: "#%02x%02x%02x", data[0], data[1], data[2])
    }

    private func summarize(_ take: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: take, includingPropertiesForKeys: [.fileSizeKey]))
            ?? []
        print("📁 \(take.path)")
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            print("   \(file.lastPathComponent)  \(formatted)")
        }
    }
}
