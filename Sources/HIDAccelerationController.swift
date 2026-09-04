import Foundation
import Darwin

private typealias HIDHandle = mach_port_t

@_silgen_name("NXOpenEventStatus")
private func NXOpenEventStatus() -> HIDHandle

@_silgen_name("NXCloseEventStatus")
private func NXCloseEventStatus(_ handle: HIDHandle)

@_silgen_name("IOHIDGetAccelerationWithKey")
private func IOHIDGetAccelerationWithKey(
    _ handle: HIDHandle,
    _ key: CFString,
    _ acceleration: UnsafeMutablePointer<Double>
) -> kern_return_t

@_silgen_name("IOHIDSetAccelerationWithKey")
private func IOHIDSetAccelerationWithKey(
    _ handle: HIDHandle,
    _ key: CFString,
    _ acceleration: Double
) -> kern_return_t

final class HIDAccelerationController {
    private enum Key {
        static let mouse = "HIDMouseAcceleration" as CFString
        static let trackpad = "HIDTrackpadAcceleration" as CFString
        static let hasBackup = "hidAccelerationHasBackup"
        static let mouseBackup = "hidMouseAccelerationBackup"
        static let trackpadBackup = "hidTrackpadAccelerationBackup"
    }

    private let defaults = UserDefaults.standard
    private let handle: HIDHandle
    private var originalMouse: Double?
    private var originalTrackpad: Double?
    private var lastWeight: CGFloat = -1
    private(set) var isActive = false
    private(set) var lastOperationSucceeded = true
    private(set) var lastRollbackSucceeded = true
    private(set) var hadOrphanedBackup = false
    private(set) var didRestoreOrphanedBackup = false
    private(set) var isSafetyDisabled = false
    /// Called after the original values are durably saved but before the first
    /// HID write. Returning false prevents weighting entirely. The app uses
    /// this to require an external crash-recovery watchdog.
    var backupPreparedHandler: ((Double?, Double?) -> Bool)?

    init(restoreOrphanedBackup: Bool = true) {
        handle = NXOpenEventStatus()
        if restoreOrphanedBackup {
            restoreOrphanedBackupIfNeeded()
        }
    }

    deinit {
        // A read-only diagnostic controller has no originals of its own. It
        // must not clear another running app's persistent recovery backup.
        if originalMouse != nil || originalTrackpad != nil {
            restore()
        }
        if handle != 0 {
            NXCloseEventStatus(handle)
        }
    }

    func currentValues() -> (mouse: Double?, trackpad: Double?) {
        (read(Key.mouse), read(Key.trackpad))
    }

    var recoveryValues: (mouse: Double?, trackpad: Double?) {
        (originalMouse, originalTrackpad)
    }

    func update(weight: CGFloat) {
        guard !isSafetyDisabled else { return }
        guard handle != 0 else {
            isActive = false
            lastOperationSucceeded = false
            lastRollbackSucceeded = false
            isSafetyDisabled = true
            return
        }
        let clamped = max(0, min(1, weight))

        if clamped <= 0.005 {
            _ = restore()
            return
        }

        guard captureOriginalValuesIfNeeded() else {
            isActive = false
            lastOperationSucceeded = false
            lastRollbackSucceeded = true
            isSafetyDisabled = true
            return
        }
        guard originalMouse != nil || originalTrackpad != nil else {
            isActive = false
            lastOperationSucceeded = false
            isSafetyDisabled = true
            return
        }
        guard abs(lastWeight - clamped) > 0.005 else { return }

        var changed: [(key: CFString, value: Double)] = []

        // A zero or negative acceleration value is not a safe weighting
        // target on every macOS/input-device combination. Leave an already
        // non-positive setting untouched; otherwise preserve at least the
        // product's 10% minimum response.
        if let originalMouse,
           let target = WeightCurve.hardwareAccelerationTarget(original: originalMouse, weight: clamped) {
            changed.append((Key.mouse, originalMouse))
            guard write(Key.mouse, target) else {
                failUpdate(afterRollingBack: changed)
                return
            }
        }
        if let originalTrackpad,
           let target = WeightCurve.hardwareAccelerationTarget(original: originalTrackpad, weight: clamped) {
            changed.append((Key.trackpad, originalTrackpad))
            guard write(Key.trackpad, target) else {
                failUpdate(afterRollingBack: changed)
                return
            }
        }

        // No positive value means there is nothing safe for this private HID
        // path to change. Fail open rather than guessing a device setting.
        guard !changed.isEmpty else {
            isActive = false
            lastOperationSucceeded = false
            lastRollbackSucceeded = true
            originalMouse = nil
            originalTrackpad = nil
            clearBackup()
            isSafetyDisabled = true
            return
        }

        lastOperationSucceeded = true
        lastRollbackSucceeded = true
        isActive = true
        lastWeight = clamped
    }

    @discardableResult
    func restore() -> Bool {
        guard handle != 0 else {
            isActive = false
            lastOperationSucceeded = false
            lastRollbackSucceeded = false
            return false
        }
        guard originalMouse != nil || originalTrackpad != nil else {
            if defaults.bool(forKey: Key.hasBackup) {
                restoreOrphanedBackupIfNeeded()
                isActive = false
                lastWeight = -1
                return didRestoreOrphanedBackup
            }
            isActive = false
            lastWeight = -1
            lastOperationSucceeded = true
            lastRollbackSucceeded = true
            return true
        }
        var success = true
        if let originalMouse { success = write(Key.mouse, originalMouse) && success }
        if let originalTrackpad { success = write(Key.trackpad, originalTrackpad) && success }
        lastWeight = -1
        isActive = false
        lastOperationSucceeded = success
        lastRollbackSucceeded = success
        if !success {
            isSafetyDisabled = true
        }
        if success {
            originalMouse = nil
            originalTrackpad = nil
            clearBackup()
        }
        return success
    }

    private func failUpdate(afterRollingBack changed: [(key: CFString, value: Double)]) {
        // A failed two-device update must not leave only one device weighted.
        // Keep the originals and persistent backup if rollback itself fails so
        // the next tick or a relaunch can retry restoration safely.
        var rollbackSucceeded = true
        for change in changed.reversed() {
            rollbackSucceeded = write(change.key, change.value) && rollbackSucceeded
        }
        lastWeight = -1
        isActive = false
        lastRollbackSucceeded = rollbackSucceeded
        // The update failed even if the rollback succeeded. Disable HID
        // weighting for this session instead of retrying against live input.
        lastOperationSucceeded = false
        isSafetyDisabled = true
    }

    func resetSafetyLockout() {
        isSafetyDisabled = false
    }

    func disableForSafety() {
        isSafetyDisabled = true
    }

    private func captureOriginalValuesIfNeeded() -> Bool {
        guard originalMouse == nil && originalTrackpad == nil else { return true }
        originalMouse = read(Key.mouse)
        originalTrackpad = read(Key.trackpad)

        guard originalMouse != nil || originalTrackpad != nil else { return false }

        if let originalMouse {
            defaults.set(originalMouse, forKey: Key.mouseBackup)
        }
        if let originalTrackpad {
            defaults.set(originalTrackpad, forKey: Key.trackpadBackup)
        }
        defaults.set(true, forKey: Key.hasBackup)
        defaults.synchronize()

        if let backupPreparedHandler,
           !backupPreparedHandler(originalMouse, originalTrackpad) {
            originalMouse = nil
            originalTrackpad = nil
            clearBackup()
            return false
        }
        return true
    }

    private func restoreOrphanedBackupIfNeeded() {
        guard handle != 0 else {
            if defaults.bool(forKey: Key.hasBackup) {
                lastOperationSucceeded = false
                lastRollbackSucceeded = false
            }
            return
        }
        hadOrphanedBackup = defaults.bool(forKey: Key.hasBackup)
        guard hadOrphanedBackup else { return }
        var success = true
        if defaults.object(forKey: Key.mouseBackup) != nil {
            success = write(Key.mouse, defaults.double(forKey: Key.mouseBackup)) && success
        }
        if defaults.object(forKey: Key.trackpadBackup) != nil {
            success = write(Key.trackpad, defaults.double(forKey: Key.trackpadBackup)) && success
        }
        lastOperationSucceeded = success
        lastRollbackSucceeded = success
        didRestoreOrphanedBackup = success
        if !success {
            isSafetyDisabled = true
        }
        if success {
            clearBackup()
        }
    }

    private func read(_ key: CFString) -> Double? {
        guard handle != 0 else { return nil }
        var value = 0.0
        return IOHIDGetAccelerationWithKey(handle, key, &value) == KERN_SUCCESS ? value : nil
    }

    @discardableResult
    private func write(_ key: CFString, _ value: Double) -> Bool {
        guard IOHIDSetAccelerationWithKey(handle, key, value) == KERN_SUCCESS,
              let actual = read(key) else { return false }
        return abs(actual - value) <= 0.001
    }

    private func clearBackup() {
        defaults.removeObject(forKey: Key.hasBackup)
        defaults.removeObject(forKey: Key.mouseBackup)
        defaults.removeObject(forKey: Key.trackpadBackup)
        defaults.synchronize()
    }

    /// Emergency recovery for a known pre-launch value when an older build
    /// has already lost its backup. Normal app behavior never calls this.
    func restoreKnownValues(mouse: Double?, trackpad: Double?) -> Bool {
        guard handle != 0 else { return false }
        var attempted = false
        var success = true
        if let mouse {
            attempted = true
            success = write(Key.mouse, mouse) && success
        }
        if let trackpad {
            attempted = true
            success = write(Key.trackpad, trackpad) && success
        }
        if attempted && success {
            clearBackup()
        }
        return attempted && success
    }
}
