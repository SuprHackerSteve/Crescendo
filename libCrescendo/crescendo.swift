import EndpointSecurityPrivate
import Foundation

public enum CrescendoError: Error {
    case success
    case failedEnable
    case alreadyEnabled
    case newClientError
    case failedSubscription
}

public func enableCrescendo(completion: @escaping (_: CrescendoEvent) -> Void) ->
    (client: ESClient, error: CrescendoError) {
    let client = ESClient(completion: completion)
    let ret = client.startEventProducer()
    if ret != ESClientError.success {
        return (client, CrescendoError.failedSubscription)
    }
    NSLog("Enabled Crescendo subsystem.")
    return (client, CrescendoError.success)
}

public func disableCrescendo(esclient: ESClient) -> CrescendoError {
    esclient.stopEventProducer()
    NSLog("Crescendo disabled.")
    return CrescendoError.success
}
