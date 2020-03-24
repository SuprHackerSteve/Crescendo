import Foundation

import EndpointSecurityPrivate

public enum ESClientError: Error {
    case success
    case missingEntitlements
    case alreadyEnabled
    case newClientError
    case failedSubscription
}

// Main structure for events. Uses Codable for painless serialization.
public struct CrescendoEvent: Codable {
    public var eventtype: String
    public var processpath: String
    public var pid: Int32
    public var ppid: Int32
    public var isplatform: Bool
    public var timestamp: Int
    public var username: String
    public var signingid: String
    public var props: [String: String]

    public var description: String {
        let pretty = """
        Event Type: \(eventtype)
        Process: \(processpath)
        Pid: \(pid) (Parent) -> \(ppid)
        User: \(username)
        Timestamp: \(timestamp)
        Platform Binary: \(isplatform)
        Signing ID: \(signingid)
        Props:
        \(props as AnyObject)
        """
        return pretty
    }

    init() {
        eventtype = ""
        processpath = ""
        pid = -1
        ppid = -1
        timestamp = 0
        isplatform = false
        signingid = ""
        username = ""
        props = [String: String]()
    }
}

public class ESClient {
    var client: OpaquePointer?
    var connected: Bool
    var callback: (CrescendoEvent) -> Void
    let subEvents = [ES_EVENT_TYPE_AUTH_EXEC,
                     ES_EVENT_TYPE_NOTIFY_CREATE,
                     ES_EVENT_TYPE_NOTIFY_KEXTLOAD,
                     ES_EVENT_TYPE_NOTIFY_MOUNT,
                     ES_EVENT_TYPE_NOTIFY_RENAME,
                     ES_EVENT_TYPE_NOTIFY_UIPC_CONNECT,
                     ES_EVENT_TYPE_NOTIFY_FORK,
                     ES_EVENT_TYPE_NOTIFY_UNLINK]

    var blacklist: [String] = []

    init(completion: @escaping (CrescendoEvent) -> Void) {
        connected = false
        client = nil
        callback = completion
    }

    // startEventProducer will start a task that will listen for real time events.
    func startEventProducer() -> ESClientError {
        var client: OpaquePointer?
        var err = ESClientError.success

        if connected {
            NSLog("ESClient already connected.")
            return err
        }

        let dispatchQueue = DispatchQueue(label: "esclient", qos: .userInitiated)
        dispatchQueue.async {
            let res = es_new_client(&client) { _, event in
                if !self.connected {
                    return
                }
                self.eventDispatcher(msg: event)
            }

            if res != ES_NEW_CLIENT_RESULT_SUCCESS {
                if res == ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED {
                    NSLog("Endpoint Security entitlement not found.")
                    err = ESClientError.missingEntitlements
                    return
                }
                NSLog("Failed to initialize ES client: \(res)")
                exit(EXIT_FAILURE)
            }

            let ret = es_subscribe(client!, self.subEvents, UInt32(self.subEvents.count))
            if ret != ES_RETURN_SUCCESS {
                err = ESClientError.failedSubscription
                NSLog("Failed to subscribe to event source: \(ret)")
                exit(EXIT_FAILURE)
            }

            self.client = client
            self.connected = true
        }
        return err
    }

    public func updateCrescendoBlacklist(blockedItems: [String]) {
        NSLog("Updating blacklist items with %d items.", blockedItems.count)
        blacklist = blockedItems
    }

    public func getCrescendoBlacklist() -> [String] {
        return blacklist
    }

    func stopEventProducer() {
        if connected {
            if ES_RETURN_ERROR == es_delete_client(client!) {
                NSLog("Unable to delete resources - ESF resource leak")
            }
            client = nil
        }

        connected = false
    }

    func eventDispatcher(msg: UnsafePointer<es_message_t>) {
        // Right now we are using the notify version of listeners, could change this in future
        // to support the auth versions. My concern for using auth is we are in a blocking path
        // any user provided callbacks will block pending io.

        let proc: es_process_t = msg.pointee.process.pointee
        var cEvent = CrescendoEvent()

        let path = proc.executable.pointee.path

        cEvent.processpath = getString(tok: path)
        cEvent.pid = audit_token_to_pid(proc.audit_token)
        cEvent.ppid = proc.ppid
        cEvent.timestamp = Int(msg.pointee.time.tv_sec * 1000) + Int(msg.pointee.time.tv_nsec / (1000 * 1000))
        cEvent.username = getUsername(id: audit_token_to_euid(proc.audit_token))
        cEvent.isplatform = proc.is_platform_binary
        cEvent.signingid = getString(tok: proc.signing_id)

        switch msg.pointee.event_type {
        case ES_EVENT_TYPE_AUTH_EXEC:
            cEvent.eventtype = "process::exec"
            parseProcEvent(msg: msg, cEvent: &cEvent)
        case ES_EVENT_TYPE_NOTIFY_CREATE:
            cEvent.eventtype = "file::create"
            parseFileEvent(msg: msg, cEvent: &cEvent)
        case ES_EVENT_TYPE_NOTIFY_KEXTLOAD:
            cEvent.eventtype = "process:kext::load"
            parseKextEvent(msg: msg, cEvent: &cEvent)
        case ES_EVENT_TYPE_NOTIFY_MOUNT:
            cEvent.eventtype = "file::mount"
            parseMountEvent(msg: msg, cEvent: &cEvent)
        case ES_EVENT_TYPE_NOTIFY_UNLINK:
            cEvent.eventtype = "file::unlink"
            parseUnlinkEvent(msg: msg, cEvent: &cEvent)
        case ES_EVENT_TYPE_NOTIFY_RENAME:
            cEvent.eventtype = "file::rename"
            parseRenameEvent(msg: msg, cEvent: &cEvent)
        case ES_EVENT_TYPE_NOTIFY_UIPC_CONNECT:
            cEvent.eventtype = "network::ipcconnect"
            parseIPCEvent(msg: msg, cEvent: &cEvent)
        case ES_EVENT_TYPE_NOTIFY_FORK:
            cEvent.eventtype = "process::fork"
            parseForkEvent(msg: msg, cEvent: &cEvent)
        default:
            break
        }
    }
}
