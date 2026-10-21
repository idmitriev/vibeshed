import AppKit
import ScreenCaptureKit

/// Checks (and asks for) everything a take needs inside the VM. Each prompt
/// appears in the VM, for whoever is at its screen to answer.
@MainActor
enum Doctor {
    static func run(vibeshedApp: String) async -> Int32 {
        var healthy = true
        func check(_ name: String, _ passed: Bool, _ hint: String = "") {
            Log.info("\(passed ? "✓" : "✗") \(name)\(passed || hint.isEmpty ? "" : " — \(hint)")")
            healthy = healthy && passed
        }

        let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        check(
            "Accessibility (ShowreelAgent)", AXIsProcessTrustedWithOptions(prompt),
            "allow ShowreelAgent in the VM's System Settings › Privacy & Security › Accessibility"
        )
        let screen = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        check(
            "Screen Recording (ShowreelAgent)", screen,
            "allow ShowreelAgent in the VM's System Settings › Privacy & Security › Screen & System Audio Recording"
        )
        if screen {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                check("ScreenCaptureKit", true)
            } catch {
                check("ScreenCaptureKit", false, "\(error)")
            }
        }
        check("Automation of System Events (for `appearance`)", automationAllowed(), "allow it when the VM asks")
        reportDisplay()
        reportVibeshed(at: vibeshedApp, check: check)
        return healthy ? 0 : 1
    }

    private static func automationAllowed() -> Bool {
        var error: NSDictionary?
        let script = "tell application \"System Events\" to get dark mode of appearance preferences"
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error == nil
    }

    private static func reportDisplay() {
        guard let screen = NSScreen.main else { return }
        let size = screen.frame.size
        Log.info("• display \(Int(size.width))×\(Int(size.height)) pt @\(screen.backingScaleFactor)x")
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(CGMainDisplayID(), options) as? [CGDisplayMode]) ?? []
        let names = Set(modes.map { "\($0.width)x\($0.height)\($0.pixelWidth > $0.width ? "@2x" : "")" })
        Log.info("• display modes: \(names.sorted().joined(separator: ", "))")
    }

    private static func reportVibeshed(at path: String, check: (String, Bool, String) -> Void) {
        let url = URL(fileURLWithPath: path)
        guard let bundle = Bundle(url: url) else {
            check("Vibeshed", false, "not installed at \(path) — run `scripts/showreel vm install-vibeshed`")
            return
        }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Windows.vibeshedBundleID)
            .isEmpty
        check("Vibeshed \(bundle.shortVersion ?? "?") at \(path)\(running ? ", running" : "")", true, "")
        Log.info("• Vibeshed needs Accessibility and Input Monitoring in the VM; grant them when it asks")
    }
}
