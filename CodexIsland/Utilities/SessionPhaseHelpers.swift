//
//  SessionPhaseHelpers.swift
//  CodexIsland
//
//  Helper functions for session phase display
//

import SwiftUI

enum SessionSummaryBucket: Equatable {
    case running
    case waiting
    case idle
}

struct SessionPhaseSummary: Equatable {
    let runningCount: Int
    let waitingCount: Int
    let idleCount: Int

    init(phases: [SessionPhase]) {
        var runningCount = 0
        var waitingCount = 0
        var idleCount = 0

        for phase in phases {
            switch SessionPhaseHelpers.summaryBucket(for: phase) {
            case .running:
                runningCount += 1
            case .waiting:
                waitingCount += 1
            case .idle:
                idleCount += 1
            case nil:
                continue
            }
        }

        self.runningCount = runningCount
        self.waitingCount = waitingCount
        self.idleCount = idleCount
    }

    var totalCount: Int {
        runningCount + waitingCount + idleCount
    }
}

struct SessionPhaseHelpers {
    static func summaryBucket(for phase: SessionPhase) -> SessionSummaryBucket? {
        switch phase {
        case .processing, .compacting:
            return .running
        case .waitingForApproval, .waitingForInput:
            return .waiting
        case .idle:
            return .idle
        case .ended:
            return nil
        }
    }

    /// Get color for session phase
    static func phaseColor(for phase: SessionPhase) -> Color {
        switch summaryBucket(for: phase) {
        case .running:
            return TerminalColors.blue
        case .waiting:
            return TerminalColors.amber
        case .idle:
            return TerminalColors.green
        case nil:
            return TerminalColors.dim
        }
    }

    /// Get description for session phase
    static func phaseDescription(for phase: SessionPhase) -> String {
        switch phase {
        case .waitingForApproval(let ctx):
            return "Waiting for approval: \(ctx.toolName)"
        case .waitingForInput:
            return "Ready for input"
        case .processing:
            return "Processing..."
        case .compacting:
            return "Compacting context..."
        case .idle:
            return "Idle"
        case .ended:
            return "Ended"
        }
    }

    /// Format time ago string
    static func timeAgo(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "now" }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}
