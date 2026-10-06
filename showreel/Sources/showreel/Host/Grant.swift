import Foundation

/// `vm grant`: gives ShowreelAgent and Vibeshed their permissions in the VM
/// without any dialogs, so takes never stop for one. Run by you, with the VM
/// user's password from the host Keychain (or `SHOWREEL_VM_PASSWORD`):
///
/// - postpones macOS's "bypass the private window picker" screen-recording
///   confirmation for ShowreelAgent and Vibeshed, which captures the screen
///   too (a per-user plist; no SIP change needed);
/// - writes Accessibility, Screen Recording, Input Monitoring, Automation and
///   Calendar grants into the VM's privacy (TCC) databases with sudo — macOS
///   only lets that happen with System Integrity Protection off in the VM, and
///   the per-user one (Automation, Calendar) also needs "Allow full disk
///   access for remote users" in the VM's Remote Login settings;
/// - clears the quarantine flag Homebrew puts on the apps it installs, so
///   they open without the "downloaded from the Internet" check;
/// - keeps the VM from sleeping.
///
/// `--dry-run` shows what it would change and needs no password.
extension VMCommands {
    static let keychainService = "vibeshed-showreel-vm"

    func grant(dryRun: Bool) throws {
        let host = try vm.ensureReady()
        try takes.deployAgent(host: host)
        var password = ""
        if !dryRun {
            guard let saved = vmPassword() else {
                throw HostError("""
                no password for \(vm.user) in the VM. Save it in your Keychain (it prompts for it):
                    security add-generic-password -s \(Self.keychainService) -a \(vm.user) -w
                or set SHOWREEL_VM_PASSWORD for this run.
                """)
            }
            password = saved
        }
        try vm.runScript(host: host, Self.grantScript(password: password, dryRun: dryRun))
    }

    private func vmPassword() -> String? {
        if let password = ProcessInfo.processInfo.environment["SHOWREEL_VM_PASSWORD"], !password.isEmpty {
            return password
        }
        let command = ["/usr/bin/security", "find-generic-password", "-s", Self.keychainService, "-a", vm.user, "-w"]
        guard let output = try? Shell.capture(command) else { return nil }
        let password = output.trimmingCharacters(in: .newlines)
        return password.isEmpty ? nil : password
    }

    /// The password reaches the VM inside this script, over SSH's stdin; it
    /// is never part of a command line or printed.
    static func grantScript(password: String, dryRun: Bool) -> String {
        """
        set -u
        dry=\(dryRun ? 1 : 0)
        pw=$(cat <<'SHOWREEL_PASSWORD_END'
        \(password)
        SHOWREEL_PASSWORD_END
        )
        \(grantScriptBody)
        """
    }

    private static let grantScriptBody = #"""
    agent="$HOME/Applications/ShowreelAgent.app"
    vibeshed=/Applications/Vibeshed.app
    systemdb="/Library/Application Support/com.apple.TCC/TCC.db"
    userdb="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    approvals="$HOME/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist"

    echo "→ Screen recording confirmation for ShowreelAgent and Vibeshed: postponed to 2100"
    if (( dry )); then
        echo "  (dry run) would update $approvals"
    else
        /usr/bin/python3 - "$approvals" "file://$agent/" "file://$vibeshed/" <<'PY' || exit 1
    import datetime, os, plistlib, sys
    path, keys = sys.argv[1], sys.argv[2:]
    data = {}
    if os.path.exists(path):
        with open(path, "rb") as f:
            data = plistlib.load(f)
    for key in keys:
        entry = data.setdefault(key, {})
        entry["kScreenCaptureApprovalLastAlerted"] = datetime.datetime.utcnow()
        entry["kScreenCapturePrivacyHintDate"] = datetime.datetime(2100, 1, 1)
        entry.setdefault("kScreenCapturePrivacyHintPolicy", 2592000)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        plistlib.dump(data, f)
    PY
        killall replayd 2>/dev/null
    fi

    if (( ! dry )); then
        printf '%s\n' "$pw" | sudo -S -p '' -v 2>/dev/null || { echo "✗ sudo rejected the password"; exit 1; }
    fi
    run() { if (( dry )); then echo "  (dry run) sudo $*"; else sudo "$@"; fi }

    echo "→ Gatekeeper: apps Homebrew installed open without the first-launch check"
    for app in /Applications/*.app "$HOME"/Applications/*.app; do
        flag=$(xattr -p com.apple.quarantine "$app" 2>/dev/null) || continue
        [[ $flag == *"Homebrew"* ]] || continue
        if (( dry )); then
            echo "  (dry run) would clear the quarantine flag on ${app:t}"
        else
            xattr -dr com.apple.quarantine "$app" && echo "  ✓ ${app:t}"
        fi
    done

    echo "→ Keeping the VM awake"
    run pmset -a sleep 0 displaysleep 0 disksleep 0
    if (( dry )); then
        echo "  (dry run) defaults -currentHost write com.apple.screensaver idleTime -int 0"
    else
        defaults -currentHost write com.apple.screensaver idleTime -int 0
    fi

    if csrutil status | grep -q enabled; then
        echo "✗ System Integrity Protection is on in the VM, so its privacy database can't be written."
        echo "  Turn it off once (this VM only):"
        echo "    utmctl stop macOS && utmctl start --recovery macOS"
        echo "    in Recovery: Utilities › Terminal → csrutil disable → restart"
        echo "  then run scripts/showreel vm grant again."
        (( dry )) || exit 3
    fi

    # The code requirement macOS checks a granted app against, as hex.
    requirement() {
        codesign -d -r- "$1" 2>&1 | sed -n 's/^designated => //p' | csreq -r- -b /tmp/showreel-csreq.bin \
            && xxd -p /tmp/showreel-csreq.bin | tr -d '\n'
    }
    # grant <db> <service> <bundle id> <app path> [<Apple Events target bundle id>]
    grant() {
        local req target=${5:-UNUSED}
        req=$(requirement "$4") || { echo "  ✗ can't read the signature of $4"; return 1; }
        if (( dry )); then echo "  (dry run) would grant $2 to $3${5:+ for $5}"; return; fi
        run sqlite3 "$1" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason,
            auth_version, csreq, flags, indirect_object_identifier_type, indirect_object_identifier)
            VALUES ('$2', '$3', 0, 2, 3, 1, X'$req', 0, 0, '$target');" 2>/dev/null || return 1
        echo "  ✓ $2 → $3${5:+ → $5}"
    }

    echo "→ Privacy grants"
    for service in kTCCServiceAccessibility kTCCServiceScreenCapture kTCCServicePostEvent; do
        grant "$systemdb" $service com.ivandmitriev.Vibeshed.ShowreelAgent "$agent" \
            || { echo "  ✗ couldn't write $service to $systemdb"; exit 1; }
    done
    # Automation and Calendar live in the per-user database, which SSH can only
    # write with Sharing › Remote Login › ⓘ › "Allow full disk access for remote
    # users" on (root and SIP off aren't enough).
    user_grants() {
        grant "$userdb" kTCCServiceAppleEvents com.ivandmitriev.Vibeshed.ShowreelAgent "$agent" com.apple.systemevents \
            || return 1
        grant "$userdb" kTCCServiceCalendar com.ivandmitriev.Vibeshed.ShowreelAgent "$agent" || return 1
        [ -d "$vibeshed" ] || return 0
        grant "$userdb" kTCCServiceCalendar com.ivandmitriev.Vibeshed "$vibeshed" || return 1
        # What Vibeshed's modules script: appearance, browser tabs, terminals, Spotify.
        for target in com.apple.systemevents com.google.Chrome com.apple.Safari com.mitchellh.ghostty \
            com.spotify.client com.apple.Terminal com.apple.finder; do
            grant "$userdb" kTCCServiceAppleEvents com.ivandmitriev.Vibeshed "$vibeshed" $target || return 1
        done
    }
    user_grants || echo "  ⚠️  Automation and Calendar grants need Sharing › Remote Login › ⓘ ›" \
        "Allow full disk access for remote users in the VM (or a one-time Allow on each prompt)"
    if [ -d "$vibeshed" ]; then
        for service in kTCCServiceAccessibility kTCCServiceListenEvent kTCCServicePostEvent kTCCServiceScreenCapture; do
            grant "$systemdb" $service com.ivandmitriev.Vibeshed "$vibeshed" \
                || { echo "  ✗ couldn't write $service to $systemdb"; exit 1; }
        done
    else
        echo "  (Vibeshed isn't installed yet: run vm install-vibeshed, then vm grant again)"
    fi
    run killall tccd
    echo "✓ Done. Check with: scripts/showreel vm doctor"
    """#
}
