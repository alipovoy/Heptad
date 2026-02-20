import Cocoa
import SwiftUI
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusBarItem: NSStatusItem!
    var detachedWindow: NSWindow?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = self.statusBarItem.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "7Notes")
            button.action = #selector(toggleWindow(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
    
    @objc func toggleWindow(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit 7Notes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusBarItem.menu = menu
            statusBarItem.button?.performClick(nil)
            statusBarItem.menu = nil
        } else {
            if detachedWindow == nil || !detachedWindow!.isVisible {
                showNativeWindow(sender: sender)
            } else {
                detachedWindow?.orderOut(nil)
            }
        }
    }
    
    private func showNativeWindow(sender: NSStatusBarButton) {
        if detachedWindow == nil {
            let contentView = ContentView()
                .modelContainer(SevenNotesApp.sharedModelContainer)
            
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                backing: .buffered, defer: false)
            
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: contentView)
            
            self.detachedWindow = panel
        }
        
        guard let window = detachedWindow else { return }
        
        if sender.window?.screen != nil {
            let buttonRect = sender.window?.convertToScreen(sender.frame) ?? .zero
            let xPos = buttonRect.midX - (window.frame.width / 2)
            let yPos = buttonRect.minY - window.frame.height - 5
            
            window.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        }
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
