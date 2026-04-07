//
//  CodexConversationParser+Interactions.swift
//  CodexIsland
//
//  Event and pending-interaction parsing helpers for Codex transcripts.
//

import Foundation

extension CodexConversationParser {
    func parseResponseItem(
        _ payload: [String: Any],
        lineIndex: Int,
        timestamp: Date,
        messages: inout [ChatMessage],
        completedToolIds: inout Set<String>,
        toolResults: inout [String: ConversationParser.ToolResult],
        pendingInteractionOrder: inout [String],
        pendingInteractions: inout [String: PendingInteraction],
        proposedPlanPendingInteraction: inout PendingInteraction?,
        transcriptPhase: inout SessionPhase?
    ) {
        guard let payloadType = payload["type"] as? String else { return }

        switch payloadType {
        case "message":
            parseMessageResponseItem(
                payload,
                lineIndex: lineIndex,
                timestamp: timestamp,
                messages: &messages,
                proposedPlanPendingInteraction: &proposedPlanPendingInteraction,
                transcriptPhase: &transcriptPhase
            )
        case "reasoning":
            let text = parseReasoningText(payload)
            guard !text.isEmpty else { return }
            messages.append(ChatMessage(
                id: "codex-reasoning-\(lineIndex)",
                role: .assistant,
                timestamp: timestamp,
                content: [.thinking(text)]
            ))
        case "local_shell_call":
            let callId = (payload["call_id"] as? String) ?? "local-shell-\(lineIndex)"
            transcriptPhase = .processing
            messages.append(ChatMessage(
                id: "codex-tool-\(callId)",
                role: .assistant,
                timestamp: timestamp,
                content: [.toolUse(ToolUseBlock(id: callId, name: "Bash", input: ["command": parseLocalShellCommand(payload)]))]
            ))
        case "function_call":
            parseFunctionCallResponseItem(
                payload,
                timestamp: timestamp,
                messages: &messages,
                pendingInteractionOrder: &pendingInteractionOrder,
                pendingInteractions: &pendingInteractions,
                transcriptPhase: &transcriptPhase
            )
        case "custom_tool_call":
            guard let callId = payload["call_id"] as? String else { return }
            transcriptPhase = .processing
            messages.append(ChatMessage(
                id: "codex-tool-\(callId)",
                role: .assistant,
                timestamp: timestamp,
                content: [.toolUse(ToolUseBlock(id: callId, name: payload["name"] as? String ?? "CustomTool", input: ["input": payload["input"] as? String ?? ""]))]
            ))
        case "tool_search_call":
            let callId = (payload["call_id"] as? String) ?? "tool-search-\(lineIndex)"
            transcriptPhase = .processing
            messages.append(ChatMessage(
                id: "codex-tool-\(callId)",
                role: .assistant,
                timestamp: timestamp,
                content: [.toolUse(ToolUseBlock(id: callId, name: "ToolSearch", input: parseJSONObjectInput(payload["arguments"] as? [String: Any])))]
            ))
        case "web_search_call":
            let callId = (payload["id"] as? String) ?? "web-search-\(lineIndex)"
            transcriptPhase = .processing
            messages.append(ChatMessage(
                id: "codex-tool-\(callId)",
                role: .assistant,
                timestamp: timestamp,
                content: [.toolUse(ToolUseBlock(id: callId, name: "WebSearch", input: parseWebSearchInput(payload["action"] as? [String: Any])))]
            ))
            if let result = parseWebSearchResult(payload["action"] as? [String: Any]) {
                completedToolIds.insert(callId)
                toolResults[callId] = ConversationParser.ToolResult(content: result, stdout: nil, stderr: nil, isError: false)
            }
        case "image_generation_call":
            let callId = (payload["id"] as? String) ?? "image-generation-\(lineIndex)"
            transcriptPhase = .processing
            messages.append(ChatMessage(
                id: "codex-tool-\(callId)",
                role: .assistant,
                timestamp: timestamp,
                content: [.toolUse(ToolUseBlock(id: callId, name: "ImageGeneration", input: [:]))]
            ))
            if let result = payload["revised_prompt"] as? String ?? payload["result"] as? String {
                completedToolIds.insert(callId)
                toolResults[callId] = ConversationParser.ToolResult(content: result, stdout: nil, stderr: nil, isError: false)
            }
        case "function_call_output", "custom_tool_call_output":
            guard let callId = payload["call_id"] as? String else { return }
            completedToolIds.insert(callId)
            toolResults[callId] = ConversationParser.ToolResult(
                content: parseOutputText(payload["output"]),
                stdout: nil,
                stderr: nil,
                isError: false
            )
            pendingInteractions.removeValue(forKey: callId)
            pendingInteractionOrder.removeAll { $0 == callId }
        case "tool_search_output":
            let callId = (payload["call_id"] as? String) ?? "tool-search-output-\(lineIndex)"
            completedToolIds.insert(callId)
            toolResults[callId] = ConversationParser.ToolResult(
                content: parseToolSearchOutput(payload),
                stdout: nil,
                stderr: nil,
                isError: false
            )
        default:
            break
        }
    }

    func parseEventMsg(
        eventType: String,
        payload: [String: Any],
        completedToolIds: inout Set<String>,
        toolResults: inout [String: ConversationParser.ToolResult],
        pendingInteractionOrder: inout [String],
        pendingInteractions: inout [String: PendingInteraction],
        proposedPlanPendingInteraction: inout PendingInteraction?,
        transcriptPhase: inout SessionPhase?
    ) {
        switch eventType {
        case "task_started":
            pendingInteractions.removeAll()
            pendingInteractionOrder.removeAll()
            proposedPlanPendingInteraction = nil
            transcriptPhase = .processing
        case "exec_command_end":
            guard let callId = payload["call_id"] as? String else { return }
            completedToolIds.insert(callId)
            toolResults[callId] = ConversationParser.ToolResult(
                content: payload["aggregated_output"] as? String,
                stdout: payload["stdout"] as? String,
                stderr: payload["stderr"] as? String,
                isError: (payload["exit_code"] as? Int ?? 0) != 0
            )
        case "request_permissions":
            if let interaction = parseRequestPermissionsEvent(payload: payload) {
                recordPendingInteraction(interaction, order: &pendingInteractionOrder, pendingInteractions: &pendingInteractions)
            }
            transcriptPhase = .waitingForApproval(PermissionContext(
                toolUseId: payload["call_id"] as? String ?? "request_permissions",
                toolName: "Permissions Request",
                toolInput: nil,
                receivedAt: Date()
            ))
        case "exec_approval_request":
            if let interaction = parseExecApprovalEvent(payload: payload) {
                recordPendingInteraction(interaction, order: &pendingInteractionOrder, pendingInteractions: &pendingInteractions)
                transcriptPhase = .waitingForApproval(PermissionContext(
                    toolUseId: interaction.id,
                    toolName: "Command Execution",
                    toolInput: nil,
                    receivedAt: Date()
                ))
            }
        case "request_user_input":
            if let interaction = parseRequestUserInputEvent(payload: payload) {
                recordPendingInteraction(interaction, order: &pendingInteractionOrder, pendingInteractions: &pendingInteractions)
            }
            transcriptPhase = .waitingForInput
        case "turn_complete", "task_complete":
            transcriptPhase = .waitingForInput
        case "turn_aborted":
            pendingInteractions.removeAll()
            pendingInteractionOrder.removeAll()
            proposedPlanPendingInteraction = nil
            transcriptPhase = .waitingForInput
        default:
            break
        }
    }

    func finalizeTranscriptPhase(
        _ phase: SessionPhase?,
        pendingInteractions: [PendingInteraction]
    ) -> SessionPhase? {
        guard let pending = pendingInteractions.last else { return phase }
        switch pending {
        case .approval(let approval):
            return .waitingForApproval(PermissionContext(
                toolUseId: approval.id,
                toolName: approval.title,
                toolInput: nil,
                receivedAt: Date()
            ))
        case .userInput:
            return .waitingForInput
        }
    }

    private func parseMessageResponseItem(
        _ payload: [String: Any],
        lineIndex: Int,
        timestamp: Date,
        messages: inout [ChatMessage],
        proposedPlanPendingInteraction: inout PendingInteraction?,
        transcriptPhase: inout SessionPhase?
    ) {
        let rawRole = payload["role"] as? String
        guard rawRole != "developer", rawRole != "system" else { return }

        let role = rawRole.flatMap(ChatRole.init(rawValue:)) ?? .assistant
        let parsedContent = parseMessageContent(payload["content"] as? [[String: Any]])
        let blocks = parsedContent.blocks.filter { block in
            guard case .text(let text) = block else { return true }
            return !isCodexInjectedText(text)
        }
        guard !blocks.isEmpty else { return }

        messages.append(ChatMessage(
            id: "codex-message-\(lineIndex)",
            role: role,
            timestamp: timestamp,
            content: blocks
        ))

        if role == .assistant, parsedContent.containsProposedPlan {
            proposedPlanPendingInteraction = .userInput(makeProposedPlanFollowupInteraction(lineIndex: lineIndex))
            transcriptPhase = .waitingForInput
        }
    }

    private func parseFunctionCallResponseItem(
        _ payload: [String: Any],
        timestamp: Date,
        messages: inout [ChatMessage],
        pendingInteractionOrder: inout [String],
        pendingInteractions: inout [String: PendingInteraction],
        transcriptPhase: inout SessionPhase?
    ) {
        guard let callId = payload["call_id"] as? String else { return }
        let name = payload["name"] as? String ?? "Tool"
        let arguments = payload["arguments"] as? String
        transcriptPhase = .processing
        messages.append(ChatMessage(
            id: "codex-tool-\(callId)",
            role: .assistant,
            timestamp: timestamp,
            content: [.toolUse(ToolUseBlock(id: callId, name: name, input: parseJSONStringInput(arguments)))]
        ))
        if let interaction = parsePendingInteraction(callId: callId, toolName: name, arguments: arguments) {
            recordPendingInteraction(interaction, order: &pendingInteractionOrder, pendingInteractions: &pendingInteractions)
        }
    }

    private func recordPendingInteraction(
        _ interaction: PendingInteraction,
        order: inout [String],
        pendingInteractions: inout [String: PendingInteraction]
    ) {
        pendingInteractions[interaction.id] = interaction
        if !order.contains(interaction.id) {
            order.append(interaction.id)
        }
    }
}
