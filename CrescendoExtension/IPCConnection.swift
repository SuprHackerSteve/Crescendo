import Foundation
import libCrescendo

@objc protocol ProviderCommunication {
    func register(_ completionHandler: @escaping (Bool) -> Void)
    func updateBlacklist(items: [String])
    func getBlacklist(withData response: @escaping ([String]) -> Void)
    func unregister()
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
        NSLog("Starting XPC listener for mach service %@", machServiceName)

        let newListener = NSXPCListener(machServiceName: machServiceName)
        newListener.delegate = self
        newListener.resume()
        listener = newListener
        client = esclient
    }

    private func extensionMachServiceName(from bundle: Bundle) -> String {
        guard let networkExtensionKeys = bundle.object(forInfoDictionaryKey: "EndpointExtension") as? [String: Any],
            let machServiceName = networkExtensionKeys["MachServiceName"] as? String else {
            fatalError("Mach service name is missing from the Info.plist")
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
            fatalError("Failed to create a remote object proxy for the provider")
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
            fatalError("Failed to create a remote object proxy for the app")
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
            fatalError("Failed to create a remote object proxy for the app")
        }

        return providerProxy.getBlacklist(withData: response)
    }

    // drop events if no client is connected
    func sendEventToApp(newEvent event: String) {
        guard let connection = currentConnection else {
            return
        }

        guard let appProxy = connection.remoteObjectProxyWithErrorHandler({ sendError in
            NSLog("Failed to sent event to app %@", sendError.localizedDescription)
            self.currentConnection = nil
        }) as? AppCommunication else {
            fatalError("Failed to create a remote object proxy for the app")
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
        }

        newConnection.interruptionHandler = {
            self.currentConnection = nil
        }

        currentConnection = newConnection
        newConnection.resume()

        return true
    }
}

extension IPCConnection: ProviderCommunication {
    func register(_ completionHandler: @escaping (Bool) -> Void) {
        NSLog("App client connected.")
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

    func unregister() {
        currentConnection = nil
        NSLog("App client disconnected.")
    }
}
