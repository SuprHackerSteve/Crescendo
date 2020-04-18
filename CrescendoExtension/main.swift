import Foundation
import libCrescendo

autoreleasepool {
    NSLog("Init Crescendo system extension")

    let client = startCrescendoClient()
    IPCConnection.shared.startListener(esclient: client)
}

dispatchMain()
