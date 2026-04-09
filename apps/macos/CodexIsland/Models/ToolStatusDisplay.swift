//
//  ToolStatusDisplay.swift
//  CodexIsland
//

import Foundation

nonisolated struct ToolStatusDisplay {
    let text: String
    let isRunning: Bool

    private nonisolated static func genericFailureText(for toolName: String) -> String {
        switch toolName {
        case "Bash", "Command", "SlashCommand":
            return "Command failed"
        case "Edit":
            return "Edit failed"
        case "Write":
            return "Write failed"
        case "Read":
            return "Read failed"
        case "WebFetch":
            return "Fetch failed"
        case "WebSearch":
            return "Search failed"
        case "Task":
            return "Agent failed"
        default:
            return "Failed"
        }
    }

    nonisolated static func running(for toolName: String, input: [String: String]) -> ToolStatusDisplay {
        switch toolName {
        case "Read":
            return ToolStatusDisplay(text: "Reading...", isRunning: true)
        case "Edit":
            return ToolStatusDisplay(text: "Editing...", isRunning: true)
        case "Write":
            return ToolStatusDisplay(text: "Writing...", isRunning: true)
        case "Bash":
            if let desc = input["description"], !desc.isEmpty {
                return ToolStatusDisplay(text: desc, isRunning: true)
            }
            return ToolStatusDisplay(text: "Running...", isRunning: true)
        case "Grep", "Glob":
            if let pattern = input["pattern"] {
                return ToolStatusDisplay(text: "Searching: \(pattern)", isRunning: true)
            }
            return ToolStatusDisplay(text: "Searching...", isRunning: true)
        case "WebSearch":
            if let query = input["query"] {
                return ToolStatusDisplay(text: "Searching: \(query)", isRunning: true)
            }
            return ToolStatusDisplay(text: "Searching...", isRunning: true)
        case "WebFetch":
            return ToolStatusDisplay(text: "Fetching...", isRunning: true)
        case "Task":
            if let desc = input["description"], !desc.isEmpty {
                return ToolStatusDisplay(text: desc, isRunning: true)
            }
            return ToolStatusDisplay(text: "Running agent...", isRunning: true)
        case "TodoWrite":
            return ToolStatusDisplay(text: "Updating todos...", isRunning: true)
        case "EnterPlanMode":
            return ToolStatusDisplay(text: "Entering plan mode...", isRunning: true)
        case "ExitPlanMode":
            return ToolStatusDisplay(text: "Exiting plan mode...", isRunning: true)
        default:
            return ToolStatusDisplay(text: "Running...", isRunning: true)
        }
    }

    nonisolated static func completed(for toolName: String, result: ToolResultData?) -> ToolStatusDisplay {
        guard let result = result else {
            return ToolStatusDisplay(text: "Completed", isRunning: false)
        }

        switch result {
        case .read(let r):
            let lineText = r.totalLines > r.numLines ? "\(r.numLines)+ lines" : "\(r.numLines) lines"
            return ToolStatusDisplay(text: "Read \(r.filename) (\(lineText))", isRunning: false)
        case .edit(let r):
            return ToolStatusDisplay(text: "Edited \(r.filename)", isRunning: false)
        case .write(let r):
            let action = r.type == .create ? "Created" : "Wrote"
            return ToolStatusDisplay(text: "\(action) \(r.filename)", isRunning: false)
        case .bash(let r):
            if let bgId = r.backgroundTaskId {
                return ToolStatusDisplay(text: "Running in background (\(bgId))", isRunning: false)
            }
            if let interpretation = r.returnCodeInterpretation {
                return ToolStatusDisplay(text: interpretation, isRunning: false)
            }
            return ToolStatusDisplay(text: "Completed", isRunning: false)
        case .grep(let r):
            let fileWord = r.numFiles == 1 ? "file" : "files"
            return ToolStatusDisplay(text: "Found \(r.numFiles) \(fileWord)", isRunning: false)
        case .glob(let r):
            let fileWord = r.numFiles == 1 ? "file" : "files"
            if r.numFiles == 0 {
                return ToolStatusDisplay(text: "No files found", isRunning: false)
            }
            return ToolStatusDisplay(text: "Found \(r.numFiles) \(fileWord)", isRunning: false)
        case .todoWrite:
            return ToolStatusDisplay(text: "Updated todos", isRunning: false)
        case .task(let r):
            return ToolStatusDisplay(text: r.status.capitalized, isRunning: false)
        case .webFetch(let r):
            return ToolStatusDisplay(text: "\(r.code) \(r.codeText)", isRunning: false)
        case .webSearch(let r):
            let time = r.durationSeconds >= 1 ? "\(Int(r.durationSeconds))s" : "\(Int(r.durationSeconds * 1000))ms"
            let searchWord = r.results.count == 1 ? "search" : "searches"
            return ToolStatusDisplay(text: "Did 1 \(searchWord) in \(time)", isRunning: false)
        case .askUserQuestion:
            return ToolStatusDisplay(text: "Answered", isRunning: false)
        case .bashOutput(let r):
            return ToolStatusDisplay(text: "Status: \(r.status)", isRunning: false)
        case .killShell:
            return ToolStatusDisplay(text: "Terminated", isRunning: false)
        case .exitPlanMode:
            return ToolStatusDisplay(text: "Plan ready", isRunning: false)
        case .mcp, .generic:
            return ToolStatusDisplay(text: "Completed", isRunning: false)
        }
    }

    nonisolated static func failed(for toolName: String, result: ToolResultData?) -> ToolStatusDisplay {
        guard let result else {
            return ToolStatusDisplay(text: genericFailureText(for: toolName), isRunning: false)
        }

        switch result {
        case .bash(let r):
            if let interpretation = r.returnCodeInterpretation, !interpretation.isEmpty {
                return ToolStatusDisplay(text: interpretation, isRunning: false)
            }
            return ToolStatusDisplay(text: genericFailureText(for: toolName), isRunning: false)
        case .bashOutput(let r):
            return ToolStatusDisplay(text: "Status: \(r.status)", isRunning: false)
        case .webFetch(let r):
            return ToolStatusDisplay(text: "\(r.code) \(r.codeText)", isRunning: false)
        case .task(let r):
            return ToolStatusDisplay(text: r.status.capitalized, isRunning: false)
        default:
            let completedDisplay = completed(for: toolName, result: result)
            if completedDisplay.text != "Completed" {
                return completedDisplay
            }
            return ToolStatusDisplay(text: genericFailureText(for: toolName), isRunning: false)
        }
    }
}
