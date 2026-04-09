//
//  CodexConversationParser.swift
//  CodexIsland
//
//  Parses Codex rollout/transcript JSONL files.
//

import Foundation

actor CodexConversationParser {
    static let shared = CodexConversationParser()

    // Exposes the subset of snapshot state that callers need when they already
    // have transcript content in memory instead of a file path on disk.
    nonisolated struct ParsedHistorySnapshot: Sendable {
        let history: [ChatHistoryItem]
        let pendingInteractions: [PendingInteraction]
        let transcriptPhase: SessionPhase?
        let runtimeInfo: SessionRuntimeInfo
    }

    // Snapshot is the parser's canonical, cacheable view of one transcript
    // revision. All public accessors read from this model so file parsing,
    // message ordering, pending interaction tracking, and conversation summary
    // stay consistent.
    private struct Snapshot {
        let modificationDate: Date
        let messages: [ChatMessage]
        let messageIds: Set<String>
        let completedToolIds: Set<String>
        let toolResults: [String: ConversationParser.ToolResult]
        let structuredResults: [String: ToolResultData]
        let pendingInteractions: [PendingInteraction]
        let transcriptPhase: SessionPhase?
        let conversationInfo: ConversationInfo
        let runtimeInfo: SessionRuntimeInfo
    }

    private var snapshots: [String: Snapshot] = [:]

    func parse(sessionId: String, transcriptPath: String?) -> ConversationInfo {
        loadSnapshot(sessionId: sessionId, transcriptPath: transcriptPath)?.conversationInfo
            ?? ConversationInfo(
                summary: nil,
                lastMessage: nil,
                lastMessageRole: nil,
                lastToolName: nil,
                firstUserMessage: nil,
                lastUserMessageDate: nil
            )
    }

    func runtimeInfo(sessionId: String, transcriptPath: String?) -> SessionRuntimeInfo {
        loadSnapshot(sessionId: sessionId, transcriptPath: transcriptPath)?.runtimeInfo ?? .empty
    }

    func parseFullConversation(sessionId: String, transcriptPath: String?) -> [ChatMessage] {
        loadSnapshot(sessionId: sessionId, transcriptPath: transcriptPath)?.messages ?? []
    }

    func parseIncremental(
        sessionId: String,
        transcriptPath: String?
    ) -> ConversationParser.IncrementalParseResult {
        guard let transcriptPath,
              FileManager.default.fileExists(atPath: transcriptPath),
              let attrs = try? FileManager.default.attributesOfItem(atPath: transcriptPath),
              let modDate = attrs[.modificationDate] as? Date else {
            return ConversationParser.IncrementalParseResult(
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

        let key = cacheKey(sessionId: sessionId, transcriptPath: transcriptPath)
        let previous = snapshots[key]
        let snapshot = buildSnapshot(transcriptPath: transcriptPath, modificationDate: modDate)
        snapshots[key] = snapshot

        let newMessages: [ChatMessage]
        if let previous {
            newMessages = snapshot.messages.filter { !previous.messageIds.contains($0.id) }
        } else {
            newMessages = snapshot.messages
        }

        return ConversationParser.IncrementalParseResult(
            newMessages: newMessages,
            allMessages: snapshot.messages,
            completedToolIds: snapshot.completedToolIds,
            toolResults: snapshot.toolResults,
            structuredResults: snapshot.structuredResults,
            pendingInteractions: snapshot.pendingInteractions,
            transcriptPhase: snapshot.transcriptPhase,
            clearDetected: false
        )
    }

    func completedToolIds(sessionId: String, transcriptPath: String?) -> Set<String> {
        loadSnapshot(sessionId: sessionId, transcriptPath: transcriptPath)?.completedToolIds ?? []
    }

    func toolResults(sessionId: String, transcriptPath: String?) -> [String: ConversationParser.ToolResult] {
        loadSnapshot(sessionId: sessionId, transcriptPath: transcriptPath)?.toolResults ?? [:]
    }

    func structuredResults(sessionId: String, transcriptPath: String?) -> [String: ToolResultData] {
        loadSnapshot(sessionId: sessionId, transcriptPath: transcriptPath)?.structuredResults ?? [:]
    }

    func pendingInteractions(sessionId: String, transcriptPath: String?) -> [PendingInteraction] {
        loadSnapshot(sessionId: sessionId, transcriptPath: transcriptPath)?.pendingInteractions ?? []
    }

    func transcriptPhase(sessionId: String, transcriptPath: String?) -> SessionPhase? {
        loadSnapshot(sessionId: sessionId, transcriptPath: transcriptPath)?.transcriptPhase
    }

    func parseContent(sessionId: String, content: String) -> ParsedHistorySnapshot {
        let snapshot = buildSnapshot(content: content, modificationDate: Date())
        return ParsedHistorySnapshot(
            history: buildHistoryItems(
                messages: snapshot.messages,
                completedToolIds: snapshot.completedToolIds,
                toolResults: snapshot.toolResults,
                structuredResults: snapshot.structuredResults
            ),
            pendingInteractions: snapshot.pendingInteractions,
            transcriptPhase: snapshot.transcriptPhase,
            runtimeInfo: snapshot.runtimeInfo
        )
    }

    private func loadSnapshot(sessionId: String, transcriptPath: String?) -> Snapshot? {
        guard let transcriptPath,
              FileManager.default.fileExists(atPath: transcriptPath),
              let attrs = try? FileManager.default.attributesOfItem(atPath: transcriptPath),
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }

        let key = cacheKey(sessionId: sessionId, transcriptPath: transcriptPath)
        if let cached = snapshots[key], cached.modificationDate == modDate {
            return cached
        }

        let snapshot = buildSnapshot(transcriptPath: transcriptPath, modificationDate: modDate)
        snapshots[key] = snapshot
        return snapshot
    }

    private func cacheKey(sessionId: String, transcriptPath: String) -> String {
        "\(sessionId):\(transcriptPath)"
    }

    private func buildSnapshot(transcriptPath: String, modificationDate: Date) -> Snapshot {
        guard let data = FileManager.default.contents(atPath: transcriptPath),
              let content = String(data: data, encoding: .utf8) else {
            return emptySnapshot(modificationDate: modificationDate)
        }

        return buildSnapshot(content: content, modificationDate: modificationDate)
    }

    private func buildSnapshot(content: String, modificationDate: Date) -> Snapshot {
        guard !content.isEmpty else {
            return emptySnapshot(modificationDate: modificationDate)
        }

        var messages: [ChatMessage] = []
        var completedToolIds: Set<String> = []
        var toolResults: [String: ConversationParser.ToolResult] = [:]
        var pendingInteractionOrder: [String] = []
        var pendingInteractions: [String: PendingInteraction] = [:]
        var proposedPlanPendingInteraction: PendingInteraction?
        var transcriptPhase: SessionPhase?
        var runtimeInfo = SessionRuntimeInfo.empty

        // Local Codex transcripts are append-only JSONL. We intentionally parse
        // line-by-line and tolerate malformed records so one bad event does not
        // hide the rest of the conversation from the UI.
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for (lineIndex, line) in lines.enumerated() {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let lineType = json["type"] as? String else {
                continue
            }

            let timestamp = parseTimestamp(json["timestamp"] as? String)

            switch lineType {
            case "session_meta":
                if let payload = json["payload"] as? [String: Any] {
                    updateRuntimeInfo(&runtimeInfo, sessionMetaPayload: payload)
                }
            case "turn_context":
                if let payload = json["payload"] as? [String: Any] {
                    updateRuntimeInfo(&runtimeInfo, turnContextPayload: payload)
                }
            case "response_item":
                guard let payload = json["payload"] as? [String: Any] else { continue }
                parseResponseItem(
                    payload,
                    lineIndex: lineIndex,
                    timestamp: timestamp,
                    messages: &messages,
                    completedToolIds: &completedToolIds,
                    toolResults: &toolResults,
                    pendingInteractionOrder: &pendingInteractionOrder,
                    pendingInteractions: &pendingInteractions,
                    proposedPlanPendingInteraction: &proposedPlanPendingInteraction,
                    transcriptPhase: &transcriptPhase
                )
            case "event_msg":
                guard let payload = json["payload"] as? [String: Any],
                      let eventType = payload["type"] as? String,
                      let eventPayload = eventPayload(from: payload) else {
                    continue
                }
                updateRuntimeInfo(&runtimeInfo, eventType: eventType, payload: eventPayload)
                parseEventMsg(
                    eventType: eventType,
                    payload: eventPayload,
                    completedToolIds: &completedToolIds,
                    toolResults: &toolResults,
                    pendingInteractionOrder: &pendingInteractionOrder,
                    pendingInteractions: &pendingInteractions,
                    proposedPlanPendingInteraction: &proposedPlanPendingInteraction,
                    transcriptPhase: &transcriptPhase
                )
            default:
                continue
            }
        }

        messages.sort { $0.timestamp < $1.timestamp }
        let orderedPendingInteractions: [PendingInteraction]
        // Plan mode can emit a proposed plan marker without an explicit
        // request_user_input tool call. We synthesize a single follow-up
        // interaction so the local UI still offers the expected "implement or
        // keep planning" decision.
        if pendingInteractionOrder.isEmpty, let proposedPlanPendingInteraction {
            orderedPendingInteractions = [proposedPlanPendingInteraction]
        } else {
            orderedPendingInteractions = pendingInteractionOrder.compactMap { pendingInteractions[$0] }
        }
        let conversationInfo = buildConversationInfo(
            messages: messages,
            pendingInteractions: orderedPendingInteractions
        )

        return Snapshot(
            modificationDate: modificationDate,
            messages: messages,
            messageIds: Set(messages.map(\.id)),
            completedToolIds: completedToolIds,
            toolResults: toolResults,
            structuredResults: [:],
            pendingInteractions: orderedPendingInteractions,
            transcriptPhase: finalizeTranscriptPhase(
                transcriptPhase,
                pendingInteractions: orderedPendingInteractions
            ),
            conversationInfo: conversationInfo,
            runtimeInfo: runtimeInfo
        )
    }

    private func emptySnapshot(modificationDate: Date) -> Snapshot {
        Snapshot(
            modificationDate: modificationDate,
            messages: [],
            messageIds: [],
            completedToolIds: [],
            toolResults: [:],
            structuredResults: [:],
            pendingInteractions: [],
            transcriptPhase: nil,
            conversationInfo: ConversationInfo(
                summary: nil,
                lastMessage: nil,
                lastMessageRole: nil,
                lastToolName: nil,
                firstUserMessage: nil,
                lastUserMessageDate: nil
            ),
            runtimeInfo: .empty
        )
    }
}
