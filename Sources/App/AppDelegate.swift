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
    private var statusIcon: NSImage?
    private let panelSize = NSSize(width: 360, height: 540)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        if let repoPath = Self.effectiveRepoPath(),
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
        if !override.isEmpty { return override }
        return RepoLocator.locate()
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
            service.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updateStatusItem()
                }
                .store(in: &self.cancellables)
        }
    }

    /// Rebuild the service when the repo path changes (takes effect immediately); keep the old one and show an error on failure.
    private func reloadServiceIfNeeded() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let repoPath = Self.effectiveRepoPath() else {
                self.service.lastError = "仓库路径无效，已保持原路径"
                return
            }
            guard let newStore = try? WeekStore(repoPath: repoPath),
                  let newService = try? TodoService(store: newStore) else {
                self.service.lastError = "无法打开该仓库路径，已保持原路径"
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
            button.image = statusIcon
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
            self?.resizePanelToFit(contentHeight: height)
        }
    }

    /// Resize the window to fit content on collapse/expand, keeping the top edge fixed.
    private func resizePanelToFit(contentHeight: CGFloat) {
        guard let panel, panel.isVisible else { return }
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
    }

    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.service.flushPush()
            }
        }
        let refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.service.refreshPendingCount()
                self?.updateStatusItem()
            }
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        flushTimer?.invalidate()
        service?.shutdown()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            statusIcon = NSImage(systemSymbolName: "checkmark.seal.fill", accessibilityDescription: nil)
            statusIcon?.isTemplate = true
            button.image = statusIcon
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
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(nil)
        }
    }

    private func positionPanel() {
        guard let button = statusItem.button, let screen = NSScreen.main else {
            panel.center()
            return
        }
        let btnFrame = button.window?.frame ?? NSRect(x: screen.visibleFrame.maxX, y: screen.visibleFrame.maxY, width: 0, height: 0)
        var origin = NSPoint(x: btnFrame.midX - panelSize.width / 2, y: btnFrame.minY - panelSize.height - 6)
        if origin.x + panelSize.width > screen.visibleFrame.maxX {
            origin.x = screen.visibleFrame.maxX - panelSize.width - 8
        }
        if origin.x < screen.visibleFrame.minX {
            origin.x = screen.visibleFrame.minX + 8
        }
        if origin.y < screen.visibleFrame.minY {
            origin.y = screen.visibleFrame.minY + 8
        }
        panel.setFrameOrigin(origin)
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
            guard let self,
                  let repoPath = Self.effectiveRepoPath(),
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
