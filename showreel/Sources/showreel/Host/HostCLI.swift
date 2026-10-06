import Foundation
import ShowreelCore

enum HostCLI {
    static let usage = """
    usage: scripts/showreel <command>

      record <scene>...       record scenes in the VM and cut their outputs
        --no-post             skip cutting outputs
      post <scene>...         re-cut outputs from the last take (no VM needed)
      list                    list scenes

      vm setup [--host IP]    create the SSH key; with --host, record the guest's details
      vm doctor               check (and ask for) the agent's permissions in the VM
      vm grant [--dry-run]    grant ShowreelAgent + Vibeshed their permissions in the VM with
                              sudo (password from Keychain); needs SIP off in the VM
      vm inspect              screenshot + window frames, for writing scenes
      vm install-vibeshed     install Vibeshed in the VM from Homebrew
        --dev                 …or copy this checkout's build (make build)
      vm start | stop | status
      vm ssh [command]        shell into the VM

    Scenes live in showreel/scenes/; takes and outputs land in showreel/out/<scene>/.
    """

    static func main(_ arguments: [String]) -> Int32 {
        do {
            let repo = try findRepo()
            let vm = VirtualMachine.load(repo: repo)
            let takes = Takes(repo: repo, vm: vm)
            var rest = arguments.dropFirst()
            switch arguments.first {
            case "record":
                let postProcess = !rest.contains("--no-post")
                rest.removeAll { $0 == "--no-post" }
                guard !rest.isEmpty else { throw HostError("which scene? (scripts/showreel list)") }
                try takes.record(Array(rest), postProcess: postProcess)
            case "post":
                guard !rest.isEmpty else { throw HostError("which scene?") }
                try takes.postProcess(Array(rest))
            case "list":
                try list(takes)
            case "vm":
                try VMCommands(repo: repo, vm: vm, takes: takes).run(Array(rest))
            case nil, "help", "-h", "--help":
                print(usage)
            default:
                throw HostError("unknown command '\(arguments[0])'\n\n\(usage)")
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("✗ \(error)\n".utf8))
            return 1
        }
    }

    /// `SHOWREEL_REPO` (set by scripts/showreel), else the nearest folder up
    /// from here with `showreel/Package.swift`.
    private static func findRepo() throws -> URL {
        if let repo = ProcessInfo.processInfo.environment["SHOWREEL_REPO"] {
            return URL(fileURLWithPath: repo)
        }
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("showreel/Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw HostError("run this from the Vibeshed repo")
    }

    private static func list(_ takes: Takes) throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: takes.scenesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "yaml" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            do {
                let scene = try Scene.load(from: file)
                let outputs = scene.outputs.map(\.fileName).joined(separator: ", ")
                print("\(name.padding(toLength: 24, withPad: " ", startingAt: 0)) \(scene.title ?? "")")
                print("\(String(repeating: " ", count: 25))\(scene.actions.count) actions → \(outputs)")
            } catch {
                print("\(name): ✗ \(error)")
            }
        }
    }
}

struct VMCommands {
    let repo: URL
    let vm: VirtualMachine
    let takes: Takes

    func run(_ arguments: [String]) throws {
        let options = Array(arguments.dropFirst())
        switch arguments.first {
        case "setup": try setup(options)
        case "start", "stop": try arguments[0] == "start" ? vm.start() : vm.stop()
        case "status": print("\(vm.name): \(vm.status()), address \(vm.address() ?? "unknown")")
        case "ssh": try ssh(options)
        case "doctor": try doctor()
        case "grant": try grant(dryRun: options.contains("--dry-run"))
        case "inspect": try inspect()
        case "install-vibeshed": try installVibeshed(dev: options.contains("--dev"))
        case "deploy": try takes.deployAgent(host: vm.ensureReady())
        default: throw HostError("unknown vm command\n\n\(HostCLI.usage)")
        }
    }

    private func ssh(_ command: [String]) throws {
        let host = try vm.ensureReady()
        try Shell.run(["/usr/bin/ssh"] + vm.sshOptions(tty: true) + ["\(vm.user)@\(host)"] + command, check: false)
    }

    private func setup(_ options: [String]) throws {
        let key = VirtualMachine.keyPath
        if !FileManager.default.fileExists(atPath: key) {
            try Shell.run(["/usr/bin/ssh-keygen", "-t", "ed25519", "-N", "", "-C", "vibeshed-showreel", "-f", key])
        }
        try FileManager.default.createDirectory(at: vm.stateDirectory, withIntermediateDirectories: true)
        let publicKey = vm.stateDirectory.appendingPathComponent("host_key.pub")
        try? FileManager.default.removeItem(at: publicKey)
        try FileManager.default.copyItem(atPath: key + ".pub", toPath: publicKey.path)

        guard let index = options.firstIndex(of: "--host"), index + 1 < options.count else {
            print("""
            Key ready. Turn on Remote Login in the VM, then either run this in the VM's Terminal:
                sh "/Volumes/My Shared Files/<share>/showreel/guest/bootstrap.sh"
            or authorize the key from here (asks for the VM user's password) and record the guest:
                ssh-copy-id -i \(key).pub \(vm.user)@<vm-ip>
                scripts/showreel vm setup --host <vm-ip>
            """)
            return
        }
        var configured = vm
        configured.fixedHost = options[index + 1]
        if let userIndex = options.firstIndex(of: "--user"), userIndex + 1 < options.count {
            configured.user = options[userIndex + 1]
        }
        let host = options[index + 1]
        let probe = """
        iface=$(route -n get default | awk '/interface:/ { print $2 }')
        echo "GUEST_MAC=$(ifconfig $iface | awk '/ether / { print $2 }')"
        echo "GUEST_MACOS=$(sw_vers -productVersion)"
        """
        let output = try Shell.capture(configured.sshCommand(host: host, probe))
        let values = VirtualMachine.parseEnv(output)
        configured.mac = values["GUEST_MAC"]
        configured.fixedHost = nil
        try configured.save(extra: ["GUEST_MACOS": values["GUEST_MACOS"] ?? ""])
        print("✓ guest \(configured.user)@\(host), macOS \(values["GUEST_MACOS"] ?? "?"), MAC \(configured.mac ?? "?")")
        print("Next: make showreel && scripts/showreel vm doctor")
    }

    private func doctor() throws {
        for tool in ["ffmpeg", "rsync", "utmctl"] {
            print("\(Shell.which(tool) != nil ? "✓" : "✗") \(tool) on the host")
        }
        let host = try vm.ensureReady()
        print("✓ VM “\(vm.name)” at \(vm.user)@\(host)")
        try takes.deployAgent(host: host)
        print("Asking the agent in the VM (answer any prompts there)…")
        try takes.runAgent(host: host, ["doctor"], output: "Showreel/takes/_doctor")
    }

    private func inspect() throws {
        let host = try vm.ensureReady()
        try takes.deployAgent(host: host)
        let guestOutput = "Showreel/takes/_inspect"
        try takes.runAgent(host: host, ["inspect", "--out", guestOutput], output: guestOutput)
        let local = takes.outDirectory.appendingPathComponent("_inspect")
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try vm.fetch(host: host, guestOutput + "/", to: local.path + "/")
        print("📁 \(local.path)/screen.png")
    }

    private func installVibeshed(dev: Bool) throws {
        let host = try vm.ensureReady()
        if dev {
            try Shell.run(["/usr/bin/make", "-C", repo.path, "build"])
            try vm.runScript(host: host, "pkill -x Vibeshed; true")
            try vm.rsync(
                host: host, [repo.appendingPathComponent(".build/Vibeshed.app").path + "/"],
                to: "/Applications/Vibeshed.app/", extra: ["--delete"]
            )
            print("✓ installed this checkout's build at /Applications/Vibeshed.app in the VM")
        } else {
            try vm.runScript(host: host, """
            export PATH=/opt/homebrew/bin:$PATH
            if brew list --cask vibeshed >/dev/null 2>&1; then
                brew upgrade --cask vibeshed || true
            else
                brew install --cask idmitriev/tap/vibeshed
            fi
            """)
        }
        print("Open Vibeshed once in the VM and grant Accessibility + Input Monitoring when it asks.")
    }
}
