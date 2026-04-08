//
//  NativeTerminalScriptFocuser.swift
//  CodexIsland
//
//  Uses native terminal scripting APIs for precise session focus.
//

import Foundation

enum TerminalAppleScript {
    nonisolated static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    nonisolated static func ttyVariants(for tty: String) -> (short: String, full: String) {
        let shortTTY = tty.replacingOccurrences(of: "/dev/", with: "")
        let fullTTY = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        return (escaped(shortTTY), escaped(fullTTY))
    }

    nonisolated static func run(_ script: String) async -> Result<String, Error> {
        let result = await ProcessExecutor.shared.runWithResult("/usr/bin/osascript", arguments: ["-e", script])
        switch result {
        case .success(let processResult):
            return .success(processResult.output.trimmingCharacters(in: .whitespacesAndNewlines))
        case .failure(let error):
            return .failure(error)
        }
    }
}

actor NativeTerminalScriptFocuser {
    static let shared = NativeTerminalScriptFocuser()

    private init() {}

    func focus(session: SessionState) async -> Bool {
        let bundleId = session.terminalBundleId
        let terminalName = session.terminalName?.lowercased()

        if bundleId == "com.mitchellh.ghostty" || terminalName == "ghostty" {
            return await focusGhostty(session: session)
        }

        if bundleId == "com.apple.Terminal" || terminalName == "apple_terminal" || terminalName == "terminal" {
            return await focusTerminalApp(tty: session.tty)
        }

        if bundleId == "com.googlecode.iterm2" || terminalName?.contains("iterm") == true {
            return await focusITerm(tty: session.tty)
        }

        return false
    }

    private func focusGhostty(session: SessionState) async -> Bool {
        if let surfaceId = session.terminalSurfaceId {
            let script = """
            tell application "Ghostty"
                focus terminal id "\(TerminalAppleScript.escaped(surfaceId))"
            end tell
            return "ok"
            """
            if await run(script: script) == "ok" {
                return true
            }
        }

        if let tabId = session.terminalTabId,
           let windowId = session.terminalWindowId {
            let script = """
            tell application "Ghostty"
                activate window id "\(TerminalAppleScript.escaped(windowId))"
                select tab id "\(TerminalAppleScript.escaped(tabId))"
            end tell
            return "ok"
            """
            if await run(script: script) == "ok" {
                return true
            }
        }

        if let windowId = session.terminalWindowId {
            let script = """
            tell application "Ghostty"
                activate window id "\(TerminalAppleScript.escaped(windowId))"
            end tell
            return "ok"
            """
            if await run(script: script) == "ok" {
                return true
            }
        }

        return false
    }

    private func focusTerminalApp(tty: String?) async -> Bool {
        guard let tty else { return false }

        let ttyVariants = TerminalAppleScript.ttyVariants(for: tty)
        let script = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    set terminalTTY to (tty of t as text)
                    if terminalTTY is "\(ttyVariants.short)" or terminalTTY is "\(ttyVariants.full)" then
                        set selected of t to true
                        set frontmost of w to true
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        return "miss"
        """

        return await run(script: script) == "ok"
    }

    private func focusITerm(tty: String?) async -> Bool {
        guard let tty else { return false }

        let ttyVariants = TerminalAppleScript.ttyVariants(for: tty)
        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionTTY to (tty of s as text)
                        if sessionTTY is "\(ttyVariants.short)" or sessionTTY is "\(ttyVariants.full)" then
                            tell w
                                set current tab to t
                                set frontmost to true
                            end tell
                            tell t
                                set current session to s
                            end tell
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "miss"
        """

        return await run(script: script) == "ok"
    }

    private func run(script: String) async -> String? {
        switch await TerminalAppleScript.run(script) {
        case .success(let output):
            return output
        case .failure:
            return nil
        }
    }
}
