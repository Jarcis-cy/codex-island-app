//
//  ToolResultDecoder.swift
//  CodexIsland
//

import Foundation

nonisolated enum ToolResultDecoder {
    static func decode(
        toolName: String,
        toolUseResult: [String: Any],
        isError: Bool
    ) -> ToolResultData {
        if toolName.hasPrefix("mcp__") {
            return decodeMCP(toolName: toolName, toolUseResult: toolUseResult)
        }

        switch toolName {
        case "Read":
            return decodeRead(toolUseResult)
        case "Edit":
            return decodeEdit(toolUseResult)
        case "Write":
            return decodeWrite(toolUseResult)
        case "Bash":
            return decodeBash(toolUseResult)
        case "Grep":
            return decodeGrep(toolUseResult)
        case "Glob":
            return decodeGlob(toolUseResult)
        case "TodoWrite":
            return decodeTodoWrite(toolUseResult)
        case "Task":
            return decodeTask(toolUseResult)
        case "WebFetch":
            return decodeWebFetch(toolUseResult)
        case "WebSearch":
            return decodeWebSearch(toolUseResult)
        case "AskUserQuestion":
            return decodeAskUserQuestion(toolUseResult)
        case "BashOutput":
            return decodeBashOutput(toolUseResult)
        case "KillShell":
            return decodeKillShell(toolUseResult)
        case "ExitPlanMode":
            return decodeExitPlanMode(toolUseResult)
        default:
            return decodeGeneric(toolUseResult, isError: isError)
        }
    }

    private static func decodeMCP(toolName: String, toolUseResult: [String: Any]) -> ToolResultData {
        let withoutPrefix = String(toolName.dropFirst(5))
        let parts = withoutPrefix.components(separatedBy: "__")
        let serverName = !parts.isEmpty ? String(parts[0]) : "unknown"
        let mcpToolName = parts.count > 1 ? parts[1] : toolName
        return .mcp(MCPResult(
            serverName: serverName,
            toolName: mcpToolName,
            rawResult: toolUseResult
        ))
    }

    private static func decodeRead(_ data: [String: Any]) -> ToolResultData {
        let payload = nestedPayload(in: data, key: "file")
        return .read(ReadResult(
            filePath: payload["filePath"] as? String ?? "",
            content: payload["content"] as? String ?? "",
            numLines: payload["numLines"] as? Int ?? 0,
            startLine: payload["startLine"] as? Int ?? 1,
            totalLines: payload["totalLines"] as? Int ?? 0
        ))
    }

    private static func decodeEdit(_ data: [String: Any]) -> ToolResultData {
        .edit(EditResult(
            filePath: data["filePath"] as? String ?? "",
            oldString: data["oldString"] as? String ?? "",
            newString: data["newString"] as? String ?? "",
            replaceAll: data["replaceAll"] as? Bool ?? false,
            userModified: data["userModified"] as? Bool ?? false,
            structuredPatch: parsePatchHunks(data["structuredPatch"] as? [[String: Any]])
        ))
    }

    private static func decodeWrite(_ data: [String: Any]) -> ToolResultData {
        let typeStr = data["type"] as? String ?? "create"
        let writeType: WriteResult.WriteType = typeStr == "overwrite" ? .overwrite : .create

        return .write(WriteResult(
            type: writeType,
            filePath: data["filePath"] as? String ?? "",
            content: data["content"] as? String ?? "",
            structuredPatch: parsePatchHunks(data["structuredPatch"] as? [[String: Any]])
        ))
    }

    private static func decodeBash(_ data: [String: Any]) -> ToolResultData {
        .bash(BashResult(
            stdout: data["stdout"] as? String ?? "",
            stderr: data["stderr"] as? String ?? "",
            interrupted: data["interrupted"] as? Bool ?? false,
            isImage: data["isImage"] as? Bool ?? false,
            returnCodeInterpretation: data["returnCodeInterpretation"] as? String,
            backgroundTaskId: data["backgroundTaskId"] as? String
        ))
    }

    private static func decodeGrep(_ data: [String: Any]) -> ToolResultData {
        let mode: GrepResult.Mode
        switch data["mode"] as? String ?? "files_with_matches" {
        case "content":
            mode = .content
        case "count":
            mode = .count
        default:
            mode = .filesWithMatches
        }

        return .grep(GrepResult(
            mode: mode,
            filenames: data["filenames"] as? [String] ?? [],
            numFiles: data["numFiles"] as? Int ?? 0,
            content: data["content"] as? String,
            numLines: data["numLines"] as? Int,
            appliedLimit: data["appliedLimit"] as? Int
        ))
    }

    private static func decodeGlob(_ data: [String: Any]) -> ToolResultData {
        .glob(GlobResult(
            filenames: data["filenames"] as? [String] ?? [],
            durationMs: data["durationMs"] as? Int ?? 0,
            numFiles: data["numFiles"] as? Int ?? 0,
            truncated: data["truncated"] as? Bool ?? false
        ))
    }

    private static func decodeTodoWrite(_ data: [String: Any]) -> ToolResultData {
        .todoWrite(TodoWriteResult(
            oldTodos: parseTodoItems(data["oldTodos"] as? [[String: Any]]),
            newTodos: parseTodoItems(data["newTodos"] as? [[String: Any]])
        ))
    }

    private static func decodeTask(_ data: [String: Any]) -> ToolResultData {
        .task(TaskResult(
            agentId: data["agentId"] as? String ?? "",
            status: data["status"] as? String ?? "unknown",
            content: data["content"] as? String ?? "",
            prompt: data["prompt"] as? String,
            totalDurationMs: data["totalDurationMs"] as? Int,
            totalTokens: data["totalTokens"] as? Int,
            totalToolUseCount: data["totalToolUseCount"] as? Int
        ))
    }

    private static func decodeWebFetch(_ data: [String: Any]) -> ToolResultData {
        .webFetch(WebFetchResult(
            url: data["url"] as? String ?? "",
            code: data["code"] as? Int ?? 0,
            codeText: data["codeText"] as? String ?? "",
            bytes: data["bytes"] as? Int ?? 0,
            durationMs: data["durationMs"] as? Int ?? 0,
            result: data["result"] as? String ?? ""
        ))
    }

    private static func decodeWebSearch(_ data: [String: Any]) -> ToolResultData {
        .webSearch(WebSearchResult(
            query: data["query"] as? String ?? "",
            durationSeconds: data["durationSeconds"] as? Double ?? 0,
            results: parseSearchResults(data["results"] as? [[String: Any]])
        ))
    }

    private static func decodeAskUserQuestion(_ data: [String: Any]) -> ToolResultData {
        let answers = data["answers"] as? [String: String] ?? [:]
        return .askUserQuestion(AskUserQuestionResult(
            questions: parseQuestions(data["questions"] as? [[String: Any]]),
            answers: answers
        ))
    }

    private static func decodeBashOutput(_ data: [String: Any]) -> ToolResultData {
        .bashOutput(BashOutputResult(
            shellId: data["shellId"] as? String ?? "",
            status: data["status"] as? String ?? "",
            stdout: data["stdout"] as? String ?? "",
            stderr: data["stderr"] as? String ?? "",
            stdoutLines: data["stdoutLines"] as? Int ?? 0,
            stderrLines: data["stderrLines"] as? Int ?? 0,
            exitCode: data["exitCode"] as? Int,
            command: data["command"] as? String,
            timestamp: data["timestamp"] as? String
        ))
    }

    private static func decodeKillShell(_ data: [String: Any]) -> ToolResultData {
        .killShell(KillShellResult(
            shellId: data["shell_id"] as? String ?? data["shellId"] as? String ?? "",
            message: data["message"] as? String ?? ""
        ))
    }

    private static func decodeExitPlanMode(_ data: [String: Any]) -> ToolResultData {
        .exitPlanMode(ExitPlanModeResult(
            filePath: data["filePath"] as? String,
            plan: data["plan"] as? String,
            isAgent: data["isAgent"] as? Bool ?? false
        ))
    }

    private static func decodeGeneric(_ data: [String: Any], isError _: Bool) -> ToolResultData {
        let content = data["content"] as? String ?? data["stdout"] as? String ?? data["result"] as? String
        return .generic(GenericResult(rawContent: content, rawData: data))
    }

    private static func nestedPayload(in data: [String: Any], key: String) -> [String: Any] {
        (data[key] as? [String: Any]) ?? data
    }

    private static func parsePatchHunks(_ patches: [[String: Any]]?) -> [PatchHunk]? {
        guard let patches else { return nil }
        return patches.compactMap { patch in
            guard let oldStart = patch["oldStart"] as? Int,
                  let oldLines = patch["oldLines"] as? Int,
                  let newStart = patch["newStart"] as? Int,
                  let newLines = patch["newLines"] as? Int,
                  let lines = patch["lines"] as? [String] else {
                return nil
            }
            return PatchHunk(
                oldStart: oldStart,
                oldLines: oldLines,
                newStart: newStart,
                newLines: newLines,
                lines: lines
            )
        }
    }

    private static func parseTodoItems(_ items: [[String: Any]]?) -> [TodoItem] {
        guard let items else { return [] }
        return items.compactMap { item in
            guard let content = item["content"] as? String,
                  let status = item["status"] as? String else {
                return nil
            }
            return TodoItem(
                content: content,
                status: status,
                activeForm: item["activeForm"] as? String
            )
        }
    }

    private static func parseSearchResults(_ results: [[String: Any]]?) -> [SearchResultItem] {
        guard let results else { return [] }
        return results.compactMap { item in
            guard let title = item["title"] as? String,
                  let url = item["url"] as? String else {
                return nil
            }
            return SearchResultItem(
                title: title,
                url: url,
                snippet: item["snippet"] as? String ?? ""
            )
        }
    }

    private static func parseQuestions(_ questions: [[String: Any]]?) -> [QuestionItem] {
        guard let questions else { return [] }
        return questions.compactMap { question in
            guard let prompt = question["question"] as? String else {
                return nil
            }
            return QuestionItem(
                question: prompt,
                header: question["header"] as? String,
                options: parseQuestionOptions(question["options"] as? [[String: Any]])
            )
        }
    }

    private static func parseQuestionOptions(_ options: [[String: Any]]?) -> [QuestionOption] {
        guard let options else { return [] }
        return options.compactMap { option in
            guard let label = option["label"] as? String else {
                return nil
            }
            return QuestionOption(
                label: label,
                description: option["description"] as? String
            )
        }
    }
}
