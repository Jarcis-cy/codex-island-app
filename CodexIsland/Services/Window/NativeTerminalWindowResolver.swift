//
//  NativeTerminalWindowResolver.swift
//  CodexIsland
//
//  Resolves and focuses non-tmux terminal windows via Accessibility APIs.
//

import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

actor NativeTerminalWindowResolver {
    static let shared = NativeTerminalWindowResolver()

    private init() {}

    func resolveWindow(appPid: Int, bundleId: String?, tty: String?) async -> TerminalWindowResolution {
        guard AXIsProcessTrusted() else {
            return TerminalWindowResolution(
                terminalBundleId: bundleId,
                terminalProcessId: appPid,
                focusTarget: nil,
                focusCapability: .requiresAccessibility
            )
        }

        let appElement = AXUIElementCreateApplication(pid_t(appPid))
        guard let focusedWindow = copyWindowAttribute(appElement, attribute: kAXFocusedWindowAttribute) else {
            return TerminalWindowResolution(
                terminalBundleId: bundleId,
                terminalProcessId: appPid,
                focusTarget: nil,
                focusCapability: .unresolved
            )
        }

        let title = windowTitle(for: focusedWindow)
        let windowId = currentWindowId(appPid: appPid, title: title)
        let canMatchWindow = (title?.isEmpty == false) || windowId != nil

        return TerminalWindowResolution(
            terminalBundleId: bundleId,
            terminalProcessId: appPid,
            focusTarget: canMatchWindow ? TerminalFocusTarget(
                kind: .nativeWindow,
                appBundleId: bundleId,
                appPid: appPid,
                windowId: windowId,
                windowTitle: title,
                tty: tty
            ) : nil,
            focusCapability: canMatchWindow ? .ready : .unresolved
        )
    }

    func focus(target: TerminalFocusTarget) async -> TerminalFocusCapability {
        guard let appPid = target.appPid,
              let app = NSRunningApplication(processIdentifier: pid_t(appPid)) else {
            return .unresolved
        }

        let _ = app.activate(options: [.activateAllWindows])

        guard AXIsProcessTrusted() else {
            return .requiresAccessibility
        }

        let appElement = AXUIElementCreateApplication(pid_t(appPid))
        if let window = findWindowElement(appElement: appElement, target: target) {
            _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            let focusedValue = kCFBooleanTrue as CFTypeRef
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, focusedValue)
            AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, focusedValue)
            return .ready
        }

        return .stale
    }

    private func findWindowElement(appElement: AXUIElement, target: TerminalFocusTarget) -> AXUIElement? {
        if let focusedWindow = copyWindowAttribute(appElement, attribute: kAXFocusedWindowAttribute),
           matches(window: focusedWindow, target: target) {
            return focusedWindow
        }

        guard let windows = copyAttributeArray(appElement, attribute: kAXWindowsAttribute) else {
            return nil
        }

        for window in windows where matches(window: window, target: target) {
            return window
        }

        return nil
    }

    private func matches(window: AXUIElement, target: TerminalFocusTarget) -> Bool {
        let title = windowTitle(for: window)
        if let targetTitle = target.windowTitle, !targetTitle.isEmpty, title == targetTitle {
            return true
        }

        if let targetWindowId = target.windowId,
           let appPid = target.appPid,
           currentWindowId(appPid: appPid, title: title) == targetWindowId {
            return true
        }

        return false
    }

    private func currentWindowId(appPid: Int, title: String?) -> Int? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        for window in windowList {
            guard let ownerPid = window[kCGWindowOwnerPID as String] as? Int,
                  ownerPid == appPid,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let windowId = window[kCGWindowNumber as String] as? Int else {
                continue
            }

            let windowTitle = (window[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if normalizedTitle == nil || normalizedTitle == windowTitle {
                return windowId
            }
        }

        return nil
    }

    private func windowTitle(for window: AXUIElement) -> String? {
        copyAttribute(window, attribute: kAXTitleAttribute) as? String
    }

    private func copyWindowAttribute(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        guard let value = copyAttribute(element, attribute: attribute) else {
            return nil
        }

        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyAttribute(_ element: AXUIElement, attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value as AnyObject?
    }

    private func copyAttributeArray(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
        guard let raw = copyAttribute(element, attribute: attribute) as? [AnyObject] else {
            return nil
        }

        return raw.compactMap { value in
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeBitCast(value, to: AXUIElement.self)
        }
    }
}
