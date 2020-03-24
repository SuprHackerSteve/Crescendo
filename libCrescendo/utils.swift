import Darwin
import EndpointSecurityPrivate
import Foundation

// https://stackoverflow.com/questions/24376829/converting-a-c-string-inside-a-struct-to-a-swift-string/40433950
extension String {
    init<T>(tupleOfCChars: T, length: Int = Int.max) {
        self = withUnsafePointer(to: tupleOfCChars) {
            let lengthOfTuple = MemoryLayout<T>.size / MemoryLayout<CChar>.size
            return $0.withMemoryRebound(to: UInt8.self, capacity: lengthOfTuple) {
                String(bytes: UnsafeBufferPointer(start: $0, count: Swift.min(length, lengthOfTuple)), encoding: .utf8)!
            }
        }
    }
}

// swiftlint:disable:next identifier_name
public func getUsername(id: uid_t) -> String {
    guard let passwd = getpwuid(id)?.pointee.pw_name else { return "" }
    return String(cString: passwd)
}

// Given a es_process_t this func will populate a prop dict for a process
func getProcessProps(proc: es_process_t, exec: es_event_exec_t) -> [String: String] {
    var props: Dictionary = [String: String]()

    props["teamid"] = getString(tok: proc.team_id)
    props["signingid"] = getString(tok: proc.signing_id)
    props["isplatformbin"] = String(proc.is_platform_binary)
    props["size"] = String(proc.executable.pointee.stat.st_size)
    props["ppid"] = String(proc.ppid)

    var ref: es_event_exec_t = exec
    let argc = es_exec_arg_count(&ref)
    props["argc"] = String(argc)

    var argv = ""

    // swiftlint:disable:next identifier_name
    for i in 0 ..< argc {
        argv += getString(tok: es_exec_arg(&ref, i)) + " "
    }

    props["argv"] = argv

    return props
}

// Converts a es_string_token_t to swift string
func getString(tok: es_string_token_t) -> String {
    if tok.length > 0 {
        return String(cString: tok.data)
    }

    return ""
}
