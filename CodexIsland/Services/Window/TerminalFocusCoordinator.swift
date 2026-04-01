//
//  TerminalFocusCoordinator.swift
//  CodexIsland
//
//  Unified entry point for focusing a session's terminal target.
//

import AppKit
import Foundation

actor TerminalFocusCoordinator {
    static let shared = TerminalFocusCoordinator()

    private init() {}

    func focus(session: SessionState) async -> Bool {
        guard let target = session.focusTarget else {
            return false
        }

        switch target.kind {
        case .tmuxPane:
            return await focusTmuxTarget(session: session, target: target)
        case .nativeWindow:
            let capability = await NativeTerminalWindowResolver.shared.focus(target: target)
            return capability == .ready
        }
    }

    private func focusTmuxTarget(session: SessionState, target: TerminalFocusTarget) async -> Bool {
        guard let targetString = target.tmuxTarget,
              let tmuxTarget = TmuxTarget(from: targetString) else {
            return await focusFallback(session: session)
        }

        _ = await TmuxController.shared.switchToPane(target: tmuxTarget)

        if await NativeTerminalWindowResolver.shared.focus(target: target) == .ready {
            return true
        }

        if let pid = session.pid {
            return await YabaiController.shared.focusWindow(forClaudePid: pid)
        }

        return await focusFallback(session: session)
    }

    private func focusFallback(session: SessionState) async -> Bool {
        if let appPid = session.terminalProcessId,
           let app = NSRunningApplication(processIdentifier: pid_t(appPid)) {
            return app.activate(options: [.activateAllWindows])
        }

        if let bundleId = session.terminalBundleId,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
            return app.activate(options: [.activateAllWindows])
        }

        if let pid = session.pid {
            return await YabaiController.shared.focusWindow(forClaudePid: pid)
        }

        return false
    }
}
