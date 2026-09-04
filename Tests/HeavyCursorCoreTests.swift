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
        expect(abs(WeightCurve.hardwareScale(for: 1) - 0.10) < 0.001, "hardware weight never reaches zero")
        expect(
            abs((WeightCurve.hardwareAccelerationTarget(original: 0.6875, weight: 1) ?? 0) - 0.06875) < 0.0001,
            "maximum hardware weight preserves ten percent of the original value"
        )
        expect(
            WeightCurve.hardwareAccelerationTarget(original: 0, weight: 1) == nil,
            "unsafe non-positive HID values fail open"
        )
        expect(HeavyCursorConstants.pointerTapActivationWeight > 0, "pointer tap waits for meaningful weight")
        expect(HeavyCursorConstants.pointerWarpGainThreshold < 1, "near-one gain skips cursor warp")
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
            CursorWeightingPolicy.mode(
                isUIPreview: false,
                isOnBreak: false,
                isAccessibilityTrusted: true,
                weight: 0.5
            ) == .software,
            "active work uses only software weighting"
        )
        expect(
            CursorWeightingPolicy.mode(
                isUIPreview: false,
                isOnBreak: true,
                isAccessibilityTrusted: true,
                weight: 1
            ) == .hardware,
            "break uses only native-cursor hardware weighting"
        )
        expect(
            CursorWeightingPolicy.mode(
                isUIPreview: false,
                isOnBreak: false,
                isAccessibilityTrusted: false,
                weight: 1
            ) == .none,
            "untrusted active work fails open"
        )
        expect(
            CursorWeightingPolicy.mode(
                isUIPreview: true,
                isOnBreak: true,
                isAccessibilityTrusted: true,
                weight: 1
            ) == .none,
            "UI preview never changes pointer behavior"
        )

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
