import Foundation
import CoreGraphics

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum HeavyCursorCoreTests {
    static func main() {
        let interval: TimeInterval = 60 * 60
        expect(WeightCurve.weight(elapsed: 0, interval: interval) == 0, "session starts weightless")
        expect(WeightCurve.weight(elapsed: 30 * 60, interval: interval) == 0, "first half stays weightless")
        expect(abs(WeightCurve.weight(elapsed: 45 * 60, interval: interval) - 0.5) < 0.001, "three quarters is half weight")
        expect(WeightCurve.weight(elapsed: interval, interval: interval) == 1, "deadline reaches full weight")
        expect(abs(WeightCurve.pointerGain(for: 1) - 0.10) < 0.001, "full weight caps at 10 percent gain")
        expect(WeightCurve.visualWeight(elapsed: 0, interval: interval) >= 0.16, "started session has a visible comet immediately")
        expect(WeightCurve.visualWeight(elapsed: interval, interval: interval) == 1, "deadline keeps the comet at full strength")

        let rampDuration: TimeInterval = 10 * 60
        expect(
            abs(WeightCurve.workSensitivity(
                elapsed: 0, interval: interval, rampDuration: rampDuration
            ) - 1) < 0.001,
            "work starts at native sensitivity"
        )
        expect(
            abs(WeightCurve.workSensitivity(
                elapsed: interval - rampDuration - 1,
                interval: interval,
                rampDuration: rampDuration
            ) - 1) < 0.001,
            "the first part of work stays at native sensitivity"
        )
        expect(
            abs(WeightCurve.workSensitivity(
                elapsed: interval - rampDuration,
                interval: interval,
                rampDuration: rampDuration
            ) - 1) < 0.001,
            "the final ramp starts at native sensitivity"
        )
        expect(
            abs(WeightCurve.workSensitivity(
                elapsed: interval - rampDuration / 2,
                interval: interval,
                rampDuration: rampDuration
            ) - 0.75) < 0.001,
            "the middle of the final ramp is halfway between native and fifty percent"
        )
        expect(
            abs(WeightCurve.workSensitivity(
                elapsed: interval, interval: interval, rampDuration: rampDuration
            ) - 0.50) < 0.001,
            "work ends at fifty percent sensitivity"
        )
        expect(
            abs(WeightCurve.hardwareAccelerationTarget(
                original: 2,
                sensitivity: 0.5
            )! - 1) < 0.001,
            "hardware target applies the explicit work sensitivity"
        )
        expect(
            abs(WeightCurve.hardwareAccelerationTarget(
                original: 2,
                sensitivity: HeavyCursorConstants.breakSensitivity,
                minimumAcceleration: HeavyCursorConstants.breakMinimumHardwareAcceleration
            )! - 0.2) < 0.001,
            "break target applies a hard ten-percent sensitivity"
        )
        expect(
            CursorWeightingPolicy.mode(
                isUIPreview: false,
                sensitivity: 1,
                isPhysicalWeightingEnabled: true
            ) == .none,
            "native sensitivity does not activate the HID path"
        )
        expect(
            CursorWeightingPolicy.mode(
                isUIPreview: false,
                sensitivity: 0.5,
                isPhysicalWeightingEnabled: true
            ) == .hardware,
            "the final work ramp activates the HID path"
        )

        var restoreBackoff = RestoreBackoff()
        expect(restoreBackoff.shouldAttempt(now: 100), "restore is immediately eligible")
        restoreBackoff.recordFailure(now: 100)
        expect(!restoreBackoff.shouldAttempt(now: 100.5), "first restore failure is throttled")
        expect(restoreBackoff.shouldAttempt(now: 101), "first restore retry waits one second")
        restoreBackoff.recordFailure(now: 101)
        expect(!restoreBackoff.shouldAttempt(now: 102.9), "second restore failure uses exponential backoff")
        expect(restoreBackoff.shouldAttempt(now: 103), "second restore retry waits two seconds")
        restoreBackoff.reset()
        expect(restoreBackoff.shouldAttempt(now: 103), "successful restore clears the backoff")

        expect(
            MenuBarFallbackPolicy.shouldReprobeNative(hasFallback: true, menuBarHeight: 22),
            "a visible fallback should be rechecked after display changes"
        )
        expect(
            !MenuBarFallbackPolicy.shouldReprobeNative(hasFallback: false, menuBarHeight: 22),
            "native ownership should not be probed when no fallback exists"
        )
        expect(
            !MenuBarFallbackPolicy.shouldReprobeNative(hasFallback: true, menuBarHeight: 0),
            "a hidden menu bar must not create a visible fallback"
        )

        let breakClock = SessionClock(interval: 60, breakDuration: 300)
        breakClock.reset(startingAt: 0)
        _ = breakClock.tick(now: 60, idleTime: 0)
        expect(breakClock.isOnBreak, "the test clock reaches the break state")
        expect(breakClock.pause(now: 70, idleTime: 10), "break can be paused")
        let pausedRemaining = breakClock.breakRemaining(now: 170, idleTime: 10)
        expect(abs(pausedRemaining - 290) < 0.001, "pause freezes the break countdown")
        _ = breakClock.tick(now: 170, idleTime: 10)
        expect(breakClock.isPaused, "paused break ignores timer ticks")
        expect(breakClock.resume(now: 170), "paused break can be resumed")
        expect(!breakClock.isPaused, "resume clears the paused state")
        expect(
            abs(breakClock.breakRemaining(now: 170, idleTime: 0) - 290) < 0.001,
            "the resume click does not restart the break"
        )
        let resumedRemaining = breakClock.breakRemaining(now: 180, idleTime: 20)
        expect(abs(resumedRemaining - 280) < 0.001, "resume continues from the frozen break time")
        let afterRealMovement = breakClock.breakRemaining(now: 180, idleTime: 0)
        expect(abs(afterRealMovement - 300) < 0.001, "real movement after resume restarts the break")
        breakClock.reset()
        expect(!breakClock.isPaused && !breakClock.isOnBreak, "reset clears a paused break")

        expect(abs(WeightCurve.hardwareScale(for: 1) - 0.10) < 0.001, "hardware weight never reaches zero")
        expect(
            abs((WeightCurve.hardwareAccelerationTarget(original: 0.6875, weight: 1) ?? 0) - 0.10) < 0.0001,
            "maximum hardware weight preserves a non-stalling absolute response floor"
        )
        expect(
            WeightCurve.hardwareAccelerationTarget(original: 0, weight: 1) == nil,
            "unsafe non-positive HID values fail open"
        )
        expect(
            abs((WeightCurve.hardwareAccelerationTarget(original: 0.05, weight: 1) ?? 0) - 0.05) < 0.0001,
            "the safety floor never increases an already-low native setting"
        )
        expect(
            abs((WeightCurve.hardwareAccelerationTarget(original: 2, weight: 1) ?? 0) - 0.2) < 0.0001,
            "high native acceleration still reaches the ten-percent curve"
        )
        expect(
            abs((WeightCurve.hardwareAccelerationTarget(
                original: 0.6875,
                weight: 1,
                minimumAcceleration: HeavyCursorConstants.breakMinimumHardwareAcceleration
            ) ?? 0) - 0.06875) < 0.0001,
            "the break uses the stronger five-percent safety floor"
        )
        expect(
            abs((WeightCurve.hardwareAccelerationTarget(
                original: 0.03,
                weight: 1,
                minimumAcceleration: HeavyCursorConstants.breakMinimumHardwareAcceleration
            ) ?? 0) - 0.03) < 0.0001,
            "the break floor never increases an already-lower native setting"
        )
        expect(
            WeightCurve.hardwareAccelerationTarget(original: 0.6875, weight: 1, minimumAcceleration: 0) == nil,
            "an invalid acceleration floor fails open"
        )
        expect(HeavyCursorConstants.physicalWeightActivationThreshold > 0,
               "physical weighting waits for a meaningful weight")
        expect(
            !MaintenancePolicy.shouldRotateLog(currentBytes: 100, incomingBytes: 100),
            "small diagnostic logs stay in place"
        )
        expect(
            MaintenancePolicy.shouldRotateLog(
                currentBytes: MaintenancePolicy.maximumLogBytes,
                incomingBytes: 1
            ),
            "diagnostic logs rotate at the size limit"
        )
        expect(MaintenancePolicy.installerBackupsToKeep == 1, "installer keeps one rollback copy")
        expect(
            !MenuBarFallbackPolicy.shouldUseFallback(menuBarHeight: 0, nativeWindowHeight: 0),
            "a hidden menu bar must not be bypassed by a floating launcher"
        )
        expect(
            MenuBarFallbackPolicy.shouldUseFallback(menuBarHeight: 24, nativeWindowHeight: nil),
            "a visible menu bar with no native status window needs the fallback"
        )
        expect(
            MenuBarFallbackPolicy.shouldUseFallback(menuBarHeight: 24, nativeWindowHeight: 0),
            "a visible menu bar with a zero-height native window needs the fallback"
        )
        expect(
            !MenuBarFallbackPolicy.shouldUseFallback(menuBarHeight: 24, nativeWindowHeight: 22),
            "a real native status window must suppress the fallback"
        )
        expect(
            MenuBarFallbackPolicy.shouldUseFallback(
                menuBarHeight: 24, nativeWindowHeight: 22, nativeWindowOnScreen: false
            ),
            "a detached native window must use the fallback even when its height looks valid"
        )
        expect(
            MenuBarFallbackPolicy.shouldUseFallback(
                menuBarHeight: 24, nativeWindowHeight: 22,
                nativeWindowOnScreen: true, nativeButtonClipped: true
            ),
            "a clipped native button must use the fallback"
        )

        for restored in [false, true] {
            for hardwareActive in [false, true] {
                for watchdogRunning in [false, true] {
                    let ready = RecoveryNoticePolicy.shouldShow(pending: true,
                        hardwareRestored: restored, hardwareActive: hardwareActive,
                        watchdogRunning: watchdogRunning)
                    expect(ready == (restored && !hardwareActive && !watchdogRunning),
                        "recovery notice waits for confirmed restoration and the watchdog to stop")
                }
            }
        }
        expect(!RecoveryNoticePolicy.shouldShow(pending: false, hardwareRestored: true,
            hardwareActive: false, watchdogRunning: false),
            "completed recovery notice does not repeat")

        expect(CursorWeightingPolicy.mode(isUIPreview: false, weight: 1,
            isPhysicalWeightingEnabled: false) == .none,
            "opt-out disables all physical weighting")

        expect(
            CursorWeightingPolicy.mode(
                isUIPreview: false,
                weight: 0.5, isPhysicalWeightingEnabled: true
            ) == .hardware,
            "active work never intercepts or warps pointer events"
        )
        expect(
            CursorWeightingPolicy.mode(
                isUIPreview: false,
                weight: 1, isPhysicalWeightingEnabled: true
            ) == .hardware,
            "break uses only native-cursor hardware weighting"
        )
        expect(
            CursorWeightingPolicy.mode(
                isUIPreview: true,
                weight: 1, isPhysicalWeightingEnabled: true
            ) == .none,
            "UI preview never changes pointer behavior"
        )

        expect(
            LoginItemPromptPolicy.shouldPrompt(
                hasCompletedOnboarding: true,
                hasPrompted: false
            ),
            "completed onboarding prompts once for manual login-item setup"
        )
        expect(
            !LoginItemPromptPolicy.shouldPrompt(
                hasCompletedOnboarding: false,
                hasPrompted: false
            ),
            "login-item prompt waits until the initial setup is complete"
        )
        expect(
            !LoginItemPromptPolicy.shouldPrompt(
                hasCompletedOnboarding: true,
                hasPrompted: true
            ),
            "login-item prompt is not repeated after the user has seen it"
        )

        expect(ReminderSoundPolicy.defaultEnabled, "reminder sounds are enabled by default")
        expect(ReminderSoundEvent.progress.systemSoundName == "Tink",
               "progress reminders use a subtle built-in sound")
        expect(ReminderSoundEvent.breakStarted.systemSoundName == "Glass",
               "break start uses a distinct built-in sound")
        expect(ReminderSoundEvent.breakEnded.systemSoundName == "Hero",
               "break completion uses a distinct built-in sound")

        let fortyFiveMinutes: TimeInterval = 45 * 60
        expect(ReminderSchedule.progressMark(elapsed: 14 * 60 + 59, workInterval: fortyFiveMinutes) == 0, "no reminder before fifteen minutes")
        expect(ReminderSchedule.progressMark(elapsed: 15 * 60, workInterval: fortyFiveMinutes) == 1, "first reminder occurs at fifteen minutes")
        expect(ReminderSchedule.progressMark(elapsed: 30 * 60, workInterval: fortyFiveMinutes) == 2, "second reminder occurs at thirty minutes")
        expect(ReminderSchedule.progressMark(elapsed: fortyFiveMinutes, workInterval: fortyFiveMinutes) == 0, "deadline is reserved for the break reminder")
        expect(ReminderSchedule.progressMark(elapsed: 75 * 60, workInterval: 90 * 60) == 5, "ninety-minute sessions include the seventy-five-minute reminder")

        let clock = SessionClock(interval: 10, breakDuration: 5 * 60)
        _ = clock.tick(now: 0, idleTime: 0)
        expect(clock.elapsed == 0, "a session waits for the first physical input")
        clock.reset(startingAt: 0)
        _ = clock.tick(now: 6, idleTime: 0)
        expect(abs(clock.elapsed - 6) < 0.001, "active time accumulates")
        expect(clock.weight > 0, "weight begins after half the interval")
        _ = clock.tick(now: 7, idleTime: clock.breakDuration - 1)
        expect(clock.elapsed == 7, "a short idle does not reset the session")
        expect(clock.breakRemaining(now: 7, idleTime: 120) == 180, "pre-deadline break preview reflects configured duration")
        _ = clock.tick(now: 9, idleTime: 120)
        _ = clock.tick(now: 11, idleTime: 122)
        expect(clock.isOnBreak, "deadline enters a native-input break state")
        expect(clock.breakRemaining(now: 11, idleTime: 122) == 299, "break countdown starts at the deadline")
        _ = clock.tick(now: 12, idleTime: 1)
        expect(clock.breakRemaining(now: 12, idleTime: 1) == 299, "input after the deadline restarts the break countdown")
        let recovered = clock.tick(now: 312, idleTime: 301)
        expect(recovered, "configured break duration triggers recovery")
        expect(!clock.isOnBreak, "completed break leaves the break state")
        expect(clock.elapsed == 0 && clock.weight == 0, "recovery clears the session")
        expect(clock.isAway, "clock remains away until input resumes")
        _ = clock.tick(now: 311, idleTime: 0)
        expect(!clock.isAway && clock.elapsed == 0, "first returning input begins a fresh session")

        let idleWorkClock = SessionClock(interval: 45 * 60, breakDuration: 5 * 60)
        idleWorkClock.reset(startingAt: 0)
        _ = idleWorkClock.tick(now: 15 * 60, idleTime: 0)
        _ = idleWorkClock.tick(now: 20 * 60, idleTime: 5 * 60)
        expect(
            abs(idleWorkClock.elapsed - 20 * 60) < 0.001,
            "pre-deadline inactivity no longer resets the work session"
        )

        clock.breakDuration = 10 * 60
        expect(clock.breakRemaining(now: 60, idleTime: 60) == 9 * 60, "break duration can change to ten minutes")

        clock.primeForPreview()
        expect(clock.elapsed == clock.interval, "preview starts at the completed interval")
        expect(clock.weight == 1, "preview starts at maximum weight")

        let progressPreviewClock = SessionClock(interval: 45 * 60, breakDuration: 5 * 60)
        progressPreviewClock.primeForProgressPreview()
        expect(progressPreviewClock.elapsed == progressPreviewClock.interval - ReminderSchedule.progressInterval, "progress preview starts one reminder before the deadline")
        expect(progressPreviewClock.remaining == ReminderSchedule.progressInterval, "progress preview leaves fifteen minutes remaining")

        print("HeavyCursorCoreTests passed")
    }
}
