import Cocoa
import SystemExtensions

import libCrescendo

// swiftlint:disable:next type_body_length
class ViewController: NSViewController {
    enum Status {
        case stopped
        case indeterminate
        case running
    }

    @IBOutlet var startButton: NSButton!
    @IBOutlet var stopButton: NSButton!
    @IBOutlet var clearButton: NSButton!
    @IBOutlet var logTableView: NSTableView!
    @IBOutlet var searchBar: NSSearchField!
    @IBOutlet var autoscrollToggle: NSButton!
    @IBOutlet var statusSpinner: NSProgressIndicator!

    @IBOutlet var eventFilter: NSSegmentedControl!
    @IBOutlet var searchField: NSSearchField!
    @IBOutlet var eventLabel: NSTextField!
    @IBOutlet var eventProps: NSTextField!

    // event array of filtered (if applicable) events
    var activeItems = [CrescendoEvent]()
    // event array of all events
    var savedItems = [CrescendoEvent]()
    // timer to handle how often we update the tableview
    var updateTimer = Date()

    var status: Status = .stopped {
        didSet {
            switch status {
            case .stopped:
                statusSpinner.stopAnimation(self)
                statusSpinner.isHidden = true
                stopButton.isHidden = true
                startButton.isHidden = false
            case .indeterminate:
                statusSpinner.startAnimation(self)
                statusSpinner.isHidden = false
                stopButton.isHidden = true
                startButton.isHidden = true
            case .running:
                statusSpinner.stopAnimation(self)
                statusSpinner.isHidden = false
                stopButton.isHidden = false
                startButton.isHidden = true
            }
            if !statusSpinner.isHidden {
                statusSpinner.startAnimation(self)
            } else {
                statusSpinner.stopAnimation(self)
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        status = .stopped
        logTableView.delegate = self
        logTableView.dataSource = self
        logTableView.target = self
        makeSearchFieldOptions()
        updateTimer = Date()
    }

    // Helper to move our app to the /Applications folder, since it is a requirement for system extensions
    override func viewWillAppear() {
        PFMoveToApplicationsFolderIfNecessary()
    }

    lazy var extensionBundle: Bundle = {
        let extensionsDirectoryURL = URL(fileURLWithPath: "Contents/Library/SystemExtensions",
                                         relativeTo: Bundle.main.bundleURL)
        let extensionURLs: [URL]
        do {
            extensionURLs = try FileManager.default.contentsOfDirectory(at: extensionsDirectoryURL,
                                                                        includingPropertiesForKeys: nil,
                                                                        options: .skipsHiddenFiles)
        } catch {
            // swiftlint:disable:next line_length
            fatalError("Failed to get the contents of \(extensionsDirectoryURL.absoluteString): \(error.localizedDescription)")
        }

        guard let extensionURL = extensionURLs.first else {
            showError(error: "Failed to find system extension")
            fatalError("Failed to find system extension")
        }

        guard let extensionBundle = Bundle(url: extensionURL) else {
            fatalError("Failed to create a bundle with URL \(extensionURL.absoluteString)")
        }
        return extensionBundle
    }()

    // Helper for reloading events while maintaining selection in tableview
    func reloadEvents() {
        // only reload tableview every 1 second
        if Date().timeIntervalSince(updateTimer) > 1 {
            let row = logTableView.selectedRow
            logTableView.reloadData()
            let indexPath = IndexSet(integer: row)
            logTableView.selectRowIndexes(indexPath, byExtendingSelection: false)
            if logTableView.numberOfRows > 0, autoscrollToggle.state.rawValue == 1 {
                logTableView.scrollRowToVisible(logTableView.numberOfRows - 1)
            }
            updateTimer = Date()
        }
    }

    // Handles updating the detail pane view for event details in our prop bags
    func updateSelectedRow() {
        if logTableView.selectedRowIndexes.count == 0 || logTableView.selectedRow > activeItems.count {
            return
        }
        displayEventDetails(event: activeItems[logTableView.selectedRow])
    }

    // Handles deserialization of income events and stores into our event array
    func logEvent(event: String) {
        // drop events if we are stopped
        if status == .stopped {
            return
        }
        let decoder = JSONDecoder()

        guard let jsonData = event.data(using: .utf8),
            let crescendoEvent = try? decoder.decode(CrescendoEvent.self, from: jsonData)
        else {
            NSLog("Failed to deseralize json into crescendo event")
            return
        }

        // need to ensure we run these on the main thread since they touch UI elements
        DispatchQueue.main.async {
            self.savedItems.append(crescendoEvent)
            self.addEventIfFilterIsSet(event: crescendoEvent)
            self.reloadEvents()
        }
    }

    // Generic function to display error in NSAlert as well as log
    func showError(error: String) {
        let alert = NSAlert()
        NSLog("%@", error)
        alert.informativeText = error
        alert.alertStyle = .critical
        alert.messageText = "Error"
        alert.runModal()
    }

    // Save button handler
    @IBAction func saveEvents(_: Any) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "events.json"
        let resp = panel.runModal()
        if resp == NSApplication.ModalResponse.OK {
            guard let outFile = panel.url else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            guard let data = try? encoder.encode(savedItems)
            else {
                showError(error: "Failed to serialize events for file.")
                return
            }
            let json = String(data: data, encoding: .utf8)!
            do {
                try json.write(to: outFile, atomically: true, encoding: .utf8)
            } catch {
                showError(error: "Failed to write events to disk.")
            }
        }
    }

    // Clear button handler, will drop _all_ events from both saved and active. Will also clear filters.
    @IBAction func clearData(_: Any) {
        activeItems.removeAll()
        savedItems.removeAll()
        eventLabel.stringValue = ""
        eventProps.stringValue = ""
        searchField.stringValue = ""
        eventFilter.selectSegment(withTag: 0)
        reloadEvents()
    }

    // Start button handler
    @IBAction func startListener(_: Any) {
        status = .indeterminate
        guard let extensionIdentifier = extensionBundle.bundleIdentifier else {
            status = .stopped
            return
        }
        // swiftlint:disable:next line_length
        let activationRequest = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionIdentifier,
                                                                           queue: .main)
        activationRequest.delegate = self
        OSSystemExtensionManager.shared.submitRequest(activationRequest)
        status = .indeterminate
    }

    // Init our menu items in the search field
    func makeSearchFieldOptions() {
        let menu = NSMenu()

        let allMenuItem = NSMenuItem()
        allMenuItem.title = "All Fields"
        allMenuItem.target = self
        allMenuItem.action = #selector(searchFieldChange(_:))

        let procMenuItem = NSMenuItem()
        procMenuItem.title = "Process"
        procMenuItem.target = self
        procMenuItem.action = #selector(searchFieldChange(_:))

        let pidMenuItem = NSMenuItem()
        pidMenuItem.title = "PID"
        pidMenuItem.target = self
        pidMenuItem.action = #selector(searchFieldChange(_:))

        let userMenuItem = NSMenuItem()
        userMenuItem.title = "Username"
        userMenuItem.target = self
        userMenuItem.action = #selector(searchFieldChange(_:))

        menu.addItem(allMenuItem)
        menu.addItem(procMenuItem)
        menu.addItem(pidMenuItem)
        menu.addItem(userMenuItem)

        searchField.searchMenuTemplate = menu
        searchFieldChange(allMenuItem)
    }

    // addEventIfFilterIsSet was added to reduce CPU time when an active filter is enabled. It will only add an event
    // to the current view _if_ a filter is active. This will reduce the complexity and overhead of new events coming in
    // when a filter has already been specified.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func addEventIfFilterIsSet(event: CrescendoEvent) {
        var searchBarIsMatched = false
        var filterButtonIsMatched = false

        let searchText = searchField.stringValue

        if !searchText.isEmpty {
            if (searchField.cell as? NSSearchFieldCell)?.placeholderString == "All Fields" {
                if event.processpath.localizedCaseInsensitiveContains(searchText) ||
                    event.eventtype.localizedCaseInsensitiveContains(searchText) ||
                    event.processpath.localizedCaseInsensitiveContains(searchText) ||
                    String(event.pid).localizedCaseInsensitiveContains(searchText) ||
                    event.username.localizedCaseInsensitiveContains(searchText) ||
                    String(event.timestamp).localizedCaseInsensitiveContains(searchText) ||
                    event.signingid.localizedCaseInsensitiveContains(searchText) {
                    searchBarIsMatched = true
                }
            } else if (searchField.cell as? NSSearchFieldCell)?.placeholderString == "Process" {
                if event.processpath.localizedCaseInsensitiveContains(searchText) {
                    searchBarIsMatched = true
                }
            } else if (searchField.cell as? NSSearchFieldCell)?.placeholderString == "PID" {
                if String(event.pid).localizedCaseInsensitiveContains(searchText) {
                    searchBarIsMatched = true
                }
            } else if (searchField.cell as? NSSearchFieldCell)?.placeholderString == "Username" {
                if event.username.localizedCaseInsensitiveContains(searchText) {
                    searchBarIsMatched = true
                }
            }
        } else {
            // search bar is empty, always add event
            searchBarIsMatched = true
        }

        switch eventFilter.selectedSegment {
        // all events selected, no filter
        case 0:
            filterButtonIsMatched = true
        case 1:
            if event.eventtype.contains("file") {
                filterButtonIsMatched = true
            }
        case 2:
            if event.eventtype.contains("proc") ||
                event.eventtype.contains("kext") {
                filterButtonIsMatched = true
            }
        case 3:
            if event.eventtype.contains("network") {
                filterButtonIsMatched = true
            }
        case 4:
            if event.signingid.isEmpty {
                filterButtonIsMatched = true
            }
        case 5:
            if !event.signingid.starts(with: "com.apple") {
                filterButtonIsMatched = true
            }
        default: ()
        }

        if searchBarIsMatched, filterButtonIsMatched {
            activeItems.append(event)
        }
    }

    // Updates our tableview based on the user's filters
    // swiftlint:disable:next cyclomatic_complexity
    func updateFilteredEvents() {
        let searchText = searchField.stringValue
        if !searchText.isEmpty {
            if (searchField.cell as? NSSearchFieldCell)?.placeholderString == "All Fields" {
                activeItems = savedItems.filter { $0.processpath.localizedCaseInsensitiveContains(searchText) ||
                    $0.eventtype.localizedCaseInsensitiveContains(searchText) ||
                    String($0.pid).localizedCaseInsensitiveContains(searchText) ||
                    $0.username.localizedCaseInsensitiveContains(searchText) ||
                    $0.signingid.localizedCaseInsensitiveContains(searchText) ||
                    String($0.timestamp).localizedCaseInsensitiveContains(searchText)
                }
            } else if (searchField.cell as? NSSearchFieldCell)?.placeholderString == "Process" {
                activeItems = savedItems.filter { $0.processpath.localizedCaseInsensitiveContains(searchText) }
            } else if (searchField.cell as? NSSearchFieldCell)?.placeholderString == "PID" {
                activeItems = savedItems.filter { String($0.pid) == searchText }
            } else if (searchField.cell as? NSSearchFieldCell)?.placeholderString == "Username" {
                activeItems = savedItems.filter { $0.username.localizedCaseInsensitiveContains(searchText) }
            }
        } else {
            activeItems = savedItems
        }

        switch eventFilter.selectedSegment {
        case 1:
            activeItems = activeItems.filter { $0.eventtype.contains("file") }
        case 2:
            activeItems = activeItems.filter { $0.eventtype.contains("proc") ||
                $0.eventtype.contains("kext")
            }
        case 3:
            activeItems = activeItems.filter { $0.eventtype.contains("network") }
        case 4:
            activeItems = activeItems.filter { $0.signingid.isEmpty }
        case 5:
            activeItems = activeItems.filter { !$0.signingid.starts(with: "com.apple") }
        default: ()
        }
        reloadEvents()
    }

    // Handler for unloading the system extension. This should only be used for extreme situations.
    @IBAction func unloadSystemExtension(sender _: NSMenuItem) {
        IPCConnection.shared.unregister()
        guard let extensionIdentifier = extensionBundle.bundleIdentifier else {
            NSLog("Unable to get bundle identifier.")
            return
        }
        // swiftlint:disable:next line_length
        let deactivationRequest = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: extensionIdentifier,
                                                                               queue: .main)
        deactivationRequest.delegate = self
        OSSystemExtensionManager.shared.submitRequest(deactivationRequest)
        NSLog("System extension unload request sent.")
    }

    //  We may want to unload the system extension but I'm not quite sure what the
    // "correct" state management looks like right now...
    @IBAction func stopListener(_: Any) {
        IPCConnection.shared.unregister()
        status = .stopped
    }

    @IBAction func searchFieldChange(_ sender: Any) {
        if let menu = sender as? NSMenuItem {
            (searchField.cell as? NSSearchFieldCell)?.placeholderString = menu.title
        }
        updateFilteredEvents()
    }

    // call into extension IPC interface
    func registerWithProvider() {
        IPCConnection.shared.register(withExtension: extensionBundle, delegate: self) { success in
            DispatchQueue.main.async {
                self.status = (success ? .running : .stopped)
            }
        }
    }
}
