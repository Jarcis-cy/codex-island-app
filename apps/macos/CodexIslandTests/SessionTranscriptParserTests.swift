import XCTest
@testable import Codex_Island

final class SessionTranscriptParserTests: XCTestCase {
    // facade 只有 provider 路由职责；这里锁住 codex 路径的运行时/交互转发，以及 claude 的空值约定。
    func testCodexSessionRoutesToCodexConversationParser() async throws {
        let transcript = #"""
        {"timestamp":"2026-04-07T01:00:00Z","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.4","collaboration_mode":{"mode":"default","settings":{"reasoning_effort":"high"}}}}
        {"timestamp":"2026-04-07T01:00:01Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Assistant reply"}]}}
        {"timestamp":"2026-04-07T01:00:02Z","type":"event_msg","payload":{"type":"request_user_input","payload":{"call_id":"call-followup","turn_id":"turn-1","questions":[{"header":"Next","id":"next_step","question":"Implement this plan?","options":[{"label":"Yes, implement this plan","description":"Proceed."},{"label":"No, stay in Plan mode","description":"Stay in planning."}]}]}}}
        """#
        let transcriptURL = try makeTranscriptFile(contents: transcript)
        let session = SessionState(
            sessionId: "codex-session",
            provider: .codex,
            cwd: "/tmp/codex-session",
            transcriptPath: transcriptURL.path
        )

        let runtimeInfo = await SessionTranscriptParser.shared.runtimeInfo(session: session)
        let conversationInfo = await SessionTranscriptParser.shared.parse(session: session)
        let interactions = await SessionTranscriptParser.shared.pendingInteractions(session: session)
        let phase = await SessionTranscriptParser.shared.transcriptPhase(session: session)

        XCTAssertEqual(runtimeInfo.model, "gpt-5.4")
        XCTAssertEqual(runtimeInfo.reasoningEffort, "high")
        XCTAssertEqual(conversationInfo.lastMessage, "Implement this plan?")
        XCTAssertEqual(interactions.count, 1)
        XCTAssertEqual(interactions.first?.id, "call-followup")
        XCTAssertEqual(phase, .waitingForInput)
    }

    // Claude parser 目前不产出 runtime info / pending interactions / transcript phase；facade 需要保持这个契约。
    func testClaudeSessionKeepsEmptyOptionalCapabilities() async {
        let session = SessionState(
            sessionId: "missing-claude-session",
            provider: .claude,
            cwd: "/tmp/non-existent-claude-project"
        )

        let runtimeInfo = await SessionTranscriptParser.shared.runtimeInfo(session: session)
        let interactions = await SessionTranscriptParser.shared.pendingInteractions(session: session)
        let phase = await SessionTranscriptParser.shared.transcriptPhase(session: session)

        XCTAssertEqual(runtimeInfo, .empty)
        XCTAssertTrue(interactions.isEmpty)
        XCTAssertNil(phase)
    }

    private func makeTranscriptFile(contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("rollout.jsonl")
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return fileURL
    }
}
