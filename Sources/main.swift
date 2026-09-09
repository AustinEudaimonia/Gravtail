import Cocoa
import ApplicationServices
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = UserDefaults.standard
    private let isFortyFiveMinutePreview = ProcessInfo.processInfo.arguments.contains("--preview-45")
    private let isProgressPreview = ProcessInfo.processInfo.arguments.contains("--preview-progress")
    private let isUIPreview = ProcessInfo.processInfo.arguments.contains("--preview-ui")
    private var isAnyPreview: Bool { isFortyFiveMinutePreview || isProgressPreview || isUIPreview }
    private let launchUptime = ProcessInfo.processInfo.systemUptime
    private lazy var clock = SessionClock(
        interval: isAnyPreview ? 45 * 60 : selectedInterval,
        breakDuration: selectedBreakDuration
    )
    private let pointerController = PointerWeightController()
    private let hidAccelerationController = HIDAccelerationController()
    private let breakReminder = BreakReminderPanel()
    private let hidRecoveryWatchdog = RecoveryWatchdog()
    private var sessionSafetyDisabled = false
    private var pendingRecoveryNotice = false
    private var settingsWindow: NSWindow?
    private var settingsSummary: NSTextField?
    private var settingsPrimaryButton: NSButton?

    private var physicalWeightingEnabled: Bool {
        get { settings.bool(forKey: "physicalWeightingEnabled") }
        set { settings.set(newValue, forKey: "physicalWeightingEnabled") }
    }

    private var statusItem: NSStatusItem?
    private var overlayWindows: [NSWindow] = []
    private var renderTimer: Timer?
    private var logicTimer: Timer?
    private var needsFinalClear = false
    private var hasShownBreakReminder = false
    private var lastProgressReminderMark = 0
    private var hasStartedWorkSession = false
    private var sessionInputBaselineUptime: TimeInterval
    private var isShowingOnboarding = false
    private var terminatingOldInstancePIDs = Set<pid_t>()
    private var lastDiagnosticState = ""

    override init() {
        sessionInputBaselineUptime = launchUptime
        super.init()
    }

    private var selectedInterval: TimeInterval {
        get {
            let minutes = settings.integer(forKey: "workIntervalMinutes")
            return TimeInterval(minutes == 45 || minutes == 90 ? minutes : 60) * 60
        }
        set {
            settings.set(Int(newValue / 60), forKey: "workIntervalMinutes")
        }
    }

    private var selectedBreakDuration: TimeInterval {
        get {
            let minutes = settings.integer(forKey: "breakDurationMinutes")
            return TimeInterval(minutes == 5 || minutes == 10 ? minutes : 3) * 60
        }
        set {
            settings.set(Int(newValue / 60), forKey: "breakDurationMinutes")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherInstances()
        NSApp.setActivationPolicy(isUIPreview ? .regular : .accessory)
        setUpMenuBarIcon()
        if !isUIPreview {
            rebuildOverlayWindows()
        }

        pointerController.gainProvider = { [weak self] in
            self?.isUIPreview == true ? 1 : (self?.clock.pointerGain ?? 1)
        }
        hidAccelerationController.backupPreparedHandler = { [weak self] mouse, trackpad in
            self?.startHIDRecoveryWatchdog(mouse: mouse, trackpad: trackpad) ?? false
        }

        if isAnyPreview {
            if isProgressPreview {
                clock.primeForProgressPreview()
            } else {
                clock.primeForPreview()
            }
            hasStartedWorkSession = true
        }
        startTimers()
        if !isAnyPreview {
            showOnboardingIfNeeded()
            if settings.object(forKey: "physicalWeightingEnabled") == nil {
                // Older versions did not persist the user's choice. Do not
                // infer consent from an existing Accessibility grant.
                physicalWeightingEnabled = false
            }
            // A visible entry point even when macOS has no room for our item.
            showSettingsWindow()
        }
        if !isUIPreview {
            startPointerWeightIfPossible()
        }
        DiagnosticLog.shared.record("launch", fields: [
            "app": Bundle.main.bundlePath,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "accessibility": pointerController.isTrusted ? "trusted" : "not-trusted",
            "workMinutes": String(Int(clock.interval / 60)),
            "breakMinutes": String(Int(clock.breakDuration / 60)),
            "hidCompatibility": hidAccelerationController.compatibility.rawValue,
        ])
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// A previous build can still be running when a newly built app is opened
    /// from the Finder. Both copies share the same bundle identifier, so make
    /// sure an older copy cannot keep its event tap and pointer weighting
    /// alive after the new copy starts.
    private func terminateOtherInstances() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentLaunchDate = NSRunningApplication(processIdentifier: currentPID)?.launchDate
        for application in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            where application.processIdentifier != currentPID {
            // Only an older instance should be asked to exit. Without this
            // ordering check, two copies launched close together can see each
            // other and terminate one another, leaving an old event tap alive
            // just long enough to make Quit appear ineffective.
            let isOlder = application.launchDate.map { otherDate in
                guard let currentLaunchDate else { return true }
                return otherDate < currentLaunchDate
            } ?? true
            if isOlder {
                if application.terminate() {
                    terminatingOldInstancePIDs.insert(application.processIdentifier)
                }
            }
        }
    }

    @discardableResult
    private func restoreHardware() -> Bool {
        pointerController.stop()
        pointerTapIsActive = false
        if hidAccelerationController.restore() {
            return stopHIDRecoveryWatchdog()
        } else {
            DiagnosticLog.shared.record("hid-restore-deferred-to-watchdog")
            return false
        }
    }

    /// Start an independent copy of the executable before the first HID write.
    /// Missing main-loop heartbeats, parent death or disconnected IPC trigger
    /// restoration of the exact pre-weight values in the independent child.
    private func startHIDRecoveryWatchdog(mouse: Double?, trackpad: Double?) -> Bool {
        if hidRecoveryWatchdog.isRunning { return hidRecoveryWatchdog.pulse() }
        guard mouse != nil || trackpad != nil,
              let executableURL = Bundle.main.executableURL else { return false }

        let arguments = [
            "--hid-watchdog",
            String(ProcessInfo.processInfo.processIdentifier),
            mouse.map { String(format: "%.17g", $0) } ?? "none",
            trackpad.map { String(format: "%.17g", $0) } ?? "none",
        ]
        return hidRecoveryWatchdog.start(executable: executableURL, arguments: arguments)
    }

    @discardableResult
    private func stopHIDRecoveryWatchdog() -> Bool {
        let stopped = hidRecoveryWatchdog.stop()
        if !stopped { sessionSafetyDisabled = true }
        return stopped
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        restoreHardware()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        restoreHardware()
    }

    private func showOnboardingIfNeeded() {
        guard !settings.bool(forKey: "hasCompletedOnboarding") else { return }

        isShowingOnboarding = true
        defer {
            isShowingOnboarding = false
            sessionInputBaselineUptime = ProcessInfo.processInfo.systemUptime
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "什么时候让光标变重？"
        alert.informativeText = "第一次操作后会出现轻微彗尾；后半程逐渐变重，直到提醒你起身活动。"
        alert.addButton(withTitle: "60 分钟")
        alert.addButton(withTitle: "45 分钟")
        alert.addButton(withTitle: "90 分钟")

        let response = alert.runModal()
        let minutes: Int
        switch response {
        case .alertSecondButtonReturn: minutes = 45
        case .alertThirdButtonReturn: minutes = 90
        default: minutes = 60
        }

        selectedInterval = TimeInterval(minutes * 60)
        clock.interval = selectedInterval

        let breakAlert = NSAlert()
        breakAlert.messageText = "每次休息多久？"
        breakAlert.informativeText = "休息期间再次使用键盘或鼠标，倒计时会重新开始。"
        breakAlert.addButton(withTitle: "3 分钟")
        breakAlert.addButton(withTitle: "5 分钟")
        breakAlert.addButton(withTitle: "10 分钟")

        let breakResponse = breakAlert.runModal()
        let breakMinutes: Int
        switch breakResponse {
        case .alertSecondButtonReturn: breakMinutes = 5
        case .alertThirdButtonReturn: breakMinutes = 10
        default: breakMinutes = 3
        }
        selectedBreakDuration = TimeInterval(breakMinutes * 60)
        clock.breakDuration = selectedBreakDuration
        hasStartedWorkSession = false
        clock.reset(startingAt: nil)
        settings.set(true, forKey: "hasCompletedOnboarding")

        let permission = NSAlert()
        permission.messageText = "允许 Gravtail 调整鼠标重量"
        permission.informativeText = "开启后允许 Gravtail 降低鼠标响应，并申请辅助功能权限。选择暂不开启时，所有阶段都只显示彗尾和休息提醒。"
        permission.addButton(withTitle: "开启")
        permission.addButton(withTitle: "暂不开启")
        if permission.runModal() == .alertFirstButtonReturn {
            physicalWeightingEnabled = true
            pointerController.requestPermission()
        } else {
            physicalWeightingEnabled = false
        }
    }

    private func startTimers() {
        let logic = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.logicTick()
        }
        RunLoop.main.add(logic, forMode: .common)
        logicTimer = logic

        // 60 FPS is enough for a smooth comet while leaving more headroom for
        // high-Hz pointer streams and multi-display Macs.
        let render = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderTick()
        }
        RunLoop.main.add(render, forMode: .common)
        renderTimer = render
    }

    private func logicTick() {
        if hidAccelerationController.isActive && !hidRecoveryWatchdog.pulse() {
            // A stalled loop, dead child or broken IPC ends physical weighting
            // until the user explicitly resets. Never spawn a replacement that
            // would silently undo the watchdog's recovery.
            sessionSafetyDisabled = true
            _ = restoreHardware()
        }
        // Preview sessions are intentionally frozen at the requested demo
        // state. Otherwise a user who has been away from the keyboard for
        // longer than the configured break duration can launch --preview-45
        // and have it immediately mark the break as completed, hiding the
        // very heavy pointer effect the preview is meant to demonstrate.
        let idleTime = isAnyPreview ? 0 : currentIdleTime()
        let now = ProcessInfo.processInfo.systemUptime
        // A previous copy may still be unwinding its event tap and restoring
        // HID settings. Keep this instance passive until it has exited so two
        // builds cannot compete for the same pointer stream.
        if !terminatingOldInstancePIDs.isEmpty {
            terminatingOldInstancePIDs = terminatingOldInstancePIDs.filter { pid in
                NSRunningApplication(processIdentifier: pid)?.isTerminated == false
            }
            if !terminatingOldInstancePIDs.isEmpty {
                restoreHardware()
                return
            }
        }

        if !isAnyPreview && !isShowingOnboarding && !hasStartedWorkSession {
            if hasPhysicalInputSinceBaseline(now: now, idleTime: idleTime) {
                hasStartedWorkSession = true
                clock.reset(startingAt: now)
            }
        }

        let recovered = clock.tick(
            now: now,
            idleTime: idleTime
        )
        if recovered {
            pointerController.resetSafetyLockout()
            hidAccelerationController.resetSafetyLockout()
            CometModel.shared.clear()
            needsFinalClear = true
            hasShownBreakReminder = false
            lastProgressReminderMark = 0
            pendingRecoveryNotice = true
            breakReminder.hide()
        }
        let progressMark = ReminderSchedule.progressMark(
            elapsed: clock.elapsed,
            workInterval: clock.interval
        )
        if progressMark > lastProgressReminderMark {
            lastProgressReminderMark = progressMark
            breakReminder.showProgress(remaining: clock.remaining)
        }
        if clock.elapsed >= clock.interval {
            let remaining = clock.breakRemaining(now: now, idleTime: idleTime)
            if hasShownBreakReminder {
                breakReminder.update(remaining: remaining)
            } else {
                hasShownBreakReminder = true
                breakReminder.showBreak(remaining: remaining) { [weak self] in
                    self?.quitApplication()
                }
            }
        }

        let weightingMode = CursorWeightingPolicy.mode(
            isUIPreview: isUIPreview,
            isOnBreak: clock.isOnBreak,
            isAccessibilityTrusted: pointerController.isTrusted,
            weight: clock.weight,
            isPhysicalWeightingEnabled: physicalWeightingEnabled && !sessionSafetyDisabled
        )

        // The ordering here is a safety invariant: restore the outgoing
        // implementation before enabling the incoming one. The old dual-path
        // behavior compounded both gains and could pin the pointer at zero.
        switch weightingMode {
        case .software:
            let restored = hidAccelerationController.restore()
            let watchdogStopped = restored && stopHIDRecoveryWatchdog()
            if restored, watchdogStopped, !sessionSafetyDisabled,
               !pointerController.isSafetyDisabled,
               !pointerTapIsActive {
                pointerTapIsActive = pointerController.start()
            } else if !restored || !watchdogStopped || sessionSafetyDisabled || pointerController.isSafetyDisabled {
                if pointerTapIsActive {
                    pointerController.stop()
                }
                pointerTapIsActive = false
            }
        case .hardware:
            if pointerTapIsActive {
                pointerController.stop()
            }
            pointerTapIsActive = false
            if hidAccelerationController.isSafetyDisabled {
                if hidAccelerationController.restore() {
                    stopHIDRecoveryWatchdog()
                }
            } else {
                hidAccelerationController.update(weight: clock.weight)
            }
        case .none:
            if pointerTapIsActive {
                pointerController.stop()
            }
            pointerTapIsActive = false
            if hidAccelerationController.restore() {
                stopHIDRecoveryWatchdog()
            }
        }

        if RecoveryNoticePolicy.shouldShow(pending: pendingRecoveryNotice,
            hardwareRestored: hidAccelerationController.lastRollbackSucceeded,
            hardwareActive: hidAccelerationController.isActive,
            softwareActive: pointerTapIsActive, watchdogRunning: hidRecoveryWatchdog.isRunning) {
            pendingRecoveryNotice = false
            breakReminder.showRecovered()
        }
        settingsSummary?.stringValue = statusText
        settingsPrimaryButton?.title = settingsPrimaryTitle
        recordDiagnosticState()
    }

    private var pointerTapIsActive = false

    /// Visual feedback starts subtly with the first real input and remains at
    /// full strength during the break. This is independent from Accessibility
    /// permission; only the stronger software pointer transform needs it.
    private var activeVisualWeight: CGFloat {
        guard hasStartedWorkSession, !clock.isAway else { return 0 }
        return WeightCurve.visualWeight(elapsed: clock.elapsed, interval: clock.interval)
    }

    private func renderTick() {
        let weight = activeVisualWeight
        if weight > 0.005 {
            CometModel.shared.tick(weight: weight, now: CACurrentMediaTime())
        } else if !CometModel.shared.points.isEmpty {
            CometModel.shared.clear()
            needsFinalClear = true
        }

        if !CometModel.shared.points.isEmpty || needsFinalClear {
            needsFinalClear = !CometModel.shared.points.isEmpty
            overlayWindows.forEach { $0.contentView?.needsDisplay = true }
        }
    }

    /// Returns the time since the last physical keyboard or pointing-device
    /// event. We deliberately read the HID state instead of the combined
    /// session state: the latter can include events posted by applications or
    /// accessibility tools. A window repaint, notification, or a new WeChat
    /// message is not user input and must not make the cursor heavy again.
    private static func secondsSinceLastInput(includeMouseMovement: Bool = true) -> TimeInterval {
        var physicalInputTypes: [CGEventType] = [
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel, .keyDown,
        ]
        if includeMouseMovement {
            physicalInputTypes.insert(.mouseMoved, at: 0)
        }
        return physicalInputTypes.map {
            CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0)
        }.min() ?? .greatestFiniteMagnitude
    }

    /// Returns inactivity based on physical input only. While the pointer
    /// weighting event tap is active, the app deliberately excludes the
    /// global mouseMoved HID clock: warping the cursor to apply resistance can
    /// update that clock without any user movement. The event tap timestamp
    /// tracks the actual pointer events delivered to the app instead.
    private func currentIdleTime() -> TimeInterval {
        let hidIdle = Self.secondsSinceLastInput(includeMouseMovement: !pointerTapIsActive)
        guard pointerTapIsActive,
              let lastPointerInput = pointerController.lastPhysicalInputUptime else {
            return hidIdle
        }
        let pointerIdle = max(0, ProcessInfo.processInfo.systemUptime - lastPointerInput)
        return min(hidIdle, pointerIdle)
    }

    private func hasPhysicalInputSinceBaseline(now: TimeInterval, idleTime: TimeInterval) -> Bool {
        // If the machine has already been idle for a complete configured break
        // duration, do not treat an input that happened before launch as the
        // beginning of a new work session. The next fresh input will start it.
        guard idleTime.isFinite, idleTime < selectedBreakDuration else { return false }
        let lastInputUptime = now - max(0, idleTime)
        // A strict baseline keeps clicks used to finish onboarding or reset
        // the session from accidentally starting the next work interval.
        return lastInputUptime > sessionInputBaselineUptime
    }

    @objc private func screensChanged() {
        rebuildOverlayWindows()
        breakReminder.screenConfigurationChanged()
    }

    private func rebuildOverlayWindows() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()

        for screen in NSScreen.screens {
            let drawingFrame = screen.visibleFrame
            let window = NSWindow(
                contentRect: drawingFrame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            // Keep the comet above ordinary app windows but below the system
            // menu bar. A screen-saver-level full-screen window hides menu bar
            // items even when the window itself is transparent.
            window.level = .floating
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isReleasedWhenClosed = false
            window.setAccessibilityElement(false)

            let view = CometView(frame: NSRect(origin: .zero, size: drawingFrame.size))
            view.setAccessibilityElement(false)
            view.screenOrigin = drawingFrame.origin
            view.weightProvider = { [weak self] in self?.activeVisualWeight ?? 0 }
            window.contentView = view
            window.orderFrontRegardless()
            overlayWindows.append(window)
        }
    }

    private func setUpMenuBarIcon() {
        guard !isUIPreview else { return }

        // A genuine status item reserves its own menu-bar slot. The previous
        // floating panel could overlap the clock or another app because macOS
        // did not know it occupied menu-bar space.
        // Use a fixed, slightly wider slot instead of squareLength. On some
        // macOS menu-bar layouts a square item with a custom raster image is
        // compressed to zero width when the bar recalculates its contents.
        let item = NSStatusBar.system.statusItem(withLength: 26)
        item.isVisible = true
        if let button = item.button {
            let image = HeavyCursorIconRenderer.makeImage(size: NSSize(width: 20, height: 20))
            image.isTemplate = false
            image.size = NSSize(width: 20, height: 20)
            button.image = image
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            button.frame = NSRect(x: 0, y: 0, width: 26, height: 22)
            button.wantsLayer = true
            button.toolTip = "Gravtail · 点击打开设置"
            button.setAccessibilityLabel("打开 Gravtail 设置")
            button.setAccessibilityHelp("打开 Gravtail 工作、休息和退出选项")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if hidAccelerationController.compatibility != .available {
            let compatibility = NSMenuItem(
                title: hidAccelerationController.compatibility.userFacingDescription,
                action: nil,
                keyEquivalent: ""
            )
            compatibility.isEnabled = false
            menu.addItem(compatibility)
        }
        menu.addItem(.separator())

        if isAnyPreview {
            if !pointerController.isTrusted {
                let permission = NSMenuItem(
                    title: "开启鼠标加重…",
                    action: #selector(enablePermission),
                    keyEquivalent: ""
                )
                permission.target = self
                menu.addItem(permission)
                menu.addItem(.separator())
            }
            menu.addItem(NSMenuItem(
                title: "退出预览",
                action: #selector(quitApplication),
                keyEquivalent: "q"
            ))
            menu.items.last?.target = self
            return
        }

        let workMenu = NSMenu()
        for minutes in [45, 60, 90] {
            let item = NSMenuItem(
                title: "\(minutes) 分钟",
                action: #selector(selectInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = minutes
            item.state = Int(clock.interval / 60) == minutes ? .on : .off
            workMenu.addItem(item)
        }
        let workItem = NSMenuItem(title: "工作时长", action: nil, keyEquivalent: "")
        workItem.submenu = workMenu
        menu.addItem(workItem)

        let breakMenu = NSMenu()
        for minutes in [3, 5, 10] {
            let item = NSMenuItem(
                title: "\(minutes) 分钟",
                action: #selector(selectBreakDuration(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = minutes
            item.state = Int(clock.breakDuration / 60) == minutes ? .on : .off
            breakMenu.addItem(item)
        }
        let breakItem = NSMenuItem(title: "休息时长", action: nil, keyEquivalent: "")
        breakItem.submenu = breakMenu
        menu.addItem(breakItem)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let toggle = NSMenuItem(title: physicalWeightingEnabled ? "关闭鼠标加重" : "开启鼠标加重…",
                                action: #selector(toggleWeighting), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())
        let reset = NSMenuItem(title: "重置本轮", action: #selector(resetSession), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        if physicalWeightingEnabled && !pointerController.isTrusted {
            menu.addItem(.separator())
            let permission = NSMenuItem(
                title: "授予辅助功能权限…",
                action: #selector(enablePermission),
                keyEquivalent: ""
            )
            permission.target = self
            menu.addItem(permission)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Gravtail", action: #selector(quitApplication), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private var statusText: String {
        if isUIPreview {
            return "仅预览界面 · 鼠标加重未开启"
        }
        if !hidAccelerationController.lastRollbackSucceeded {
            return "正在尝试恢复鼠标 · 请勿重新开启加重"
        }
        if sessionSafetyDisabled { return "检测到运行异常 · 加重已停用，可重置后重试" }
        if !physicalWeightingEnabled {
            if clock.isAway { return "休息完成 · 鼠标加重未开启" }
            return "仅彗尾和提醒 · 鼠标加重未开启"
        }
        if !pointerController.isTrusted {
            if !hasStartedWorkSession {
                return "需要辅助功能权限 · 点击“去授权鼠标加重”"
            }
            if clock.isOnBreak {
                let now = ProcessInfo.processInfo.systemUptime
                let effect: String
                if hidAccelerationController.compatibility != .available {
                    effect = "当前设备仅支持彗尾"
                } else {
                    effect = hidAccelerationController.isActive ? "硬件加重" : "仅彗尾效果"
                }
                return "休息中 · \(Self.format(clock.breakRemaining(now: now, idleTime: currentIdleTime()))) · \(effect)"
            }
            let minutes = max(1, Int(ceil(clock.remaining / 60)))
            let effect = hidAccelerationController.isActive ? "硬件加重" : "彗尾已开启"
            return "距离起身还有 \(minutes) 分钟 · \(effect) · 强加重未开启"
        }
        if !hasStartedWorkSession {
            return "已准备好 · 第一次键鼠输入后开始计时"
        }
        if isFortyFiveMinutePreview {
            if clock.isAway {
                return "休息完成 · 移动鼠标开始新一轮"
            }
            if clock.elapsed >= clock.interval {
                return hidAccelerationController.isActive
                    ? "该起身了 · 鼠标加重"
                    : "该起身了 · 仅彗尾效果"
            }
            return "45 分钟预览 · 正在变重"
        }
        if clock.isAway { return "休息完成 · 移动鼠标开始新一轮" }
        if clock.isOnBreak {
            let now = ProcessInfo.processInfo.systemUptime
            let effect: String
            if hidAccelerationController.compatibility != .available {
                effect = "仅彗尾 · 当前设备不支持加重"
            } else if hidAccelerationController.isSafetyDisabled {
                effect = "加重已安全停用"
            } else {
                effect = hidAccelerationController.isActive ? "鼠标加重" : "鼠标正常"
            }
            return "休息中 · \(Self.format(clock.breakRemaining(now: now, idleTime: currentIdleTime()))) · \(effect)"
        }
        if pointerController.isSafetyDisabled {
            return "软件加重已安全停用 · 重置本轮后重试"
        }
        if clock.remaining <= 0 {
            let now = ProcessInfo.processInfo.systemUptime
            let effect: String
            if !pointerTapIsActive {
                effect = " · 仅彗尾效果"
            } else if hidAccelerationController.isActive {
                effect = " · 鼠标加重"
            } else {
                effect = " · 软件加重"
            }
            return "该起身了 · \(Self.format(clock.breakRemaining(now: now, idleTime: currentIdleTime())))\(effect)"
        }
        let minutes = max(1, Int(ceil(clock.remaining / 60)))
        return "距离起身还有 \(minutes) 分钟"
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        selectedInterval = TimeInterval(minutes * 60)
        clock.interval = selectedInterval
        resetSession()
    }

    @objc private func selectBreakDuration(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        selectedBreakDuration = TimeInterval(minutes * 60)
        clock.breakDuration = selectedBreakDuration
        resetSession()
    }

    @objc private func resetSession() {
        // Resetting from the menu can happen while the event tap is active.
        // Restore synchronously so the next pointer event is never processed
        // by a stale weighting transform.
        let restored = restoreHardware()
        sessionSafetyDisabled = !restored
        pointerController.resetSafetyLockout()
        hidAccelerationController.resetSafetyLockout()
        hasStartedWorkSession = false
        clock.reset(startingAt: nil)
        sessionInputBaselineUptime = ProcessInfo.processInfo.systemUptime
        CometModel.shared.clear()
        needsFinalClear = true
        hasShownBreakReminder = false
        pendingRecoveryNotice = false
        lastProgressReminderMark = 0
        breakReminder.hide()
    }

    @objc private func enablePermission() {
        physicalWeightingEnabled = true
        DiagnosticLog.shared.record("permission-request", fields: [
            "accessibility": pointerController.isTrusted ? "trusted" : "not-trusted",
        ])
        pointerController.requestPermission()
    }

    private var settingsPrimaryTitle: String {
        if !physicalWeightingEnabled { return "开启鼠标加重…" }
        return pointerController.isTrusted ? "开始使用" : "去授权鼠标加重…"
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return false
    }

    @objc private func toggleWeighting() {
        if physicalWeightingEnabled {
            physicalWeightingEnabled = false
            restoreHardware()
        } else {
            enablePermission()
        }
        if settingsWindow?.isVisible == true { showSettingsWindow() }
    }

    @objc private func settingsPrimaryAction() {
        if !physicalWeightingEnabled {
            physicalWeightingEnabled = true
        }
        guard pointerController.isTrusted else {
            enablePermission()
            settingsSummary?.stringValue = "请在系统设置中打开 Gravtail 的辅助功能权限，然后回到这里点击“开始使用”。"
            settingsPrimaryButton?.title = settingsPrimaryTitle
            return
        }

        // The session still begins on the next real keyboard/mouse input. This
        // keeps opening or clicking Settings from consuming work time.
        settings.set(true, forKey: "hasCompletedOnboarding")
        sessionInputBaselineUptime = ProcessInfo.processInfo.systemUptime
        settingsWindow?.orderOut(nil)
    }

    @objc private func changeWorkSetting(_ sender: NSPopUpButton) {
        selectedInterval = TimeInterval([45, 60, 90][sender.indexOfSelectedItem] * 60)
        clock.interval = selectedInterval
        resetSession()
    }

    @objc private func changeBreakSetting(_ sender: NSPopUpButton) {
        selectedBreakDuration = TimeInterval([3, 5, 10][sender.indexOfSelectedItem] * 60)
        clock.breakDuration = selectedBreakDuration
        resetSession()
    }

    @objc private func showSettingsWindow() {
        let window = settingsWindow ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 310),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        if settingsWindow == nil { window.center() }
        window.title = "Gravtail 设置"
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 310))
        let summary = NSTextField(wrappingLabelWithString: statusText)
        summary.frame = NSRect(x: 24, y: 246, width: 372, height: 44)
        content.addSubview(summary)
        settingsSummary = summary
        for (row, title, values, selected, action) in [
            (0, "工作时长", [45, 60, 90], Int(selectedInterval / 60), #selector(changeWorkSetting(_:))),
            (1, "休息时长", [3, 5, 10], Int(selectedBreakDuration / 60), #selector(changeBreakSetting(_:)))
        ] {
            let y = CGFloat(205 - row * 36)
            let label = NSTextField(labelWithString: title)
            label.frame = NSRect(x: 24, y: y, width: 100, height: 24)
            content.addSubview(label)
            let popup = NSPopUpButton(frame: NSRect(x: 166, y: y, width: 170, height: 26))
            popup.addItems(withTitles: values.map { "\($0) 分钟" })
            popup.selectItem(at: values.firstIndex(of: selected) ?? 0)
            popup.target = self
            popup.action = action
            content.addSubview(popup)
        }
        let toggle = NSButton(checkboxWithTitle: "启用鼠标加重（关闭后保留彗尾和提醒）",
                              target: self, action: #selector(toggleWeighting))
        toggle.state = physicalWeightingEnabled ? .on : .off
        toggle.frame = NSRect(x: 24, y: 131, width: 372, height: 24)
        content.addSubview(toggle)

        let primary = NSButton(title: settingsPrimaryTitle, target: self, action: #selector(settingsPrimaryAction))
        primary.frame = NSRect(x: 110, y: 76, width: 200, height: 34)
        primary.bezelStyle = .rounded
        primary.keyEquivalent = "\r"
        content.addSubview(primary)
        settingsPrimaryButton = primary

        for (x, title, action) in [
            (24, "重置本轮", #selector(resetSession)),
            (271, "退出 Gravtail", #selector(quitApplication))
        ] {
            let button = NSButton(title: title, target: self, action: action)
            button.frame = NSRect(x: x, y: 22, width: 125, height: 32)
            button.bezelStyle = .rounded
            content.addSubview(button)
        }
        window.contentView = content
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApplication() {
        restoreHardware()
        NSApp.terminate(nil)
    }

    private func startPointerWeightIfPossible() {
        let mode = CursorWeightingPolicy.mode(
            isUIPreview: isUIPreview,
            isOnBreak: clock.isOnBreak,
            isAccessibilityTrusted: pointerController.isTrusted,
            weight: clock.weight,
            isPhysicalWeightingEnabled: physicalWeightingEnabled && !sessionSafetyDisabled
        )
        guard mode == .software else {
            pointerTapIsActive = false
            return
        }
        pointerTapIsActive = pointerController.start()
    }

    private func recordDiagnosticState() {
        let phase: String
        if !hasStartedWorkSession {
            phase = "waiting-for-input"
        } else if clock.isAway {
            phase = "away"
        } else if clock.isOnBreak {
            phase = "break"
        } else if clock.weight > HeavyCursorConstants.pointerTapActivationWeight {
            phase = "weighting"
        } else {
            phase = "early-work"
        }

        let state = [
            phase,
            pointerController.isTrusted ? "trusted" : "not-trusted",
            pointerTapIsActive ? "tap-on" : "tap-off",
            hidAccelerationController.isActive ? "hid-on" : "hid-off",
            pointerController.isSafetyDisabled ? "tap-safe-off" : "tap-ready",
            hidAccelerationController.isSafetyDisabled ? "hid-safe-off" : "hid-ready",
            hidAccelerationController.compatibility.rawValue,
        ].joined(separator: "|")
        guard state != lastDiagnosticState else { return }
        lastDiagnosticState = state
        DiagnosticLog.shared.record("state", fields: [
            "phase": phase,
            "accessibility": pointerController.isTrusted ? "trusted" : "not-trusted",
            "eventTap": pointerTapIsActive ? "active" : "inactive",
            "hid": hidAccelerationController.isActive ? "active" : "inactive",
            "eventTapSafety": pointerController.isSafetyDisabled ? "disabled" : "ready",
            "hidSafety": hidAccelerationController.isSafetyDisabled ? "disabled" : "ready",
            "hidCompatibility": hidAccelerationController.compatibility.rawValue,
            "elapsedSeconds": String(Int(clock.elapsed)),
            "physicalWeight": String(format: "%.3f", Double(clock.weight)),
            "visualWeight": String(format: "%.3f", Double(activeVisualWeight)),
        ])
    }

    private static func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(ceil(interval)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

if let watchdogIndex = ProcessInfo.processInfo.arguments.firstIndex(of: "--hid-watchdog"),
   ProcessInfo.processInfo.arguments.indices.contains(watchdogIndex + 3) {
    let arguments = ProcessInfo.processInfo.arguments
    guard let parentPID = Int32(arguments[watchdogIndex + 1]), parentPID > 1 else {
        exit(2)
    }
    let mouse = Double(arguments[watchdogIndex + 2])
    let trackpad = Double(arguments[watchdogIndex + 3])

    let controller = HIDAccelerationController(restoreOrphanedBackup: false)
    let result = RecoveryWatchdog.run(parentPID: parentPID) {
        let restored = controller.restoreKnownValues(mouse: mouse, trackpad: trackpad)
        _ = CGAssociateMouseAndMouseCursorPosition(1)
        return restored
    }
    DiagnosticLog.shared.record(
        result == 0 ? "hid-watchdog-stopped" : (result == 70 ? "hid-watchdog-restored" : "hid-watchdog-restore-failed"),
        fields: ["parentPID": String(parentPID)]
    )
    exit(result)
} else if ProcessInfo.processInfo.arguments.contains("--check-accessibility") {
    print(AXIsProcessTrusted() ? "trusted" : "not-trusted")
} else if ProcessInfo.processInfo.arguments.contains("--check-hid") {
    // Diagnostics must be read-only; normal app launches still restore an
    // orphaned backup automatically.
    let controller = HIDAccelerationController(restoreOrphanedBackup: false)
    let values = controller.currentValues()
    let mouseText = values.mouse.map { String($0) } ?? "unavailable"
    let trackpadText = values.trackpad.map { String($0) } ?? "unavailable"
    print("compatibility=\(controller.compatibility.rawValue)")
    print("mouse=\(mouseText)")
    print("trackpad=\(trackpadText)")
} else if ProcessInfo.processInfo.arguments.contains("--restore-hid") {
    let controller = HIDAccelerationController()
    let restored = controller.didRestoreOrphanedBackup
    _ = CGAssociateMouseAndMouseCursorPosition(1)
    if restored {
        print("HID acceleration restored from saved backup")
    } else if controller.hadOrphanedBackup {
        fputs("Saved HID backup could not be restored\n", stderr)
        exit(1)
    } else {
        print("No saved HID backup; values unchanged")
    }
} else if let recoveryIndex = ProcessInfo.processInfo.arguments.firstIndex(of: "--restore-known-hid"),
          ProcessInfo.processInfo.arguments.indices.contains(recoveryIndex + 1),
          let value = Double(ProcessInfo.processInfo.arguments[recoveryIndex + 1]) {
    let controller = HIDAccelerationController(restoreOrphanedBackup: false)
    guard controller.restoreKnownValues(mouse: value, trackpad: value) else {
        fputs("Known HID value could not be restored\n", stderr)
        exit(1)
    }
    _ = CGAssociateMouseAndMouseCursorPosition(1)
    print("HID acceleration restored to \(value)")
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
