import Foundation
import libCrescendo

@objc protocol ProviderCommunication {
    func register(_ completionHandler: @escaping (Bool) -> Void)
    func updateBlacklist(items: [String])
    func getBlacklist(withData response: @escaping ([String]) -> Void)
}

@objc protocol AppCommunication {
    func sendEventToApp(newEvent event: String)
}

class IPCConnection: NSObject {
    var listener: NSXPCListener?
    var currentConnection: NSXPCConnection?
    weak var delegate: AppCommunication?
    static let shared = IPCConnection()
    var client: ESClient?

    func startListener(esclient: ESClient) {
        let machServiceName = extensionMachServiceName(from: Bundle.main)
        NSLog("Starting XPC listener for mach service.")

        let newListener = NSXPCListener(machServiceName: machServiceName)
        newListener.delegate = self
        newListener.resume()
        listener = newListener
        client = esclient
    }

    private func extensionMachServiceName(from bundle: Bundle) -> String {
        guard let networkExtensionKeys = bundle.object(forInfoDictionaryKey: "EndpointExtension") as? [String: Any],
            let machServiceName = networkExtensionKeys["MachServiceName"] as? String else {
            NSLog("Mach service name is missing from the Info.plist")
            return ""
        }
        return machServiceName
    }

    func register(withExtension bundle: Bundle,
                  delegate: AppCommunication,
                  completionHandler: @escaping (Bool) -> Void) {
        self.delegate = delegate
        guard currentConnection == nil else {
            NSLog("Already registered with the provider")
            completionHandler(true)
            return
        }

        let machServiceName = extensionMachServiceName(from: bundle)
        NSLog("Trying to connect to service: %@", machServiceName)

        let newConnection = NSXPCConnection(machServiceName: machServiceName, options: [])
        newConnection.exportedInterface = NSXPCInterface(with: AppCommunication.self)
        newConnection.exportedObject = delegate
        newConnection.remoteObjectInterface = NSXPCInterface(with: ProviderCommunication.self)
        currentConnection = newConnection
        newConnection.resume()

        guard let providerProxy = newConnection.remoteObjectProxyWithErrorHandler({ registerError in
            NSLog("Failed to register with the provider: %@", registerError.localizedDescription)
            self.currentConnection?.invalidate()
            self.currentConnection = nil
            completionHandler(false)
        }) as? ProviderCommunication else {
            NSLog("Failed to create a remote object proxy for the provider")
            return
        }

        providerProxy.register(completionHandler)
    }

    func updateBlacklist(blockedItems: [String], delegate: AppCommunication) {
        guard let connection = currentConnection else {
            return
        }

        self.delegate = delegate

        guard let providerProxy = connection.remoteObjectProxyWithErrorHandler({ updateError in
            NSLog("Failed to update blacklist %@", updateError.localizedDescription)
            self.currentConnection = nil
        }) as? ProviderCommunication else {
            NSLog("Failed to create a remote object proxy for the app")
            return
        }

        providerProxy.updateBlacklist(items: blockedItems)
    }

    func getBlackList(delegate: AppCommunication, withData response: @escaping ([String]) -> Void) {
        guard let connection = currentConnection else {
            return
        }

        self.delegate = delegate

        guard let providerProxy = connection.remoteObjectProxyWithErrorHandler({ updateError in
            NSLog("Failed to get blacklist %@", updateError.localizedDescription)
            self.currentConnection = nil
        }) as? ProviderCommunication else {
            NSLog("Failed to create a remote object proxy for the app")
            return
        }

        return providerProxy.getBlacklist(withData: response)
    }

    func terminateESClient() {
        if self.client != nil {
            let ret = disableCrescendo(esclient: self.client!)
            if ret != CrescendoError.success {
                NSLog("Failed to disable Crescendo listener")
            }
        }
        self.client = nil
    }

    func sendEventToApp(newEvent event: String) {
        guard let connection = currentConnection else {
            // no app client connected, do not attempt to send event.
            return
        }

        guard let appProxy = connection.remoteObjectProxyWithErrorHandler({ sendError in
            NSLog("Failed to sent event to app %@", sendError.localizedDescription)
            self.currentConnection = nil
        }) as? AppCommunication else {
            NSLog("Failed to create a remote object proxy for the app")
            return
        }

        appProxy.sendEventToApp(newEvent: event)
    }
}

extension IPCConnection: NSXPCListenerDelegate {
    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: ProviderCommunication.self)
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = NSXPCInterface(with: AppCommunication.self)
        newConnection.invalidationHandler = {
            self.currentConnection = nil
            NSLog("App disconnected.")
            self.terminateESClient()
        }

        newConnection.interruptionHandler = {
            self.currentConnection = nil
            NSLog("App connection interrupt.")
        }

        currentConnection = newConnection
        newConnection.resume()
        return true
    }
}

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

func startCrescendoClient() -> ESClient {
    let esclient = enableCrescendo(completion: sender)
    if esclient.error != CrescendoError.success {
        NSLog("Failed to create Crescendo listener.")
    }

    return esclient.client
}

extension IPCConnection: ProviderCommunication {
    func register(_ completionHandler: @escaping (Bool) -> Void) {
        NSLog("App client connected.")

        if self.client == nil {
            self.client = startCrescendoClient()
            NSLog("Created esclient.")
        }
        completionHandler(true)
    }

    func updateBlacklist(items: [String]) {
        guard let client = self.client else {
            return
        }
        client.updateCrescendoBlacklist(blockedItems: items)
    }

    func getBlacklist(withData response: @escaping ([String]) -> Void) {
        guard let client = self.client else {
            return
        }
        response(client.getCrescendoBlacklist())
    }

}
