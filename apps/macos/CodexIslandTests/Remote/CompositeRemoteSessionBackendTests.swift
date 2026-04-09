import Combine
import XCTest
@testable import Codex_Island

@MainActor
final class CompositeRemoteSessionBackendTests: XCTestCase {
    func testCompositeBackendMergesPublishedState() {
        let primary = RecordingRemoteSessionBackend()
        let secondary = RecordingRemoteSessionBackend()
        let backend = CompositeRemoteSessionBackend(
            primary: primary,
            secondary: secondary,
            secondaryHostIDs: ["local-app-server"]
        )

        primary.hostsSubject.send([
            RemoteHostConfig(id: "remote-1", name: "Remote 1", sshTarget: "devbox", defaultCwd: "/repo", isEnabled: true)
        ])
        primary.threadsSubject.send([Self.makeThread(hostId: "remote-1", threadId: "thread-remote")])
        primary.hostStatesSubject.send(["remote-1": .connected])
        secondary.hostsSubject.send([
            RemoteHostConfig(id: "local-app-server", name: "Local", sshTarget: "local-app-server", defaultCwd: "", isEnabled: true)
        ])
        secondary.threadsSubject.send([Self.makeThread(hostId: "local-app-server", threadId: "thread-local")])
        secondary.hostStatesSubject.send(["local-app-server": .connecting])

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(backend.hosts.map(\.id), ["remote-1", "local-app-server"])
        XCTAssertEqual(backend.threads.map(\.threadId), ["thread-remote", "thread-local"])
        XCTAssertEqual(backend.hostStates["remote-1"], .connected)
        XCTAssertEqual(backend.hostStates["local-app-server"], .connecting)
    }

    func testCompositeBackendRoutesLocalHostOperationsToSecondaryBackend() async throws {
        let primary = RecordingRemoteSessionBackend()
        let secondary = RecordingRemoteSessionBackend()
        let backend = CompositeRemoteSessionBackend(
            primary: primary,
            secondary: secondary,
            secondaryHostIDs: ["local-app-server"]
        )

        primary.hostsSubject.send([
            RemoteHostConfig(id: "remote-1", name: "Remote 1", sshTarget: "devbox", defaultCwd: "/repo", isEnabled: true)
        ])
        secondary.hostsSubject.send([
            RemoteHostConfig(id: "local-app-server", name: "Local", sshTarget: "local-app-server", defaultCwd: "", isEnabled: true)
        ])
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        _ = try await backend.openThread(hostId: "local-app-server", threadId: "thread-local")
        backend.addHost()

        XCTAssertEqual(secondary.openThreadCalls.first?.hostId, "local-app-server")
        XCTAssertEqual(secondary.openThreadCalls.first?.threadId, "thread-local")
        XCTAssertEqual(primary.addHostCallCount, 1)
        XCTAssertTrue(primary.openThreadCalls.isEmpty)
    }

    fileprivate static func makeThread(hostId: String, threadId: String) -> RemoteThreadState {
        RemoteThreadState(
            hostId: hostId,
            hostName: hostId,
            threadId: threadId,
            logicalSessionId: "logical-\(threadId)",
            preview: "Preview",
            name: threadId,
            cwd: "/repo",
            phase: .idle,
            lastActivity: Date(timeIntervalSince1970: 10),
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 10),
            lastMessage: nil,
            lastMessageRole: nil,
            lastToolName: nil,
            lastUserMessageDate: nil,
            history: [],
            activeTurnId: nil,
            isLoaded: true,
            canSteerTurn: false,
            pendingApproval: nil,
            pendingInteractions: [],
            connectionState: .connected,
            turnContext: .empty,
            tokenUsage: nil
        )
    }
}

@MainActor
private final class RecordingRemoteSessionBackend: RemoteSessionControlling {
    let hostsSubject = CurrentValueSubject<[RemoteHostConfig], Never>([])
    let threadsSubject = CurrentValueSubject<[RemoteThreadState], Never>([])
    let hostStatesSubject = CurrentValueSubject<[String: RemoteHostConnectionState], Never>([:])
    let hostActionErrorsSubject = CurrentValueSubject<[String: String], Never>([:])
    let hostActionInProgressSubject = CurrentValueSubject<Set<String>, Never>([])

    private(set) var openThreadCalls: [(hostId: String, threadId: String)] = []
    private(set) var addHostCallCount = 0

    var hostsPublisher: AnyPublisher<[RemoteHostConfig], Never> { hostsSubject.eraseToAnyPublisher() }
    var threadsPublisher: AnyPublisher<[RemoteThreadState], Never> { threadsSubject.eraseToAnyPublisher() }
    var hostStatesPublisher: AnyPublisher<[String: RemoteHostConnectionState], Never> { hostStatesSubject.eraseToAnyPublisher() }
    var hostActionErrorsPublisher: AnyPublisher<[String: String], Never> { hostActionErrorsSubject.eraseToAnyPublisher() }
    var hostActionInProgressPublisher: AnyPublisher<Set<String>, Never> { hostActionInProgressSubject.eraseToAnyPublisher() }

    func startMonitoring() {}
    func createThread(hostId: String, onSuccess: @escaping @MainActor (RemoteThreadState) -> Void) {}
    func refreshHost(id: String) {}
    func refreshHostNow(id: String) async throws {}
    func listModels(hostId: String, includeHidden: Bool) async throws -> [RemoteAppServerModel] { [] }
    func listCollaborationModes(hostId: String) async throws -> [RemoteAppServerCollaborationModeMask] { [] }

    func addHost() {
        addHostCallCount += 1
    }

    func updateHost(_ host: RemoteHostConfig) {}
    func removeHost(id: String) {}
    func connectHost(id: String) {}
    func disconnectHost(id: String) {}
    func startThread(hostId: String) async throws -> RemoteThreadState { CompositeRemoteSessionBackendTests.makeThread(hostId: hostId, threadId: "started") }
    func startFreshThread(hostId: String) async throws -> RemoteThreadState { CompositeRemoteSessionBackendTests.makeThread(hostId: hostId, threadId: "fresh") }
    func startFreshThread(hostId: String, defaultCwd: String) async throws -> RemoteThreadState { CompositeRemoteSessionBackendTests.makeThread(hostId: hostId, threadId: "fresh") }

    func openThread(hostId: String, threadId: String) async throws -> RemoteThreadState {
        openThreadCalls.append((hostId, threadId))
        return CompositeRemoteSessionBackendTests.makeThread(hostId: hostId, threadId: threadId)
    }

    func sendMessage(thread: RemoteThreadState, text: String) async throws {}

    func setTurnContext(
        thread: RemoteThreadState,
        turnContext desiredTurnContext: RemoteThreadTurnContext,
        synchronizeThread: Bool
    ) async throws -> RemoteThreadState {
        thread
    }

    func interrupt(thread: RemoteThreadState) async throws {}
    func approve(thread: RemoteThreadState) async throws {}
    func deny(thread: RemoteThreadState) async throws {}
    func respond(thread: RemoteThreadState, action: PendingApprovalAction) async throws {}
    func respond(
        thread: RemoteThreadState,
        interaction: PendingUserInputInteraction,
        answers: PendingInteractionAnswerPayload
    ) async throws {}
    func availableThreads(hostId: String, excluding threadId: String?) -> [RemoteThreadState] { [] }
    func findThread(hostId: String, threadId: String?, transcriptPath: String?) -> RemoteThreadState? { nil }
    func appendLocalInfoMessage(thread: RemoteThreadState, message: String) {}
}
