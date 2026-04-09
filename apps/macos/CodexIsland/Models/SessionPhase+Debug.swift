//
//  SessionPhase+Debug.swift
//  CodexIsland
//
//  Debug string helpers for SessionPhase.
//

import Foundation

nonisolated extension SessionPhase: CustomStringConvertible {
    nonisolated var description: String {
        switch self {
        case .idle:
            return "idle"
        case .processing:
            return "processing"
        case .waitingForInput:
            return "waitingForInput"
        case .waitingForApproval(let context):
            return "waitingForApproval(\(context.toolName))"
        case .compacting:
            return "compacting"
        case .ended:
            return "ended"
        }
    }
}
