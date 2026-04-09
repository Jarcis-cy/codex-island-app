//
//  SessionStore+Publishing.swift
//  CodexIsland
//
//  File sync scheduling, published state, and query helpers.
//

import Combine
import Foundation

extension SessionStore {
    func scheduleFileSync(sessionId: String) {
        cancelPendingSync(sessionId: sessionId)

        pendingSyncs[sessionId] = Task { [weak self, syncDebounceNs] in
            try? await Task.sleep(nanoseconds: syncDebounceNs)
            guard !Task.isCancelled else { return }
            guard let self,
                  let session = await self.session(for: sessionId) else { return }

            let result = await SessionTranscriptParser.shared.parseIncremental(session: session)

            if result.clearDetected {
                await self.process(.clearDetected(sessionId: sessionId))
            }

            guard !result.newMessages.isEmpty || result.clearDetected else {
                return
            }

            let payload = FileUpdatePayload(
                sessionId: sessionId,
                cwd: session.cwd,
                messages: result.newMessages,
                isIncremental: !result.clearDetected,
                completedToolIds: result.completedToolIds,
                toolResults: result.toolResults,
                structuredResults: result.structuredResults,
                pendingInteractions: result.pendingInteractions,
                transcriptPhase: result.transcriptPhase
            )

            await self.process(.fileUpdated(payload))
        }
    }

    func cancelPendingSync(sessionId: String) {
        pendingSyncs[sessionId]?.cancel()
        pendingSyncs.removeValue(forKey: sessionId)
    }

    func publishState() {
        let publishedSessionIds = Set(logicalBindings.values)
        let sortedSessions = sessions.values
            .filter { publishedSessionIds.contains($0.sessionId) }
            .sorted { lhs, rhs in
                if lhs.logicalSessionId == rhs.logicalSessionId {
                    return lhs.lastActivity > rhs.lastActivity
                }
                return lhs.projectName < rhs.projectName
            }
        sessionsSubject.send(sortedSessions)
    }

    func session(for sessionId: String) -> SessionState? {
        sessions[sessionId]
    }

    func hasActivePermission(sessionId: String) -> Bool {
        guard let session = sessions[sessionId] else { return false }
        if case .waitingForApproval = session.phase {
            return true
        }
        return false
    }

    func allSessions() -> [SessionState] {
        Array(sessions.values)
    }
}
