//
//  TerminalWindowResolver.swift
//  CodexIsland
//
//  Resolves persisted focus targets for session terminal windows.
//

import AppKit
import Foundation

protocol TerminalWindowResolving: Sendable {
    func resolve(for session: SessionState) async -> TerminalWindowResolution
}

struct TerminalWindowResolution: Sendable {
    let terminalBundleId: String?
    let terminalProcessId: Int?
    let focusTarget: TerminalFocusTarget?
    let focusCapability: TerminalFocusCapability
}

actor TerminalWindowResolver: TerminalWindowResolving {
    static let shared = TerminalWindowResolver()

    private init() {}

    func resolve(for session: SessionState) async -> TerminalWindowResolution {
        guard let sessionPid = session.pid else {
            return TerminalWindowResolution(
                terminalBundleId: session.terminalBundleId,
                terminalProcessId: session.terminalProcessId,
                focusTarget: session.focusTarget,
                focusCapability: .unresolved
            )
        }

        let tree = ProcessTreeBuilder.shared.buildTree()
        guard let terminalPid = ProcessTreeBuilder.shared.findTerminalPid(forProcess: sessionPid, tree: tree) else {
            return TerminalWindowResolution(
                terminalBundleId: session.terminalBundleId,
                terminalProcessId: nil,
                focusTarget: session.focusTarget,
                focusCapability: .unresolved
            )
        }

        let app = NSRunningApplication(processIdentifier: pid_t(terminalPid))
        let bundleId = app?.bundleIdentifier

        if session.isInTmux {
            let tmuxTarget = await resolveTmuxTarget(for: session)
            let focusTarget = TerminalFocusTarget(
                kind: .tmuxPane,
                appBundleId: bundleId,
                appPid: terminalPid,
                tty: session.tty,
                tmuxTarget: tmuxTarget
            )

            return TerminalWindowResolution(
                terminalBundleId: bundleId,
                terminalProcessId: terminalPid,
                focusTarget: focusTarget,
                focusCapability: tmuxTarget == nil ? .unresolved : .ready
            )
        }

        let nativeResolution = await NativeTerminalWindowResolver.shared.resolveWindow(
            appPid: terminalPid,
            bundleId: bundleId,
            tty: session.tty
        )

        return TerminalWindowResolution(
            terminalBundleId: bundleId,
            terminalProcessId: terminalPid,
            focusTarget: nativeResolution.focusTarget,
            focusCapability: nativeResolution.focusCapability
        )
    }

    private func resolveTmuxTarget(for session: SessionState) async -> String? {
        if let pid = session.pid,
           let target = await TmuxController.shared.findTmuxTarget(forClaudePid: pid) {
            return target.targetString
        }

        if let tty = session.tty,
           let target = await TmuxController.shared.findTmuxTarget(forTTY: tty) {
            return target.targetString
        }

        if let target = await TmuxController.shared.findTmuxTarget(forWorkingDirectory: session.cwd) {
            return target.targetString
        }

        return nil
    }
}
