import Darwin

// ShowreelAgent.app's executable: starts ~/Showreel/bin/showreel as a child
// and waits for it. macOS attributes a child's Accessibility, Screen
// Recording and Automation use to this app, and the VM's privacy settings
// drop a grant when the granted binary changes — so this stays tiny and
// stable while the real agent is rebuilt freely.
//
// Opened by hand (no arguments), it runs the permission check.

let home = getenv("HOME").map { String(cString: $0) } ?? "/tmp"
let agent = home + "/Showreel/bin/showreel"
var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty {
    arguments = ["agent", "doctor"]
}

var argv: [UnsafeMutablePointer<CChar>?] = ([agent] + arguments).map { strdup($0) } + [nil]
var pid: pid_t = 0
let spawned = posix_spawn(&pid, agent, nil, nil, &argv, environ)
guard spawned == 0 else {
    fputs("ShowreelAgent: can't start \(agent): \(String(cString: strerror(spawned)))\n", stderr)
    exit(127)
}

var status: Int32 = 0
while waitpid(pid, &status, 0) == -1, errno == EINTR {}
// WIFEXITED / WEXITSTATUS, which Swift doesn't import.
let signal = status & 0x7F
exit(signal == 0 ? (status >> 8) & 0xFF : 128 + signal)
