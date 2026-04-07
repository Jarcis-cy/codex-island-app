//
//  SessionStore+LocalSessions.swift
//  CodexIsland
//
//  Logical session binding and terminal identity helpers.
//

import Foundation

extension SessionStore {
    func resolveLogicalSessionId(for session: SessionState) -> String {
        let appId = normalizedTerminalIdentity(for: session)

        if let surfaceId = normalizedComponent(session.terminalSurfaceId) {
            let candidate = "local|\(appId)|surface|\(surfaceId)"
            if shouldFallbackFromTerminalMetadata(candidate: candidate, session: session) {
                return fallbackLogicalSessionId(for: session, appId: appId)
            }
            return candidate
        }

        if let windowId = normalizedComponent(session.terminalWindowId),
           let tabId = normalizedComponent(session.terminalTabId) {
            let candidate = "local|\(appId)|window-tab|\(windowId)|\(tabId)"
            if shouldFallbackFromTerminalMetadata(candidate: candidate, session: session) {
                return fallbackLogicalSessionId(for: session, appId: appId)
            }
            return candidate
        }

        if let windowId = normalizedComponent(session.terminalWindowId) {
            let candidate = "local|\(appId)|window|\(windowId)"
            if shouldFallbackFromTerminalMetadata(candidate: candidate, session: session) {
                return fallbackLogicalSessionId(for: session, appId: appId)
            }
            return candidate
        }

        return fallbackLogicalSessionId(for: session, appId: appId)
    }

    func fallbackLogicalSessionId(for session: SessionState, appId: String) -> String {
        if let tty = normalizedComponent(session.tty) {
            return "local|\(appId)|tty|\(tty)"
        }
        if let pid = session.pid {
            return "local|\(appId)|pid|\(pid)"
        }
        return "local|fallback|\(session.sessionId)"
    }

    func shouldFallbackFromTerminalMetadata(candidate: String, session: SessionState) -> Bool {
        guard isGhosttySession(session),
              let existingSessionId = logicalBindings[candidate],
              existingSessionId != session.sessionId,
              let existingSession = sessions[existingSessionId] else {
            return false
        }

        if let existingTTY = normalizedComponent(existingSession.tty),
           let currentTTY = normalizedComponent(session.tty) {
            return existingTTY != currentTTY
        }

        let existingCwd = normalizedPathComponent(existingSession.cwd)
        let currentCwd = normalizedPathComponent(session.cwd)
        return existingCwd != nil && currentCwd != nil && existingCwd != currentCwd
    }

    func normalizedTerminalIdentity(for session: SessionState) -> String {
        if let bundleId = normalizedComponent(session.terminalBundleId) {
            return bundleId
        }
        if let terminalName = normalizedComponent(session.terminalName) {
            return terminalName
        }
        return "unknown-terminal"
    }

    func normalizedComponent(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }

    func normalizedPathComponent(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    func isGhosttySession(_ session: SessionState) -> Bool {
        isGhosttySession(terminalName: session.terminalName, bundleId: session.terminalBundleId)
    }

    func isGhosttySession(terminalName: String?, bundleId: String?) -> Bool {
        normalizedComponent(bundleId) == "com.mitchellh.ghostty" ||
            normalizedComponent(terminalName) == "ghostty"
    }

    func bind(session: inout SessionState) {
        let sessionId = session.sessionId
        let logicalSessionId = session.logicalSessionId

        if let existingLogicalId = sessions[sessionId]?.logicalSessionId,
           existingLogicalId != logicalSessionId {
            logicalBindings.removeValue(forKey: existingLogicalId)
        }

        if let displacedSessionId = logicalBindings[logicalSessionId],
           displacedSessionId != sessionId {
            removeSession(sessionId: displacedSessionId, removeLogicalBinding: false)
        }

        logicalBindings[logicalSessionId] = sessionId
    }

    func removeSession(sessionId: String, removeLogicalBinding: Bool = true) {
        guard let removed = sessions.removeValue(forKey: sessionId) else {
            cancelPendingSync(sessionId: sessionId)
            return
        }

        if removeLogicalBinding {
            logicalBindings.removeValue(forKey: removed.logicalSessionId)
        }

        cancelPendingSync(sessionId: sessionId)
        if removed.provider == .claude {
            Task {
                await ConversationParser.shared.resetState(for: sessionId)
            }
        }
    }
}
