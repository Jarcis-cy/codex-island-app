//
//  RemoteAppServerProtocol.swift
//  CodexIsland
//
//  Minimal app-server v2 protocol subset used for remote session management.
//

import Foundation

nonisolated struct RemoteAppServerEnvelope: Codable, Sendable {
    let method: String?
    let id: RemoteRPCID?
    let params: AnyCodable?
    let result: AnyCodable?
    let error: RemoteAppServerErrorPayload?
}

nonisolated struct RemoteAppServerErrorPayload: Codable, Error, Sendable {
    let code: Int
    let message: String
}

extension RemoteAppServerErrorPayload: LocalizedError {
    nonisolated var errorDescription: String? {
        message
    }
}

nonisolated enum RemoteAppServerThreadStatus: Codable, Equatable, Sendable {
    case notLoaded
    case idle
    case systemError
    case active(activeFlags: [RemoteAppServerThreadActiveFlag])

    private enum CodingKeys: String, CodingKey {
        case type
        case activeFlags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "notLoaded":
            self = .notLoaded
        case "idle":
            self = .idle
        case "systemError":
            self = .systemError
        case "active":
            self = .active(
                activeFlags: try container.decode([RemoteAppServerThreadActiveFlag].self, forKey: .activeFlags)
            )
        default:
            self = .systemError
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notLoaded:
            try container.encode("notLoaded", forKey: .type)
        case .idle:
            try container.encode("idle", forKey: .type)
        case .systemError:
            try container.encode("systemError", forKey: .type)
        case .active(let activeFlags):
            try container.encode("active", forKey: .type)
            try container.encode(activeFlags, forKey: .activeFlags)
        }
    }
}

nonisolated enum RemoteAppServerThreadActiveFlag: String, Codable, Equatable, Sendable {
    case waitingOnApproval
    case waitingOnUserInput
}

nonisolated struct RemoteAppServerThreadListResponse: Codable, Sendable {
    let data: [RemoteAppServerThread]
    let nextCursor: String?
}

nonisolated struct RemoteAppServerThreadReadResponse: Codable, Sendable {
    let thread: RemoteAppServerThread
}

nonisolated struct RemoteAppServerThreadResumeResponse: Codable, Sendable {
    let thread: RemoteAppServerThread
    let model: String?
    let modelProvider: String?
    let serviceTier: RemoteAppServerServiceTier?
    let cwd: String?
    let approvalPolicy: RemoteAppServerApprovalPolicy?
    let approvalsReviewer: RemoteAppServerApprovalsReviewer?
    let sandbox: RemoteAppServerSandboxPolicy?
    let reasoningEffort: RemoteAppServerReasoningEffort?
    let collaborationMode: RemoteAppServerCollaborationMode?
}

nonisolated struct RemoteAppServerThreadStartResponse: Codable, Sendable {
    let thread: RemoteAppServerThread
    let model: String?
    let modelProvider: String?
    let serviceTier: RemoteAppServerServiceTier?
    let cwd: String?
    let approvalPolicy: RemoteAppServerApprovalPolicy?
    let approvalsReviewer: RemoteAppServerApprovalsReviewer?
    let sandbox: RemoteAppServerSandboxPolicy?
    let reasoningEffort: RemoteAppServerReasoningEffort?
    let collaborationMode: RemoteAppServerCollaborationMode?
}

nonisolated struct RemoteAppServerTurnStartResponse: Codable, Sendable {
    let turn: RemoteAppServerTurn
}

nonisolated struct RemoteAppServerTurnSteerResponse: Codable, Sendable {
    let turnId: String
}

nonisolated enum RemoteAppServerApprovalsReviewer: String, Codable, Equatable, Sendable {
    case user
    case guardianSubagent = "guardian_subagent"
}

nonisolated enum RemoteAppServerServiceTier: String, Codable, Equatable, Sendable {
    case fast
    case flex
}

nonisolated enum RemoteAppServerReasoningEffort: String, Codable, Equatable, Sendable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
}

nonisolated struct RemoteAppServerReasoningEffortOption: Codable, Equatable, Sendable {
    let reasoningEffort: RemoteAppServerReasoningEffort
    let description: String
}

nonisolated enum RemoteAppServerApprovalPolicy: Codable, Equatable, Sendable {
    case untrusted
    case onFailure
    case onRequest
    case never
    case granular
    case unsupported(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let rawValue = try? container.decode(String.self) {
            switch rawValue {
            case "untrusted":
                self = .untrusted
            case "on-failure":
                self = .onFailure
            case "on-request":
                self = .onRequest
            case "never":
                self = .never
            default:
                self = .unsupported(rawValue)
            }
            return
        }

        if let granular = try? container.decode([String: AnyCodable].self),
           granular["granular"] != nil {
            self = .granular
            return
        }

        self = .unsupported("unsupported")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .untrusted:
            try container.encode("untrusted")
        case .onFailure:
            try container.encode("on-failure")
        case .onRequest:
            try container.encode("on-request")
        case .never:
            try container.encode("never")
        case .granular:
            let granular: [String: [String: Bool]] = ["granular": [:]]
            try container.encode(granular)
        case .unsupported(let rawValue):
            try container.encode(rawValue)
        }
    }
}

nonisolated enum RemoteAppServerSandboxMode: String, Codable, Equatable, Sendable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
    case externalSandbox = "external-sandbox"
}

nonisolated struct RemoteAppServerSandboxPolicy: Codable, Equatable, Sendable {
    let mode: RemoteAppServerSandboxMode
    let networkAccessEnabled: Bool?
    let writableRoots: [String]
    let excludeTmpdirEnvVar: Bool
    let excludeSlashTmp: Bool

    private enum CodingKeys: String, CodingKey {
        case type
        case networkAccess
        case writableRoots
        case excludeTmpdirEnvVar
        case excludeSlashTmp
    }

    init(
        mode: RemoteAppServerSandboxMode,
        networkAccessEnabled: Bool? = nil,
        writableRoots: [String] = [],
        excludeTmpdirEnvVar: Bool = false,
        excludeSlashTmp: Bool = false
    ) {
        self.mode = mode
        self.networkAccessEnabled = networkAccessEnabled
        self.writableRoots = writableRoots
        self.excludeTmpdirEnvVar = excludeTmpdirEnvVar
        self.excludeSlashTmp = excludeSlashTmp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "dangerFullAccess":
            self = .dangerFullAccess
        case "readOnly":
            self = .readOnly(
                networkAccessEnabled: try container.decodeIfPresent(Bool.self, forKey: .networkAccess) ?? false
            )
        case "workspaceWrite":
            self = .workspaceWrite(
                networkAccessEnabled: try container.decodeIfPresent(Bool.self, forKey: .networkAccess) ?? false,
                writableRoots: try container.decodeIfPresent([String].self, forKey: .writableRoots) ?? [],
                excludeTmpdirEnvVar: try container.decodeIfPresent(Bool.self, forKey: .excludeTmpdirEnvVar) ?? false,
                excludeSlashTmp: try container.decodeIfPresent(Bool.self, forKey: .excludeSlashTmp) ?? false
            )
        case "externalSandbox":
            self = .externalSandbox
        default:
            self = .readOnly(networkAccessEnabled: false)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch mode {
        case .dangerFullAccess:
            try container.encode("dangerFullAccess", forKey: .type)
        case .readOnly:
            try container.encode("readOnly", forKey: .type)
            try container.encode(networkAccessEnabled ?? false, forKey: .networkAccess)
        case .workspaceWrite:
            try container.encode("workspaceWrite", forKey: .type)
            try container.encode(networkAccessEnabled ?? false, forKey: .networkAccess)
            try container.encode(writableRoots, forKey: .writableRoots)
            try container.encode(excludeTmpdirEnvVar, forKey: .excludeTmpdirEnvVar)
            try container.encode(excludeSlashTmp, forKey: .excludeSlashTmp)
        case .externalSandbox:
            try container.encode("externalSandbox", forKey: .type)
        }
    }

    static var dangerFullAccess: RemoteAppServerSandboxPolicy {
        RemoteAppServerSandboxPolicy(mode: .dangerFullAccess)
    }

    static func readOnly(networkAccessEnabled: Bool = false) -> RemoteAppServerSandboxPolicy {
        RemoteAppServerSandboxPolicy(
            mode: .readOnly,
            networkAccessEnabled: networkAccessEnabled
        )
    }

    static func workspaceWrite(
        networkAccessEnabled: Bool = false,
        writableRoots: [String] = [],
        excludeTmpdirEnvVar: Bool = false,
        excludeSlashTmp: Bool = false
    ) -> RemoteAppServerSandboxPolicy {
        RemoteAppServerSandboxPolicy(
            mode: .workspaceWrite,
            networkAccessEnabled: networkAccessEnabled,
            writableRoots: writableRoots,
            excludeTmpdirEnvVar: excludeTmpdirEnvVar,
            excludeSlashTmp: excludeSlashTmp
        )
    }

    static var externalSandbox: RemoteAppServerSandboxPolicy {
        RemoteAppServerSandboxPolicy(mode: .externalSandbox)
    }

    var sandboxMode: RemoteAppServerSandboxMode {
        mode
    }
}

nonisolated enum RemoteAppServerModeKind: String, Codable, Equatable, Sendable {
    case plan
    case `default`
}

nonisolated struct RemoteAppServerCollaborationSettings: Codable, Equatable, Sendable {
    let developerInstructions: String?
    let model: String
    let reasoningEffort: RemoteAppServerReasoningEffort?
}

nonisolated struct RemoteAppServerCollaborationMode: Codable, Equatable, Sendable {
    let mode: RemoteAppServerModeKind
    let settings: RemoteAppServerCollaborationSettings
}

nonisolated struct RemoteAppServerCollaborationModeMask: Codable, Equatable, Sendable {
    let name: String
    let mode: RemoteAppServerModeKind?
    let model: String?
    let reasoningEffort: RemoteAppServerReasoningEffort?

    private enum CodingKeys: String, CodingKey {
        case name
        case mode
        case model
        case reasoningEffort = "reasoning_effort"
    }
}

nonisolated struct RemoteAppServerCollaborationModeListResponse: Codable, Sendable {
    let data: [RemoteAppServerCollaborationModeMask]
}

nonisolated struct RemoteAppServerModel: Codable, Equatable, Sendable {
    let id: String
    let model: String
    let displayName: String
    let description: String
    let hidden: Bool
    let supportedReasoningEfforts: [RemoteAppServerReasoningEffortOption]
    let defaultReasoningEffort: RemoteAppServerReasoningEffort
    let isDefault: Bool
}

nonisolated struct RemoteAppServerModelListResponse: Codable, Sendable {
    let data: [RemoteAppServerModel]
    let nextCursor: String?
}

extension RemoteAppServerApprovalPolicy {
    nonisolated var requestValue: String? {
        switch self {
        case .untrusted:
            return "untrusted"
        case .onFailure:
            return "on-failure"
        case .onRequest:
            return "on-request"
        case .never:
            return "never"
        case .granular, .unsupported:
            return nil
        }
    }
}

extension RemoteAppServerSandboxMode {
    nonisolated var requestValue: String {
        switch self {
        case .readOnly:
            return "read-only"
        case .workspaceWrite:
            return "workspace-write"
        case .dangerFullAccess:
            return "danger-full-access"
        case .externalSandbox:
            return "external-sandbox"
        }
    }
}

extension RemoteAppServerSandboxPolicy {
    nonisolated var requestValue: [String: Any] {
        switch mode {
        case .dangerFullAccess:
            return ["type": "dangerFullAccess"]
        case .readOnly:
            return [
                "type": "readOnly",
                "networkAccess": networkAccessEnabled ?? false
            ]
        case .workspaceWrite:
            return [
                "type": "workspaceWrite",
                "networkAccess": networkAccessEnabled ?? false,
                "writableRoots": writableRoots,
                "excludeTmpdirEnvVar": excludeTmpdirEnvVar,
                "excludeSlashTmp": excludeSlashTmp,
                "readOnlyAccess": ["type": "fullAccess"]
            ]
        case .externalSandbox:
            return ["type": "externalSandbox"]
        }
    }
}

extension RemoteAppServerCollaborationMode {
    nonisolated var requestValue: [String: Any] {
        var payloadSettings: [String: Any] = [
            "model": settings.model
        ]
        if let reasoningEffort = settings.reasoningEffort?.rawValue {
            payloadSettings["reasoning_effort"] = reasoningEffort
        }
        if let developerInstructions = settings.developerInstructions {
            payloadSettings["developerInstructions"] = developerInstructions
        } else {
            payloadSettings["developerInstructions"] = NSNull()
        }

        return [
            "mode": mode.rawValue,
            "settings": payloadSettings
        ]
    }
}

nonisolated struct RemoteAppServerThread: Codable, Equatable, Sendable {
    let id: String
    let preview: String
    let ephemeral: Bool
    let modelProvider: String
    let createdAt: Int64
    let updatedAt: Int64
    let status: RemoteAppServerThreadStatus
    let path: String?
    let cwd: String
    let cliVersion: String
    let name: String?
    let turns: [RemoteAppServerTurn]
}

nonisolated struct RemoteAppServerTurn: Codable, Equatable, Sendable {
    let id: String
    let items: [RemoteAppServerThreadItem]
    let status: RemoteAppServerTurnStatus
    let error: RemoteAppServerTurnError?
}

nonisolated enum RemoteAppServerTurnStatus: String, Codable, Equatable, Sendable {
    case completed
    case interrupted
    case failed
    case inProgress
}

nonisolated struct RemoteAppServerTurnError: Codable, Equatable, Sendable {
    let message: String
    let additionalDetails: String?
}

nonisolated struct RemoteAppServerErrorNotification: Codable, Sendable {
    let error: RemoteAppServerTurnError
    let willRetry: Bool
    let threadId: String
    let turnId: String
}

nonisolated struct RemoteAppServerCodexEventErrorNotification: Codable, Sendable {
    let id: String
    let msg: RemoteAppServerCodexEventErrorPayload
    let conversationId: String
}

nonisolated struct RemoteAppServerCodexEventErrorPayload: Codable, Sendable {
    let type: String
    let message: String
    let additionalDetails: String?
}

nonisolated enum RemoteAppServerUserInput: Codable, Equatable, Sendable {
    case text(String)
    case image(String)
    case localImage(String)
    case skill(String)
    case mention(String)
    case unsupported

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case url
        case path
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image":
            self = .image(try container.decode(String.self, forKey: .url))
        case "localImage":
            self = .localImage(try container.decode(String.self, forKey: .path))
        case "skill":
            self = .skill(try container.decode(String.self, forKey: .name))
        case "mention":
            self = .mention(try container.decode(String.self, forKey: .name))
        default:
            self = .unsupported
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let url):
            try container.encode("image", forKey: .type)
            try container.encode(url, forKey: .url)
        case .localImage(let path):
            try container.encode("localImage", forKey: .type)
            try container.encode(path, forKey: .path)
        case .skill(let name):
            try container.encode("skill", forKey: .type)
            try container.encode(name, forKey: .name)
        case .mention(let name):
            try container.encode("mention", forKey: .type)
            try container.encode(name, forKey: .name)
        case .unsupported:
            try container.encode("text", forKey: .type)
            try container.encode("", forKey: .text)
        }
    }

    var displayText: String? {
        switch self {
        case .text(let text):
            return text
        case .image(let url):
            return url
        case .localImage(let path):
            return path
        case .skill(let name), .mention(let name):
            return name
        case .unsupported:
            return nil
        }
    }
}

nonisolated enum RemoteAppServerCommandExecutionStatus: String, Codable, Equatable, Sendable {
    case inProgress
    case completed
    case failed
    case declined
}

nonisolated enum RemoteAppServerPatchApplyStatus: String, Codable, Equatable, Sendable {
    case inProgress
    case completed
    case failed
    case declined
}

nonisolated struct RemoteAppServerFileUpdateChange: Codable, Equatable, Sendable {
    let path: String
    let diff: String
}

nonisolated enum RemoteAppServerThreadItem: Equatable, Sendable {
    case userMessage(id: String, content: [RemoteAppServerUserInput])
    case agentMessage(id: String, text: String)
    case reasoning(id: String, summary: [String], content: [String])
    case plan(id: String, text: String)
    case commandExecution(
        id: String,
        command: String,
        cwd: String,
        status: RemoteAppServerCommandExecutionStatus,
        aggregatedOutput: String?
    )
    case fileChange(
        id: String,
        changes: [RemoteAppServerFileUpdateChange],
        status: RemoteAppServerPatchApplyStatus
    )
    case enteredReviewMode(id: String, review: String)
    case exitedReviewMode(id: String, review: String)
    case contextCompaction(id: String)
    case unsupported(id: String?)
}

extension RemoteAppServerThreadItem {
    var id: String {
        switch self {
        case .userMessage(let id, _),
             .agentMessage(let id, _),
             .reasoning(let id, _, _),
             .plan(let id, _),
             .commandExecution(let id, _, _, _, _),
             .fileChange(let id, _, _),
             .enteredReviewMode(let id, _),
             .exitedReviewMode(let id, _),
             .contextCompaction(let id):
            return id
        case .unsupported(let id):
            return id ?? UUID().uuidString
        }
    }
}

extension RemoteAppServerThreadItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case content
        case text
        case summary
        case command
        case cwd
        case status
        case aggregatedOutput
        case changes
        case review
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let id = try? container.decode(String.self, forKey: .id)

        switch type {
        case "userMessage":
            self = .userMessage(
                id: try container.decode(String.self, forKey: .id),
                content: try container.decode([RemoteAppServerUserInput].self, forKey: .content)
            )
        case "agentMessage":
            self = .agentMessage(
                id: try container.decode(String.self, forKey: .id),
                text: try container.decode(String.self, forKey: .text)
            )
        case "reasoning":
            self = .reasoning(
                id: try container.decode(String.self, forKey: .id),
                summary: (try? container.decode([String].self, forKey: .summary)) ?? [],
                content: (try? container.decode([String].self, forKey: .content)) ?? []
            )
        case "plan":
            self = .plan(
                id: try container.decode(String.self, forKey: .id),
                text: try container.decode(String.self, forKey: .text)
            )
        case "commandExecution":
            self = .commandExecution(
                id: try container.decode(String.self, forKey: .id),
                command: try container.decode(String.self, forKey: .command),
                cwd: try container.decode(String.self, forKey: .cwd),
                status: try container.decode(RemoteAppServerCommandExecutionStatus.self, forKey: .status),
                aggregatedOutput: try? container.decode(String.self, forKey: .aggregatedOutput)
            )
        case "fileChange":
            self = .fileChange(
                id: try container.decode(String.self, forKey: .id),
                changes: (try? container.decode([RemoteAppServerFileUpdateChange].self, forKey: .changes)) ?? [],
                status: try container.decode(RemoteAppServerPatchApplyStatus.self, forKey: .status)
            )
        case "enteredReviewMode":
            self = .enteredReviewMode(
                id: try container.decode(String.self, forKey: .id),
                review: try container.decode(String.self, forKey: .review)
            )
        case "exitedReviewMode":
            self = .exitedReviewMode(
                id: try container.decode(String.self, forKey: .id),
                review: try container.decode(String.self, forKey: .review)
            )
        case "contextCompaction":
            self = .contextCompaction(id: try container.decode(String.self, forKey: .id))
        default:
            self = .unsupported(id: id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .userMessage(let id, let content):
            try container.encode("userMessage", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(content, forKey: .content)
        case .agentMessage(let id, let text):
            try container.encode("agentMessage", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(text, forKey: .text)
        case .reasoning(let id, let summary, let content):
            try container.encode("reasoning", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(summary, forKey: .summary)
            try container.encode(content, forKey: .content)
        case .plan(let id, let text):
            try container.encode("plan", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(text, forKey: .text)
        case .commandExecution(let id, let command, let cwd, let status, let aggregatedOutput):
            try container.encode("commandExecution", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(command, forKey: .command)
            try container.encode(cwd, forKey: .cwd)
            try container.encode(status, forKey: .status)
            try container.encodeIfPresent(aggregatedOutput, forKey: .aggregatedOutput)
        case .fileChange(let id, let changes, let status):
            try container.encode("fileChange", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(changes, forKey: .changes)
            try container.encode(status, forKey: .status)
        case .enteredReviewMode(let id, let review):
            try container.encode("enteredReviewMode", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(review, forKey: .review)
        case .exitedReviewMode(let id, let review):
            try container.encode("exitedReviewMode", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(review, forKey: .review)
        case .contextCompaction(let id):
            try container.encode("contextCompaction", forKey: .type)
            try container.encode(id, forKey: .id)
        case .unsupported(let id):
            try container.encode("unsupported", forKey: .type)
            try container.encodeIfPresent(id, forKey: .id)
        }
    }
}

nonisolated struct RemoteAppServerThreadStartedNotification: Codable, Sendable {
    let thread: RemoteAppServerThread
}

nonisolated struct RemoteAppServerThreadStatusChangedNotification: Codable, Sendable {
    let threadId: String
    let status: RemoteAppServerThreadStatus
}

nonisolated struct RemoteAppServerTurnStartedNotification: Codable, Sendable {
    let threadId: String
    let turn: RemoteAppServerTurn
}

nonisolated struct RemoteAppServerTurnCompletedNotification: Codable, Sendable {
    let threadId: String
    let turn: RemoteAppServerTurn
}

nonisolated struct RemoteAppServerPlanStep: Codable, Equatable, Sendable {
    let step: String
    let status: String
}

nonisolated struct RemoteAppServerTurnPlanUpdatedNotification: Codable, Sendable {
    let threadId: String
    let turnId: String
    let explanation: String?
    let plan: [RemoteAppServerPlanStep]
}

nonisolated struct RemoteAppServerThreadTokenUsageUpdatedNotification: Codable, Sendable {
    let threadId: String
    let turnId: String
    let tokenUsage: RemoteAppServerThreadTokenUsage
}

nonisolated struct RemoteAppServerThreadTokenUsage: Codable, Equatable, Sendable {
    let total: RemoteAppServerTokenUsageBreakdown
    let last: RemoteAppServerTokenUsageBreakdown
    let modelContextWindow: Int?
}

nonisolated struct RemoteAppServerTokenUsageBreakdown: Codable, Equatable, Sendable {
    let totalTokens: Int
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
}

nonisolated struct RemoteAppServerItemStartedNotification: Codable, Sendable {
    let item: RemoteAppServerThreadItem
    let threadId: String
    let turnId: String
}

nonisolated struct RemoteAppServerItemCompletedNotification: Codable, Sendable {
    let item: RemoteAppServerThreadItem
    let threadId: String
    let turnId: String
}

nonisolated struct RemoteAppServerAgentMessageDeltaNotification: Codable, Sendable {
    let threadId: String
    let turnId: String
    let itemId: String
    let delta: String
}

nonisolated struct RemoteAppServerServerRequestResolvedNotification: Codable, Sendable {
    let threadId: String
    let requestId: RemoteRPCID
}

nonisolated struct RemoteAppServerCommandApprovalRequest: Codable, Sendable {
    let threadId: String
    let turnId: String
    let itemId: String
    let approvalId: String?
    let reason: String?
    let command: String?
    let cwd: String?
}

nonisolated struct RemoteAppServerFileChangeApprovalRequest: Codable, Sendable {
    let threadId: String
    let turnId: String
    let itemId: String
    let reason: String?
}

nonisolated struct RemoteAppServerPermissionsApprovalRequest: Codable, Sendable {
    let threadId: String
    let turnId: String
    let itemId: String
    let reason: String?
    let permissions: RemoteAppServerPermissionProfile
}

nonisolated struct RemoteAppServerPermissionProfile: Codable, Sendable {
    let network: RemoteAppServerNetworkPermission?
    let fileSystem: RemoteAppServerFileSystemPermission?
}

nonisolated struct RemoteAppServerNetworkPermission: Codable, Sendable {
    let enabled: Bool?
}

nonisolated struct RemoteAppServerFileSystemPermission: Codable, Sendable {
    let read: [String]?
    let write: [String]?
}

extension RemoteAppServerThreadTokenUsage {
    nonisolated var sessionValue: SessionTokenUsageInfo {
        SessionTokenUsageInfo(
            totalTokenUsage: total.sessionValue,
            lastTokenUsage: last.sessionValue,
            modelContextWindow: modelContextWindow
        )
    }
}

extension RemoteAppServerTokenUsageBreakdown {
    nonisolated var sessionValue: SessionTokenUsage {
        SessionTokenUsage(
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            reasoningOutputTokens: reasoningOutputTokens,
            totalTokens: totalTokens
        )
    }
}

nonisolated func remoteDecodeValue<T: Decodable>(_ value: AnyCodable, as type: T.Type) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(type, from: data)
}
