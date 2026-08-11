//
//  RewriteView.swift
//  UnpackdKeyboard
//
//  Original vs. rewrite, with the choice left to the user.
//

import SwiftUI

struct RewriteView: View {

    let original: String
    let reflection: Reflection
    @Binding var selection: Int
    let onUse: (String) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Here's an improved version of your message.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            // Showing the original alongside the rewrite is a deliberate
            // product choice: the user should see what changed and be able to
            // disagree, not be handed a replacement to accept blindly.
            HStack(alignment: .top, spacing: 10) {
                messageCard(
                    caption: "Original",
                    text: original,
                    badge: reflection.detectedEmotion.label,
                    badgeTint: .red
                )

                Image(systemName: "arrow.right")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 34)

                messageCard(
                    caption: "Rewrite",
                    text: currentRewrite?.text ?? "",
                    badge: currentRewrite?.toneLabel ?? "",
                    badgeTint: .green
                )
            }

            if reflection.rewrites.count > 1 {
                pager
            }

            Button {
                if let text = currentRewrite?.text { onUse(text) }
            } label: {
                Text("Use this message")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary)
                    )
                    .foregroundStyle(Color(uiColor: .systemBackground))
            }
            .buttonStyle(.plain)
        }
    }

    private var currentRewrite: Rewrite? {
        reflection.rewrites.indices.contains(selection) ? reflection.rewrites[selection] : reflection.rewrites.first
    }

    private func messageCard(
        caption: String,
        text: String,
        badge: String,
        badgeTint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)

                if !badge.isEmpty {
                    Pill(badge, tint: badgeTint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )
        }
    }

    /// Dots to move between alternatives. Tapping cycles; the model produced
    /// three, and one of them is usually closer to how the user actually talks.
    private var pager: some View {
        HStack(spacing: 6) {
            ForEach(reflection.rewrites.indices, id: \.self) { index in
                Circle()
                    .fill(index == selection ? Color.primary.opacity(0.7) : Color.primary.opacity(0.18))
                    .frame(width: 6, height: 6)
                    .onTapGesture { selection = index }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rewrite \(selection + 1) of \(reflection.rewrites.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selection = min(selection + 1, reflection.rewrites.count - 1)
            case .decrement: selection = max(selection - 1, 0)
            @unknown default: break
            }
        }
    }
}
