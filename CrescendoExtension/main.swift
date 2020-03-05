import Foundation
import libCrescendo

autoreleasepool {
    NSLog("Init Crescendo system extension")
    func sender(event: CrescendoEvent) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(event)
        else {
            NSLog("Failed to seralize event")
            return
        }
        guard let json = String(data: data, encoding: .utf8) else {
            NSLog("Invalid json encode.")
            return
        }

        IPCConnection.shared.sendEventToApp(newEvent: json)
    }

    let client = enableCrescendo(completion: sender)
    if client.error != CrescendoError.success {
        NSLog("Failed to create Crescendo listener.")
        exit(EXIT_FAILURE)
    }

    IPCConnection.shared.startListener()
}

dispatchMain()
