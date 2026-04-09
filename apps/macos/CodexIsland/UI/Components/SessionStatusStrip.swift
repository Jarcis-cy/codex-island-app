//
//  SessionStatusStrip.swift
//  CodexIsland
//
//  Compact runtime status chips for model and context information.
//

import SwiftUI

struct SessionStatusStrip: View {
    let model: String?
    let reasoningEffort: String?
    let serviceTier: String?
    let contextRemainingPercent: Int?

    private var items: [(icon: String, text: String)] {
        var values: [(String, String)] = []

        if let model, !model.isEmpty {
            values.append(("sparkles", model))
        }
        if let reasoningEffort, !reasoningEffort.isEmpty {
            values.append(("brain", reasoningEffort.lowercased()))
        }
        if let serviceTier, !serviceTier.isEmpty {
            values.append(("bolt", serviceTier.lowercased()))
        }
        if let contextRemainingPercent {
            values.append(("gauge.with.dots.needle.50percent", "\(contextRemainingPercent)% left"))
        }

        return values
    }

    var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        SessionStatusChip(icon: item.icon, text: item.text)
                    }
                }
            }
            .scrollDisabled(true)
        }
    }
}

private struct SessionStatusChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))

            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
    }
}
