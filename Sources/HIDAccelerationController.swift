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

    init(restoreOrphanedBackup: Bool = true) {
        handle = NXOpenEventStatus()
        if restoreOrphanedBackup {
            restoreOrphanedBackupIfNeeded()
        }
    }

    deinit {
        restore()
        if handle != 0 {
            NXCloseEventStatus(handle)
        }
    }

    func currentValues() -> (mouse: Double?, trackpad: Double?) {
        (read(Key.mouse), read(Key.trackpad))
    }

    func update(weight: CGFloat) {
        guard handle != 0 else {
            isActive = false
            lastOperationSucceeded = false
            lastRollbackSucceeded = false
            return
        }
        let clamped = max(0, min(1, weight))

        if clamped <= 0.005 {
            _ = restore()
            return
        }

        captureOriginalValuesIfNeeded()
        guard originalMouse != nil || originalTrackpad != nil else {
            isActive = false
            lastOperationSucceeded = false
            return
        }
        guard abs(lastWeight - clamped) > 0.005 else { return }

        var changed: [(key: CFString, value: Double)] = []

        if let originalMouse {
            let target = max(0, originalMouse * Double(1 - clamped))
            guard write(Key.mouse, target) else {
                failUpdate(afterRollingBack: changed)
                return
            }
            changed.append((Key.mouse, originalMouse))
        }
        if let originalTrackpad {
            let target = max(0, originalTrackpad * Double(1 - clamped))
            guard write(Key.trackpad, target) else {
                failUpdate(afterRollingBack: changed)
                return
            }
            changed.append((Key.trackpad, originalTrackpad))
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
        var success = true
        if let originalMouse { success = write(Key.mouse, originalMouse) && success }
        if let originalTrackpad { success = write(Key.trackpad, originalTrackpad) && success }
        lastWeight = -1
        isActive = false
        lastOperationSucceeded = success
        lastRollbackSucceeded = success
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
        // The update failed even if the rollback succeeded; this lets the app
        // surface a real failure while it retries on the next logic tick.
        lastOperationSucceeded = false
    }

    private func captureOriginalValuesIfNeeded() {
        guard originalMouse == nil && originalTrackpad == nil else { return }
        originalMouse = read(Key.mouse)
        originalTrackpad = read(Key.trackpad)

        guard originalMouse != nil || originalTrackpad != nil else { return }

        if let originalMouse {
            defaults.set(originalMouse, forKey: Key.mouseBackup)
        }
        if let originalTrackpad {
            defaults.set(originalTrackpad, forKey: Key.trackpadBackup)
        }
        defaults.set(true, forKey: Key.hasBackup)
    }

    private func restoreOrphanedBackupIfNeeded() {
        guard handle != 0 else {
            if defaults.bool(forKey: Key.hasBackup) {
                lastOperationSucceeded = false
                lastRollbackSucceeded = false
            }
            return
        }
        guard defaults.bool(forKey: Key.hasBackup) else { return }
        var success = true
        if defaults.object(forKey: Key.mouseBackup) != nil {
            success = write(Key.mouse, defaults.double(forKey: Key.mouseBackup)) && success
        }
        if defaults.object(forKey: Key.trackpadBackup) != nil {
            success = write(Key.trackpad, defaults.double(forKey: Key.trackpadBackup)) && success
        }
        lastOperationSucceeded = success
        lastRollbackSucceeded = success
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
        IOHIDSetAccelerationWithKey(handle, key, value) == KERN_SUCCESS
    }

    private func clearBackup() {
        defaults.removeObject(forKey: Key.hasBackup)
        defaults.removeObject(forKey: Key.mouseBackup)
        defaults.removeObject(forKey: Key.trackpadBackup)
    }
}
