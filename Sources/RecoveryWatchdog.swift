import Foundation
import Darwin

/// Main-loop heartbeats only: a background timer could keep a hung app looking
/// healthy. Once a lease expires, resuming the loop must not re-enable weighting.
struct HeartbeatLease {
    let timeout: TimeInterval
    private(set) var lastBeat: TimeInterval
    private(set) var expired = false

    mutating func renew(now: TimeInterval) -> Bool {
        guard !expired, now.isFinite, now >= lastBeat,
              now - lastBeat < timeout else {
            expired = true
            return false
        }
        lastBeat = now
        return true
    }
}

final class RecoveryWatchdog {
    static let timeout: TimeInterval = 5
    private var process: Process?
    private var socket: Int32 = -1
    private var lease: HeartbeatLease?
    var isRunning: Bool { process?.isRunning == true }

    func start(executable: URL, arguments: [String]) -> Bool {
        guard process == nil else { return false }
        var sockets: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else { return false }
        var noPipe: Int32 = 1
        guard setsockopt(sockets[0], SOL_SOCKET, SO_NOSIGPIPE, &noPipe,
                         socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            close(sockets[0]); close(sockets[1]); return false
        }
        _ = fcntl(sockets[0], F_SETFD, FD_CLOEXEC)
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        let input = FileHandle(fileDescriptor: sockets[1], closeOnDealloc: true)
        child.standardInput = input
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        do {
            try child.run()
        } catch {
            close(sockets[0])
            try? input.close()
            return false
        }
        try? input.close()
        process = child
        socket = sockets[0]
        var descriptor = pollfd(fd: socket, events: Int16(POLLIN), revents: 0)
        var ready: UInt8 = 0
        guard poll(&descriptor, 1, 1500) > 0,
              recv(socket, &ready, 1, MSG_DONTWAIT) == 1, ready == 82 else {
            _ = stop()
            return false
        }
        // Stop the parent earlier than the child so a resumed main loop never
        // races a watchdog already restoring the original settings.
        lease = HeartbeatLease(timeout: Self.timeout / 2,
                               lastBeat: ProcessInfo.processInfo.systemUptime)
        return pulse()
    }

    func pulse() -> Bool {
        guard isRunning, socket >= 0,
              lease?.renew(now: ProcessInfo.processInfo.systemUptime) == true else { return false }
        var beat: UInt8 = 72
        return send(socket, &beat, 1, MSG_DONTWAIT) == 1
    }

    /// Call only after hardware restoration. Wait for the outgoing child so it
    /// cannot restore stale values over a subsequent session's writes.
    @discardableResult
    func stop() -> Bool {
        guard let process else { return true }
        if socket >= 0 {
            var stop: UInt8 = 83
            _ = send(socket, &stop, 1, MSG_DONTWAIT)
            close(socket)
            socket = -1
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            usleep(10_000)
        }
        guard !process.isRunning else { return false }
        self.process = nil
        lease = nil
        return true
    }

    static func run(parentPID: pid_t, timeout: TimeInterval = timeout,
                    restore: () -> Bool) -> Int32 {
        var noPipe: Int32 = 1
        _ = setsockopt(STDIN_FILENO, SOL_SOCKET, SO_NOSIGPIPE, &noPipe,
                       socklen_t(MemoryLayout<Int32>.size))
        var ready: UInt8 = 82
        guard send(STDIN_FILENO, &ready, 1, MSG_DONTWAIT) == 1 else { return 71 }
        var lastBeat = ProcessInfo.processInfo.systemUptime
        while true {
            let now = ProcessInfo.processInfo.systemUptime
            // Check expiry BEFORE accepting buffered beats from a resumed app.
            if now - lastBeat >= timeout { break }
            errno = 0
            if kill(parentPID, 0) != 0 && errno != EPERM { break }
            var bytes = [UInt8](repeating: 0, count: 64)
            let count = recv(STDIN_FILENO, &bytes, bytes.count, MSG_DONTWAIT)
            if count == 0 { break }
            if count > 0 {
                let messages = bytes.prefix(count)
                if messages.contains(83) { return 0 }
                if messages.contains(72) { lastBeat = now }
            } else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                break
            }
            usleep(50_000)
        }
        // Retry transient restore failures without touching the user's backup
        // unless restoration succeeds. The caller logs the final outcome.
        for _ in 0..<5 {
            if restore() { return 70 }
            usleep(100_000)
        }
        return 71
    }
}
