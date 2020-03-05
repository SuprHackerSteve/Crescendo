import Crescendo
import Foundation

signal(SIGINT, SIG_IGN)

func printer(event: CrescendoEvent) {
    NSLog(event)
}

let client = enableCrescendo(completion: printer)
if client.error != CrescendoError.success {
    print("Failed to create Crescendo listern: \(client.error)")
    exit(EXIT_FAILURE)
}

print("Listening for events. Press CNTL-C to exit...")

let keyboardInterruptWaiter = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
keyboardInterruptWaiter.setEventHandler {
    _ = disableCrescendo(esclient: client.client)
    exit(EXIT_SUCCESS)
}

keyboardInterruptWaiter.resume()
dispatchMain()
