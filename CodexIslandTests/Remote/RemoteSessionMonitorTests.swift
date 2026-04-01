import XCTest
@testable import Codex_Island

@MainActor
final class RemoteSessionMonitorTests: XCTestCase {
    func testStartThreadRecoversNewThreadAfterTimeout() async throws {
        let logger = TestDiagnosticsLogger()
        let connection = FakeRemoteConnection()
        let host = RemoteHostConfig(id: "host-1", name: "Remote", sshTarget: "ssh-target", defaultCwd: "", isEnabled: true)
        let recoveredThread = makeThread(id: "thread-new", preview: "Recovered")

        connection.startThreadHandler = { _ in
            throw RemoteSessionError.timeout("Timed out waiting for app-server response to thread/start")
        }
        connection.refreshThreadsHandler = {
            await connection.emit?(.threadUpsert(hostId: host.id, thread: recoveredThread))
        }

        let monitor = RemoteSessionMonitor(
            initialHosts: [host],
            loadHosts: { [host] in [host] },
            saveHosts: { _ in },
            diagnosticsLogger: logger,
            connectionFactory: { _, emit in
                connection.emit = emit
                return connection
            }
        )
        TestObjectRetainer.retain(monitor)

        monitor.startMonitoring()
        let recovered = try await monitor.startThread(hostId: host.id)

        XCTAssertEqual(recovered.threadId, "thread-new")
        XCTAssertNil(monitor.hostActionErrors[host.id])
    }

    func testSendMessageAddsOptimisticUserItemOnTimeout() async throws {
        let logger = TestDiagnosticsLogger()
        let connection = FakeRemoteConnection()
        let host = RemoteHostConfig(id: "host-1", name: "Remote", sshTarget: "ssh-target", defaultCwd: "", isEnabled: true)
        let baseThread = makeThread(id: "thread-1", preview: "Preview", status: .idle)

        connection.startThreadHandler = { _ in baseThread }
        connection.sendMessageHandler = { _, _, _ in
            throw RemoteSessionError.timeout("Timed out waiting for app-server response to turn/start")
        }

        let monitor = RemoteSessionMonitor(
            initialHosts: [host],
            loadHosts: { [host] in [host] },
            saveHosts: { _ in },
            diagnosticsLogger: logger,
            connectionFactory: { _, emit in
                connection.emit = emit
                return connection
            }
        )
        TestObjectRetainer.retain(monitor)

        monitor.startMonitoring()
        monitor.apply(event: .threadUpsert(hostId: host.id, thread: baseThread))
        let thread = try XCTUnwrap(monitor.threads.first)

        try await monitor.sendMessage(thread: thread, text: "hi")

        let updated = try XCTUnwrap(monitor.threads.first)
        XCTAssertEqual(updated.history.last?.type, .user("hi"))
        XCTAssertEqual(updated.phase, .processing)
    }

    func testApprovalEventSetsPendingApprovalState() throws {
        let logger = TestDiagnosticsLogger()
        let connection = FakeRemoteConnection()
        let host = RemoteHostConfig(id: "host-1", name: "Remote", sshTarget: "ssh-target", defaultCwd: "", isEnabled: true)
        let thread = makeThread(id: "thread-1", preview: "Preview", status: .idle)
        let approval = RemotePendingApproval(
            id: "approval-1",
            requestId: .int(1),
            kind: .commandExecution,
            itemId: "item-1",
            threadId: "thread-1",
            turnId: "turn-1",
            title: "Command Execution",
            detail: "pwd",
            requestedPermissions: .none
        )

        let monitor = RemoteSessionMonitor(
            initialHosts: [host],
            loadHosts: { [host] in [host] },
            saveHosts: { _ in },
            diagnosticsLogger: logger,
            connectionFactory: { _, emit in
                connection.emit = emit
                return connection
            }
        )
        TestObjectRetainer.retain(monitor)

        monitor.apply(event: .threadUpsert(hostId: host.id, thread: thread))
        monitor.apply(event: .approval(hostId: host.id, threadId: "thread-1", approval: approval))

        let updated = try XCTUnwrap(monitor.threads.first)
        XCTAssertEqual(updated.pendingApproval?.id, "approval-1")
        XCTAssertEqual(updated.phase.approvalToolName, "Command Execution")
        XCTAssertEqual(updated.pendingToolInput, "pwd")
    }

}
