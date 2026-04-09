//
//  ConversationParser+LineParsing.swift
//  CodexIsland
//
//  Line-level helpers shared by full and incremental Claude transcript parsing.
//

import Foundation
import os.log

extension ConversationParser {
    static func formatToolInput(_ input: [String: Any]?, toolName: String) -> String {
        guard let input else { return "" }

        switch toolName {
        case "Read", "Write", "Edit":
            if let filePath = input["file_path"] as? String {
                return (filePath as NSString).lastPathComponent
            }
        case "Bash":
            if let command = input["command"] as? String {
                return command
            }
        case "Grep", "Glob":
            if let pattern = input["pattern"] as? String {
                return pattern
            }
        case "Task":
            if let description = input["description"] as? String {
                return description
            }
        case "WebFetch":
            if let url = input["url"] as? String {
                return url
            }
        case "WebSearch":
            if let query = input["query"] as? String {
                return query
            }
        default:
            for (_, value) in input {
                if let string = value as? String, !string.isEmpty {
                    return string
                }
            }
        }
        return ""
    }

    static func truncateMessage(_ message: String?, maxLength: Int = 80) -> String? {
        guard let message else { return nil }
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard cleaned.count > maxLength else { return cleaned }
        return String(cleaned.prefix(maxLength - 3)) + "..."
    }

    static func sessionFilePath(sessionId: String, cwd: String) -> String {
        let projectDir = cwd.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        return NSHomeDirectory() + "/.claude/projects/" + projectDir + "/" + sessionId + ".jsonl"
    }

    func parseNewLines(filePath: String, state: inout IncrementalParseState) -> [ChatMessage] {
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            return []
        }
        defer { try? fileHandle.close() }

        let fileSize: UInt64
        do {
            fileSize = try fileHandle.seekToEnd()
        } catch {
            return []
        }

        if fileSize < state.lastFileOffset {
            state = IncrementalParseState()
        }

        if fileSize == state.lastFileOffset {
            return state.messages
        }

        do {
            try fileHandle.seek(toOffset: state.lastFileOffset)
        } catch {
            return state.messages
        }

        guard let newData = try? fileHandle.readToEnd(),
              let newContent = String(data: newData, encoding: .utf8) else {
            return state.messages
        }

        state.clearPending = false
        let isIncrementalRead = state.lastFileOffset > 0
        var newMessages: [ChatMessage] = []

        for line in newContent.components(separatedBy: "\n") where !line.isEmpty {
            if line.contains("<command-name>/clear</command-name>") {
                state.messages = []
                state.seenToolIds = []
                state.toolIdToName = [:]
                state.completedToolIds = []
                state.toolResults = [:]
                state.structuredResults = [:]

                if isIncrementalRead {
                    state.clearPending = true
                    state.lastClearOffset = state.lastFileOffset
                    Self.logger.debug("/clear detected (new), will notify UI")
                }
                continue
            }

            if line.contains("\"tool_result\"") {
                parseToolResultLine(line, state: &state)
                continue
            }

            if line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\""),
               let lineData = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
               let message = parseMessageLine(
                   json,
                   seenToolIds: &state.seenToolIds,
                   toolIdToName: &state.toolIdToName
               ) {
                newMessages.append(message)
                state.messages.append(message)
            }
        }

        state.lastFileOffset = fileSize
        return newMessages
    }

    private func parseToolResultLine(_ line: String, state: inout IncrementalParseState) {
        guard let lineData = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let messageDict = json["message"] as? [String: Any],
              let contentArray = messageDict["content"] as? [[String: Any]] else {
            return
        }

        let toolUseResult = json["toolUseResult"] as? [String: Any]
        let topLevelToolName = json["toolName"] as? String
        let stdout = toolUseResult?["stdout"] as? String
        let stderr = toolUseResult?["stderr"] as? String

        for block in contentArray {
            guard block["type"] as? String == "tool_result",
                  let toolUseId = block["tool_use_id"] as? String else {
                continue
            }

            state.completedToolIds.insert(toolUseId)

            let content = block["content"] as? String
            let isError = block["is_error"] as? Bool ?? false
            state.toolResults[toolUseId] = ToolResult(
                content: content,
                stdout: stdout,
                stderr: stderr,
                isError: isError
            )

            let toolName = topLevelToolName ?? state.toolIdToName[toolUseId]
            if let toolUseResult, let toolName {
                state.structuredResults[toolUseId] = Self.parseStructuredResult(
                    toolName: toolName,
                    toolUseResult: toolUseResult,
                    isError: isError
                )
            }
        }
    }

    func parseMessageLine(
        _ json: [String: Any],
        seenToolIds: inout Set<String>,
        toolIdToName: inout [String: String]
    ) -> ChatMessage? {
        guard let type = json["type"] as? String,
              let uuid = json["uuid"] as? String,
              type == "user" || type == "assistant",
              json["isMeta"] as? Bool != true,
              let messageDict = json["message"] as? [String: Any] else {
            return nil
        }

        let timestamp: Date
        if let timestampStr = json["timestamp"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = formatter.date(from: timestampStr) ?? Date()
        } else {
            timestamp = Date()
        }

        var blocks: [MessageBlock] = []

        if let content = messageDict["content"] as? String {
            if content.hasPrefix("<command-name>") || content.hasPrefix("<local-command") || content.hasPrefix("Caveat:") {
                return nil
            }
            blocks.append(content.hasPrefix("[Request interrupted by user") ? .interrupted : .text(content))
        } else if let contentArray = messageDict["content"] as? [[String: Any]] {
            for block in contentArray {
                guard let blockType = block["type"] as? String else { continue }
                switch blockType {
                case "text":
                    if let text = block["text"] as? String {
                        blocks.append(text.hasPrefix("[Request interrupted by user") ? .interrupted : .text(text))
                    }
                case "tool_use":
                    if let toolId = block["id"] as? String {
                        if seenToolIds.contains(toolId) {
                            continue
                        }
                        seenToolIds.insert(toolId)
                        if let toolName = block["name"] as? String {
                            toolIdToName[toolId] = toolName
                        }
                    }
                    if let toolBlock = parseToolUse(block) {
                        blocks.append(.toolUse(toolBlock))
                    }
                case "thinking":
                    if let thinking = block["thinking"] as? String {
                        blocks.append(.thinking(thinking))
                    }
                default:
                    break
                }
            }
        }

        guard !blocks.isEmpty else { return nil }
        return ChatMessage(id: uuid, role: type == "user" ? .user : .assistant, timestamp: timestamp, content: blocks)
    }

    func parseToolUse(_ block: [String: Any]) -> ToolUseBlock? {
        guard let id = block["id"] as? String,
              let name = block["name"] as? String else {
            return nil
        }

        var input: [String: String] = [:]
        if let inputDict = block["input"] as? [String: Any] {
            for (key, value) in inputDict {
                if let stringValue = value as? String {
                    input[key] = stringValue
                } else if let intValue = value as? Int {
                    input[key] = String(intValue)
                } else if let boolValue = value as? Bool {
                    input[key] = boolValue ? "true" : "false"
                }
            }
        }

        return ToolUseBlock(id: id, name: name, input: input)
    }

    static func parseStructuredResult(
        toolName: String,
        toolUseResult: [String: Any],
        isError: Bool
    ) -> ToolResultData {
        ToolResultDecoder.decode(
            toolName: toolName,
            toolUseResult: toolUseResult,
            isError: isError
        )
    }
}
