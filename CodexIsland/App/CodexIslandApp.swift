//
//  CodexIslandApp.swift
//  CodexIsland
//
//  Dynamic Island for monitoring Codex CLI sessions
//

import SwiftUI

@main
struct CodexIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use a completely custom window, so no default scene needed
        Settings {
            EmptyView()
        }
    }
}
