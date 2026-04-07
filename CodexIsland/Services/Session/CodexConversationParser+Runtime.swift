//
//  CodexConversationParser+Runtime.swift
//  CodexIsland
//
//  Runtime info parsing helpers for Codex transcripts.
//

import Foundation

extension CodexConversationParser {
    func updateRuntimeInfo(_ runtimeInfo: inout SessionRuntimeInfo, sessionMetaPayload: [String: Any]) {
        if let modelProvider = sessionMetaPayload["model_provider"] as? String,
           !modelProvider.isEmpty {
            runtimeInfo.modelProvider = modelProvider
        }
    }

    func eventPayload(from payload: [String: Any]) -> [String: Any]? {
        if let nested = payload["payload"] as? [String: Any] {
            return nested
        }

        var flattened = payload
        flattened.removeValue(forKey: "type")
        return flattened
    }

    func updateRuntimeInfo(_ runtimeInfo: inout SessionRuntimeInfo, turnContextPayload: [String: Any]) {
        if let model = turnContextPayload["model"] as? String, !model.isEmpty {
            runtimeInfo.model = model
        }

        if let collaboration = turnContextPayload["collaboration_mode"] as? [String: Any],
           let settings = collaboration["settings"] as? [String: Any],
           let reasoningEffort = settings["reasoning_effort"] as? String,
           !reasoningEffort.isEmpty {
            runtimeInfo.reasoningEffort = reasoningEffort
        } else if let reasoningEffort = turnContextPayload["reasoning_effort"] as? String,
                  !reasoningEffort.isEmpty {
            runtimeInfo.reasoningEffort = reasoningEffort
        } else if let effort = turnContextPayload["effort"] as? String, !effort.isEmpty {
            runtimeInfo.reasoningEffort = effort
        }
    }

    func updateRuntimeInfo(
        _ runtimeInfo: inout SessionRuntimeInfo,
        eventType: String,
        payload: [String: Any]
    ) {
        switch eventType {
        case "task_started":
            if let modelContextWindow = parseInteger(payload["model_context_window"]) {
                let existing = runtimeInfo.tokenUsage
                runtimeInfo.tokenUsage = SessionTokenUsageInfo(
                    totalTokenUsage: existing?.totalTokenUsage ?? .zero,
                    lastTokenUsage: existing?.lastTokenUsage ?? .zero,
                    modelContextWindow: modelContextWindow
                )
            }
        case "token_count":
            guard let info = payload["info"] as? [String: Any] else { return }
            let totalTokenUsage = parseTokenUsage(info["total_token_usage"] as? [String: Any]) ?? .zero
            let lastTokenUsage = parseTokenUsage(info["last_token_usage"] as? [String: Any]) ?? .zero
            let contextWindow = parseInteger(info["model_context_window"]) ?? runtimeInfo.tokenUsage?.modelContextWindow
            runtimeInfo.tokenUsage = SessionTokenUsageInfo(
                totalTokenUsage: totalTokenUsage,
                lastTokenUsage: lastTokenUsage,
                modelContextWindow: contextWindow
            )
        default:
            break
        }
    }

    func parseTokenUsage(_ payload: [String: Any]?) -> SessionTokenUsage? {
        guard let payload else { return nil }
        return SessionTokenUsage(
            inputTokens: parseInteger(payload["input_tokens"]) ?? 0,
            cachedInputTokens: parseInteger(payload["cached_input_tokens"]) ?? 0,
            outputTokens: parseInteger(payload["output_tokens"]) ?? 0,
            reasoningOutputTokens: parseInteger(payload["reasoning_output_tokens"]) ?? 0,
            totalTokens: parseInteger(payload["total_tokens"]) ?? 0
        )
    }

    func parseInteger(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? Int64 {
            return Int(value)
        }
        if let value = value as? Double {
            return Int(value)
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }
}
