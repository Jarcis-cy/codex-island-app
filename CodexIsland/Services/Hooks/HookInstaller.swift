//
//  HookInstaller.swift
//  CodexIsland
//
//  Auto-installs Codex hooks on app launch.
//

import Foundation

struct HookInstaller {
    private static let scriptName = "codex-island-state.py"
    private static let legacyScriptNames = ["claude-island-state.py"]
    private static let supportedHookEvents = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "Stop",
    ]

    /// Install hook script and update hooks.json on app launch.
    static func installIfNeeded() {
        let codexDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
        let hooksDir = codexDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent(scriptName)
        let hooksConfig = codexDir.appendingPathComponent("hooks.json")
        let configToml = codexDir.appendingPathComponent("config.toml")

        try? FileManager.default.createDirectory(
            at: hooksDir,
            withIntermediateDirectories: true
        )

        if let bundled = Bundle.main.url(forResource: "codex-island-state", withExtension: "py") {
            try? FileManager.default.removeItem(at: pythonScript)
            try? FileManager.default.copyItem(at: bundled, to: pythonScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pythonScript.path
            )
        }

        updateHooks(at: hooksConfig)
        enableCodexHooksFeature(at: configToml)
    }

    private static func updateHooks(at hooksURL: URL) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: hooksURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
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

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: hooksURL)
        }
    }

    private static func enableCodexHooksFeature(at configURL: URL) {
        let fileManager = FileManager.default
        var content = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""

        if content.contains("codex_hooks = true") {
            return
        }

        if let featuresRange = content.range(of: #"(?m)^\[features\]\s*$"#, options: .regularExpression) {
            let suffix = content[featuresRange.upperBound...]
            if let nextSection = suffix.range(of: #"(?m)^\["#, options: .regularExpression) {
                content.insert(contentsOf: "\ncodex_hooks = true\n", at: nextSection.lowerBound)
            } else {
                if !content.hasSuffix("\n") {
                    content.append("\n")
                }
                content.append("codex_hooks = true\n")
            }
        } else {
            if !content.isEmpty && !content.hasSuffix("\n") {
                content.append("\n")
            }
            content.append("\n[features]\ncodex_hooks = true\n")
        }

        if !fileManager.fileExists(atPath: configURL.deletingLastPathComponent().path) {
            try? fileManager.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        try? content.write(to: configURL, atomically: true, encoding: .utf8)
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
    static func uninstall() {
        let codexDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
        let hooksDir = codexDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent(scriptName)
        let hooksConfig = codexDir.appendingPathComponent("hooks.json")

        try? FileManager.default.removeItem(at: pythonScript)
        for legacyScriptName in legacyScriptNames {
            try? FileManager.default.removeItem(at: hooksDir.appendingPathComponent(legacyScriptName))
        }

        guard let data = try? Data(contentsOf: hooksConfig),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        pruneManagedHooks(from: &hooks)

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: hooksConfig)
        }
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
