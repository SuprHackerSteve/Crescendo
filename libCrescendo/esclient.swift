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
    let subEvents = [ES_EVENT_TYPE_NOTIFY_EXEC,
                     ES_EVENT_TYPE_NOTIFY_CREATE,
                     ES_EVENT_TYPE_NOTIFY_KEXTLOAD,
                     ES_EVENT_TYPE_NOTIFY_MOUNT,
                     ES_EVENT_TYPE_NOTIFY_RENAME,
                     ES_EVENT_TYPE_NOTIFY_UIPC_CONNECT,
                     ES_EVENT_TYPE_NOTIFY_FORK,
                     ES_EVENT_TYPE_NOTIFY_UNLINK]

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
            NSLog("Client already connected.")
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

            let events: UnsafeMutablePointer = UnsafeMutablePointer(mutating: self.subEvents)

            let ret = es_subscribe(client!, events, UInt32(self.subEvents.count))
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

    func stopEventProducer() {
        if connected {
            if ES_RETURN_ERROR == es_delete_client(client!) {
                NSLog("Unable to delete resources - ESF resource leak")
            }
            client = nil
        }

        connected = false
    }

    func parseProcEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        if let proc: es_process_t = msg.pointee.process?.pointee {
            cEvent.props = getProcessProps(proc: proc, exec: msg.pointee.event.exec)
        }
        callback(cEvent)
    }

    func parseForkEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        let forkedProc: es_event_fork_t = msg.pointee.event.fork
        if let proc = forkedProc.child?.pointee {
            cEvent.props = getProcessProps(proc: proc, exec: msg.pointee.event.exec)
        }
        callback(cEvent)
    }

    // swiftlint:disable:next cyclomatic_complexity
    func parseIPCEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        var IPCEvent: Dictionary = [String: String]()

        let conn: es_event_uipc_connect_t = msg.pointee.event.uipc_connect
        var domainString: String
        var typeString: String
        var protoString: String

        switch conn.domain {
        case AF_UNIX:
            domainString = "AF_UNIX"
        case AF_INET:
            domainString = "AF_INET"
        case AF_LOCAL:
            domainString = "AF_LOCAL"
        default:
            domainString = String(conn.domain)
        }

        switch conn.type {
        case SOCK_STREAM:
            typeString = "SOCK_STREAM"
        case SOCK_DGRAM:
            typeString = "SOCK_DGRAM"
        case SOCK_RAW:
            typeString = "SOCK_RAW"
        default:
            typeString = String(conn.type)
        }

        switch conn.protocol {
        case IPPROTO_IP:
            protoString = "IPPROTO_IP"
        case IPPROTO_UDP:
            protoString = "IPPROTO_UDP"
        case IPPROTO_TCP:
            protoString = "IPPROTO_TCP"
        default:
            protoString = String(conn.protocol)
        }

        IPCEvent["domain"] = domainString
        IPCEvent["proto"] = protoString
        IPCEvent["type"] = typeString
        if let file: es_file_t = conn.file?.pointee {
            IPCEvent["path"] = getString(tok: file.path)
        }
        cEvent.props = IPCEvent

        callback(cEvent)
    }

    func parseFileEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        var fileEvent: Dictionary = [String: String]()

        if let file: es_file_t = msg.pointee.event.create.destination.new_path.dir?.pointee {
            fileEvent["path"] = getString(tok: file.path)
            fileEvent["size"] = String(file.stat.st_size)
        }
        cEvent.props = fileEvent

        callback(cEvent)
    }

    func parseRenameEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        var fileEvent: Dictionary = [String: String]()

        if let file: es_file_t = msg.pointee.event.rename.source?.pointee {
            fileEvent["srcpath"] = getString(tok: file.path)
            fileEvent["srcsize"] = String(file.stat.st_size)
        }
        fileEvent["desttype"] = String(msg.pointee.event.rename.destination_type.rawValue)
        fileEvent["destfile"] = getString(tok: msg.pointee.event.rename.destination.new_path.filename)

        if let dstfile: es_file_t = msg.pointee.event.rename.destination.existing_file?.pointee {
            fileEvent["destdir"] = getString(tok: dstfile.path)
        }

        cEvent.props = fileEvent

        callback(cEvent)
    }

    func parseKextEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        var kextEvent: Dictionary = [String: String]()
        kextEvent["identifier"] = getString(tok: msg.pointee.event.kextload.identifier)

        cEvent.props = kextEvent

        callback(cEvent)
    }

    func parseMountEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        var mountEvent: Dictionary = [String: String]()

        if var remoteBytes = msg.pointee.event.mount.statfs?.pointee.f_mntonname {
            let remoteName = String(cString: UnsafeRawPointer(&remoteBytes).assumingMemoryBound(to: CChar.self))
            mountEvent["remotename"] = remoteName
        }
        if var localBytes = msg.pointee.event.mount.statfs?.pointee.f_mntonname {
            let localName = String(cString: UnsafeRawPointer(&localBytes).assumingMemoryBound(to: CChar.self))
            mountEvent["localname"] = localName
        }

        cEvent.props = mountEvent

        callback(cEvent)
    }

    func parseUnlinkEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        var deleteEvent: Dictionary = [String: String]()

        if let dir = msg.pointee.event.unlink.parent_dir?.pointee.path {
            deleteEvent["dir"] = getString(tok: dir)
        }
        if let path = msg.pointee.event.unlink.target?.pointee.path {
            deleteEvent["path"] = getString(tok: path)
        }

        cEvent.props = deleteEvent

        callback(cEvent)
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func eventDispatcher(msg: UnsafePointer<es_message_t>) {
        // Right now we are using the notify version of listeners, could change this in future
        // to support the auth versions. My concern for using auth is we are in a blocking path
        // any user provided callbacks will block pending io.

        guard let proc: es_process_t = msg.pointee.process?.pointee else {
            NSLog("Got bad event from ES")
            return
        }

        var cEvent = CrescendoEvent()

        guard let path = proc.executable?.pointee.path else {
            NSLog("Missing executable path")
            return
        }

        cEvent.processpath = getString(tok: path)
        cEvent.pid = audit_token_to_pid(proc.audit_token)
        cEvent.ppid = proc.ppid
        cEvent.timestamp = Int(msg.pointee.time.tv_sec * 1000) + Int(msg.pointee.time.tv_nsec / 1000)
        cEvent.username = getUsername(id: audit_token_to_euid(proc.audit_token))
        cEvent.isplatform = proc.is_platform_binary
        cEvent.signingid = getString(tok: proc.signing_id)

        switch msg.pointee.event_type {
        case ES_EVENT_TYPE_NOTIFY_EXEC:
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
