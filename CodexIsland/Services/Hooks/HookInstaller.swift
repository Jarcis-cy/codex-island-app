//
//  HookInstaller.swift
//  CodexIsland
//
//  Auto-installs Codex hooks on app launch.
//

import Foundation
import os.log

struct HookInstaller {
    private static let logger = Logger(subsystem: "com.codexisland", category: "Hooks")
    private static let scriptName = "codex-island-state.py"
    private static let legacyScriptNames = ["claude-island-state.py"]
    private static let supportedHookEvents = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "Stop",
    ]

    enum HookInstallerError: LocalizedError {
        case bundledScriptMissing
        case createDirectoryFailed(URL, Error)
        case removeExistingScriptFailed(URL, Error)
        case copyScriptFailed(URL, Error)
        case setPermissionsFailed(URL, Error)
        case readHooksConfigFailed(URL, Error)
        case decodeHooksConfigFailed(URL)
        case writeHooksConfigFailed(URL, Error)
        case readConfigFailed(URL, Error)
        case writeConfigFailed(URL, Error)
        case removeScriptFailed(URL, Error)

        var errorDescription: String? {
            switch self {
            case .bundledScriptMissing:
                return "Bundled hook script is missing."
            case .createDirectoryFailed(let url, let error):
                return "Failed to create hooks directory at \(url.path): \(error.localizedDescription)"
            case .removeExistingScriptFailed(let url, let error):
                return "Failed to remove existing hook script at \(url.path): \(error.localizedDescription)"
            case .copyScriptFailed(let url, let error):
                return "Failed to install hook script to \(url.path): \(error.localizedDescription)"
            case .setPermissionsFailed(let url, let error):
                return "Failed to set hook script permissions at \(url.path): \(error.localizedDescription)"
            case .readHooksConfigFailed(let url, let error):
                return "Failed to read hooks config at \(url.path): \(error.localizedDescription)"
            case .decodeHooksConfigFailed(let url):
                return "Hooks config at \(url.path) is not valid JSON."
            case .writeHooksConfigFailed(let url, let error):
                return "Failed to write hooks config at \(url.path): \(error.localizedDescription)"
            case .readConfigFailed(let url, let error):
                return "Failed to read config at \(url.path): \(error.localizedDescription)"
            case .writeConfigFailed(let url, let error):
                return "Failed to write config at \(url.path): \(error.localizedDescription)"
            case .removeScriptFailed(let url, let error):
                return "Failed to remove hook script at \(url.path): \(error.localizedDescription)"
            }
        }
    }

    private struct InstallationPaths {
        let codexDir: URL
        let hooksDir: URL
        let pythonScript: URL
        let hooksConfig: URL
        let configToml: URL

        var managedScripts: [URL] {
            [pythonScript] + HookInstaller.legacyScriptNames.map { hooksDir.appendingPathComponent($0) }
        }
    }

    private struct FileSnapshot {
        let url: URL
        let existed: Bool
        let data: Data?
        let permissions: NSNumber?
    }

    /// Install hook script and update hooks.json on app launch.
    static func installIfNeeded() throws {
        try installIfNeeded(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            bundledScriptURL: bundledScriptURL(),
            fileManager: .default
        )
    }

    static func installIfNeeded(
        homeDirectory: URL,
        bundledScriptURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let paths = makePaths(homeDirectory: homeDirectory)
        let snapshots = try captureSnapshots(for: [paths.pythonScript, paths.hooksConfig, paths.configToml], fileManager: fileManager)
        let hooksDirExists = fileManager.fileExists(atPath: paths.hooksDir.path)

        do {
            try fileManager.createDirectory(at: paths.hooksDir, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: paths.pythonScript.path) {
                do {
                    try fileManager.removeItem(at: paths.pythonScript)
                } catch {
                    throw HookInstallerError.removeExistingScriptFailed(paths.pythonScript, error)
                }
            }

            do {
                try fileManager.copyItem(at: bundledScriptURL, to: paths.pythonScript)
            } catch {
                throw HookInstallerError.copyScriptFailed(paths.pythonScript, error)
            }

            do {
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.pythonScript.path)
            } catch {
                throw HookInstallerError.setPermissionsFailed(paths.pythonScript, error)
            }

            try updateHooks(at: paths.hooksConfig)
            try enableCodexHooksFeature(at: paths.configToml)
        } catch {
            do {
                try restoreSnapshots(snapshots, fileManager: fileManager)
                if !hooksDirExists {
                    try removeDirectoryIfEmpty(paths.hooksDir, fileManager: fileManager)
                }
            } catch {
                logger.error("Failed to roll back hook installation state: \(error.localizedDescription, privacy: .public)")
            }
            logger.error("Hook installation failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private static func updateHooks(at hooksURL: URL) throws {
        var json: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: hooksURL.path) {
            let data: Data
            do {
                data = try Data(contentsOf: hooksURL)
            } catch {
                throw HookInstallerError.readHooksConfigFailed(hooksURL, error)
            }

            guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HookInstallerError.decodeHooksConfigFailed(hooksURL)
            }
            json = existing
        }

        let python = detectPython()
        let command = "\(python) ~/.codex/hooks/\(scriptName)"
        let hookEntry: [String: Any] = ["type": "command", "command": command, "timeout": 30]
        let hookGroup: [[String: Any]] = [["hooks": [hookEntry]]]

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        pruneManagedHooks(from: &hooks)

        for event in supportedHookEvents {
            var eventEntries = sanitizedEntries(from: hooks[event] as? [[String: Any]] ?? [])
            eventEntries.append(contentsOf: hookGroup)
            hooks[event] = eventEntries
        }

        json["hooks"] = hooks

        let data = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )

        do {
            try data.write(to: hooksURL)
        } catch {
            throw HookInstallerError.writeHooksConfigFailed(hooksURL, error)
        }
    }

    private static func enableCodexHooksFeature(at configURL: URL) throws {
        let fileManager = FileManager.default
        let contentExists = fileManager.fileExists(atPath: configURL.path)
        let initialContent: String

        if contentExists {
            do {
                initialContent = try String(contentsOf: configURL, encoding: .utf8)
            } catch {
                throw HookInstallerError.readConfigFailed(configURL, error)
            }
        } else {
            initialContent = ""
        }

        let content = updatedConfigContentEnablingCodexHooks(initialContent)

        if !fileManager.fileExists(atPath: configURL.deletingLastPathComponent().path) {
            do {
                try fileManager.createDirectory(
                    at: configURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                throw HookInstallerError.createDirectoryFailed(configURL.deletingLastPathComponent(), error)
            }
        }

        do {
            try content.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw HookInstallerError.writeConfigFailed(configURL, error)
        }
    }

    private static func updatedConfigContentEnablingCodexHooks(_ content: String) -> String {
        let normalizedContent = content.isEmpty || content.hasSuffix("\n") ? content : "\(content)\n"

        guard let featuresRange = normalizedContent.range(of: #"(?m)^\[features\]\s*$"#, options: .regularExpression) else {
            if normalizedContent.isEmpty {
                return "[features]\ncodex_hooks = true\n"
            }
            return "\(normalizedContent)\n[features]\ncodex_hooks = true\n"
        }

        let suffix = normalizedContent[featuresRange.upperBound...]
        let nextSectionRange = suffix.range(of: #"(?m)^\["#, options: .regularExpression)
        let sectionEnd = nextSectionRange?.lowerBound ?? normalizedContent.endIndex
        let featureBodyRange = featuresRange.upperBound ..< sectionEnd
        let featureBody = String(normalizedContent[featureBodyRange])

        if let codexHooksRange = featureBody.range(
            of: #"(?m)^(\s*codex_hooks\s*=\s*)(true|false)\s*(#.*)?$"#,
            options: .regularExpression
        ) {
            let existingLine = String(featureBody[codexHooksRange])
            let comment = existingLine.firstIndex(of: "#").map { String(existingLine[$0...]).trimmingCharacters(in: .whitespaces) }
            var replacement = "codex_hooks = true"
            if let comment, !comment.isEmpty {
                replacement.append(" \(comment)")
            }

            var updatedContent = normalizedContent
            updatedContent.replaceSubrange(codexHooksRange, with: replacement)
            return updatedContent
        }

        var insertion = "codex_hooks = true\n"
        if !featureBody.isEmpty, !featureBody.hasPrefix("\n") {
            insertion = "\n" + insertion
        }

        var updatedContent = normalizedContent
        updatedContent.insert(contentsOf: insertion, at: sectionEnd)
        return updatedContent
    }

    /// Check if hooks are currently installed
    static func isInstalled() -> Bool {
        let codexDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
        let hooksConfig = codexDir.appendingPathComponent("hooks.json")

        guard let data = try? Data(contentsOf: hooksConfig),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        for hook in entryHooks {
                            if let cmd = hook["command"] as? String,
                               isManagedCommand(cmd) {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    /// Uninstall hooks from settings.json and remove script
    static func uninstall() throws {
        try uninstall(homeDirectory: FileManager.default.homeDirectoryForCurrentUser, fileManager: .default)
    }

    static func uninstall(
        homeDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        let paths = makePaths(homeDirectory: homeDirectory)
        let snapshots = try captureSnapshots(for: paths.managedScripts + [paths.hooksConfig], fileManager: fileManager)

        do {
            for scriptURL in paths.managedScripts where fileManager.fileExists(atPath: scriptURL.path) {
                do {
                    try fileManager.removeItem(at: scriptURL)
                } catch {
                    throw HookInstallerError.removeScriptFailed(scriptURL, error)
                }
            }

            guard fileManager.fileExists(atPath: paths.hooksConfig.path) else {
                return
            }

            let data: Data
            do {
                data = try Data(contentsOf: paths.hooksConfig)
            } catch {
                throw HookInstallerError.readHooksConfigFailed(paths.hooksConfig, error)
            }

            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var hooks = json["hooks"] as? [String: Any] else {
                throw HookInstallerError.decodeHooksConfigFailed(paths.hooksConfig)
            }

            pruneManagedHooks(from: &hooks)

            if hooks.isEmpty {
                json.removeValue(forKey: "hooks")
            } else {
                json["hooks"] = hooks
            }

            let encoded = try JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys]
            )

            do {
                try encoded.write(to: paths.hooksConfig)
            } catch {
                throw HookInstallerError.writeHooksConfigFailed(paths.hooksConfig, error)
            }
        } catch {
            do {
                try restoreSnapshots(snapshots, fileManager: fileManager)
            } catch {
                logger.error("Failed to roll back hook uninstall state: \(error.localizedDescription, privacy: .public)")
            }
            logger.error("Hook uninstall failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private static func makePaths(homeDirectory: URL) -> InstallationPaths {
        let codexDir = homeDirectory.appendingPathComponent(".codex")
        let hooksDir = codexDir.appendingPathComponent("hooks")
        return InstallationPaths(
            codexDir: codexDir,
            hooksDir: hooksDir,
            pythonScript: hooksDir.appendingPathComponent(scriptName),
            hooksConfig: codexDir.appendingPathComponent("hooks.json"),
            configToml: codexDir.appendingPathComponent("config.toml")
        )
    }

    private static func bundledScriptURL() throws -> URL {
        guard let bundled = Bundle.main.url(forResource: "codex-island-state", withExtension: "py") else {
            throw HookInstallerError.bundledScriptMissing
        }
        return bundled
    }

    private static func captureSnapshots(for urls: [URL], fileManager: FileManager) throws -> [FileSnapshot] {
        try urls.map { url in
            let existed = fileManager.fileExists(atPath: url.path)
            let data = existed ? try Data(contentsOf: url) : nil
            let permissions = existed ? try fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber : nil
            return FileSnapshot(url: url, existed: existed, data: data, permissions: permissions)
        }
    }

    private static func restoreSnapshots(_ snapshots: [FileSnapshot], fileManager: FileManager) throws {
        for snapshot in snapshots {
            if snapshot.existed {
                let parentDirectory = snapshot.url.deletingLastPathComponent()
                try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
                try snapshot.data?.write(to: snapshot.url)
                if let permissions = snapshot.permissions {
                    try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: snapshot.url.path)
                }
            } else if fileManager.fileExists(atPath: snapshot.url.path) {
                try fileManager.removeItem(at: snapshot.url)
            }
        }
    }

    private static func removeDirectoryIfEmpty(_ directory: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }

        let contents = try fileManager.contentsOfDirectory(atPath: directory.path)
        guard contents.isEmpty else {
            return
        }

        try fileManager.removeItem(at: directory)
    }

    private static func detectPython() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return "python3"
            }
        } catch {}

        return "python"
    }

    private static func pruneManagedHooks(from hooks: inout [String: Any]) {
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }

            let sanitized = sanitizedEntries(from: entries)
            if sanitized.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = sanitized
            }
        }
    }

    private static func sanitizedEntries(from entries: [[String: Any]]) -> [[String: Any]] {
        entries.compactMap { entry in
            guard let entryHooks = entry["hooks"] as? [[String: Any]] else {
                return entry
            }

            let retainedHooks = entryHooks.filter { hook in
                let command = hook["command"] as? String ?? ""
                return !isManagedCommand(command)
            }

            guard !retainedHooks.isEmpty else {
                return nil
            }

            var sanitizedEntry = entry
            sanitizedEntry["hooks"] = retainedHooks
            return sanitizedEntry
        }
    }

    private static func isManagedCommand(_ command: String) -> Bool {
        ([scriptName] + legacyScriptNames).contains { managedName in
            command.contains(managedName)
        }
    }
}
