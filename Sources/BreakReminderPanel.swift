import Cocoa

private final class ReminderNSPanel: NSPanel {
    override var canBecomeKey: Bool {
        ProcessInfo.processInfo.arguments.contains("--preview-ui")
    }
    override var canBecomeMain: Bool { false }
}

final class BreakReminderPanel: NSObject {
    private let panel: ReminderNSPanel
    private let icon = NSImageView()
    private let message = NSTextField(labelWithString: "起身动一下")
    private let countdown = NSTextField(labelWithString: "03:00")
    private let divider = NSBox()
    private let quitButton = NSButton(title: "退出", target: nil, action: nil)
    private var dismissWorkItem: DispatchWorkItem?
    private var onQuit: (() -> Void)?
    private var pointerMonitor: Any?
    private(set) var isVisible = false

    override init() {
        panel = ReminderNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 244, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.setAccessibilityTitle("休息提醒")
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Keep the reminder above ordinary app windows without covering
        // password, permission, or other system-security dialogs.
        panel.level = .floating
        // Stay click-through unless the pointer is actually over the pill.
        // This prevents the reminder from stealing focus from a text field
        // underneath it while preserving a clickable Quit button.
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0
        panel.contentView = makeContentView()
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updatePointerInteraction()
        }
    }

    deinit {
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
        }
    }

    func showBreak(remaining: TimeInterval, onQuit: @escaping () -> Void) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        self.onQuit = onQuit
        configureBreakState()
        update(remaining: remaining)

        guard !isVisible else { return }
        isVisible = true
        positionPanel()
        updatePointerInteraction()
        if ProcessInfo.processInfo.arguments.contains("--preview-ui") {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(restingOrigin())
        }
    }

    func update(remaining: TimeInterval) {
        countdown.stringValue = Self.format(remaining)
    }

    func showProgress(remaining: TimeInterval) {
        dismissWorkItem?.cancel()
        onQuit = nil
        icon.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "距离起身时间")
        icon.contentTintColor = NSColor(srgbRed: 0.98, green: 0.62, blue: 0.28, alpha: 1)
        message.stringValue = "还有 \(max(1, Int(ceil(remaining / 60)))) 分钟 · 起身走走"
        countdown.isHidden = true
        divider.isHidden = true
        quitButton.isHidden = true
        fitPanelToContent()
        presentIfNeeded()

        let item = DispatchWorkItem { [weak self] in self?.hide() }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: item)
    }

    func showRecovered() {
        dismissWorkItem?.cancel()
        onQuit = nil
        icon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "鼠标已恢复轻盈")
        icon.contentTintColor = .systemGreen
        message.stringValue = "鼠标已恢复轻盈"
        countdown.isHidden = true
        divider.isHidden = true
        quitButton.isHidden = true
        fitPanelToContent()
        presentIfNeeded(animated: false)

        let item = DispatchWorkItem { [weak self] in self?.hide() }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    func hide() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        guard isVisible else { return }
        isVisible = false
        panel.ignoresMouseEvents = true

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }

    @objc private func quitPressed() {
        onQuit?()
    }

    private func configureBreakState() {
        icon.image = NSImage(systemSymbolName: "figure.walk.motion", accessibilityDescription: "起身活动")
        icon.contentTintColor = NSColor(srgbRed: 0.98, green: 0.62, blue: 0.28, alpha: 1)
        message.stringValue = "起身动一下"
        countdown.isHidden = false
        divider.isHidden = false
        quitButton.isHidden = false
        fitPanelToContent()
    }

    private func presentIfNeeded(animated: Bool = true) {
        guard !isVisible else { return }
        isVisible = true
        positionPanel()
        updatePointerInteraction()
        if ProcessInfo.processInfo.arguments.contains("--preview-ui") {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }

        guard animated else {
            panel.alphaValue = 1
            panel.setFrameOrigin(restingOrigin())
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(restingOrigin())
        }
    }

    private func positionPanel() {
        let origin = restingOrigin()
        panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y - 6))
    }

    private func updatePointerInteraction() {
        guard isVisible else {
            panel.ignoresMouseEvents = true
            return
        }
        panel.ignoresMouseEvents = !panel.frame.contains(NSEvent.mouseLocation)
    }

    private func restingOrigin() -> NSPoint {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return .zero }
        let visible = screen.visibleFrame
        return NSPoint(
            x: screen.frame.midX - panel.frame.width / 2,
            y: visible.maxY - panel.frame.height - 18
        )
    }

    private func makeContentView() -> NSView {
        let effect = NSView()
        effect.wantsLayer = true
        effect.layer?.backgroundColor = NSColor(srgbRed: 0.055, green: 0.06, blue: 0.07, alpha: 0.94).cgColor
        effect.layer?.cornerRadius = 18
        effect.layer?.masksToBounds = true

        icon.translatesAutoresizingMaskIntoConstraints = false

        message.font = .systemFont(ofSize: 12, weight: .semibold)
        message.textColor = NSColor.white.withAlphaComponent(0.94)
        message.lineBreakMode = .byTruncatingTail

        countdown.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        countdown.textColor = NSColor.white.withAlphaComponent(0.72)
        countdown.alignment = .right

        divider.boxType = .separator
        divider.fillColor = NSColor.white.withAlphaComponent(0.20)
        divider.translatesAutoresizingMaskIntoConstraints = false

        quitButton.target = self
        quitButton.action = #selector(quitPressed)
        quitButton.isBordered = false
        quitButton.font = .systemFont(ofSize: 11, weight: .medium)
        quitButton.contentTintColor = NSColor.white.withAlphaComponent(0.62)
        quitButton.setButtonType(.momentaryChange)

        let stack = NSStackView(views: [icon, message, countdown, divider, quitButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            countdown.widthAnchor.constraint(equalToConstant: 39),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 13),
            quitButton.widthAnchor.constraint(equalToConstant: 30),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
        ])
        return effect
    }

    /// Keep the capsule as tight as its current content. The panel used to
    /// stay at a fixed 244pt width, which left a noticeable empty tail after
    /// the Quit action in the compact break state.
    private func fitPanelToContent() {
        let items: [(view: NSView, width: CGFloat)] = [
            (icon, 14),
            (message, max(0, message.intrinsicContentSize.width)),
            (countdown, 39),
            (divider, 1),
            (quitButton, 30),
        ]
        let visible = items.filter { !$0.view.isHidden }
        let gaps = max(0, visible.count - 1)
        let contentWidth = visible.reduce(0) { $0 + $1.width }
            + CGFloat(gaps) * 4
            + 20
        let minimumWidth: CGFloat = 132
        panel.setContentSize(NSSize(
            width: max(minimumWidth, ceil(contentWidth)),
            height: 36
        ))
    }

    private static func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(interval)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
