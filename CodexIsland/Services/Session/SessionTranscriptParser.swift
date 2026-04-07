//
//  SessionTranscriptParser.swift
//  CodexIsland
//
//  Provider-aware transcript parsing facade.
//

import Foundation

actor SessionTranscriptParser {
    static let shared = SessionTranscriptParser()

    /// 这层 facade 的职责是把上层调用方从 provider-specific parser 中隔离出来。
    /// 上层只依赖统一的 transcript 能力集，新增 provider 时只需要补这一处路由。
    private struct Backend {
        let parse: @Sendable () async -> ConversationInfo
        let runtimeInfo: @Sendable () async -> SessionRuntimeInfo
        let parseFullConversation: @Sendable () async -> [ChatMessage]
        let parseIncremental: @Sendable () async -> ConversationParser.IncrementalParseResult
        let completedToolIds: @Sendable () async -> Set<String>
        let toolResults: @Sendable () async -> [String: ConversationParser.ToolResult]
        let structuredResults: @Sendable () async -> [String: ToolResultData]
        let pendingInteractions: @Sendable () async -> [PendingInteraction]
        let transcriptPhase: @Sendable () async -> SessionPhase?
    }

    func parse(session: SessionState) async -> ConversationInfo {
        await backend(for: session).parse()
    }

    func runtimeInfo(session: SessionState) async -> SessionRuntimeInfo {
        await backend(for: session).runtimeInfo()
    }

    func parseFullConversation(session: SessionState) async -> [ChatMessage] {
        await backend(for: session).parseFullConversation()
    }

    func parseIncremental(session: SessionState) async -> ConversationParser.IncrementalParseResult {
        await backend(for: session).parseIncremental()
    }

    func completedToolIds(session: SessionState) async -> Set<String> {
        await backend(for: session).completedToolIds()
    }

    func toolResults(session: SessionState) async -> [String: ConversationParser.ToolResult] {
        await backend(for: session).toolResults()
    }

    func structuredResults(session: SessionState) async -> [String: ToolResultData] {
        await backend(for: session).structuredResults()
    }

    func pendingInteractions(session: SessionState) async -> [PendingInteraction] {
        await backend(for: session).pendingInteractions()
    }

    func transcriptPhase(session: SessionState) async -> SessionPhase? {
        await backend(for: session).transcriptPhase()
    }

    private func backend(for session: SessionState) -> Backend {
        switch session.provider {
        case .claude:
            return Backend(
                parse: {
                    await ConversationParser.shared.parse(sessionId: session.sessionId, cwd: session.cwd)
                },
                runtimeInfo: { .empty },
                parseFullConversation: {
                    await ConversationParser.shared.parseFullConversation(
                        sessionId: session.sessionId,
                        cwd: session.cwd
                    )
                },
                parseIncremental: {
                    await ConversationParser.shared.parseIncremental(
                        sessionId: session.sessionId,
                        cwd: session.cwd
                    )
                },
                completedToolIds: {
                    await ConversationParser.shared.completedToolIds(for: session.sessionId)
                },
                toolResults: {
                    await ConversationParser.shared.toolResults(for: session.sessionId)
                },
                structuredResults: {
                    await ConversationParser.shared.structuredResults(for: session.sessionId)
                },
                pendingInteractions: {
                    await ConversationParser.shared.pendingInteractions(for: session.sessionId)
                },
                transcriptPhase: { nil }
            )
        case .codex:
            return Backend(
                parse: {
                    await CodexConversationParser.shared.parse(
                        sessionId: session.sessionId,
                        transcriptPath: session.transcriptPath
                    )
                },
                runtimeInfo: {
                    await CodexConversationParser.shared.runtimeInfo(
                        sessionId: session.sessionId,
                        transcriptPath: session.transcriptPath
                    )
                },
                parseFullConversation: {
                    await CodexConversationParser.shared.parseFullConversation(
                        sessionId: session.sessionId,
                        transcriptPath: session.transcriptPath
                    )
                },
                parseIncremental: {
                    await CodexConversationParser.shared.parseIncremental(
                        sessionId: session.sessionId,
                        transcriptPath: session.transcriptPath
                    )
                },
                completedToolIds: {
                    await CodexConversationParser.shared.completedToolIds(
                        sessionId: session.sessionId,
                        transcriptPath: session.transcriptPath
                    )
                },
                toolResults: {
                    await CodexConversationParser.shared.toolResults(
                        sessionId: session.sessionId,
                        transcriptPath: session.transcriptPath
                    )
                },
                structuredResults: {
                    await CodexConversationParser.shared.structuredResults(
                        sessionId: session.sessionId,
                        transcriptPath: session.transcriptPath
                    )
                },
                pendingInteractions: {
                    await CodexConversationParser.shared.pendingInteractions(
                        sessionId: session.sessionId,
                        transcriptPath: session.transcriptPath
                    )
                },
                transcriptPhase: {
                    await CodexConversationParser.shared.transcriptPhase(
                        sessionId: session.sessionId,
                        transcriptPath: session.transcriptPath
                    )
                }
            )
        }
    }
}
