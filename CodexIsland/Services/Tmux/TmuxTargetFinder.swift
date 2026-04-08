//
//  TmuxTargetFinder.swift
//  CodexIsland
//
//  Finds tmux targets for Claude processes
//

import Foundation

actor TmuxCommandRunner {
    static let shared = TmuxCommandRunner()

    private init() {}

    func run(arguments: [String]) async throws -> String {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            throw TmuxCommandError.tmuxNotFound
        }

        return try await ProcessExecutor.shared.run(tmuxPath, arguments: arguments)
    }

    func runOrNil(arguments: [String]) async -> String? {
        try? await run(arguments: arguments)
    }
}

enum TmuxCommandError: Error {
    case tmuxNotFound
}

/// Finds tmux session/window/pane targets for Claude processes
actor TmuxTargetFinder {
    static let shared = TmuxTargetFinder()

    private init() {}

    /// Find the tmux target for a given Claude PID
    func findTarget(forClaudePid claudePid: Int) async -> TmuxTarget? {
        guard let output = await TmuxCommandRunner.shared.runOrNil(arguments: [
            "list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_pid}"
        ]) else {
            return nil
        }

        let tree = ProcessTreeBuilder.shared.buildTree()

        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2,
                  let panePid = Int(parts[1]) else { continue }

            let targetString = String(parts[0])

            if ProcessTreeBuilder.shared.isDescendant(targetPid: claudePid, ofAncestor: panePid, tree: tree) {
                return TmuxTarget(from: targetString)
            }
        }

        return nil
    }

    /// Find the tmux target for a given working directory
    func findTarget(forWorkingDirectory workingDir: String) async -> TmuxTarget? {
        guard let output = await TmuxCommandRunner.shared.runOrNil(arguments: [
            "list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_current_path}"
        ]) else {
            return nil
        }

        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let targetString = String(parts[0])
            let panePath = String(parts[1])

            if panePath == workingDir {
                return TmuxTarget(from: targetString)
            }
        }

        return nil
    }

    /// Find the tmux target for a given pane TTY
    func findTarget(forTTY tty: String) async -> TmuxTarget? {
        guard let output = await TmuxCommandRunner.shared.runOrNil(arguments: [
            "list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_tty}"
        ]) else {
            return nil
        }

        let normalizedTTY = tty.replacingOccurrences(of: "/dev/", with: "")

        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let targetString = String(parts[0])
            let paneTTY = String(parts[1]).replacingOccurrences(of: "/dev/", with: "")

            if paneTTY == normalizedTTY {
                return TmuxTarget(from: targetString)
            }
        }

        return nil
    }

    /// Check if a session's tmux pane is currently the active pane
    func isSessionPaneActive(claudePid: Int) async -> Bool {
        guard let sessionTarget = await findTarget(forClaudePid: claudePid) else {
            return false
        }

        guard let output = await TmuxCommandRunner.shared.runOrNil(arguments: [
            "display-message", "-p", "#{session_name}:#{window_index}.#{pane_index}"
        ]) else {
            return false
        }

        let activeTarget = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return sessionTarget.targetString == activeTarget
    }
}
