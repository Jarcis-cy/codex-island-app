//
//  SessionPhase+StateMachine.swift
//  CodexIsland
//
//  State transition and convenience helpers for SessionPhase.
//

import Foundation

extension SessionPhase {
    /// Check if a transition to the target phase is valid
    nonisolated func canTransition(to next: SessionPhase) -> Bool {
        switch (self, next) {
        case (.ended, _):
            return false
        case (_, .ended):
            return true
        case (.idle, .processing), (.idle, .waitingForApproval), (.idle, .compacting):
            return true
        case (.processing, .waitingForInput), (.processing, .waitingForApproval), (.processing, .compacting), (.processing, .idle):
            return true
        case (.waitingForInput, .processing), (.waitingForInput, .idle), (.waitingForInput, .compacting):
            return true
        case (.waitingForApproval, .processing), (.waitingForApproval, .idle), (.waitingForApproval, .waitingForInput), (.waitingForApproval, .waitingForApproval):
            return true
        case (.compacting, .processing), (.compacting, .idle), (.compacting, .waitingForInput):
            return true
        default:
            return self == next
        }
    }

    nonisolated func transition(to next: SessionPhase) -> SessionPhase? {
        canTransition(to: next) ? next : nil
    }

    nonisolated var needsAttention: Bool {
        switch self {
        case .waitingForApproval, .waitingForInput:
            return true
        default:
            return false
        }
    }

    nonisolated var isActive: Bool {
        switch self {
        case .processing, .compacting:
            return true
        default:
            return false
        }
    }

    nonisolated var isWaitingForApproval: Bool {
        if case .waitingForApproval = self {
            return true
        }
        return false
    }

    nonisolated var approvalToolName: String? {
        if case .waitingForApproval(let context) = self {
            return context.toolName
        }
        return nil
    }
}
