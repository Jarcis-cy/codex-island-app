//
//  SharedEngineRemoteSessionBackend.swift
//  CodexIsland
//
//  Shared-engine-backed remote/session backend scaffold for macOS migration.
//

import Combine
import Foundation

@MainActor
final class SharedEngineRemoteSessionBackend: ObservableObject, RemoteSessionControlling {
    @Published private(set) var hosts: [RemoteHostConfig]
    @Published private(set) var threads: [RemoteThreadState] = []
    @Published private(set) var hostStates: [String: RemoteHostConnectionState] = [:]
    @Published private(set) var hostActionErrors: [String: String] = [:]
    @Published private(set) var hostActionInProgress: Set<String> = []

    private let runtime: any SharedEngineRuntimeDriving
    private let hostID: String

    var hostsPublisher: AnyPublisher<[RemoteHostConfig], Never> {
        $hosts.eraseToAnyPublisher()
    }

    var threadsPublisher: AnyPublisher<[RemoteThreadState], Never> {
        $threads.eraseToAnyPublisher()
    }

    var hostStatesPublisher: AnyPublisher<[String: RemoteHostConnectionState], Never> {
        $hostStates.eraseToAnyPublisher()
    }

    var hostActionErrorsPublisher: AnyPublisher<[String: String], Never> {
        $hostActionErrors.eraseToAnyPublisher()
    }

    var hostActionInProgressPublisher: AnyPublisher<Set<String>, Never> {
        $hostActionInProgress.eraseToAnyPublisher()
    }

    init(
        host: RemoteHostConfig,
        runtime: any SharedEngineRuntimeDriving
    ) {
        self.hosts = [host]
        self.hostID = host.id
        self.runtime = runtime
        apply(runtimeState: runtime.currentState())
    }

    func startMonitoring() {
        do {
            _ = try runtime.send(.requestConnection)
            _ = try runtime.send(.getSnapshot)
            apply(runtimeState: runtime.currentState())
        } catch {
            hostActionErrors[hostID] = error.localizedDescription
        }
    }

    func createThread(hostId: String, onSuccess: @escaping @MainActor (RemoteThreadState) -> Void) {
        hostActionInProgress.insert(hostId)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.hostActionInProgress.remove(hostId) }
            do {
                let thread = try await self.startFreshThread(hostId: hostId)
                onSuccess(thread)
            } catch {
                self.hostActionErrors[hostId] = error.localizedDescription
            }
        }
    }

    func refreshHost(id: String) {
        guard id == hostID else { return }
        Task { @MainActor [weak self] in
            try? await self?.refreshHostNow(id: id)
        }
    }

    func refreshHostNow(id: String) async throws {
        guard id == hostID else { return }
        _ = try runtime.send(.getSnapshot)
        apply(runtimeState: runtime.currentState())
    }

    func listModels(hostId: String, includeHidden: Bool) async throws -> [RemoteAppServerModel] {
        throw RemoteSessionError.transport("Shared engine backend has not wired model listing yet.")
    }

    func listCollaborationModes(hostId: String) async throws -> [RemoteAppServerCollaborationModeMask] {
        throw RemoteSessionError.transport("Shared engine backend has not wired collaboration mode listing yet.")
    }

    func addHost() {}

    func updateHost(_ host: RemoteHostConfig) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        hosts[index] = host
        apply(runtimeState: runtime.currentState())
    }

    func removeHost(id: String) {
        guard id == hostID else { return }
        hosts.removeAll { $0.id == id }
        threads = []
        hostStates[id] = .disconnected
    }

    func connectHost(id: String) {
        guard id == hostID else { return }
        do {
            _ = try runtime.send(.requestConnection)
            _ = try runtime.send(.getSnapshot)
            apply(runtimeState: runtime.currentState())
        } catch {
            hostActionErrors[id] = error.localizedDescription
        }
    }

    func disconnectHost(id: String) {
        guard id == hostID else { return }
        do {
            _ = try runtime.send(.setShouldReconnect(false))
            _ = try runtime.send(.transportDisconnected(reason: "Disconnected by user"))
        } catch {
            hostActionErrors[id] = error.localizedDescription
        }
        apply(runtimeState: runtime.currentState())
    }

    func startThread(hostId: String) async throws -> RemoteThreadState {
        try await startFreshThread(hostId: hostId)
    }

    func startFreshThread(hostId: String) async throws -> RemoteThreadState {
        let defaultCwd = hosts.first(where: { $0.id == hostId })?.defaultCwd ?? ""
        return try await startFreshThread(hostId: hostId, defaultCwd: defaultCwd)
    }

    func startFreshThread(hostId: String, defaultCwd: String) async throws -> RemoteThreadState {
        guard hostId == hostID else { throw RemoteSessionError.invalidConfiguration("Remote host no longer exists") }

        let payload = JSONEncoderPayload.object([
            "cwd": .string(defaultCwd)
        ]).jsonString

        _ = try runtime.send(.appServerRequest(
            requestId: "thread-start-\(UUID().uuidString)",
            method: "thread/start",
            paramsJSON: payload
        ))
        apply(runtimeState: runtime.currentState())

        guard let thread = threads.first else {
            throw RemoteSessionError.missingThread
        }
        return thread
    }

    func openThread(hostId: String, threadId: String) async throws -> RemoteThreadState {
        guard hostId == hostID else { throw RemoteSessionError.invalidConfiguration("Remote host no longer exists") }

        let payload = JSONEncoderPayload.object([
            "threadId": .string(threadId)
        ]).jsonString

        _ = try runtime.send(.appServerRequest(
            requestId: "thread-resume-\(UUID().uuidString)",
            method: "thread/resume",
            paramsJSON: payload
        ))
        apply(runtimeState: runtime.currentState())

        if let thread = findThread(hostId: hostId, threadId: threadId, transcriptPath: nil) {
            return thread
        }
        guard let thread = threads.first else {
            throw RemoteSessionError.missingThread
        }
        return thread
    }

    func sendMessage(thread: RemoteThreadState, text: String) async throws {
        let payload: String
        let method: String
        if let activeTurnId = thread.activeTurnId, thread.canSteerTurn {
            method = "turn/steer"
            payload = JSONEncoderPayload.object([
                "threadId": .string(thread.threadId),
                "expectedTurnId": .string(activeTurnId),
                "input": .array([.object(["type": .string("text"), "text": .string(text)])])
            ]).jsonString
        } else {
            method = "turn/start"
            payload = JSONEncoderPayload.object([
                "threadId": .string(thread.threadId),
                "input": .array([.object(["type": .string("text"), "text": .string(text)])])
            ]).jsonString
        }

        _ = try runtime.send(.appServerRequest(
            requestId: "\(method)-\(UUID().uuidString)",
            method: method,
            paramsJSON: payload
        ))
        appendLocalInfoMessage(thread: thread, message: "Queued via shared engine: \(text)")
        apply(runtimeState: runtime.currentState())
    }

    func setTurnContext(
        thread: RemoteThreadState,
        turnContext desiredTurnContext: RemoteThreadTurnContext,
        synchronizeThread: Bool
    ) async throws -> RemoteThreadState {
        thread
    }

    func interrupt(thread: RemoteThreadState) async throws {
        guard let turnId = thread.activeTurnId else { return }
        _ = try runtime.send(.appServerInterrupt(threadId: thread.threadId, turnId: turnId))
        apply(runtimeState: runtime.currentState())
    }

    func approve(thread: RemoteThreadState) async throws {
        try await respond(thread: thread, action: .allow)
    }

    func deny(thread: RemoteThreadState) async throws {
        try await respond(thread: thread, action: .deny)
    }

    func respond(thread: RemoteThreadState, action: PendingApprovalAction) async throws {
        let decision: String = action == .allow ? "accept" : "decline"
        _ = try runtime.send(.appServerResponse(
            requestId: "approval-\(thread.threadId)",
            resultJSON: JSONEncoderPayload.object(["decision": .string(decision)]).jsonString
        ))
        apply(runtimeState: runtime.currentState())
    }

    func respond(
        thread: RemoteThreadState,
        interaction: PendingUserInputInteraction,
        answers: PendingInteractionAnswerPayload
    ) async throws {
        let serializedAnswers = answers.answers.mapValues { value in
            JSONEncoderPayload.object(["answers": .array(value.map(JSONEncoderPayload.string))])
        }
        _ = try runtime.send(.appServerResponse(
            requestId: interaction.remoteRequestID.stringValue,
            resultJSON: JSONEncoderPayload.object([
                "answers": .object(serializedAnswers)
            ]).jsonString
        ))
        apply(runtimeState: runtime.currentState())
    }

    func availableThreads(hostId: String, excluding threadId: String?) -> [RemoteThreadState] {
        threads.filter { thread in
            thread.hostId == hostId && thread.threadId != threadId
        }
    }

    func findThread(hostId: String, threadId: String?, transcriptPath: String?) -> RemoteThreadState? {
        threads.first { thread in
            thread.hostId == hostId &&
                (threadId == nil || thread.threadId == threadId)
        }
    }

    func appendLocalInfoMessage(thread: RemoteThreadState, message: String) {
        guard let index = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        threads[index].history.append(
            ChatHistoryItem(
                id: "shared-engine-info-\(UUID().uuidString)",
                type: .assistant(message),
                timestamp: Date()
            )
        )
        threads[index].updatedAt = Date()
    }

    func applyServerEventJSON(_ eventJSON: String) throws {
        let state = try runtime.applyServerEvent(eventJSON)
        apply(runtimeState: state)
    }

    private func apply(runtimeState: SharedEngineRuntimeState) {
        guard let host = hosts.first(where: { $0.id == hostID }) else {
            threads = []
            hostStates[hostID] = .disconnected
            return
        }

        let hostProjection = EngineHostAdapterState(runtimeState: runtimeState, preferredHostName: host.displayName)
        hostStates[hostID] = hostProjection.connectionState

        if let threadProjection = EngineThreadAdapterState(
            runtimeState: runtimeState,
            preferredHostName: host.displayName,
            cwd: runtimeState.snapshot.health.appServer.cwd ?? host.defaultCwd
        ) {
            let previousHistory = findThread(hostId: hostID, threadId: threadProjection.threadID, transcriptPath: nil)?.history ?? []
            var projected = threadProjection.makeRemoteThreadState()
            projected.history = previousHistory
            threads = [projected]
        } else {
            threads = []
        }

        if let lastError = hostProjection.lastErrorMessage, !lastError.isEmpty {
            hostActionErrors[hostID] = lastError
        } else {
            hostActionErrors.removeValue(forKey: hostID)
        }
    }
}

private enum JSONEncoderPayload {
    case string(String)
    case array([JSONEncoderPayload])
    case object([String: JSONEncoderPayload])

    var jsonString: String {
        switch self {
        case .string(let value):
            return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        case .array(let values):
            return "[" + values.map(\.jsonString).joined(separator: ",") + "]"
        case .object(let values):
            let body = values.map { key, value in
                "\"\(key)\":\(value.jsonString)"
            }
            .sorted()
            .joined(separator: ",")
            return "{\(body)}"
        }
    }
}

private extension RemoteRPCID {
    var stringValue: String {
        switch self {
        case .int(let value):
            return String(value)
        case .string(let value):
            return value
        }
    }
}
