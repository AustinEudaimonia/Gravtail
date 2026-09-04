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

enum MaintenancePolicy {
    /// Diagnostic events are intentionally small, but a menu-bar app may run
    /// for years. Keep one bounded current log and one previous generation.
    static let maximumLogBytes = 512 * 1024
    static let installerBackupsToKeep = 1

    static func shouldRotateLog(currentBytes: Int, incomingBytes: Int) -> Bool {
        guard currentBytes >= 0, incomingBytes >= 0 else { return false }
        return currentBytes + incomingBytes > maximumLogBytes
    }
}

enum CursorWeightingMode: Equatable {
    case none
    case software
    case hardware
}

enum CursorWeightingPolicy {
    /// Exactly one pointer-weighting implementation may own cursor movement
    /// at a time. Applying the event-tap gain and HID acceleration together
    /// compounds the two curves and can reduce the effective movement to
    /// zero. The break uses only HID so AppKit retains native cursor shapes;
    /// active work uses only the more precise event-tap transform.
    static func mode(
        isUIPreview: Bool,
        isOnBreak: Bool,
        isAccessibilityTrusted: Bool,
        weight: CGFloat
    ) -> CursorWeightingMode {
        guard !isUIPreview,
              weight > HeavyCursorConstants.pointerTapActivationWeight else {
            return .none
        }
        if isOnBreak {
            return .hardware
        }
        return isAccessibilityTrusted ? .software : .none
    }
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

    /// The HID path is used only during the break, never together with the
    /// software event tap. Reusing the same bounded curve guarantees the
    /// hardware acceleration value cannot be reduced to zero.
    static func hardwareScale(for weight: CGFloat) -> CGFloat {
        pointerGain(for: weight)
    }

    static func hardwareAccelerationTarget(original: Double, weight: CGFloat) -> Double? {
        guard original.isFinite, original > 0 else { return nil }
        return original * Double(hardwareScale(for: weight))
    }

    /// The comet is the app's always-visible heartbeat once a real work
    /// session starts. Keep it subtle during the physically weightless half,
    /// then let the physical weight curve take over continuously.
    static func visualWeight(elapsed: TimeInterval, interval: TimeInterval) -> CGFloat {
        guard interval > 0 else { return 0 }
        let progress = CGFloat(max(0, min(1, elapsed / interval)))
        let ambientComet = 0.16 + 0.08 * progress
        return max(ambientComet, weight(elapsed: elapsed, interval: interval))
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

    /// Starts a fresh work session at a known physical-input timestamp. A
    /// nil timestamp means the clock is waiting for the first real keyboard or
    /// pointing-device event and must not accumulate time yet.
    func reset(startingAt now: TimeInterval? = nil) {
        elapsed = 0
        isAway = false
        dueSince = nil
        lastTick = now
    }

    @discardableResult
    func tick(now: TimeInterval, idleTime: TimeInterval) -> Bool {
        // A newly launched or reset session is intentionally idle until the
        // app observes a real physical input. This prevents time spent on the
        // login screen, desktop, or an already-open notification from being
        // counted as work.
        guard let previous = lastTick else { return false }
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

        let previousElapsed = elapsed
        elapsed += max(0, now - previous)
        if dueSince == nil && previousElapsed < interval && elapsed >= interval {
            let timeToDeadline = max(0, interval - previousElapsed)
            dueSince = previous + timeToDeadline
        }
        return false
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

    /// True while the configured work interval has ended and the user is
    /// completing the inactivity-based break. The reminder is visible, but
    /// the session has not yet recovered into the next work cycle.
    var isOnBreak: Bool {
        !isAway && dueSince != nil && elapsed >= interval
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
