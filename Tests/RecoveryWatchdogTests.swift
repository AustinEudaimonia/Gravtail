import Foundation
import Darwin

@main
enum RecoveryWatchdogTests {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }

    static func main() throws {
        let args = CommandLine.arguments
        let executable = URL(fileURLWithPath: args[0])
        if args.count > 1, args[1] == "--no-ready" { return }
        if args.count > 1, args[1] == "--child" {
            let marker = URL(fileURLWithPath: args[3])
            let result = RecoveryWatchdog.run(parentPID: Int32(args[2])!, timeout: 0.6) {
                // Fake restoration only: never reads/writes actual mouse settings.
                let previous = (try? String(contentsOf: marker, encoding: .utf8)) ?? ""
                try? (previous + "restore\n").write(to: marker, atomically: true, encoding: .utf8)
                return args[4] == "success"
            }
            exit(result)
        }
        if args.count > 1, args[1] == "--orphan-owner" {
            let watchdog = RecoveryWatchdog()
            expect(watchdog.start(executable: executable,
                arguments: ["--child", String(getpid()), args[2], "success"]), "orphan ready")
            _exit(0) // Simulate abrupt app death, bypassing cleanup.
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let marker = folder.appendingPathComponent("restored")
        let watchdog = RecoveryWatchdog()
        func start(_ outcome: String = "success") {
            expect(watchdog.start(executable: executable,
                arguments: ["--child", String(getpid()), marker.path, outcome]), "ready handshake")
        }
        func waitForExit() {
            let deadline = ProcessInfo.processInfo.systemUptime + 4
            while watchdog.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(20_000) }
            expect(!watchdog.isRunning, "child must exit within a bounded time")
        }

        var lease = HeartbeatLease(timeout: 2.5, lastBeat: 10)
        expect(lease.renew(now: 11), "normal main-loop heartbeat")
        expect(!lease.renew(now: 13.5), "late main-loop heartbeat rejected")
        expect(!lease.renew(now: 13.6), "expired lease cannot silently restart")

        start()
        for _ in 0..<12 { usleep(100_000); expect(watchdog.pulse(), "healthy heartbeat") }
        expect(watchdog.stop(), "normal stop acknowledged")
        expect(!FileManager.default.fileExists(atPath: marker.path), "normal stop must not restore stale values")

        start()
        waitForExit() // Parent remains alive but main-loop beats have stopped.
        let restoredText = try String(contentsOf: marker, encoding: .utf8)
        expect(restoredText == "restore\n", "hung living app recovered once")
        expect(!watchdog.pulse(), "dead watchdog rejects resumed weighting")
        expect(watchdog.stop(), "expired child can be reaped")
        try FileManager.default.removeItem(at: marker)

        start("failure")
        waitForExit()
        let retryText = try String(contentsOf: marker, encoding: .utf8)
        expect(retryText.split(separator: "\n").count == 5, "failed restoration retries are bounded")
        expect(watchdog.stop(), "failed child can be reaped")
        try FileManager.default.removeItem(at: marker)

        expect(!watchdog.start(executable: executable, arguments: ["--no-ready"]), "missing readiness prevents hardware write")
        expect(watchdog.stop(), "failed startup cleanup")

        let owner = Process()
        owner.executableURL = executable
        owner.arguments = ["--orphan-owner", marker.path]
        try owner.run()
        owner.waitUntilExit()
        expect(owner.terminationStatus == 0, "orphan owner starts successfully")
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !FileManager.default.fileExists(atPath: marker.path), ProcessInfo.processInfo.systemUptime < deadline { usleep(20_000) }
        expect(FileManager.default.fileExists(atPath: marker.path), "parent death triggers recovery")
        print("RecoveryWatchdogTests passed (fake restore; no live HID writes)")
    }
}
