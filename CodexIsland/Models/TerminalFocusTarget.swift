//
//  TerminalFocusTarget.swift
//  CodexIsland
//
//  Terminal focus metadata captured for each session.
//

import Foundation

enum TerminalFocusKind: String, Equatable, Sendable {
    case tmuxPane
    case nativeWindow
}

enum TerminalFocusCapability: String, Equatable, Sendable {
    case ready
    case requiresAccessibility
    case unresolved
    case stale
}

struct TerminalFocusTarget: Equatable, Sendable {
    let kind: TerminalFocusKind
    let appBundleId: String?
    let appPid: Int?
    let windowId: Int?
    let windowTitle: String?
    let tty: String?
    let tmuxTarget: String?
    let capturedAt: Date

    nonisolated init(
        kind: TerminalFocusKind,
        appBundleId: String? = nil,
        appPid: Int? = nil,
        windowId: Int? = nil,
        windowTitle: String? = nil,
        tty: String? = nil,
        tmuxTarget: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.kind = kind
        self.appBundleId = appBundleId
        self.appPid = appPid
        self.windowId = windowId
        self.windowTitle = windowTitle
        self.tty = tty
        self.tmuxTarget = tmuxTarget
        self.capturedAt = capturedAt
    }
}
