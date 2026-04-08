//
//  YabaiController.swift
//  CodexIsland
//
//  High-level yabai window management controller
//

import Foundation

private struct TmuxPaneMatch {
    let target: TmuxTarget
    let panePid: Int
}

/// Controller for yabai window management
actor YabaiController {
    static let shared = YabaiController()

    private init() {}

    // MARK: - Public API

    /// Focus the terminal window for a given Claude PID (tmux only)
    func focusWindow(forClaudePid claudePid: Int) async -> Bool {
        guard await WindowFinder.shared.isYabaiAvailable() else {
            return false
        }

        let windows = await WindowFinder.shared.getAllWindows()
        let tree = ProcessTreeBuilder.shared.buildTree()

        return await focusTmuxInstance(claudePid: claudePid, tree: tree, windows: windows)
    }

    /// Focus the terminal window for a given working directory (tmux only, fallback)
    func focusWindow(forWorkingDirectory workingDirectory: String) async -> Bool {
        guard await WindowFinder.shared.isYabaiAvailable() else { return false }

        return await focusWindow(forWorkingDir: workingDirectory)
    }

    // MARK: - Private Implementation

    private func focusTmuxInstance(claudePid: Int, tree: [Int: ProcessInfo], windows: [YabaiWindow]) async -> Bool {
        guard let target = await TmuxController.shared.findTmuxTarget(forClaudePid: claudePid) else {
            return false
        }

        _ = await TmuxController.shared.switchToPane(target: target)
        return await focusTerminal(forSession: target.session, tree: tree, windows: windows)
    }

    private func focusWindow(forWorkingDir workingDir: String) async -> Bool {
        let windows = await WindowFinder.shared.getAllWindows()
        let tree = ProcessTreeBuilder.shared.buildTree()

        return await focusTmuxPane(forWorkingDir: workingDir, tree: tree, windows: windows)
    }

    // MARK: - Tmux Helpers

    private func findTmuxClientTerminal(forSession session: String, tree: [Int: ProcessInfo], windows: [YabaiWindow]) async -> Int? {
        guard let output = await TmuxCommandRunner.shared.runOrNil(arguments: [
            "list-clients", "-t", session, "-F", "#{client_pid}"
        ]) else {
            return nil
        }

        for clientPid in parseClientPids(from: output) {
            if let terminalPid = terminalPid(forClientPid: clientPid, tree: tree, windows: windows) {
                return terminalPid
            }
        }

        return nil
    }

    private nonisolated func isTerminalProcess(_ command: String) -> Bool {
        let terminalCommands = ["Terminal", "iTerm", "iTerm2", "Alacritty", "kitty", "WezTerm", "wezterm-gui", "Hyper"]
        return terminalCommands.contains { command.contains($0) }
    }

    private func focusTmuxPane(forWorkingDir workingDir: String, tree: [Int: ProcessInfo], windows: [YabaiWindow]) async -> Bool {
        guard let panesOutput = await TmuxCommandRunner.shared.runOrNil(arguments: [
            "list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index}|#{pane_pid}"
        ]) else {
            return false
        }

        guard let paneMatch = matchingPane(forWorkingDir: workingDir, panesOutput: panesOutput, tree: tree) else {
            return false
        }

        _ = await TmuxController.shared.switchToPane(target: paneMatch.target)
        return await focusTerminal(forSession: paneMatch.target.session, tree: tree, windows: windows)
    }

    private func focusTerminal(forSession session: String, tree: [Int: ProcessInfo], windows: [YabaiWindow]) async -> Bool {
        guard let terminalPid = await findTmuxClientTerminal(forSession: session, tree: tree, windows: windows) else {
            return false
        }
        return await WindowFocuser.shared.focusTmuxWindow(terminalPid: terminalPid, windows: windows)
    }

    private func parseClientPids(from output: String) -> [Int] {
        output
            .components(separatedBy: "\n")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func terminalPid(
        forClientPid clientPid: Int,
        tree: [Int: ProcessInfo],
        windows: [YabaiWindow]
    ) -> Int? {
        let windowPids = Set(windows.map(\.pid))

        return ProcessTreeBuilder.shared.firstAncestorPid(startingAt: clientPid, tree: tree) { info in
            isTerminalProcess(info.command) && windowPids.contains(info.pid)
        }
    }

    private func matchingPane(
        forWorkingDir workingDir: String,
        panesOutput: String,
        tree: [Int: ProcessInfo]
    ) -> TmuxPaneMatch? {
        for pane in panesOutput.components(separatedBy: "\n").filter({ !$0.isEmpty }) {
            guard let paneMatch = parsePane(pane) else { continue }
            if paneContainsMatchingAgent(panePid: paneMatch.panePid, workingDir: workingDir, tree: tree) {
                return paneMatch
            }
        }
        return nil
    }

    private func parsePane(_ pane: String) -> TmuxPaneMatch? {
        let parts = pane.components(separatedBy: "|")
        guard parts.count >= 2,
              let panePid = Int(parts[1]),
              let target = TmuxTarget(from: parts[0]) else {
            return nil
        }
        return TmuxPaneMatch(target: target, panePid: panePid)
    }

    private func paneContainsMatchingAgent(
        panePid: Int,
        workingDir: String,
        tree: [Int: ProcessInfo]
    ) -> Bool {
        for (pid, info) in tree {
            guard ProcessTreeBuilder.shared.isDescendant(targetPid: pid, ofAncestor: panePid, tree: tree),
                  isCodingAgentProcess(info.command),
                  let cwd = ProcessTreeBuilder.shared.getWorkingDirectory(forPid: pid),
                  cwd == workingDir else {
                continue
            }
            return true
        }
        return false
    }

    private func isCodingAgentProcess(_ command: String) -> Bool {
        let lowercasedCommand = command.lowercased()
        return lowercasedCommand.contains("claude") || lowercasedCommand.contains("codex")
    }
}
