import Cocoa
import Foundation

import libCrescendo

extension ViewController: NSTableViewDelegate {
    fileprivate enum CellIdentifiers {
        static let timestamp = "Timestamp"
        static let eventName = "EventName"
        static let username = "User"
        static let pid = "PID"
        static let procPath = "ProcessPath"
        static let signingID = "SigningID"
    }

    func tableViewSelectionDidChange(_: Notification) {
        updateSelectedRow()
    }

    func displayEventDetails(event: CrescendoEvent) {
        switch event.eventtype {
        case "process::exec":
            eventLabel.stringValue = "Process Execution:🚀 \(event.processpath)"
        case "process::fork":
            eventLabel.stringValue = "Process Fork:🚀 \(event.processpath)"
        case "file::unlink":
            eventLabel.stringValue = "Unlink Event:🗑 \(event.props["path"] ?? "<missing>")"
        case "file::create":
            eventLabel.stringValue = "File Create Event:📂 \(event.props["path"] ?? "<missing>")"
        case "file::rename":
            eventLabel.stringValue = "File Rename Event:📂 \(event.props["srcpath"] ?? "<missing>")"
        case "process::kext::load":
            eventLabel.stringValue = "Kext Load Event:🙉 \(event.props["identifier"] ?? "<missing>")"
        case "file::mount":
            eventLabel.stringValue = "Image Mount Event:💾 \(event.props["remotename"] ?? "<missing>")"
        case "network::ipcconnect":
            eventLabel.stringValue = "New IPC Event:🖲 \(event.props["path"] ?? "<missing>")"
        default:
            eventLabel.stringValue = "New Event:🧩 \(event.eventtype)"
        }
        eventProps.stringValue = event.description
    }
}

extension ViewController: NSTableViewDataSource {
    func numberOfRows(in _: NSTableView) -> Int {
        return activeItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var text: String = ""
        var cellIdentifier: String = ""

        if logTableView.numberOfRows == 0 {
            return nil
        }

        if row >= logTableView.numberOfRows || row >= activeItems.count {
            return nil
        }

        let event = activeItems[row]

        if tableColumn == tableView.tableColumns[0] {
            text = String(event.timestamp)
            cellIdentifier = CellIdentifiers.timestamp
        } else if tableColumn == tableView.tableColumns[1] {
            text = event.eventtype
            cellIdentifier = CellIdentifiers.eventName
        } else if tableColumn == tableView.tableColumns[2] {
            text = event.username
            cellIdentifier = CellIdentifiers.username
        } else if tableColumn == tableView.tableColumns[3] {
            text = String(event.pid)
            cellIdentifier = CellIdentifiers.pid
        } else if tableColumn == tableView.tableColumns[4] {
            text = (event.processpath as NSString).lastPathComponent
            cellIdentifier = CellIdentifiers.procPath
        } else if tableColumn == tableView.tableColumns[5] {
            text = event.signingid
            cellIdentifier = CellIdentifiers.signingID
        }

        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: cellIdentifier),
                                         owner: nil) as? NSTableCellView {
            cell.textField?.stringValue = text
            if event.signingid.isEmpty {
                cell.textField?.textColor = .red
            } else {
                cell.textField?.textColor = .none
            }
            return cell
        }

        return nil
    }
}
