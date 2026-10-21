import Foundation

/// The UTM macOS guest, reached over SSH with a key of its own. What the host
/// knows about it lives in `tools/showreel/.vm/guest.env` (written by `vm setup` or
/// by `guest/bootstrap.sh`); `SHOWREEL_VM`, `SHOWREEL_HOST` and
/// `SHOWREEL_USER` override it.
struct VirtualMachine {
    var name: String
    var user: String
    var mac: String?
    var fixedHost: String?
    let stateDirectory: URL

    static let keyPath = NSHomeDirectory() + "/.ssh/vibeshed_showreel"
    static let agentPath = "Applications/ShowreelAgent.app"

    static func load(repo: URL) -> VirtualMachine {
        let state = repo.appendingPathComponent("tools/showreel/.vm")
        let saved = (try? String(contentsOf: state.appendingPathComponent("guest.env"), encoding: .utf8))
            .map(parseEnv) ?? [:]
        let env = ProcessInfo.processInfo.environment
        return VirtualMachine(
            name: env["SHOWREEL_VM"] ?? saved["UTM_VM"] ?? "macOS",
            user: env["SHOWREEL_USER"] ?? saved["GUEST_USER"] ?? NSUserName(),
            mac: saved["GUEST_MAC"].flatMap { $0.isEmpty ? nil : $0 },
            fixedHost: env["SHOWREEL_HOST"] ?? saved["GUEST_HOST"].flatMap { $0.isEmpty ? nil : $0 },
            stateDirectory: state
        )
    }

    static func parseEnv(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { values[String(parts[0])] = String(parts[1]) }
        }
        return values
    }

    func save(extra: [String: String] = [:]) throws {
        var values = ["UTM_VM": name, "GUEST_USER": user, "GUEST_MAC": mac ?? ""]
        values.merge(extra) { $1 }
        let text = values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let file = stateDirectory.appendingPathComponent("guest.env")
        try (text + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - UTM

    var utmctl: String {
        Shell.which("utmctl") ?? "/Applications/UTM.app/Contents/MacOS/utmctl"
    }

    func status() -> String {
        let output = (try? Shell.capture([utmctl, "status", name], check: false)) ?? ""
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func start() throws {
        try Shell.run([utmctl, "start", name])
    }

    func stop() throws {
        try Shell.run([utmctl, "stop", name])
    }

    /// Asks the guest to shut down, then powers it off if it hasn't within `timeout`.
    func shutDown(timeout: Double = 45) throws {
        guard exists, status() != "stopped" else { return }
        print("Stopping VM “\(name)”…")
        _ = try? Shell.capture([utmctl, "stop", name, "--request"], check: false)
        if waitUntilStopped(timeout: timeout) { return }
        try Shell.run([utmctl, "stop", name, "--force"])
        guard waitUntilStopped(timeout: 30) else { throw HostError("VM “\(name)” won't stop") }
    }

    private func waitUntilStopped(timeout: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if status() == "stopped" { return true }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    var exists: Bool {
        let list = (try? Shell.capture([utmctl, "list"], check: false)) ?? ""
        // Rows are "<UUID> <status> <name>"; names may contain spaces.
        return list.split(separator: "\n").contains { row in
            row.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).dropFirst(2).first
                .map { String($0).trimmingCharacters(in: .whitespaces) == name } ?? false
        }
    }

    /// The VM fresh takes run on: a clone of this one, made anew for each take.
    var cloneName: String { "\(name) Take" }

    /// Replaces the clone with a new copy of this VM, stopped first so its disk is
    /// consistent. UTM keeps the MAC address, so the clone gets this VM's IP address
    /// and SSH host key; only one of the two can run at a time.
    func makeClone() throws -> VirtualMachine {
        var clone = self
        clone.name = cloneName
        try clone.delete()
        try shutDown()
        print("Cloning “\(name)” as “\(clone.name)”…")
        try Shell.run([utmctl, "clone", name, "--name", clone.name])
        return clone
    }

    func delete() throws {
        guard exists else { return }
        try shutDown()
        try Shell.run([utmctl, "delete", name])
    }

    /// Starts the VM if needed and waits until SSH answers and, with `desktop`, until
    /// someone is logged in to the guest's desktop, where the agent runs; returns its address.
    @discardableResult
    func ensureReady(timeout: Double = 180, desktop: Bool = true) throws -> String {
        let host = try waitForSSH(timeout: timeout)
        if desktop { try waitForDesktop(host: host) }
        return host
    }

    private func waitForSSH(timeout: Double) throws -> String {
        if !["started", "running"].contains(status()) {
            // A VM and its take clone share a MAC address, so they'd answer at the same IP.
            var twin = self
            twin.name = name.hasSuffix(" Take") ? String(name.dropLast(" Take".count)) : cloneName
            if twin.exists, ["started", "running"].contains(twin.status()) {
                throw HostError("“\(twin.name)” is running and has the same address; stop it before starting “\(name)”")
            }
            print("Starting VM “\(name)”…")
            try start()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let host = address(), (try? Shell.capture(sshCommand(host: host, "true"))) != nil {
                return host
            }
            Thread.sleep(forTimeInterval: 2)
        }
        throw HostError(
            "VM “\(name)” isn't reachable over SSH — run `scripts/showreel vm setup` (or check Remote Login in the VM)"
        )
    }

    /// A guest without automatic login boots to the login window, with no session to
    /// launch the agent in.
    private func waitForDesktop(host: String, timeout: Double = 600) throws {
        let check = sshCommand(host: host, #"pgrep -qx -U "$(id -u)" Dock"#)
        if (try? Shell.capture(check)) != nil { return }
        print("▶ log in to “\(name)” in its UTM window (automatic login in the VM skips this)")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 2)
            if (try? Shell.capture(check)) != nil {
                Thread.sleep(forTimeInterval: 5) // the session's login items settle
                return
            }
        }
        throw HostError("nobody logged in to “\(name)” within \(Int(timeout / 60)) minutes")
    }

    /// The guest's address: fixed, or its newest DHCP lease from UTM's shared
    /// network, found by MAC address.
    func address() -> String? {
        if let fixedHost { return fixedHost }
        guard let mac,
              let leases = try? String(contentsOfFile: "/var/db/dhcpd_leases", encoding: .utf8)
        else { return nil }
        return Self.leaseAddress(for: mac, in: leases)
    }

    /// bootpd writes MACs without leading zeros (`1,6:e9:…`).
    static func leaseAddress(for mac: String, in leases: String) -> String? {
        func normalized(_ value: String) -> String {
            value.lowercased().split(separator: ":").map { part in
                let trimmed = part.drop { $0 == "0" }
                return trimmed.isEmpty ? "0" : String(trimmed)
            }.joined(separator: ":")
        }
        let wanted = normalized(mac)
        var best: (address: String, expiry: UInt64)?
        for block in leases.components(separatedBy: "}") {
            let fields = parseEnv(block.replacingOccurrences(of: "\t", with: ""))
            guard let address = fields["ip_address"], let hardware = fields["hw_address"],
                  normalized(String(hardware.split(separator: ",").last ?? "")) == wanted
            else { continue }
            let expiry = UInt64(fields["lease"]?.replacingOccurrences(of: "0x", with: "") ?? "", radix: 16) ?? 0
            if best == nil || expiry > best!.expiry { best = (address, expiry) }
        }
        return best?.address
    }

    // MARK: - SSH

    func sshOptions(tty: Bool = false) -> [String] {
        let options = [
            "-i", Self.keyPath, "-o", "IdentitiesOnly=yes", "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=accept-new", "-o", "LogLevel=ERROR", "-o", "ServerAliveInterval=15",
            "-o", "UserKnownHostsFile=\(stateDirectory.appendingPathComponent("known_hosts").path)",
        ]
        return options + (tty ? ["-t"] : ["-o", "BatchMode=yes"])
    }

    func sshCommand(host: String, tty: Bool = false, _ command: String) -> [String] {
        ["/usr/bin/ssh"] + sshOptions(tty: tty) + ["\(user)@\(host)", command]
    }

    /// Runs a shell script in the guest, streaming its output here.
    func runScript(host: String, _ script: String, arguments: [String] = []) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        let quoted = arguments.map(shellQuote).joined(separator: " ")
        process.arguments = sshOptions() + ["\(user)@\(host)", "/bin/zsh -s -- \(quoted)"]
        let input = Pipe()
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data(script.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw Shell.Failure(command: ["ssh", "…"], status: process.terminationStatus, output: "")
        }
    }

    /// Relative `sources` are relative to `directory`.
    func rsync(
        host: String,
        _ sources: [String],
        to destination: String,
        extra: [String] = [],
        from directory: URL? = nil
    ) throws {
        let ssh = (["/usr/bin/ssh"] + sshOptions()).map(shellQuote).joined(separator: " ")
        let command = ["/usr/bin/rsync", "-a", "-e", ssh] + extra + sources + ["\(user)@\(host):\(destination)"]
        try Shell.run(command, in: directory)
    }

    func fetch(host: String, _ source: String, to destination: String) throws {
        let ssh = (["/usr/bin/ssh"] + sshOptions()).map(shellQuote).joined(separator: " ")
        try Shell.run(["/usr/bin/rsync", "-a", "-e", ssh, "\(user)@\(host):\(source)", destination])
    }
}

func shellQuote(_ text: String) -> String {
    if text.allSatisfy({ $0.isLetter || $0.isNumber || "-_./=:@,+%".contains($0) }), !text.isEmpty {
        return text
    }
    return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

struct HostError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
