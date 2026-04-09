//
//  ToolResultData.swift
//  CodexIsland
//
//  Structured models for all Claude Code tool results
//

import Foundation

// MARK: - Tool Result Wrapper

/// Structured tool result data - parsed from JSONL tool_result blocks
nonisolated enum ToolResultData: Equatable, Sendable {
    case read(ReadResult)
    case edit(EditResult)
    case write(WriteResult)
    case bash(BashResult)
    case grep(GrepResult)
    case glob(GlobResult)
    case todoWrite(TodoWriteResult)
    case task(TaskResult)
    case webFetch(WebFetchResult)
    case webSearch(WebSearchResult)
    case askUserQuestion(AskUserQuestionResult)
    case bashOutput(BashOutputResult)
    case killShell(KillShellResult)
    case exitPlanMode(ExitPlanModeResult)
    case mcp(MCPResult)
    case generic(GenericResult)
}

// MARK: - Read Tool Result

nonisolated struct ReadResult: Equatable, Sendable {
    let filePath: String
    let content: String
    let numLines: Int
    let startLine: Int
    let totalLines: Int

    var filename: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}

// MARK: - Edit Tool Result

nonisolated struct EditResult: Equatable, Sendable {
    let filePath: String
    let oldString: String
    let newString: String
    let replaceAll: Bool
    let userModified: Bool
    let structuredPatch: [PatchHunk]?

    var filename: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}

nonisolated struct PatchHunk: Equatable, Sendable {
    let oldStart: Int
    let oldLines: Int
    let newStart: Int
    let newLines: Int
    let lines: [String]
}

// MARK: - Write Tool Result

nonisolated struct WriteResult: Equatable, Sendable {
    nonisolated enum WriteType: String, Equatable, Sendable {
        case create
        case overwrite
    }

    let type: WriteType
    let filePath: String
    let content: String
    let structuredPatch: [PatchHunk]?

    var filename: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
}

// MARK: - Bash Tool Result

nonisolated struct BashResult: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let interrupted: Bool
    let isImage: Bool
    let returnCodeInterpretation: String?
    let backgroundTaskId: String?

    var hasOutput: Bool {
        !stdout.isEmpty || !stderr.isEmpty
    }

    var displayOutput: String {
        if !stdout.isEmpty {
            return stdout
        }
        if !stderr.isEmpty {
            return stderr
        }
        return "(No content)"
    }
}

// MARK: - Grep Tool Result

nonisolated struct GrepResult: Equatable, Sendable {
    nonisolated enum Mode: String, Equatable, Sendable {
        case filesWithMatches = "files_with_matches"
        case content
        case count
    }

    let mode: Mode
    let filenames: [String]
    let numFiles: Int
    let content: String?
    let numLines: Int?
    let appliedLimit: Int?
}

// MARK: - Glob Tool Result

nonisolated struct GlobResult: Equatable, Sendable {
    let filenames: [String]
    let durationMs: Int
    let numFiles: Int
    let truncated: Bool
}

// MARK: - TodoWrite Tool Result

nonisolated struct TodoWriteResult: Equatable, Sendable {
    let oldTodos: [TodoItem]
    let newTodos: [TodoItem]
}

nonisolated struct TodoItem: Equatable, Sendable {
    let content: String
    let status: String // "pending", "in_progress", "completed"
    let activeForm: String?
}

// MARK: - Task (Agent) Tool Result

nonisolated struct TaskResult: Equatable, Sendable {
    let agentId: String
    let status: String
    let content: String
    let prompt: String?
    let totalDurationMs: Int?
    let totalTokens: Int?
    let totalToolUseCount: Int?
}

// MARK: - WebFetch Tool Result

nonisolated struct WebFetchResult: Equatable, Sendable {
    let url: String
    let code: Int
    let codeText: String
    let bytes: Int
    let durationMs: Int
    let result: String
}

// MARK: - WebSearch Tool Result

nonisolated struct WebSearchResult: Equatable, Sendable {
    let query: String
    let durationSeconds: Double
    let results: [SearchResultItem]
}

nonisolated struct SearchResultItem: Equatable, Sendable {
    let title: String
    let url: String
    let snippet: String
}

// MARK: - AskUserQuestion Tool Result

nonisolated struct AskUserQuestionResult: Equatable, Sendable {
    let questions: [QuestionItem]
    let answers: [String: String]
}

nonisolated struct QuestionItem: Equatable, Sendable {
    let question: String
    let header: String?
    let options: [QuestionOption]
}

nonisolated struct QuestionOption: Equatable, Sendable {
    let label: String
    let description: String?
}

// MARK: - BashOutput Tool Result

nonisolated struct BashOutputResult: Equatable, Sendable {
    let shellId: String
    let status: String
    let stdout: String
    let stderr: String
    let stdoutLines: Int
    let stderrLines: Int
    let exitCode: Int?
    let command: String?
    let timestamp: String?
}

// MARK: - KillShell Tool Result

nonisolated struct KillShellResult: Equatable, Sendable {
    let shellId: String
    let message: String
}

// MARK: - ExitPlanMode Tool Result

nonisolated struct ExitPlanModeResult: Equatable, Sendable {
    let filePath: String?
    let plan: String?
    let isAgent: Bool
}

// MARK: - MCP Tool Result (Generic)

nonisolated struct MCPResult: Equatable, @unchecked Sendable {
    let serverName: String
    let toolName: String
    let rawResult: [String: Any]

    static func == (lhs: MCPResult, rhs: MCPResult) -> Bool {
        lhs.serverName == rhs.serverName &&
            lhs.toolName == rhs.toolName &&
            NSDictionary(dictionary: lhs.rawResult).isEqual(to: rhs.rawResult)
    }
}

// MARK: - Generic Tool Result (Fallback)

nonisolated struct GenericResult: Equatable, @unchecked Sendable {
    let rawContent: String?
    let rawData: [String: Any]?

    static func == (lhs: GenericResult, rhs: GenericResult) -> Bool {
        lhs.rawContent == rhs.rawContent
    }
}
