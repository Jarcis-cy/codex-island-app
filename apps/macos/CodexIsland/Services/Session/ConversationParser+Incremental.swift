//
//  ConversationParser+Incremental.swift
//  CodexIsland
//
//  Incremental JSONL parsing and state management for Claude transcripts.
//

import Foundation

extension ConversationParser {
    struct IncrementalParseResult {
        let newMessages: [ChatMessage]
        let allMessages: [ChatMessage]
        let completedToolIds: Set<String>
        let toolResults: [String: ToolResult]
        let structuredResults: [String: ToolResultData]
        let pendingInteractions: [PendingInteraction]
        let transcriptPhase: SessionPhase?
        let clearDetected: Bool
    }

    func parseFullConversation(sessionId: String, cwd: String) -> [ChatMessage] {
        let sessionFile = Self.sessionFilePath(sessionId: sessionId, cwd: cwd)

        guard FileManager.default.fileExists(atPath: sessionFile) else {
            return []
        }

        var state = incrementalState[sessionId] ?? IncrementalParseState()
        _ = parseNewLines(filePath: sessionFile, state: &state)
        incrementalState[sessionId] = state

        return state.messages
    }

    func parseIncremental(sessionId: String, cwd: String) -> IncrementalParseResult {
        let sessionFile = Self.sessionFilePath(sessionId: sessionId, cwd: cwd)

        guard FileManager.default.fileExists(atPath: sessionFile) else {
            return IncrementalParseResult(
                newMessages: [],
                allMessages: [],
                completedToolIds: [],
                toolResults: [:],
                structuredResults: [:],
                pendingInteractions: [],
                transcriptPhase: nil,
                clearDetected: false
            )
        }

        var state = incrementalState[sessionId] ?? IncrementalParseState()
        let newMessages = parseNewLines(filePath: sessionFile, state: &state)
        let clearDetected = state.clearPending
        if clearDetected {
            state.clearPending = false
        }
        incrementalState[sessionId] = state

        return IncrementalParseResult(
            newMessages: newMessages,
            allMessages: state.messages,
            completedToolIds: state.completedToolIds,
            toolResults: state.toolResults,
            structuredResults: state.structuredResults,
            pendingInteractions: [],
            transcriptPhase: nil,
            clearDetected: clearDetected
        )
    }

    func completedToolIds(for sessionId: String) -> Set<String> {
        incrementalState[sessionId]?.completedToolIds ?? []
    }

    func toolResults(for sessionId: String) -> [String: ToolResult] {
        incrementalState[sessionId]?.toolResults ?? [:]
    }

    func structuredResults(for sessionId: String) -> [String: ToolResultData] {
        incrementalState[sessionId]?.structuredResults ?? [:]
    }

    func pendingInteractions(for sessionId: String) -> [PendingInteraction] {
        []
    }

    func resetState(for sessionId: String) {
        incrementalState.removeValue(forKey: sessionId)
    }

    func checkAndConsumeClearDetected(for sessionId: String) -> Bool {
        guard var state = incrementalState[sessionId], state.clearPending else {
            return false
        }
        state.clearPending = false
        incrementalState[sessionId] = state
        return true
    }
}
