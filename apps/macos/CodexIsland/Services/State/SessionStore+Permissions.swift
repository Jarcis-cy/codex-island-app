//
//  SessionStore+Permissions.swift
//  CodexIsland
//
//  Permission and tool-completion state transitions.
//

import Foundation
import os.log

extension SessionStore {
    func processPermissionApproved(sessionId: String, toolUseId: String) async {
        guard var session = sessions[sessionId] else { return }
        updateToolStatus(in: &session, toolId: toolUseId, status: .running)
        advanceApprovalPhase(afterHandling: toolUseId, session: &session, fallbackPhase: .processing, logPrefix: "Switched to next pending tool")
        sessions[sessionId] = session
    }

    func processToolCompleted(sessionId: String, toolUseId: String, result: ToolCompletionResult) async {
        guard var session = sessions[sessionId] else { return }

        if let existingItem = session.chatItems.first(where: { $0.id == toolUseId }),
           case .toolCall(let tool) = existingItem.type,
           tool.status == .success || tool.status == .error || tool.status == .interrupted {
            return
        }

        for index in 0 ..< session.chatItems.count {
            if session.chatItems[index].id == toolUseId,
               case .toolCall(var tool) = session.chatItems[index].type {
                tool.status = result.status
                tool.result = result.result
                tool.structuredResult = result.structuredResult
                session.chatItems[index] = ChatHistoryItem(
                    id: toolUseId,
                    type: .toolCall(tool),
                    timestamp: session.chatItems[index].timestamp
                )
                Self.logger.debug("Tool \(toolUseId.prefix(12), privacy: .public) completed with status: \(String(describing: result.status), privacy: .public)")
                break
            }
        }

        if case .waitingForApproval(let context) = session.phase, context.toolUseId == toolUseId {
            advanceApprovalPhase(afterHandling: toolUseId, session: &session, fallbackPhase: .processing, logPrefix: "Switched to next pending tool after completion")
        }

        sessions[sessionId] = session
    }

    func findNextPendingTool(in session: SessionState, excluding toolId: String) -> (id: String, name: String, timestamp: Date)? {
        ToolEventProcessor.findNextPendingTool(in: session, excluding: toolId)
    }

    func processPermissionDenied(sessionId: String, toolUseId: String, reason: String?) async {
        guard var session = sessions[sessionId] else { return }
        updateToolStatus(in: &session, toolId: toolUseId, status: .error)
        advanceApprovalPhase(afterHandling: toolUseId, session: &session, fallbackPhase: .processing, logPrefix: "Switched to next pending tool after denial")
        sessions[sessionId] = session
    }

    func processSocketFailure(sessionId: String, toolUseId: String) async {
        guard var session = sessions[sessionId] else { return }
        updateToolStatus(in: &session, toolId: toolUseId, status: .error)
        advanceApprovalPhase(afterHandling: toolUseId, session: &session, fallbackPhase: .idle, logPrefix: "Switched to next pending tool after socket failure")
        sessions[sessionId] = session
    }

    func updateToolStatus(in session: inout SessionState, toolId: String, status: ToolStatus) {
        ToolEventProcessor.updateToolStatus(in: &session, toolId: toolId, status: status)
    }

    private func advanceApprovalPhase(
        afterHandling toolUseId: String,
        session: inout SessionState,
        fallbackPhase: SessionPhase,
        logPrefix: String
    ) {
        if let nextPending = findNextPendingTool(in: session, excluding: toolUseId) {
            let nextPhase = SessionPhase.waitingForApproval(PermissionContext(
                toolUseId: nextPending.id,
                toolName: nextPending.name,
                toolInput: nil,
                receivedAt: nextPending.timestamp
            ))
            if session.phase.canTransition(to: nextPhase) {
                session.phase = nextPhase
                Self.logger.debug("\(logPrefix, privacy: .public): \(nextPending.id.prefix(12), privacy: .public)")
            }
            return
        }

        switch session.phase {
        case .waitingForApproval(let context) where context.toolUseId == toolUseId:
            if session.phase.canTransition(to: fallbackPhase) {
                session.phase = fallbackPhase
            }
        case .waitingForApproval:
            if session.phase.canTransition(to: fallbackPhase) {
                session.phase = fallbackPhase
            }
        default:
            break
        }
    }
}
