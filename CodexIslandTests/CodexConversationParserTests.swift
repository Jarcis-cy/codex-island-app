import XCTest
@testable import Codex_Island

final class CodexConversationParserTests: XCTestCase {
    func testRuntimeInfoParsesModelAndTokenUsage() async throws {
        let transcript = """
        {"timestamp":"2026-04-03T01:00:00Z","type":"session_meta","payload":{"model_provider":"openai"}}
        {"timestamp":"2026-04-03T01:00:01Z","type":"event_msg","payload":{"type":"task_started","payload":{"turn_id":"turn-1","model_context_window":950000}}}
        {"timestamp":"2026-04-03T01:00:02Z","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.4","effort":"xhigh","collaboration_mode":{"mode":"default","settings":{"model":"gpt-5.4","reasoning_effort":"xhigh"}}}}
        {"timestamp":"2026-04-03T01:00:03Z","type":"event_msg","payload":{"type":"token_count","payload":{"info":{"total_token_usage":{"input_tokens":120000,"cached_input_tokens":10000,"output_tokens":5000,"reasoning_output_tokens":800,"total_tokens":125000},"last_token_usage":{"input_tokens":95000,"cached_input_tokens":5000,"output_tokens":5000,"reasoning_output_tokens":1000,"total_tokens":100000},"model_context_window":950000}}}}
        """

        let url = try makeTranscriptFile(contents: transcript)

        let runtimeInfo = await CodexConversationParser.shared.runtimeInfo(
            sessionId: UUID().uuidString,
            transcriptPath: url.path
        )

        XCTAssertEqual(runtimeInfo.modelProvider, "openai")
        XCTAssertEqual(runtimeInfo.model, "gpt-5.4")
        XCTAssertEqual(runtimeInfo.reasoningEffort, "xhigh")
        XCTAssertEqual(runtimeInfo.tokenUsage?.modelContextWindow, 950000)
        XCTAssertEqual(runtimeInfo.tokenUsage?.totalTokenUsage.totalTokens, 125000)
        XCTAssertEqual(runtimeInfo.tokenUsage?.lastTokenUsage.totalTokens, 100000)
        XCTAssertEqual(runtimeInfo.tokenUsage?.contextRemainingPercent, 91)
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
