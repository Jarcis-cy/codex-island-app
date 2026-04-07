import XCTest
@testable import Codex_Island

final class RemoteAppServerConnectionTests: XCTestCase {
    // 这些回归主要锁连接层的序列化请求队列、失败态发射规则，以及 RPC 参数编码是否与 app-server 约定一致。
    func testBackgroundThreadListTimeoutDoesNotEmitFailedState() async throws {
        let transport = TestTransport()
        let logger = TestDiagnosticsLogger()
        let recorder = RemoteEventRecorder()
        let host = RemoteHostConfig(id: "host-1", name: "Remote", sshTarget: "ssh-target", defaultCwd: "", isEnabled: true)

        let connection = RemoteAppServerConnection(
            host: host,
            emit: { event in await recorder.append(event) },
            dependencies: RemoteAppServerConnectionDependencies(
                transportFactory: { _ in transport },
                processExecutor: TestProcessExecutor(),
                diagnosticsLogger: logger,
                requestTimeout: .milliseconds(50),
                initialRefreshDelay: .seconds(60),
                refreshInterval: .seconds(60),
                sleep: { duration in
                    try await Task.sleep(for: duration)
                }
            )
        )

        try await connection.installTransportForTesting(transport)
        await connection.refreshThreadsInBackground(reason: "test")

        let states = await recorder.connectionStates()
        XCTAssertFalse(states.contains { if case .failed = $0 { return true } else { return false } })
        await connection.stop()
    }

    func testQueuedThreadRequestsStillMatchResponsesByID() async throws {
        let transport = TestTransport()
        let logger = TestDiagnosticsLogger()
        let recorder = RemoteEventRecorder()
        let host = RemoteHostConfig(id: "host-1", name: "Remote", sshTarget: "ssh-target", defaultCwd: "", isEnabled: true)

        let connection = RemoteAppServerConnection(
            host: host,
            emit: { event in await recorder.append(event) },
            dependencies: RemoteAppServerConnectionDependencies(
                transportFactory: { _ in transport },
                processExecutor: TestProcessExecutor(),
                diagnosticsLogger: logger,
                requestTimeout: .seconds(1),
                initialRefreshDelay: .seconds(60),
                refreshInterval: .seconds(60),
                sleep: { duration in
                    try await Task.sleep(for: duration)
                }
            )
        )

        try await connection.installTransportForTesting(transport)

        async let startedThread: RemoteAppServerThreadStartResponse = connection.startThread(defaultCwd: "/tmp")
        async let resumedThread: RemoteAppServerThreadResumeResponse = connection.resumeThread(
            threadId: "thread-existing",
            turnContext: nil
        )

        try await waitUntil {
            let lines = await transport.sentLines
            return lines.count == 1 && ((try? Self.method(in: lines[0])) == "thread/start")
        }

        let initialLines = await transport.sentLines
        let startLine = try XCTUnwrap(initialLines.first)
        let startID = try extractID(from: startLine)

        try await transport.emitStdout(
            makeEnvelopeJSON(
                id: startID,
                result: threadResponsePayload(id: "thread-new", preview: "New")
            )
        )

        try await waitUntil {
            let lines = await transport.sentLines
            return lines.count == 2 && ((try? Self.method(in: lines[1])) == "thread/resume")
        }

        let sentLines = await transport.sentLines
        let resumeLine = try XCTUnwrap(sentLines.last)
        let resumeID = try extractID(from: resumeLine)
        try await transport.emitStdout(
            makeEnvelopeJSON(
                id: resumeID,
                result: threadResponsePayload(id: "thread-existing", preview: "Existing")
            )
        )

        let started = try await startedThread
        let resumed = try await resumedThread

        XCTAssertEqual(started.thread.id, "thread-new")
        XCTAssertEqual(resumed.thread.id, "thread-existing")

        await connection.stop()
    }

    func testStopDoesNotEmitFailedState() async throws {
        let transport = TestTransport()
        let logger = TestDiagnosticsLogger()
        let recorder = RemoteEventRecorder()
        let host = RemoteHostConfig(id: "host-1", name: "Remote", sshTarget: "ssh-target", defaultCwd: "", isEnabled: true)

        let connection = RemoteAppServerConnection(
            host: host,
            emit: { event in await recorder.append(event) },
            dependencies: RemoteAppServerConnectionDependencies(
                transportFactory: { _ in transport },
                processExecutor: TestProcessExecutor(),
                diagnosticsLogger: logger,
                requestTimeout: .seconds(1),
                initialRefreshDelay: .seconds(60),
                refreshInterval: .seconds(60),
                sleep: { duration in
                    try await Task.sleep(for: duration)
                }
            )
        )

        try await connection.installTransportForTesting(transport)
        await connection.stop()
        let states = await recorder.connectionStates()
        XCTAssertFalse(states.contains { if case .failed = $0 { return true } else { return false } })
        let stopCount = await transport.stopCount
        XCTAssertEqual(stopCount, 1)
    }

    // thread/start 前要把绝对 cwd 规范成目录路径，避免远端把文件路径误当成工作目录。
    func testStartThreadNormalizesAbsoluteCwdToDirectoryPath() async throws {
        let transport = TestTransport()
        let logger = TestDiagnosticsLogger()
        let recorder = RemoteEventRecorder()
        let host = RemoteHostConfig(id: "host-1", name: "Remote", sshTarget: "ssh-target", defaultCwd: "", isEnabled: true)

        let connection = RemoteAppServerConnection(
            host: host,
            emit: { event in await recorder.append(event) },
            dependencies: RemoteAppServerConnectionDependencies(
                transportFactory: { _ in transport },
                processExecutor: TestProcessExecutor(),
                diagnosticsLogger: logger,
                requestTimeout: .seconds(1),
                initialRefreshDelay: .seconds(60),
                refreshInterval: .seconds(60),
                sleep: { duration in
                    try await Task.sleep(for: duration)
                }
            )
        )

        try await connection.installTransportForTesting(transport)

        async let startTask: RemoteAppServerThreadStartResponse = connection.startThread(defaultCwd: "/srv/dhr")

        try await waitUntil {
            let lines = await transport.sentLines
            return lines.count == 1
        }

        let sentLines = await transport.sentLines
        let line = try XCTUnwrap(sentLines.first)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let params = try XCTUnwrap(payload["params"] as? [String: Any])
        XCTAssertEqual(payload["method"] as? String, "thread/start")
        XCTAssertEqual(params["cwd"] as? String, "/srv/dhr/")

        try await transport.emitStdout(
            makeEnvelopeJSON(
                id: try extractID(from: line),
                result: threadResponsePayload(id: "thread-new", preview: "New")
            )
        )

        _ = try await startTask
        await connection.stop()
    }

    func testQueuedRequestsWaitForPreviousResponse() async throws {
        let transport = TestTransport()
        let logger = TestDiagnosticsLogger()
        let recorder = RemoteEventRecorder()
        let host = RemoteHostConfig(id: "host-1", name: "Remote", sshTarget: "ssh-target", defaultCwd: "", isEnabled: true)

        let connection = RemoteAppServerConnection(
            host: host,
            emit: { event in await recorder.append(event) },
            dependencies: RemoteAppServerConnectionDependencies(
                transportFactory: { _ in transport },
                processExecutor: TestProcessExecutor(),
                diagnosticsLogger: logger,
                requestTimeout: .seconds(1),
                initialRefreshDelay: .seconds(60),
                refreshInterval: .seconds(60),
                sleep: { duration in
                    try await Task.sleep(for: duration)
                }
            )
        )

        try await connection.installTransportForTesting(transport)

        async let listTask: Void = {
            try await connection.refreshThreads()
        }()
        async let startTask: RemoteAppServerThreadStartResponse = connection.startThread(defaultCwd: "/tmp")

        try await waitUntil {
            let lines = await transport.sentLines
            return lines.count == 1
        }

        let firstSentLines = await transport.sentLines
        let firstLine = try XCTUnwrap(firstSentLines.first)
        XCTAssertEqual(try Self.method(in: firstLine), "thread/list")
        try await transport.emitStdout(
            makeEnvelopeJSON(
                id: try extractID(from: firstLine),
                result: ["data": [], "nextCursor": NSNull()]
            )
        )

        try await waitUntil {
            let lines = await transport.sentLines
            return lines.count == 2
        }

        let secondSentLines = await transport.sentLines
        let secondLine = try XCTUnwrap(secondSentLines.last)
        XCTAssertEqual(try Self.method(in: secondLine), "thread/start")
        try await transport.emitStdout(
            makeEnvelopeJSON(
                id: try extractID(from: secondLine),
                result: threadResponsePayload(id: "thread-new", preview: "New")
            )
        )

        _ = try await listTask
        let started = try await startTask
        XCTAssertEqual(started.thread.id, "thread-new")
        await connection.stop()
    }

    // turn/start 既发消息，也携带 model / sandbox / collaboration 覆盖项；这里锁 JSON 编码细节。
    func testSendMessageIncludesTurnStartOverrides() async throws {
        let transport = TestTransport()
        let logger = TestDiagnosticsLogger()
        let recorder = RemoteEventRecorder()
        let host = RemoteHostConfig(id: "host-1", name: "Remote", sshTarget: "ssh-target", defaultCwd: "", isEnabled: true)

        let connection = RemoteAppServerConnection(
            host: host,
            emit: { event in await recorder.append(event) },
            dependencies: RemoteAppServerConnectionDependencies(
                transportFactory: { _ in transport },
                processExecutor: TestProcessExecutor(),
                diagnosticsLogger: logger,
                requestTimeout: .seconds(1),
                initialRefreshDelay: .seconds(60),
                refreshInterval: .seconds(60),
                sleep: { duration in
                    try await Task.sleep(for: duration)
                }
            )
        )

        try await connection.installTransportForTesting(transport)

        let turnContext = RemoteThreadTurnContext(
            model: "gpt-5.4",
            reasoningEffort: .high,
            approvalPolicy: .onRequest,
            approvalsReviewer: .user,
            sandboxPolicy: .workspaceWrite(networkAccessEnabled: false),
            serviceTier: nil,
            collaborationMode: RemoteAppServerCollaborationMode(
                mode: .plan,
                settings: RemoteAppServerCollaborationSettings(
                    developerInstructions: nil,
                    model: "gpt-5.4",
                    reasoningEffort: .high
                )
            )
        )

        async let sendTask: Void = connection.sendMessage(
            threadId: "thread-1",
            text: "build the plan",
            activeTurnId: nil,
            turnContext: turnContext
        )

        try await waitUntil {
            let lines = await transport.sentLines
            return lines.count == 1
        }

        let sentLines = await transport.sentLines
        let line = try XCTUnwrap(sentLines.first)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let params = try XCTUnwrap(payload["params"] as? [String: Any])

        XCTAssertEqual(payload["method"] as? String, "turn/start")
        XCTAssertEqual(params["model"] as? String, "gpt-5.4")
        XCTAssertEqual(params["effort"] as? String, "high")
        XCTAssertEqual(params["approvalPolicy"] as? String, "on-request")
        XCTAssertEqual(params["approvalsReviewer"] as? String, "user")

        let sandbox = try XCTUnwrap(params["sandboxPolicy"] as? [String: Any])
        XCTAssertEqual(sandbox["type"] as? String, "workspaceWrite")

        let collaborationMode = try XCTUnwrap(params["collaborationMode"] as? [String: Any])
        XCTAssertEqual(collaborationMode["mode"] as? String, "plan")
        let settings = try XCTUnwrap(collaborationMode["settings"] as? [String: Any])
        XCTAssertEqual(settings["model"] as? String, "gpt-5.4")
        XCTAssertEqual(settings["reasoning_effort"] as? String, "high")
        XCTAssertTrue(settings["developerInstructions"] is NSNull)

        try await transport.emitStdout(
            makeEnvelopeJSON(
                id: try extractID(from: line),
                result: ["turn": ["id": "turn-1", "items": [], "status": "inProgress", "error": NSNull()]]
            )
        )

        _ = try await sendTask
        await connection.stop()
    }

    // 远端模型面板依赖 model/list，而不是 thread/list；这里锁 RPC 方法名和返回解码。
    func testListModelsUsesModelsListRpc() async throws {
        let transport = TestTransport()
        let logger = TestDiagnosticsLogger()
        let recorder = RemoteEventRecorder()
        let host = RemoteHostConfig(id: "host-1", name: "Remote", sshTarget: "ssh-target", defaultCwd: "", isEnabled: true)

        let connection = RemoteAppServerConnection(
            host: host,
            emit: { event in await recorder.append(event) },
            dependencies: RemoteAppServerConnectionDependencies(
                transportFactory: { _ in transport },
                processExecutor: TestProcessExecutor(),
                diagnosticsLogger: logger,
                requestTimeout: .seconds(1),
                initialRefreshDelay: .seconds(60),
                refreshInterval: .seconds(60),
                sleep: { duration in
                    try await Task.sleep(for: duration)
                }
            )
        )

        try await connection.installTransportForTesting(transport)

        async let listTask: [RemoteAppServerModel] = connection.listModels(includeHidden: false)

        try await waitUntil {
            let lines = await transport.sentLines
            return lines.count == 1
        }

        let sentLines = await transport.sentLines
        let line = try XCTUnwrap(sentLines.first)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(payload["method"] as? String, "model/list")

        try await transport.emitStdout(
            makeEnvelopeJSON(
                id: try extractID(from: line),
                result: [
                    "data": [[
                        "id": "preset-1",
                        "model": "gpt-5.4",
                        "displayName": "GPT-5.4",
                        "description": "Flagship",
                        "hidden": false,
                        "supportedReasoningEfforts": [[
                            "reasoningEffort": "medium",
                            "description": "Balanced"
                        ]],
                        "defaultReasoningEffort": "medium",
                        "isDefault": true
                    ]],
                    "nextCursor": NSNull()
                ]
            )
        )

        let models = try await listTask
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.model, "gpt-5.4")
        await connection.stop()
    }

    func testLoadTranscriptFallbackContentUsesByteTailOverSSH() async throws {
        let logger = TestDiagnosticsLogger()
        let recorder = RemoteEventRecorder()
        let host = RemoteHostConfig(id: "host-1", name: "Remote", sshTarget: "ssh-target", defaultCwd: "", isEnabled: true)
        let invocation = LockedValueBox((executable: "", arguments: [String]()))

        let connection = RemoteAppServerConnection(
            host: host,
            emit: { event in await recorder.append(event) },
            dependencies: RemoteAppServerConnectionDependencies(
                transportFactory: { _ in TestTransport() },
                processExecutor: TestProcessExecutor(
                    runHandler: { executable, arguments in
                        invocation.set((executable: executable, arguments: arguments))
                        return "{\"timestamp\":\"2026-04-03T01:00:01Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"payload\":{\"turn_id\":\"turn-1\"}}}"
                    }
                ),
                diagnosticsLogger: logger,
                requestTimeout: .seconds(1),
                initialRefreshDelay: .seconds(60),
                refreshInterval: .seconds(60),
                sleep: { duration in
                    try await Task.sleep(for: duration)
                }
            )
        )

        let content = try await connection.loadTranscriptFallbackContent(
            transcriptPath: "/remote/thread.jsonl",
            maxBytes: 4096
        )

        XCTAssertNotNil(content)
        let capturedInvocation = invocation.get()
        XCTAssertEqual(capturedInvocation.executable, "/usr/bin/ssh")
        XCTAssertTrue(capturedInvocation.arguments.contains("ssh-target"))
        XCTAssertTrue(capturedInvocation.arguments.contains("tail -c 65536 -- '/remote/thread.jsonl'"))
    }

    func testLoadTranscriptFallbackContentReadsTrailingBytesLocally() async throws {
        let logger = TestDiagnosticsLogger()
        let recorder = RemoteEventRecorder()
        let host = RemoteHostConfig(id: "local", name: "Local", sshTarget: "local-app-server", defaultCwd: "", isEnabled: true)
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let transcriptURL = temporaryDirectory.appendingPathComponent("thread.jsonl")
        let prefix = String(repeating: "x", count: 70_000)
        let suffix = #"{"timestamp":"2026-04-03T01:00:01Z","type":"event_msg","payload":{"type":"task_started","payload":{"turn_id":"turn-1"}}}"#
        try (prefix + suffix).write(to: transcriptURL, atomically: true, encoding: .utf8)

        let connection = RemoteAppServerConnection(
            host: host,
            emit: { event in await recorder.append(event) },
            dependencies: RemoteAppServerConnectionDependencies(
                transportFactory: { _ in TestTransport() },
                processExecutor: TestProcessExecutor(),
                diagnosticsLogger: logger,
                requestTimeout: .seconds(1),
                initialRefreshDelay: .seconds(60),
                refreshInterval: .seconds(60),
                sleep: { duration in
                    try await Task.sleep(for: duration)
                }
            )
        )

        let content = try await connection.loadTranscriptFallbackContent(
            transcriptPath: transcriptURL.path,
            maxBytes: 4096
        )

        XCTAssertTrue(content?.hasSuffix(suffix) ?? false)
        XCTAssertLessThanOrEqual(content?.lengthOfBytes(using: .utf8) ?? .max, 65_536)
    }

    // 测试里直接从发出的 JSON-RPC envelope 取请求 id，用于把模拟响应精确送回对应 await。
    private func extractID(from line: String) throws -> Int {
        let data = Data(line.utf8)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["id"] as? Int)
    }

    nonisolated private static func method(in line: String) throws -> String? {
        let data = Data(line.utf8)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return object["method"] as? String
    }

    // 统一最小 thread payload，避免每个测试手写一份 app-server thread JSON。
    private func threadPayload(id: String, preview: String) -> [String: Any] {
        [
            "id": id,
            "preview": preview,
            "ephemeral": false,
            "modelProvider": "openai",
            "createdAt": 1_700_000_000,
            "updatedAt": 1_700_000_100,
            "status": ["type": "idle"],
            "path": NSNull(),
            "cwd": "/tmp",
            "cliVersion": "1.0.0",
            "name": NSNull(),
            "turns": []
        ]
    }

    // thread/start / thread/resume 都返回这组包裹字段，集中复用能让协议断言保持一致。
    private func threadResponsePayload(id: String, preview: String) -> [String: Any] {
        [
            "thread": threadPayload(id: id, preview: preview),
            "model": "gpt-5.4",
            "modelProvider": "openai",
            "serviceTier": NSNull(),
            "cwd": "/tmp",
            "approvalPolicy": "on-request",
            "approvalsReviewer": "user",
            "sandbox": [
                "type": "workspaceWrite",
                "networkAccess": false,
                "writableRoots": [],
                "excludeTmpdirEnvVar": false,
                "excludeSlashTmp": false,
                "readOnlyAccess": [
                    "type": "fullAccess"
                ]
            ],
            "reasoningEffort": "medium",
            "collaborationMode": NSNull()
        ]
    }
}
