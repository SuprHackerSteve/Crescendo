import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    let menuIcon = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    @objc func hideDockIcon(_ sender: Any?) {
        NSApp.setActivationPolicy(.accessory)
    }

    @objc func showDockIcon(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
    }

    @objc func showWindow(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func buildMenuBarMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Show App Window", action: #selector(showWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Run in Background", action: #selector(hideDockIcon), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Run in Dock", action: #selector(showDockIcon), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Quit Crescendo",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        menuIcon.menu = menu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenuBarMenu()

        if let button = menuIcon.button {
            button.image = NSImage(named: NSImage.Name("menuicon"))
        }
    }
}

class AppWindowController: NSWindowController, NSWindowDelegate {
    func windowShouldClose(_: NSWindow) -> Bool {
        NSApp.hide(nil)
        return false
    }
}
