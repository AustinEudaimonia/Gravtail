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
    var gainProvider: () -> CGFloat = { 1 }

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func start() -> Bool {
        stop()
        guard isTrusted else { return false }

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
                if let tap = controller.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
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

        let gain = max(HeavyCursorConstants.minimumGain, min(1, gainProvider()))
        let deltaX = incoming.x - previous.x
        let deltaY = incoming.y - previous.y
        let output = CGPoint(
            x: previous.x + deltaX * gain,
            y: previous.y + deltaY * gain
        )

        // A session event tap can change the coordinates delivered to apps,
        // but macOS may already have moved the visible system cursor. Warping
        // it back to the weighted location creates the physical resistance the
        // product promises. This API does not generate another mouse event, so
        // it cannot recurse into this event tap.
        if CGWarpMouseCursorPosition(output) == .success {
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
            lastOutputLocation = incoming
        }
    }
}
