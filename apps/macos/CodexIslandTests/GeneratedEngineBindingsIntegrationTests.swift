import XCTest
@testable import Codex_Island

final class GeneratedEngineBindingsIntegrationTests: XCTestCase {
    func testGeneratedEngineRuntimeInitializesAndQueuesHello() {
        let runtime = EngineRuntime(config: ClientRuntimeConfig(
            clientName: "Codex Island macOS Tests",
            clientVersion: "0.0.0-test",
            authToken: "secret-token"
        ))

        let initialState = runtime.state()
        XCTAssertEqual(initialState.connection, .disconnected)
        XCTAssertEqual(runtime.clientName(), "Codex Island macOS Tests")
        XCTAssertEqual(runtime.authToken(), "secret-token")

        let requested = runtime.requestConnection()
        XCTAssertEqual(requested.connection, .connecting)
        XCTAssertEqual(requested.pendingCommands.first?.kind, .hello)

        let queuedHello = runtime.popNextCommandJson()
        XCTAssertNotNil(queuedHello)
        XCTAssertTrue(queuedHello?.contains("\"type\":\"hello\"") == true)
    }
}
