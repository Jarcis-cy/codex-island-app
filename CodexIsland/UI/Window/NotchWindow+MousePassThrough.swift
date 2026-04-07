//
//  NotchWindow+MousePassThrough.swift
//  CodexIsland
//
//  Mouse gesture capture state for click-through notch windows
//

import AppKit

private enum NotchMouseButton: Hashable {
    case left
    case right
}

struct NotchMousePassThroughState {
    private var capturedButtons: Set<NotchMouseButton> = []

    mutating func shouldPassThrough(eventType: NSEvent.EventType, hasHitTarget: Bool) -> Bool {
        switch eventType {
        case .leftMouseDown:
            return updateCapture(button: .left, isDown: true, hasHitTarget: hasHitTarget)
        case .leftMouseUp:
            return updateCapture(button: .left, isDown: false, hasHitTarget: hasHitTarget)
        case .rightMouseDown:
            return updateCapture(button: .right, isDown: true, hasHitTarget: hasHitTarget)
        case .rightMouseUp:
            return updateCapture(button: .right, isDown: false, hasHitTarget: hasHitTarget)
        default:
            return false
        }
    }

    private mutating func updateCapture(
        button: NotchMouseButton,
        isDown: Bool,
        hasHitTarget: Bool
    ) -> Bool {
        if isDown {
            if hasHitTarget {
                capturedButtons.insert(button)
                return false
            }
            return true
        }

        let captured = capturedButtons.remove(button) != nil
        return !captured && !hasHitTarget
    }
}
