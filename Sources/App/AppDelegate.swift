import AppKit
import SwiftUI
import Combine

/// A floating panel that can become the key window so text fields receive input.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var service: TodoService!
    var statusItem: NSStatusItem!
    var panel: NSPanel!
    private var hostingView: NSHostingView<ContentView>!
    private var flushTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private let panelSize = NSSize(width: 360, height: 540)
    private var savedExpandedFrame: NSRect?
    /// Mini pill origin relative to expanded panel (preserved when user drags the expanded window).
    private var savedMiniOffsetInExpanded: NSPoint?
    private var isMiniCollapsed = false
    private var miniFloatTimer: Timer?
    private var miniFloatSuppressUntil: Date?
    private var miniFloatMouseMonitor: Any?
    private var miniFloatMouseDownLocation: NSPoint?
    /// Only collapse after the pointer has entered the panel (avoids instant collapse when opening from the menu bar).
    private var miniFloatMouseWasInside = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        let override = UserDefaults.standard.string(forKey: "repoPathOverride") ?? ""
        if let repoPath = WeekStore.resolveRepoPath(override: override),
           let store = try? WeekStore(repoPath: repoPath),
           let svc = try? TodoService(store: store) {
            service = svc
            setupPanel()
            startFlushTimer()
            observePanelHeight()
            subscribeService()
            updateStatusItem()
        } else {
            setupSetupPanel()
        }
    }

    /// Repo path: user override first, otherwise auto-detect.
    private static func effectiveRepoPath() -> String? {
        let override = UserDefaults.standard.string(forKey: "repoPathOverride") ?? ""
        return WeekStore.resolveRepoPath(override: override)
    }

    /// Subscribe to service state (always-on-top, status item, path changes).
    private func subscribeService() {
        cancellables.removeAll()
        Task { @MainActor [weak self] in
            guard let self, let service = self.service else { return }
            self.panel.level = service.alwaysOnTop ? .floating : .normal
            service.$alwaysOnTop
                .sink { [weak self] onTop in
                    self?.panel.level = onTop ? .floating : .normal
                }
                .store(in: &self.cancellables)
            service.$appearanceMode
                .sink { [weak self] mode in
                    self?.applyAppearance(mode)
                }
                .store(in: &self.cancellables)
            service.$repoPathOverride
                .dropFirst()
                .sink { [weak self] _ in
                    self?.reloadServiceIfNeeded()
                }
                .store(in: &self.cancellables)
            service.$miniFloatEnabled
                .sink { [weak self] enabled in
                    self?.updateMiniFloatTimer(enabled: enabled)
                    if enabled, self?.panel.isVisible == true {
                        self?.collapseToMini()
                    } else if !enabled, self?.isMiniCollapsed == true {
                        self?.expandFromMini()
                    }
                }
                .store(in: &self.cancellables)
            service.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updateStatusItem()
                }
                .store(in: &self.cancellables)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.service?.refreshTodayIfNeeded()
            self?.updateStatusItem()
        }
    }

    /// Rebuild the service when the repo path changes (takes effect immediately); keep the old one and show an error on failure.
    private func reloadServiceIfNeeded() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let override = self.service.repoPathOverride
            guard let repoPath = WeekStore.resolveRepoPath(override: override) else {
                self.service.lastError = I18n.t("仓库路径无效，已保持原路径", "Invalid repo path; kept the previous one")
                return
            }
            guard let newStore = try? WeekStore(repoPath: repoPath),
                  let newService = try? TodoService(store: newStore) else {
                self.service.lastError = I18n.t("无法打开该仓库路径，已保持原路径", "Cannot open that repo path; kept the previous one")
                return
            }
            self.service = newService
            self.hostingView = NSHostingView(rootView: ContentView(service: newService))
            self.hostingView.autoresizingMask = [.width, .height]
            self.hostingView.frame = self.panel.contentView?.bounds ?? .zero
            self.panel.contentView = self.hostingView
            self.subscribeService()
            self.updateStatusItem()
        }
    }

    /// Apply the appearance mode to the window.
    private func applyAppearance(_ mode: AppearanceMode) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch mode {
            case .system: self.panel.appearance = nil
            case .light: self.panel.appearance = NSAppearance(named: .aqua)
            case .dark: self.panel.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    /// Update menu-bar icon color and duration text with clock state.
    private func updateStatusItem() {
        guard let button = statusItem?.button, let service else { return }
        Task { @MainActor in
            let symbol = WorkStatusSymbol.name(
                isWorking: service.isWorking,
                clockedOut: service.clockOutTime != nil
            )
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            if let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "TodoPanel") {
                button.image = base.withSymbolConfiguration(config) ?? base
                button.image?.isTemplate = true
            }
            button.imagePosition = .imageLeading
            if service.isWorking {
                button.title = " \(service.workedHoursText)"
                button.contentTintColor = .systemGreen
            } else if service.clockOutTime != nil {
                button.title = ""
                button.contentTintColor = .systemOrange
            } else {
                button.title = ""
                button.contentTintColor = nil
            }
        }
    }

    private func observePanelHeight() {
        NotificationCenter.default.addObserver(
            forName: .panelContentHeightChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let height = note.userInfo?["height"] as? CGFloat else { return }
            Task { @MainActor [weak self] in
                self?.resizePanelToFit(contentHeight: height)
            }
        }
    }

    /// Resize the window to fit content on collapse/expand, keeping the top edge fixed.
    @MainActor
    private func resizePanelToFit(contentHeight: CGFloat) {
        guard let panel, panel.isVisible, !isMiniCollapsed else { return }
        guard service?.miniFloatEnabled != true else { return }
        let chrome: CGFloat = 150
        let minH: CGFloat = 360
        let maxH = min(NSScreen.main?.visibleFrame.height ?? 800, 760)
        let target = min(max(contentHeight + chrome, minH), maxH)
        let current = panel.frame.height
        guard abs(target - current) > 2 else { return }
        let oldFrame = panel.frame
        var newFrame = oldFrame
        newFrame.size.height = target
        newFrame.origin.y = oldFrame.maxY - target
        panel.setFrame(newFrame, display: true, animate: false)
        if !isMiniCollapsed {
            savedExpandedFrame = panel.frame
        }
    }

    private func updateMiniFloatTimer(enabled: Bool) {
        miniFloatTimer?.invalidate()
        miniFloatTimer = nil
        if let monitor = miniFloatMouseMonitor {
            NSEvent.removeMonitor(monitor)
            miniFloatMouseMonitor = nil
        }
        miniFloatMouseDownLocation = nil
        guard enabled else { return }
        miniFloatTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickMiniFloatLeave()
            }
        }
        RunLoop.main.add(miniFloatTimer!, forMode: .common)
        miniFloatMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMiniFloatClick(event)
            }
            return event
        }
    }

    @MainActor
    private func handleMiniFloatClick(_ event: NSEvent) {
        guard let panel, let service, service.miniFloatEnabled, panel.isVisible, isMiniCollapsed else { return }
        let loc = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            if panel.frame.contains(loc) {
                miniFloatMouseDownLocation = loc
            }
        case .leftMouseUp:
            guard let down = miniFloatMouseDownLocation else { return }
            miniFloatMouseDownLocation = nil
            let dx = loc.x - down.x
            let dy = loc.y - down.y
            if dx * dx + dy * dy < 25, panel.frame.contains(loc) {
                expandFromMini()
            }
        default:
            break
        }
    }

    @MainActor
    private func tickMiniFloatLeave() {
        guard let panel, let service, service.miniFloatEnabled, panel.isVisible else { return }
        let inside = panel.frame.contains(NSEvent.mouseLocation)
        if inside {
            miniFloatMouseWasInside = true
            return
        }
        guard miniFloatMouseWasInside, !isMiniCollapsed else { return }
        if let until = miniFloatSuppressUntil, Date() < until { return }
        miniFloatMouseWasInside = false
        collapseToMini()
    }

    private func updatePanelMinSize(mini: Bool, expanded: Bool) {
        guard let panel else { return }
        if mini && !expanded {
            panel.minSize = MiniFloatLayout.size
        } else {
            panel.minSize = NSSize(width: 320, height: 360)
        }
    }

    @MainActor
    private func collapseToMini() {
        guard let panel, let service, service.miniFloatEnabled, !isMiniCollapsed else { return }
        savedExpandedFrame = panel.frame
        var frame = miniFrameFromExpanded(panel.frame)
        clampFrameToVisibleScreen(&frame)

        updatePanelMinSize(mini: true, expanded: false)
        service.setPanelExpanded(false)
        hostingView.needsLayout = true
        hostingView.layoutSubtreeIfNeeded()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            ctx.allowsImplicitAnimation = false
            panel.setFrame(frame, display: true, animate: false)
        }

        isMiniCollapsed = true
        miniFloatMouseWasInside = false
    }

    private func miniFrameFromExpanded(_ expanded: NSRect) -> NSRect {
        let mini = MiniFloatLayout.size
        var frame = NSRect(origin: .zero, size: mini)
        if let offset = savedMiniOffsetInExpanded {
            frame.origin.x = expanded.origin.x + offset.x
            frame.origin.y = expanded.origin.y + offset.y
        } else {
            frame.origin.x = expanded.midX - mini.width / 2
            frame.origin.y = expanded.maxY - mini.height
        }
        return frame
    }

    @MainActor
    private func expandFromMini() {
        guard let panel, let service, isMiniCollapsed else { return }
        let miniFrame = panel.frame
        let size = savedExpandedFrame?.size ?? panelSize
        let frame = expandedFrame(containing: miniFrame, size: size)

        updatePanelMinSize(mini: true, expanded: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            ctx.allowsImplicitAnimation = false
            panel.setFrame(frame, display: true, animate: false)
        }

        savedMiniOffsetInExpanded = NSPoint(
            x: miniFrame.origin.x - frame.origin.x,
            y: miniFrame.origin.y - frame.origin.y
        )
        isMiniCollapsed = false
        miniFloatMouseWasInside = true
        savedExpandedFrame = panel.frame
        miniFloatSuppressUntil = Date().addingTimeInterval(0.25)
        service.setPanelExpanded(true)
    }

    /// Place the expanded panel so it stays on screen and still covers the mini pill (mouse stays inside).
    private func expandedFrame(containing miniFrame: NSRect, size: NSSize) -> NSRect {
        var frame = NSRect(
            x: miniFrame.midX - size.width / 2,
            y: miniFrame.origin.y + miniFrame.height - size.height,
            width: size.width,
            height: size.height
        )
        clampFrameToVisibleScreen(&frame)
        nudgeFrameToContain(&frame, miniFrame)
        clampFrameToVisibleScreen(&frame)
        return frame
    }

    private func nudgeFrameToContain(_ frame: inout NSRect, _ inner: NSRect) {
        if inner.maxX > frame.maxX {
            frame.origin.x = inner.maxX - frame.width
        }
        if inner.minX < frame.minX {
            frame.origin.x = inner.minX
        }
        if inner.minY < frame.minY {
            frame.origin.y = inner.minY
        }
        if inner.maxY > frame.maxY {
            frame.origin.y = inner.maxY - frame.height
        }
    }

    private func clampFrameToVisibleScreen(_ frame: inout NSRect) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width - 8 }
        if frame.minX < visible.minX { frame.origin.x = visible.minX + 8 }
        if frame.minY < visible.minY { frame.origin.y = visible.minY + 8 }
        if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height - 8 }
    }

    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.service.flushPush()
            }
        }
        let refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.service?.refreshTodayIfNeeded()
                self?.service?.refreshPendingCount()
                self?.updateStatusItem()
            }
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        flushTimer?.invalidate()
        miniFloatTimer?.invalidate()
        if let monitor = miniFloatMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        service?.shutdown()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setupPanel() {
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                              styleMask: [.titled, .resizable, .nonactivatingPanel, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 320, height: 360)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        hostingView = NSHostingView(rootView: ContentView(service: service))
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
    }

    @objc func togglePanel() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.panel.isVisible {
                self.panel.orderOut(nil)
                self.isMiniCollapsed = false
                self.miniFloatMouseWasInside = false
            } else {
                self.savedMiniOffsetInExpanded = nil
                if self.service.miniFloatEnabled {
                    self.service.setPanelExpanded(true)
                    self.miniFloatMouseWasInside = false
                    self.miniFloatSuppressUntil = Date().addingTimeInterval(0.5)
                }
                self.positionPanel()
                self.panel.makeKeyAndOrderFront(nil)
                self.panel.makeFirstResponder(nil)
                self.updatePanelMinSize(mini: self.service.miniFloatEnabled, expanded: !self.isMiniCollapsed)
            }
        }
    }

    @MainActor
    private func positionPanel() {
        guard let button = statusItem.button, let screen = NSScreen.main else {
            panel.center()
            return
        }
        let btnFrame = button.window?.frame ?? NSRect(x: screen.visibleFrame.maxX, y: screen.visibleFrame.maxY, width: 0, height: 0)
        let mini = service?.miniFloatEnabled == true && service?.panelExpanded == false
        let size = mini ? MiniFloatLayout.size : panelSize
        var origin = NSPoint(x: btnFrame.midX - size.width / 2, y: btnFrame.minY - size.height - 6)
        if origin.x + size.width > screen.visibleFrame.maxX {
            origin.x = screen.visibleFrame.maxX - size.width - 8
        }
        if origin.x < screen.visibleFrame.minX {
            origin.x = screen.visibleFrame.minX + 8
        }
        if origin.y < screen.visibleFrame.minY {
            origin.y = screen.visibleFrame.minY + 8
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        isMiniCollapsed = mini
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    /// Show the repo-path setup screen when no repo is found.
    private func setupSetupPanel() {
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: 380, height: 220)),
                              styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let hosting = NSHostingView(rootView: SetupView(onComplete: { [weak self] in
            self?.finishSetup()
        }))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.center()
            self.panel.makeKeyAndOrderFront(nil)
            self.panel.makeFirstResponder(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Setup complete: switch to the normal UI in place (no process relaunch).
    private func finishSetup() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let override = UserDefaults.standard.string(forKey: "repoPathOverride") ?? ""
            guard let repoPath = WeekStore.resolveRepoPath(override: override),
                  let store = try? WeekStore(repoPath: repoPath),
                  let svc = try? TodoService(store: store) else {
                return
            }
            self.service = svc
            self.hostingView = NSHostingView(rootView: ContentView(service: svc))
            self.hostingView.autoresizingMask = [.width, .height]
            self.hostingView.frame = self.panel.contentView?.bounds ?? .zero
            self.panel.contentView = self.hostingView
            self.panel.minSize = NSSize(width: 320, height: 360)
            self.panel.setFrame(NSRect(origin: self.panel.frame.origin, size: self.panelSize), display: true, animate: false)
            self.startFlushTimer()
            self.observePanelHeight()
            self.subscribeService()
            self.updateStatusItem()
        }
    }
}
