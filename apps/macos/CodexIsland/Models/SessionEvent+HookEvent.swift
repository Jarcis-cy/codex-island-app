//
//  SessionEvent+HookEvent.swift
//  CodexIsland
//
//  HookEvent helpers used by the session state machine.
//

import Foundation

extension HookEvent {
    nonisolated func determinePhase() -> SessionPhase {
        if event == "PreCompact" {
            return .compacting
        }

        if expectsResponse, let tool = tool {
            return .waitingForApproval(PermissionContext(
                toolUseId: toolUseId ?? "",
                toolName: tool,
                toolInput: toolInput,
                receivedAt: Date()
            ))
        }

        if event == "Notification" && notificationType == "idle_prompt" {
            return .idle
        }

        switch status {
        case "waiting_for_input":
            return .waitingForInput
        case "running_tool", "processing", "starting":
            return .processing
        case "compacting":
            return .compacting
        case "ended":
            return .ended
        default:
            return .idle
        }
    }

    nonisolated var isToolEvent: Bool {
        event == "PreToolUse" || event == "PostToolUse" || event == "PermissionRequest"
    }

    nonisolated var shouldSyncFile: Bool {
        switch event {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop":
            return true
        default:
            return false
        }
    }
}
