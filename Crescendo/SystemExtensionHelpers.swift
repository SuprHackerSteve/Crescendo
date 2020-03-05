import Foundation
import SystemExtensions

// Handler for system extension management
extension ViewController: OSSystemExtensionRequestDelegate {
    func request(_: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        if result != .completed {
            let msg = String(format: "Unexpected result %@ for system extension request", result.rawValue)
            showError(error: msg)
            status = .stopped
        } else {
            // System extension loaded and good...
            registerWithProvider()
            status = .running
        }
    }

    func request(_: OSSystemExtensionRequest, didFailWithError error: Error) {
        let msg = String(format: "Failed to load system extension: %@", error.localizedDescription)
        showError(error: msg)
        status = .stopped
    }

    func requestNeedsUserApproval(_: OSSystemExtensionRequest) {
        // swiftlint:disable:next line_length
        showError(error: "Please \"allow\" system extension in System Preferences.\nMAKE SURE TO ENABLE FULL DISK ACCESS FOR SYSTEM EXTENSION!")
        status = .stopped
    }

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension extension: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        NSLog("Replacing extension %@ version %@ with version %@", request.identifier,
              existing.bundleShortVersion,
              `extension`.bundleShortVersion)
        return .replace
    }
}

// IPC mechanism to get events out of system extension
extension ViewController: AppCommunication {
    func sendEventToApp(newEvent event: String) {
        logEvent(event: event)
    }
}
