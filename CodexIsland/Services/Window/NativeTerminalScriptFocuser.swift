//
//  NativeTerminalScriptFocuser.swift
//  CodexIsland
//
//  Uses native terminal scripting APIs for precise session focus.
//

import Foundation

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
                focus terminal id "\(appleScriptEscaped(surfaceId))"
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
                activate window id "\(appleScriptEscaped(windowId))"
                select tab id "\(appleScriptEscaped(tabId))"
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
                activate window id "\(appleScriptEscaped(windowId))"
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

        let shortTTY = appleScriptEscaped(tty.replacingOccurrences(of: "/dev/", with: ""))
        let fullTTY = appleScriptEscaped(tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)")
        let script = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    set terminalTTY to (tty of t as text)
                    if terminalTTY is "\(shortTTY)" or terminalTTY is "\(fullTTY)" then
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

        let shortTTY = appleScriptEscaped(tty.replacingOccurrences(of: "/dev/", with: ""))
        let fullTTY = appleScriptEscaped(tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)")
        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set sessionTTY to (tty of s as text)
                        if sessionTTY is "\(shortTTY)" or sessionTTY is "\(fullTTY)" then
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
        guard let output = await ProcessExecutor.shared.runOrNil("/usr/bin/osascript", arguments: ["-e", script]) else {
            return nil
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
