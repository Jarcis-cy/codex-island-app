//
//  ConversationParser+SubagentTools.swift
//  CodexIsland
//
//  Agent JSONL parsing helpers used for Task/subagent visualization.
//

import Foundation
import os.log

extension ConversationParser {
    func parseSubagentTools(agentId: String, cwd: String) -> [SubagentToolInfo] {
        Self.parseSubagentToolsSync(agentId: agentId, cwd: cwd)
    }

    nonisolated static func parseSubagentToolsSync(agentId: String, cwd: String) -> [SubagentToolInfo] {
        guard !agentId.isEmpty else { return [] }
        guard let content = loadAgentContent(agentId: agentId, cwd: cwd) else { return [] }
        return parseSubagentToolContent(content)
    }

    private nonisolated static func loadAgentContent(agentId: String, cwd: String) -> String? {
        let projectDir = cwd.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        let agentFile = NSHomeDirectory() + "/.claude/projects/" + projectDir + "/agent-" + agentId + ".jsonl"
        guard FileManager.default.fileExists(atPath: agentFile) else { return nil }
        do {
            return try String(contentsOfFile: agentFile, encoding: .utf8)
        } catch {
            ConversationParser.logger.warning("Failed to load agent transcript \(agentFile, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private nonisolated static func parseSubagentToolContent(_ content: String) -> [SubagentToolInfo] {
        var tools: [SubagentToolInfo] = []
        var seenToolIds: Set<String> = []
        var completedToolIds: Set<String> = []

        for line in content.components(separatedBy: "\n") where !line.isEmpty {
            guard line.contains("\"tool_result\""),
                  let json = parseAgentJSONLine(line),
                  let messageDict = json["message"] as? [String: Any],
                  let contentArray = messageDict["content"] as? [[String: Any]] else {
                continue
            }

            for block in contentArray where block["type"] as? String == "tool_result" {
                if let toolUseId = block["tool_use_id"] as? String {
                    completedToolIds.insert(toolUseId)
                }
            }
        }

        for line in content.components(separatedBy: "\n") where !line.isEmpty {
            guard line.contains("\"tool_use\""),
                  let json = parseAgentJSONLine(line),
                  let messageDict = json["message"] as? [String: Any],
                  let contentArray = messageDict["content"] as? [[String: Any]] else {
                continue
            }

            for block in contentArray {
                guard block["type"] as? String == "tool_use",
                      let toolId = block["id"] as? String,
                      let toolName = block["name"] as? String,
                      !seenToolIds.contains(toolId) else {
                    continue
                }

                seenToolIds.insert(toolId)
                tools.append(SubagentToolInfo(
                    id: toolId,
                    name: toolName,
                    input: parseToolInput(block["input"] as? [String: Any]),
                    isCompleted: completedToolIds.contains(toolId),
                    timestamp: json["timestamp"] as? String
                ))
            }
        }

        return tools
    }

    private nonisolated static func parseAgentJSONLine(_ line: String) -> [String: Any]? {
        guard let lineData = line.data(using: .utf8) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: lineData) as? [String: Any]
        } catch {
            ConversationParser.logger.warning("Failed to parse agent JSONL line: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private nonisolated static func parseToolInput(_ inputDict: [String: Any]?) -> [String: String] {
        guard let inputDict else { return [:] }
        var input: [String: String] = [:]
        for (key, value) in inputDict {
            if let stringValue = value as? String {
                input[key] = stringValue
            } else if let intValue = value as? Int {
                input[key] = String(intValue)
            } else if let boolValue = value as? Bool {
                input[key] = boolValue ? "true" : "false"
            }
        }
        return input
    }
}
