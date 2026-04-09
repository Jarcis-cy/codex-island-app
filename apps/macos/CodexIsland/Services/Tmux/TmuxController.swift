//
//  TmuxController.swift
//  CodexIsland
//
//  High-level tmux operations controller
//

import Foundation

/// Controller for tmux operations
actor TmuxController {
    static let shared = TmuxController()

    private init() {}

    func findTmuxTarget(forClaudePid pid: Int) async -> TmuxTarget? {
        await TmuxTargetFinder.shared.findTarget(forClaudePid: pid)
    }

    func findTmuxTarget(forWorkingDirectory dir: String) async -> TmuxTarget? {
        await TmuxTargetFinder.shared.findTarget(forWorkingDirectory: dir)
    }

    func findTmuxTarget(forTTY tty: String) async -> TmuxTarget? {
        await TmuxTargetFinder.shared.findTarget(forTTY: tty)
    }

    func sendMessage(_ message: String, to target: TmuxTarget) async -> Bool {
        await ToolApprovalHandler.shared.sendMessage(message, to: target)
    }

    func approveOnce(target: TmuxTarget) async -> Bool {
        await ToolApprovalHandler.shared.approveOnce(target: target)
    }

    func approveAlways(target: TmuxTarget) async -> Bool {
        await ToolApprovalHandler.shared.approveAlways(target: target)
    }

    func reject(target: TmuxTarget, message: String? = nil) async -> Bool {
        await ToolApprovalHandler.shared.reject(target: target, message: message)
    }

    func switchToPane(target: TmuxTarget) async -> Bool {
        do {
            _ = try await TmuxCommandRunner.shared.run(arguments: [
                "select-window", "-t", "\(target.session):\(target.window)"
            ])

            _ = try await TmuxCommandRunner.shared.run(arguments: [
                "select-pane", "-t", target.targetString
            ])

            return true
        } catch {
            return false
        }
    }
}
