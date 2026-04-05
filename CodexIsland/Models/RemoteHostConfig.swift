//
//  RemoteHostConfig.swift
//  CodexIsland
//
//  User-configured SSH targets for remote app-server sessions.
//

import Foundation

nonisolated struct RemoteHostConfig: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var sshTarget: String
    var defaultCwd: String
    var isEnabled: Bool

    init(
        id: String = UUID().uuidString,
        name: String = "",
        sshTarget: String = "",
        defaultCwd: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.sshTarget = sshTarget
        self.defaultCwd = defaultCwd
        self.isEnabled = isEnabled
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        let target = sshTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        return target.isEmpty ? "Remote Host" : target
    }

    var isValid: Bool {
        !sshTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

nonisolated enum RemoteHostConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    var feedbackMessage: String? {
        switch self {
        case .connected:
            return nil
        case .connecting:
            return "Remote host is connecting..."
        case .disconnected:
            return "Remote host is disconnected. Reconnect and retry."
        case .failed(let message):
            return message.isEmpty ? "Remote host connection failed" : message
        }
    }

    var statusText: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .failed(let message):
            return message.isEmpty ? "Failed" : message
        }
    }
}
