import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {}

class AppWindowController: NSWindowController, NSWindowDelegate {
    func windowShouldClose(_: NSWindow) -> Bool {
        NSApp.hide(nil)
        return false
    }
}
