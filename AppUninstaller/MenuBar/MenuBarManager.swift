import SwiftUI
import AppKit

public enum MenuBarRoute {
    case overview
    case storage
    case memory
    case battery
    case cpu
    case network
}

class MenuBarManager: NSObject, ObservableObject {
    static let shared = MenuBarManager()
    
    var statusItem: NSStatusItem?
    var popoverWindow: MenuBarWindow?
    var detailWindow: MenuBarWindow?
    var memoryAlertController: MemoryAlertWindowController?
    private var mainAppWindow: NSWindow?
    private var windowCloseObserver: NSObjectProtocol?
    
    // Shared Source of Truth
    let systemMonitor = SystemMonitorService.shared
    
    @Published var isOpen: Bool = false
    @Published var currentDetailRoute: MenuBarRoute? = nil
    
    private var isSetupComplete = false
    private var isTerminating = false
    private var isClosing = false
    private var localMouseMonitor: Any?
    private var appResignObserver: NSObjectProtocol?

    override init() {
        super.init()
        DispatchQueue.main.async { [weak self] in
            self?.ensureSetup()
        }
    }

    /// Startup and reopen both restore the status item without duplicating windows or observers.
    func ensureSetup() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.ensureSetup() }
            return
        }
        guard !isTerminating else { return }
        guard NSApp != nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.ensureSetup()
            }
            return
        }
        guard setupStatusItem() else { return }
        if popoverWindow == nil {
            setupWindow()
        }
        if !isSetupComplete {
            setupAutoClose()
            isSetupComplete = true
        }
    }

    private func setupStatusItem() -> Bool {
        if statusItem?.button == nil {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "MacOptimizer.MenuBar"
            statusItem = item
        }
        guard let statusItem, let button = statusItem.button else { return false }

        // A dedicated template symbol remains legible at menu bar size.
        // The full-color app icon has an opaque background when rendered as a template.
        let icon = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "Mac优化大师")
        icon?.size = NSSize(width: 18, height: 18)
        icon?.isTemplate = true
        button.image = icon
        button.title = icon == nil ? "优" : ""
        button.toolTip = "Mac优化大师"
        button.setAccessibilityLabel("Mac优化大师")
        button.identifier = NSUserInterfaceItemIdentifier("MacOptimizer.MenuBar")
        button.action = #selector(toggleWindow)
        button.target = self
        statusItem.isVisible = true
        return true
    }

    private func setupWindow() {
        // Main Overview Window
        // Pass self as EnvironmentObject so Views can call showDetail/closeWindow
        let contentView = MenuBarView()
            .environmentObject(self)
            .environmentObject(systemMonitor)
            .edgesIgnoringSafeArea(.all)
        
        let hostingController = NSHostingController(rootView: contentView)
        let window = MenuBarWindow(contentViewController: hostingController)
        self.popoverWindow = window
        window.level = .floating
        window.setContentSize(NSSize(width: 430, height: 743))
        
        // 初始化内存警告控制器
        memoryAlertController = MemoryAlertWindowController(
            systemMonitor: systemMonitor,
            statusBarButton: statusItem?.button
        )
    }
    
    @objc func toggleWindow() {
        guard let _ = popoverWindow, let button = statusItem?.button else { return }
        
        if isOpen {
            closeWindow()
        } else {
            showWindow(relativeTo: button)
        }
    }
    
    private func showWindow(relativeTo button: NSStatusBarButton) {
        guard let window = popoverWindow else { return }

        isClosing = false
        systemMonitor.startMonitoring(client: "menuBar")
        DiskSpaceManager.shared.updateDiskSpace()
        
        // Position Logic
        let padding: CGFloat = 12
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = window.frame.size
            
            let xPos = screenFrame.maxX - windowSize.width - padding
            let yPos = screenFrame.maxY - windowSize.height - 5
            
            window.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        }
        
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        isOpen = true
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }
    
    func closeWindow() {
        guard !isClosing else { return }
        isClosing = true

        // Close Detail First
        closeDetail()
        
        guard let window = popoverWindow else {
            isClosing = false
            systemMonitor.stopMonitoring(client: "menuBar")
            return
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            self.isOpen = false
            self.isClosing = false
            self.systemMonitor.stopMonitoring(client: "menuBar")
        })
    }
    
    // MARK: - Detail Window Logic
    
    func showDetail(route: MenuBarRoute) {
        // If already open with same route, do nothing or maybe just bring to front
        if currentDetailRoute == route && detailWindow != nil { return }
        
        // Close existing detail if different
        if detailWindow != nil {
             // For smooth transition, maybe just update content?
             // But for now, let's close and reopen or just swap root view if possible.
             // Swapping controller is easier.
             updateDetailWindow(route: route)
             return
        }
        
        createAndShowDetailWindow(route: route)
    }
    
    func closeDetail() {
        guard let window = detailWindow else { return }
        currentDetailRoute = nil
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            self.detailWindow = nil
        })
    }
    
    private func createAndShowDetailWindow(route: MenuBarRoute) {
        let detailView = MenuBarDetailContainer(manager: self, systemMonitor: systemMonitor, route: route)
            .edgesIgnoringSafeArea(.all)
        
        let controller = NSHostingController(rootView: detailView)
        let window = MenuBarWindow(contentViewController: controller)
        self.detailWindow = window
        self.currentDetailRoute = route
        window.level = .floating
        
        // Position: Left of Main Window
        if let mainWindow = popoverWindow {
            let mainFrame = mainWindow.frame
            let gap: CGFloat = 10
            // We need to fetch size from content or set fixed size. 
            // MenuBarDetailContainer has .frame(width: 320, height: 500)
            let detailWidth: CGFloat = 360 
            let detailHeight: CGFloat = 620
            
            // Should align tops? usually.
            // Or center vertically relative to main window?
            // Modern macOS apps usually align top or keep them side-by-side cleanly.
            // Let's align Tops for better visual consistency.
            // Main window height is usually dynamic or ~600.
            
            let xPos = mainFrame.minX - detailWidth - gap
            // Align Tops
            let yPos = mainFrame.maxY - detailHeight
            
            window.setFrame(NSRect(x: xPos, y: yPos, width: detailWidth, height: detailHeight), display: true)
        }
        
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }
    
    private func updateDetailWindow(route: MenuBarRoute) {
        // Just replace the rootViewController
        guard let window = detailWindow else { return }
        
        let detailView = MenuBarDetailContainer(manager: self, systemMonitor: systemMonitor, route: route)
             .edgesIgnoringSafeArea(.all)
        let newController = NSHostingController(rootView: detailView)
        
        window.contentViewController = newController
        currentDetailRoute = route
    }
    
    // MARK: - Open Main App

    func registerMainWindow(_ window: NSWindow) {
        window.isReleasedWhenClosed = false
        mainAppWindow = window
        guard windowCloseObserver == nil else { return }
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow,
                  !(window is MenuBarWindow) else { return }
            // willClose arrives before the window has been ordered out.
            DispatchQueue.main.async { [weak self] in
                guard self != nil else { return }
                let hasVisibleWindow = NSApp.windows.contains {
                    !($0 is MenuBarWindow) && $0.styleMask.contains(.titled) && $0.isVisible
                }
                if !hasVisibleWindow {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    func removeStatusItem() {
        isTerminating = true
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let appResignObserver {
            NotificationCenter.default.removeObserver(appResignObserver)
            self.appResignObserver = nil
        }
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
            self.windowCloseObserver = nil
        }
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }
    
    func openMainApp(module: AppModule? = nil) {
        ensureSetup()
        NSApp.setActivationPolicy(.regular)
        if let module {
            AppNavigationController.shared.selectedModule = module
        }

        // Close menu bar windows
        closeWindow()

        if let mainAppWindow {
            mainAppWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Find and show the main window
        // The main app window usually exists if app is running.
        // We need to bring it to front or open it.
        
        // Option 1: Find existing window by looking for ContentView or similar
        for window in NSApp.windows {
            // Skip our own menu bar windows
            if window == popoverWindow || window == detailWindow {
                continue
            }
            
            // Look for the main app window (usually the one with title or specific content)
            if window.contentViewController != nil && window.isVisible == false {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            
            if window.contentViewController != nil {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
        
        // If no window found, just activate the app (it should open main window automatically)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// Custom NSWindow with auto-close logic
class MenuBarWindow: NSWindow {
    init(contentViewController: NSViewController) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView], 
            backing: .buffered,
            defer: false
        )
        
        self.contentViewController = contentViewController
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
    }
    
    override var canBecomeKey: Bool { return true }
    
    // Auto-close handler needs to be managed by Manager via delegate or notification
    // But let's keep it simple: MenuBarManager will subscribe to interruptions.
}

extension MenuBarManager {
    func setupAutoClose() {
        // Monitor global clicks to close if clicked outside
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isOpen else { return event }
            
            if let window = event.window, (window == self.popoverWindow || window == self.detailWindow) {
                // Clicked inside one of our windows, do nothing
                return event
            }
            
            // Clicked outside?
            // "transient" collectionBehavior handles some of this, but not perfectly for custom windows.
            // Actually, the main issue usually is focus.
            
            // Let's rely on standard popup behavior: if user clicks elsewhere, we close.
            // But we have TWO windows.
            
            self.closeWindow()
            return event
        }
        
        // Listen for App Deactivation (switching to another app)
        appResignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.closeWindow()
        }
    }
}
