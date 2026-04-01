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
        if !session.isInTmux, await NativeTerminalScriptFocuser.shared.focus(session: session) {
            return true
        }

        var target = session.focusTarget

        if target == nil || session.focusCapability != .ready {
            let resolution = await TerminalWindowResolver.shared.resolve(for: session)
            target = resolution.focusTarget

            if resolution.focusCapability == .ready, let resolvedTarget = target {
                switch resolvedTarget.kind {
                case .tmuxPane:
                    return await focusTmuxTarget(session: session, target: resolvedTarget)
                case .nativeWindow:
                    let capability = await NativeTerminalWindowResolver.shared.focus(target: resolvedTarget)
                    if capability == .ready {
                        return true
                    }
                }
            }
        }

        guard let target else {
            return await focusFallback(session: session)
        }

        switch target.kind {
        case .tmuxPane:
            return await focusTmuxTarget(session: session, target: target)
        case .nativeWindow:
            let capability = await NativeTerminalWindowResolver.shared.focus(target: target)
            if capability == .stale {
                let resolution = await TerminalWindowResolver.shared.resolve(for: session)
                if let refreshedTarget = resolution.focusTarget,
                   await NativeTerminalWindowResolver.shared.focus(target: refreshedTarget) == .ready {
                    return true
                }
            }
            if capability == .ready {
                return true
            }
            return await focusFallback(session: session)
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
        if session.isInTmux {
            if let pid = session.pid, await YabaiController.shared.focusWindow(forClaudePid: pid) {
                return true
            }

            if await YabaiController.shared.focusWindow(forWorkingDirectory: session.cwd) {
                return true
            }
        }

        if let appPid = session.terminalProcessId,
           let app = NSRunningApplication(processIdentifier: pid_t(appPid)) {
            return app.activate(options: [.activateAllWindows])
        }

        if let app = TerminalAppRegistry.runningApplication(
            bundleId: session.terminalBundleId,
            hint: session.terminalName
        ) {
            return app.activate(options: [.activateAllWindows])
        }

        if let pid = session.pid {
            return await YabaiController.shared.focusWindow(forClaudePid: pid)
        }

        return false
    }
}
