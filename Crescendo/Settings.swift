import Cocoa

class SettingsView: NSViewController, AppCommunication {
    @IBOutlet var addButton: NSButton!
    @IBOutlet var backButton: NSButton!
    @IBOutlet var itemList: NSScrollView!
    @IBOutlet var purgeEventCheckbox: NSButton!

    var shouldPurge = true

    override func viewWillAppear() {
        super.viewWillAppear()
        IPCConnection.shared.getBlackList(delegate: self) { response in
            DispatchQueue.main.async {
                guard let entries = self.itemList.documentView as? NSTextView else {
                    return
                }
                entries.string = response.joined(separator: "\n")
            }
        }

        if let main = presentingViewController as? ViewController {
            shouldPurge = main.shouldPurgeEvents
        }
        if shouldPurge {
            purgeEventCheckbox.state = .on
        } else {
            purgeEventCheckbox.state = .off
        }
    }

    @IBAction func backButton(_: Any) {
        dismiss(self)
    }

    func saveDismiss() {
        if let main = presentingViewController as? ViewController {
            main.shouldPurgeEvents = shouldPurge
        }
        dismiss(self)
    }

    @IBAction func addButtonHandler(_: Any) {
        guard let entries = itemList.documentView as? NSTextView else {
            return
        }

        if entries.string.isEmpty {
            saveDismiss()
            return
        }
        let items = entries.string.components(separatedBy: .newlines)
        var cleanedItems: [String] = []
        // ignore any line returns
        for item in Array(Set(items)) where item.count > 2 {
            cleanedItems.append(item)
        }
        IPCConnection.shared.updateBlacklist(blockedItems: cleanedItems, delegate: self)
        NSLog("Added %d items to blacklist.", cleanedItems.count)
        saveDismiss()
    }

    @IBAction func purgeEventsChange(_: Any) {
        if purgeEventCheckbox.state == .on {
            shouldPurge = true
        } else {
            shouldPurge = false
        }
    }

    func sendEventToApp(newEvent _: String) {}
}
