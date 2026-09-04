import Foundation
import Darwin

private typealias HIDHandle = mach_port_t

/// These HID functions are intentionally loaded at runtime. They are not part
/// of Apple's public SDK contract, so hard-linking them would make Gravtail
/// fail to launch if a future macOS release removes one of the symbols. With a
/// dynamic table, an unsupported system simply keeps native pointer behavior.
private final class HIDFunctionTable {
    typealias Open = @convention(c) () -> HIDHandle
    typealias Close = @convention(c) (HIDHandle) -> Void
    typealias Get = @convention(c) (
        HIDHandle,
        CFString,
        UnsafeMutablePointer<Double>
    ) -> kern_return_t
    typealias Set = @convention(c) (HIDHandle, CFString, Double) -> kern_return_t

    private let library: UnsafeMutableRawPointer
    let open: Open
    let close: Close
    let get: Get
    let set: Set

    private init?() {
        let path = "/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit"
        guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else {
            return nil
        }
        guard let openSymbol = dlsym(library, "NXOpenEventStatus"),
              let closeSymbol = dlsym(library, "NXCloseEventStatus"),
              let getSymbol = dlsym(library, "IOHIDGetAccelerationWithKey"),
              let setSymbol = dlsym(library, "IOHIDSetAccelerationWithKey") else {
            dlclose(library)
            return nil
        }
        self.library = library
        open = unsafeBitCast(openSymbol, to: Open.self)
        close = unsafeBitCast(closeSymbol, to: Close.self)
        get = unsafeBitCast(getSymbol, to: Get.self)
        set = unsafeBitCast(setSymbol, to: Set.self)
    }

    deinit {
        dlclose(library)
    }

    static func load() -> HIDFunctionTable? {
        HIDFunctionTable()
    }
}

enum HIDCompatibility: String {
    case available
    case systemAPIUnavailable
    case deviceSettingsUnavailable

    var userFacingDescription: String {
        switch self {
        case .available:
            return "硬件加重可用"
        case .systemAPIUnavailable:
            return "此 macOS 版本不支持硬件加重"
        case .deviceSettingsUnavailable:
            return "当前鼠标设备不支持硬件加重"
        }
    }
}

final class HIDAccelerationController {
    private enum Key {
        static let mouse = "HIDMouseAcceleration" as CFString
        static let trackpad = "HIDTrackpadAcceleration" as CFString
        static let hasBackup = "hidAccelerationHasBackup"
        static let mouseBackup = "hidMouseAccelerationBackup"
        static let trackpadBackup = "hidTrackpadAccelerationBackup"
    }

    private let defaults = UserDefaults.standard
    private let functions: HIDFunctionTable?
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
    private(set) var compatibility: HIDCompatibility
    /// Called after the original values are durably saved but before the first
    /// HID write. Returning false prevents weighting entirely. The app uses
    /// this to require an external crash-recovery watchdog.
    var backupPreparedHandler: ((Double?, Double?) -> Bool)?

    init(restoreOrphanedBackup: Bool = true) {
        functions = HIDFunctionTable.load()
        handle = functions?.open() ?? 0
        if functions == nil || handle == 0 {
            compatibility = .systemAPIUnavailable
        } else {
            compatibility = .available
        }
        if restoreOrphanedBackup {
            restoreOrphanedBackupIfNeeded()
        }
        if compatibility == .available {
            let values = currentValues()
            if values.mouse == nil && values.trackpad == nil {
                compatibility = .deviceSettingsUnavailable
                isSafetyDisabled = true
            }
        }
    }

    deinit {
        // A read-only diagnostic controller has no originals of its own. It
        // must not clear another running app's persistent recovery backup.
        if originalMouse != nil || originalTrackpad != nil {
            restore()
        }
        if handle != 0, let functions {
            functions.close(handle)
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
            // No write was attempted, so native input is already intact.
            lastRollbackSucceeded = true
            isSafetyDisabled = true
            compatibility = .systemAPIUnavailable
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
            compatibility = .deviceSettingsUnavailable
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
            compatibility = .deviceSettingsUnavailable
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
            // An unavailable API is safe when there is no persisted write to
            // recover. Report failure only if an older run left a real backup.
            let needsRecovery = defaults.bool(forKey: Key.hasBackup)
            lastOperationSucceeded = !needsRecovery
            lastRollbackSucceeded = !needsRecovery
            return !needsRecovery
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
        isSafetyDisabled = compatibility != .available
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
        guard handle != 0, let functions else { return nil }
        var value = 0.0
        return functions.get(handle, key, &value) == KERN_SUCCESS ? value : nil
    }

    @discardableResult
    private func write(_ key: CFString, _ value: Double) -> Bool {
        guard let functions,
              functions.set(handle, key, value) == KERN_SUCCESS,
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
