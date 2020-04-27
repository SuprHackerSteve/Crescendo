//
//  libCrescendoTests.swift
//  libCrescendoTests
//
//  Created by suprhackersteve on 4/26/20.
//

import XCTest
import libCrescendo
import EndpointSecurityPrivate

class libCrescendoTests: XCTestCase {

    var client: ESClient?
    var eventList = [CrescendoEvent]()

    override func setUpWithError() throws {
        let esclient = enableCrescendo(completion: callback)
        if esclient.error != CrescendoError.success {
            XCTFail("Failed to create Crescendo listener.")
        }
        self.client = esclient.client

    }

    override func tearDownWithError() throws {
        _ = libCrescendo.disableCrescendo(esclient: self.client!)
    }

    func callback(event: CrescendoEvent) {
        self.eventList.append(event)
    }

    func testClientInit() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssert(self.client != nil)

    }

    func testProcExec() throws {
        let url = URL(fileURLWithPath:"/usr/bin/say")
        do {
            try Process.run(url, arguments: ["Hello World"]) { (process) in
                process.terminate()
            }
        } catch { }

        sleep(1)
        let activeItems = eventList.filter { $0.processpath.localizedCaseInsensitiveContains("/bin/say") }
        if activeItems.count <= 0 {
            XCTFail("Missing process execution.")
        }

    }
}
