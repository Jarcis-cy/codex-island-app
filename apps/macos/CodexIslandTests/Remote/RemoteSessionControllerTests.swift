import Combine
import XCTest
@testable import Codex_Island

@MainActor
final class RemoteSessionControllerTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    func testControllerMirrorsBackendPublishedState() {
        let backend = FakeRemoteSessionBackend()
        let controller = RemoteSessionController(backend: backend)

        backend.threadsSubject.send([Self.makeThread()])
        waitUntil {
            controller.threads.map(\.threadId) == ["thread-1"]
        }

        XCTAssertEqual(controller.threads.map(\.threadId), ["thread-1"])
    }

    func testControllerForwardsAsyncOperations() async throws {
        let backend = FakeRemoteSessionBackend()
        let controller = RemoteSessionController(backend: backend)

        _ = try await controller.openThread(hostId: "host-1", threadId: "thread-1")

        XCTAssertEqual(backend.openThreadCalls.count, 1)
        XCTAssertEqual(backend.openThreadCalls.first?.hostId, "host-1")
        XCTAssertEqual(backend.openThreadCalls.first?.threadId, "thread-1")
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail("Condition not satisfied before timeout", file: file, line: line)
    }

    fileprivate static func makeThread() -> RemoteThreadState {
        RemoteThreadState(
            hostId: "host-1",
            hostName: "Remote",
            threadId: "thread-1",
            logicalSessionId: "remote|host-1|/repo",
            preview: "Preview",
            name: "Thread 1",
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
private final class FakeRemoteSessionBackend: RemoteSessionControlling {
    let hostsSubject = CurrentValueSubject<[RemoteHostConfig], Never>([])
    let threadsSubject = CurrentValueSubject<[RemoteThreadState], Never>([])
    let hostStatesSubject = CurrentValueSubject<[String: RemoteHostConnectionState], Never>([:])
    let hostActionErrorsSubject = CurrentValueSubject<[String: String], Never>([:])
    let hostActionInProgressSubject = CurrentValueSubject<Set<String>, Never>([])

    private(set) var openThreadCalls: [(hostId: String, threadId: String)] = []

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
    func addHost() {}
    func updateHost(_ host: RemoteHostConfig) {}
    func removeHost(id: String) {}
    func connectHost(id: String) {}
    func disconnectHost(id: String) {}
    func startThread(hostId: String) async throws -> RemoteThreadState { RemoteSessionControllerTests.makeThread() }
    func startFreshThread(hostId: String) async throws -> RemoteThreadState { RemoteSessionControllerTests.makeThread() }
    func startFreshThread(hostId: String, defaultCwd: String) async throws -> RemoteThreadState { RemoteSessionControllerTests.makeThread() }

    func openThread(hostId: String, threadId: String) async throws -> RemoteThreadState {
        openThreadCalls.append((hostId, threadId))
        return RemoteSessionControllerTests.makeThread()
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
