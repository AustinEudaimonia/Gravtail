import Foundation
import CoreGraphics

enum HeavyCursorConstants {
    static let minimumGain: CGFloat = 0.10
    /// Never write an acceleration value so small that ordinary one-pixel
    /// device movement feels indistinguishable from a frozen cursor.
    static let minimumHardwareAcceleration: Double = 0.10
    /// The break is deliberately heavier than the work phase, but still stays
    /// above zero so WindowServer keeps receiving native pointer movement.
    static let breakMinimumHardwareAcceleration: Double = 0.05
    static let physicalWeightActivationThreshold: CGFloat = 0.05
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

/// Throttle synchronous HID restoration after a device or WindowServer error.
/// A failed write must not turn the 250 ms logic loop into a tight retry loop
/// on the main thread, while a successful restore should be immediately
/// eligible again for the next safety transition.
struct RestoreBackoff {
    private static let initialDelay: TimeInterval = 1
    private static let maximumDelay: TimeInterval = 30
    private(set) var failureCount = 0
    private(set) var nextAttemptAt: TimeInterval = 0

    func shouldAttempt(now: TimeInterval) -> Bool {
        now.isFinite && now >= nextAttemptAt
    }

    mutating func recordFailure(now: TimeInterval) {
        guard now.isFinite else { return }
        failureCount = min(6, failureCount + 1)
        var delay = Self.initialDelay
        if failureCount > 1 {
            for _ in 1..<failureCount {
                delay = min(Self.maximumDelay, delay * 2)
            }
        }
        nextAttemptAt = now + delay
    }

    mutating func reset() {
        failureCount = 0
        nextAttemptAt = 0
    }
}

enum MenuBarFallbackPolicy {
    /// A fallback launcher is allowed only when the menu bar itself is
    /// present and macOS did not give the native status item a real window.
    /// A hidden menu bar must remain hidden instead of being bypassed by an
    /// always-on-top panel.
    static let minimumMenuBarHeight: CGFloat = 18

    static func shouldUseFallback(
        menuBarHeight: CGFloat,
        nativeWindowHeight: CGFloat?,
        nativeWindowOnScreen: Bool = true,
        nativeButtonClipped: Bool = false
    ) -> Bool {
        guard menuBarHeight >= minimumMenuBarHeight else { return false }
        guard let nativeWindowHeight else { return true }
        return nativeWindowHeight < minimumMenuBarHeight || !nativeWindowOnScreen || nativeButtonClipped
    }

    static func shouldReprobeNative(hasFallback: Bool, menuBarHeight: CGFloat) -> Bool {
        hasFallback && menuBarHeight >= minimumMenuBarHeight
    }
}

enum LoginItemPromptPolicy {
    /// The app explains manual login-item setup only after the first-run
    /// Gravtail choices are complete, and records that the explanation was
    /// shown so a user who chooses “以后再说” is not nagged on every launch.
    static func shouldPrompt(hasCompletedOnboarding: Bool, hasPrompted: Bool) -> Bool {
        hasCompletedOnboarding && !hasPrompted
    }
}

enum CursorWeightingMode: Equatable {
    case none
    case hardware
}

enum CursorWeightingPolicy {
    /// Physical weighting uses only the system acceleration setting. Gravtail
    /// never intercepts, suppresses, disconnects, or warps pointer events.
    /// Unsupported devices therefore fail open to native cursor behavior.
    static func mode(
        isUIPreview: Bool,
        weight: CGFloat,
        isPhysicalWeightingEnabled: Bool
    ) -> CursorWeightingMode {
        guard isPhysicalWeightingEnabled, !isUIPreview,
              weight > HeavyCursorConstants.physicalWeightActivationThreshold else {
            return .none
        }
        return .hardware
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

enum ReminderSoundPolicy {
    static let defaultEnabled = true
    static let settingsKey = "reminderSoundsEnabled"
}

enum ReminderSoundEvent {
    case progress
    case breakStarted
    case breakEnded

    var systemSoundName: String {
        switch self {
        case .progress: return "Tink"
        case .breakStarted: return "Glass"
        case .breakEnded: return "Hero"
        }
    }
}

enum RecoveryNoticePolicy {
    static func shouldShow(pending: Bool, hardwareRestored: Bool, hardwareActive: Bool,
                           watchdogRunning: Bool) -> Bool {
        pending && hardwareRestored && !hardwareActive && !watchdogRunning
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

    /// The single HID path reuses the bounded curve so acceleration can never
    /// be reduced to zero.
    static func hardwareScale(for weight: CGFloat) -> CGFloat {
        pointerGain(for: weight)
    }

    static func hardwareAccelerationTarget(
        original: Double,
        weight: CGFloat,
        minimumAcceleration: Double = HeavyCursorConstants.minimumHardwareAcceleration
    ) -> Double? {
        guard original.isFinite, original > 0,
              minimumAcceleration.isFinite, minimumAcceleration > 0 else { return nil }
        let scaled = original * Double(hardwareScale(for: weight))
        return min(original, max(minimumAcceleration, scaled))
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
    private(set) var isPaused = false
    private var lastTick: TimeInterval?
    private var dueSince: TimeInterval?
    private var pausedBreakRemaining: TimeInterval?
    private var ignoredBreakInputAt: TimeInterval?

    // Logic ticks run every 250 ms; allow one second for the resume click's
    // HID timestamp to settle before treating a later input as real movement.
    private static let controlInputTolerance: TimeInterval = 1.0

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
        isPaused = false
        dueSince = nil
        pausedBreakRemaining = nil
        ignoredBreakInputAt = nil
        lastTick = now
    }

    @discardableResult
    func tick(now: TimeInterval, idleTime: TimeInterval) -> Bool {
        if isPaused {
            // Keep the resume anchor current while paused so the elapsed time
            // before the pause cannot leak into the next tick.
            lastTick = now
            return false
        }
        // A newly launched or reset session is intentionally idle until the
        // app observes a real physical input. This prevents time spent on the
        // login screen, desktop, or an already-open notification from being
        // counted as work.
        guard let previous = lastTick else { return false }
        defer { lastTick = now }
        // Once the limit is reached, the break clock starts at the deadline,
        // not at the last input before it. This prevents idle time accumulated
        // while reading just before the deadline from shortening the break.
        if let dueSince {
            let breakStartedAt = effectiveBreakStart(
                dueSince: dueSince,
                now: now,
                idleTime: idleTime
            )
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

    /// Pause only the active break. The countdown is frozen and the caller
    /// can restore any physical weighting before presenting a resume control.
    @discardableResult
    func pause(now: TimeInterval, idleTime: TimeInterval) -> Bool {
        guard isOnBreak, !isPaused else { return false }
        pausedBreakRemaining = breakRemaining(now: now, idleTime: idleTime)
        isPaused = true
        lastTick = now
        return true
    }

    /// Resume a paused break without charging the paused wall-clock time.
    @discardableResult
    func resume(now: TimeInterval) -> Bool {
        guard isPaused else { return false }
        if let pausedBreakRemaining {
            let elapsedBreak = max(0, breakDuration - pausedBreakRemaining)
            dueSince = now - elapsedBreak
        }
        pausedBreakRemaining = nil
        // The click that resumes the pill is a control action, not a reason
        // to restart the user's break. Ignore that one sampled HID timestamp;
        // a later real movement still resets the break as usual.
        ignoredBreakInputAt = now
        isPaused = false
        lastTick = now
        return true
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
        if isPaused, let pausedBreakRemaining {
            return pausedBreakRemaining
        }
        guard let dueSince else {
            return max(0, breakDuration - idleTime)
        }
        let breakStartedAt = effectiveBreakStart(
            dueSince: dueSince,
            now: now,
            idleTime: idleTime
        )
        return max(0, breakDuration - (now - breakStartedAt))
    }

    private func effectiveBreakStart(
        dueSince: TimeInterval,
        now: TimeInterval,
        idleTime: TimeInterval
    ) -> TimeInterval {
        let lastInputAt = now - max(0, idleTime)
        if let ignoredBreakInputAt {
            if lastInputAt <= ignoredBreakInputAt + Self.controlInputTolerance {
                return dueSince
            }
            self.ignoredBreakInputAt = nil
        }
        return max(dueSince, lastInputAt)
    }
}
