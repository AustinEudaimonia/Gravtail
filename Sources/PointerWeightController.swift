import Cocoa
import ApplicationServices

final class PointerWeightController {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastOutputLocation: CGPoint?
    /// Monotonic timestamp of the last pointer event received by the event
    /// tap. This is used for inactivity while weighting is active because
    /// CGWarpMouseCursorPosition can otherwise make the global HID
    /// mouseMoved clock look busy even when the user has not touched the
    /// mouse.
    private(set) var lastPhysicalInputUptime: TimeInterval?
    /// Permission requests are deliberately throttled. Calling
    /// AXIsProcessTrustedWithOptions(prompt: true) on every menu click can
    /// stack duplicate macOS prompts and make the user think authorization is
    /// broken.
    private var hasRequestedPermissionThisSession = false
    /// If macOS disables the tap, keep it disabled for the rest of the work
    /// session. Re-enabling a repeatedly timing-out tap can make pointer input
    /// stutter or appear locked. A reset/new session explicitly clears this.
    private(set) var isSafetyDisabled = false
    var gainProvider: () -> CGFloat = { 1 }

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestPermission() {
        guard !isTrusted else { return }

        if hasRequestedPermissionThisSession {
            openAccessibilitySettings()
            return
        }

        // Ask macOS about this exact running bundle first. Merely opening the
        // Accessibility pane can leave an enabled row for an older Gravtail
        // copy while the current app remains untrusted. This prompt is
        // throttled to once per process so it cannot stack repeatedly.
        hasRequestedPermissionThisSession = true
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    private func openAccessibilitySettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    @discardableResult
    func start() -> Bool {
        stop()
        guard isTrusted, !isSafetyDisabled else { return false }

        let types: [CGEventType] = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
        ]
        let mask = types.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << type.rawValue)
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<PointerWeightController>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                controller.isSafetyDisabled = true
                if let tap = controller.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: false)
                }
                _ = CGAssociateMouseAndMouseCursorPosition(1)
                DiagnosticLog.shared.record("event-tap-fail-open", fields: [
                    "reason": type == .tapDisabledByTimeout ? "timeout" : "user-input",
                ])
                return Unmanaged.passUnretained(event)
            }

            controller.lastPhysicalInputUptime = ProcessInfo.processInfo.systemUptime
            controller.applyWeight(to: event)
            return Unmanaged.passUnretained(event)
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        lastOutputLocation = nil
        lastPhysicalInputUptime = nil
        return true
    }

    func resetSafetyLockout() {
        isSafetyDisabled = false
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        runLoopSource = nil
        lastOutputLocation = nil
        lastPhysicalInputUptime = nil
        // Re-associate the physical device with the visible cursor in case a
        // system-level warp left the association in a transient state.
        _ = CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func applyWeight(to event: CGEvent) {
        let incoming = event.location
        guard let previous = lastOutputLocation else {
            lastOutputLocation = incoming
            return
        }

        let requestedGain = gainProvider()
        guard requestedGain.isFinite else {
            // Invalid state must always fail open: preserve the native event
            // instead of ever sending a NaN coordinate to WindowServer.
            lastOutputLocation = incoming
            return
        }
        let gain = max(HeavyCursorConstants.minimumGain, min(1, requestedGain))
        if gain >= HeavyCursorConstants.pointerWarpGainThreshold {
            // The event tap may briefly be active as the weight curve starts,
            // but a nearly-one gain does not need a system-level warp. Avoid
            // re-associating the cursor for ordinary, unweighted movement.
            lastOutputLocation = incoming
            return
        }
        let deltaX = incoming.x - previous.x
        let deltaY = incoming.y - previous.y
        guard deltaX.isFinite, deltaY.isFinite else {
            lastOutputLocation = incoming
            return
        }
        let output = CGPoint(
            x: previous.x + deltaX * gain,
            y: previous.y + deltaY * gain
        )

        // A session event tap can change the coordinates delivered to apps,
        // but macOS may already have moved the visible system cursor. Warping
        // it back to the weighted location creates the physical resistance the
        // product promises. This API does not generate another mouse event, so
        // it cannot recurse into this event tap.
        let warpResult = CGWarpMouseCursorPosition(output)
        // Explicitly reconnect after every warp. Gravtail never asks macOS to
        // disconnect the physical device, but making the association explicit
        // prevents a transient WindowServer state from outliving this event.
        _ = CGAssociateMouseAndMouseCursorPosition(1)
        if warpResult == .success {
            event.location = output
            event.setIntegerValueField(
                .mouseEventDeltaX,
                value: Int64((CGFloat(event.getIntegerValueField(.mouseEventDeltaX)) * gain).rounded())
            )
            event.setIntegerValueField(
                .mouseEventDeltaY,
                value: Int64((CGFloat(event.getIntegerValueField(.mouseEventDeltaY)) * gain).rounded())
            )
            lastOutputLocation = output
        } else {
            // One more best-effort recovery before passing the native event.
            _ = CGAssociateMouseAndMouseCursorPosition(1)
            lastOutputLocation = incoming
        }
    }
}
