import Foundation
import CoreGraphics

enum HeavyCursorConstants {
    static let minimumGain: CGFloat = 0.10
    /// Do not install a global event tap for imperceptible changes. Keeping
    /// the tap off until the cursor is meaningfully heavy avoids touching
    /// pointer events during first-run Accessibility setup.
    static let pointerTapActivationWeight: CGFloat = 0.05
    /// At this gain the warp would be effectively identical to the incoming
    /// cursor position. Skipping it avoids unnecessary cursor re-association.
    static let pointerWarpGainThreshold: CGFloat = 0.995
}

enum ReminderSchedule {
    static let progressInterval: TimeInterval = 15 * 60

    /// Returns the latest completed 15-minute milestone. The work deadline is
    /// intentionally excluded because it is represented by the break pill.
    static func progressMark(elapsed: TimeInterval, workInterval: TimeInterval) -> Int {
        guard elapsed > 0, elapsed < workInterval else { return 0 }
        return Int(elapsed / progressInterval)
    }
}

enum WeightCurve {
    /// The first half of a session stays visually quiet. The second half eases
    /// continuously from weightless to fully heavy.
    static func weight(elapsed: TimeInterval, interval: TimeInterval) -> CGFloat {
        guard interval > 0 else { return 0 }
        let progress = max(0, min(1, elapsed / interval))
        let x = CGFloat(max(0, (progress - 0.5) / 0.5))
        return x * x * (3 - 2 * x) // smoothstep
    }

    static func pointerGain(for weight: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, weight))
        // Squaring keeps the initial physical change nearly imperceptible.
        return 1 - (1 - HeavyCursorConstants.minimumGain) * clamped * clamped
    }
}

final class SessionClock {
    private(set) var elapsed: TimeInterval = 0
    private(set) var isAway = false
    private var lastTick: TimeInterval?
    private var dueSince: TimeInterval?

    var interval: TimeInterval
    var breakDuration: TimeInterval

    init(interval: TimeInterval, breakDuration: TimeInterval) {
        self.interval = interval
        self.breakDuration = breakDuration
    }

    @discardableResult
    func tick(now: TimeInterval, idleTime: TimeInterval) -> Bool {
        defer { lastTick = now }
        // Before the work limit, a long idle period means the user already
        // stepped away and the current work session should reset.
        if dueSince == nil && idleTime >= breakDuration {
            let newlyRecovered = !isAway && elapsed > 0
            elapsed = 0
            isAway = true
            return newlyRecovered
        }

        // Once the limit is reached, the break clock starts at the deadline,
        // not at the last input before it. This prevents idle time accumulated
        // while reading just before the deadline from shortening the break.
        if let dueSince {
            let lastInputAt = now - max(0, idleTime)
            let breakStartedAt = max(dueSince, lastInputAt)
            if now - breakStartedAt >= breakDuration {
                let newlyRecovered = !isAway && elapsed > 0
                elapsed = 0
                isAway = true
                self.dueSince = nil
                return newlyRecovered
            }
        }

        if isAway {
            isAway = false
            elapsed = 0
            dueSince = nil
            return false
        }

        guard let previous = lastTick else { return false }
        let previousElapsed = elapsed
        elapsed += max(0, now - previous)
        if dueSince == nil && previousElapsed < interval && elapsed >= interval {
            let timeToDeadline = max(0, interval - previousElapsed)
            dueSince = previous + timeToDeadline
        }
        return false
    }

    func reset() {
        elapsed = 0
        isAway = false
        dueSince = nil
        lastTick = ProcessInfo.processInfo.systemUptime
    }

    /// Used by the local preview launcher to demonstrate a completed work
    /// interval without waiting in real time. It is not exposed in the app UI.
    func primeForPreview() {
        elapsed = interval
        isAway = false
        let now = ProcessInfo.processInfo.systemUptime
        dueSince = now
        lastTick = now
    }

    /// Used by the local preview launcher to demonstrate a 15-minute
    /// progress reminder without waiting in real time.
    func primeForProgressPreview() {
        elapsed = max(0, interval - ReminderSchedule.progressInterval)
        isAway = false
        dueSince = nil
        lastTick = ProcessInfo.processInfo.systemUptime
    }

    var weight: CGFloat {
        isAway ? 0 : WeightCurve.weight(elapsed: elapsed, interval: interval)
    }

    var pointerGain: CGFloat {
        WeightCurve.pointerGain(for: weight)
    }

    var remaining: TimeInterval {
        max(0, interval - elapsed)
    }

    func breakRemaining(now: TimeInterval, idleTime: TimeInterval) -> TimeInterval {
        guard let dueSince else {
            return max(0, breakDuration - idleTime)
        }
        let lastInputAt = now - max(0, idleTime)
        let breakStartedAt = max(dueSince, lastInputAt)
        return max(0, breakDuration - (now - breakStartedAt))
    }
}
