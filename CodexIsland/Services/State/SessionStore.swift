//
//  SessionStore.swift
//  CodexIsland
//
//  Central state manager for all Claude sessions.
//  Single source of truth - all state mutations flow through process().
//

import Combine
import Foundation
import Mixpanel
import os.log

/// Central state manager for all Claude sessions
/// Uses Swift actor for thread-safe state mutations
actor SessionStore {
    static let shared = SessionStore()

    /// Logger for session store (nonisolated static for cross-context access)
    nonisolated static let logger = Logger(subsystem: "com.codexisland", category: "Session")

    // MARK: - State

    /// All sessions keyed by sessionId
    var sessions: [String: SessionState] = [:]

    /// Published logical session slots keyed by logicalSessionId
    var logicalBindings: [String: String] = [:]

    /// Pending file syncs (debounced)
    var pendingSyncs: [String: Task<Void, Never>] = [:]

    /// Sync debounce interval (100ms)
    let syncDebounceNs: UInt64 = 100_000_000

    // MARK: - Published State (for UI)

    /// Publisher for session state changes (nonisolated for Combine subscription from any context)
    nonisolated(unsafe) let sessionsSubject = CurrentValueSubject<[SessionState], Never>([])

    /// Public publisher for UI subscription
    nonisolated var sessionsPublisher: AnyPublisher<[SessionState], Never> {
        sessionsSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Event Processing

    /// Process any session event - the ONLY way to mutate state
    func process(_ event: SessionEvent) async {
        Self.logger.debug("Processing: \(String(describing: event), privacy: .public)")

        switch event {
        case .hookReceived(let hookEvent):
            await processHookEvent(hookEvent)

        case .permissionApproved(let sessionId, let toolUseId):
            await processPermissionApproved(sessionId: sessionId, toolUseId: toolUseId)

        case .permissionDenied(let sessionId, let toolUseId, let reason):
            await processPermissionDenied(sessionId: sessionId, toolUseId: toolUseId, reason: reason)

        case .permissionSocketFailed(let sessionId, let toolUseId):
            await processSocketFailure(sessionId: sessionId, toolUseId: toolUseId)

        case .codexProcessExited(let sessionId):
            await processCodexProcessExited(sessionId: sessionId)

        case .fileUpdated(let payload):
            await processFileUpdate(payload)

        case .interruptDetected(let sessionId):
            await processInterrupt(sessionId: sessionId)

        case .clearDetected(let sessionId):
            await processClearDetected(sessionId: sessionId)

        case .sessionEnded(let sessionId):
            await processSessionEnd(sessionId: sessionId)

        case .loadHistory(let sessionId, let cwd):
            await loadHistoryFromFile(sessionId: sessionId, cwd: cwd)

        case .historyLoaded(let sessionId, let messages, let completedTools, let toolResults, let structuredResults, let pendingInteractions, let transcriptPhase, let conversationInfo, let runtimeInfo):
            await processHistoryLoaded(
                sessionId: sessionId,
                messages: messages,
                completedTools: completedTools,
                toolResults: toolResults,
                structuredResults: structuredResults,
                pendingInteractions: pendingInteractions,
                transcriptPhase: transcriptPhase,
                conversationInfo: conversationInfo,
                runtimeInfo: runtimeInfo
            )

        case .toolCompleted(let sessionId, let toolUseId, let result):
            await processToolCompleted(sessionId: sessionId, toolUseId: toolUseId, result: result)

        // MARK: - Subagent Events

        case .subagentStarted(let sessionId, let taskToolId):
            processSubagentStarted(sessionId: sessionId, taskToolId: taskToolId)

        case .subagentToolExecuted(let sessionId, let tool):
            processSubagentToolExecuted(sessionId: sessionId, tool: tool)

        case .subagentToolCompleted(let sessionId, let toolId, let status):
            processSubagentToolCompleted(sessionId: sessionId, toolId: toolId, status: status)

        case .subagentStopped(let sessionId, let taskToolId):
            processSubagentStopped(sessionId: sessionId, taskToolId: taskToolId)

        case .agentFileUpdated:
            // No longer used - subagent tools are populated from JSONL completion
            break
        }

        publishState()
    }

    // MARK: - Hook Event Processing

    private func processHookEvent(_ event: HookEvent) async {
        let sessionId = event.sessionId
        let isNewSession = sessions[sessionId] == nil
        var session = sessions[sessionId] ?? createSession(from: event)
        let previousPid = session.pid
        let previousTTY = session.tty
        let previousTmuxState = session.isInTmux

        // Track new session in Mixpanel
        if isNewSession {
            Mixpanel.safeMainInstance()?.track(event: "Session Started")
        }

        session.transcriptPath = event.transcriptPath ?? session.transcriptPath
        session.pid = event.pid
        session.terminalName = event.terminalName ?? session.terminalName
        updateTerminalContext(from: event, session: &session)
        if let pid = event.pid {
            let tree = ProcessTreeBuilder.shared.buildTree()
            session.isInTmux = ProcessTreeBuilder.shared.isInTmux(pid: pid, tree: tree)
        }
        if let tty = event.tty {
            session.tty = tty.replacingOccurrences(of: "/dev/", with: "")
        }
        session.lastActivity = Date()

        if shouldRefreshTerminalFocus(
            isNewSession: isNewSession,
            previousPid: previousPid,
            previousTTY: previousTTY,
            previousTmuxState: previousTmuxState,
            session: session
        ) {
            let resolution = await TerminalWindowResolver.shared.resolve(for: session)
            applyTerminalResolution(resolution, to: &session)
        }

        session.logicalSessionId = resolveLogicalSessionId(for: session)

        if event.status == "ended" {
            removeSession(sessionId: sessionId)
            return
        }

        if event.provider != .codex {
            let newPhase = event.determinePhase()

            if session.phase.canTransition(to: newPhase) {
                session.phase = newPhase
            } else {
                Self.logger.debug("Invalid transition: \(String(describing: session.phase), privacy: .public) -> \(String(describing: newPhase), privacy: .public), ignoring")
            }

            if event.event == "PermissionRequest", let toolUseId = event.toolUseId {
                Self.logger.debug("Setting tool \(toolUseId.prefix(12), privacy: .public) status to waitingForApproval")
                updateToolStatus(in: &session, toolId: toolUseId, status: .waitingForApproval)
            }

            processToolTracking(event: event, session: &session)
            processSubagentTracking(event: event, session: &session)

            if event.event == "Stop" {
                session.subagentState = SubagentState()
            }
        }

        bind(session: &session)
        sessions[sessionId] = session
        publishState()

        if event.shouldSyncFile {
            scheduleFileSync(sessionId: sessionId)
        }
    }

    private func createSession(from event: HookEvent) -> SessionState {
        SessionState(
            sessionId: event.sessionId,
            logicalSessionId: event.sessionId,
            provider: event.provider,
            cwd: event.cwd,
            projectName: URL(fileURLWithPath: event.cwd).lastPathComponent,
            transcriptPath: event.transcriptPath,
            pid: event.pid,
            tty: event.tty?.replacingOccurrences(of: "/dev/", with: ""),
            terminalName: event.terminalName,
            terminalWindowId: event.terminalWindowId,
            terminalTabId: event.terminalTabId,
            terminalSurfaceId: event.terminalSurfaceId,
            isInTmux: false,  // Will be updated
            phase: .idle
        )
    }

    private func shouldRefreshTerminalFocus(
        isNewSession: Bool,
        previousPid: Int?,
        previousTTY: String?,
        previousTmuxState: Bool,
        session: SessionState
    ) -> Bool {
        if isNewSession || session.focusTarget == nil {
            return true
        }

        if previousPid != session.pid || previousTTY != session.tty || previousTmuxState != session.isInTmux {
            return true
        }

        if session.focusCapability == .unresolved && session.pid != nil {
            return true
        }

        return false
    }

    private func applyTerminalResolution(_ resolution: TerminalWindowResolution, to session: inout SessionState) {
        session.terminalBundleId = resolution.terminalBundleId ?? session.terminalBundleId
        session.terminalProcessId = resolution.terminalProcessId ?? session.terminalProcessId
        session.focusTarget = resolution.focusTarget
        session.focusCapability = resolution.focusCapability
    }

    private func updateTerminalContext(from event: HookEvent, session: inout SessionState) {
        let isGhostty = isGhosttySession(terminalName: event.terminalName ?? session.terminalName, bundleId: session.terminalBundleId)

        if isGhostty {
            session.terminalWindowId = event.terminalWindowId
            session.terminalTabId = event.terminalTabId
            session.terminalSurfaceId = event.terminalSurfaceId
            return
        }

        session.terminalWindowId = event.terminalWindowId ?? session.terminalWindowId
        session.terminalTabId = event.terminalTabId ?? session.terminalTabId
        session.terminalSurfaceId = event.terminalSurfaceId ?? session.terminalSurfaceId
    }

    func processToolTracking(event: HookEvent, session: inout SessionState) {
        switch event.event {
        case "PreToolUse":
            ToolEventProcessor.processPreToolUse(event: event, session: &session)
        case "PostToolUse":
            ToolEventProcessor.processPostToolUse(event: event, session: &session)
        default:
            break
        }
    }

    func processSubagentTracking(event: HookEvent, session: inout SessionState) {
        switch event.event {
        case "PreToolUse":
            if event.tool == "Task", let toolUseId = event.toolUseId {
                let description = event.toolInput?["description"]?.value as? String
                session.subagentState.startTask(taskToolId: toolUseId, description: description)
                Self.logger.debug("Started Task subagent tracking: \(toolUseId.prefix(12), privacy: .public)")
            }

        case "PostToolUse":
            if event.tool == "Task" {
                Self.logger.debug("PostToolUse for Task received (subagent still running)")
            }

        case "SubagentStop":
            // SubagentStop fires when a subagent completes - stop tracking
            // Subagent tools are populated from agent file in processFileUpdated
            Self.logger.debug("SubagentStop received")

        default:
            break
        }
    }

    // MARK: - Subagent Event Handlers

    /// Handle subagent started event
    func processSubagentStarted(sessionId: String, taskToolId: String) {
        guard var session = sessions[sessionId] else { return }
        session.subagentState.startTask(taskToolId: taskToolId)
        sessions[sessionId] = session
    }

    /// Handle subagent tool executed event
    func processSubagentToolExecuted(sessionId: String, tool: SubagentToolCall) {
        guard var session = sessions[sessionId] else { return }
        session.subagentState.addSubagentTool(tool)
        sessions[sessionId] = session
    }

    /// Handle subagent tool completed event
    func processSubagentToolCompleted(sessionId: String, toolId: String, status: ToolStatus) {
        guard var session = sessions[sessionId] else { return }
        session.subagentState.updateSubagentToolStatus(toolId: toolId, status: status)
        sessions[sessionId] = session
    }

    /// Handle subagent stopped event
    func processSubagentStopped(sessionId: String, taskToolId: String) {
        guard var session = sessions[sessionId] else { return }
        session.subagentState.stopTask(taskToolId: taskToolId)
        sessions[sessionId] = session
        // Subagent tools will be populated from agent file in processFileUpdated
    }

    /// Parse ISO8601 timestamp string
    func parseTimestamp(_ timestampStr: String?) -> Date? {
        guard let str = timestampStr else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: str)
    }
}
