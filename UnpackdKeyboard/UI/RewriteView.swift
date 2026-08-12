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
            // Swiping the cards is what people actually try; the dots below are
            // an indicator first and a fallback target second. `minimumDistance`
            // keeps this from stealing taps meant for the buttons.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        page(by: value.translation.width < 0 ? 1 : -1)
                    }
            )

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

    /// Move `offset` rewrites from the current one, clamped to what exists.
    ///
    /// The single place selection changes. Swipe, dot tap and the VoiceOver
    /// adjustable action all route through here so the bounds and the
    /// animation can't drift apart.
    private func page(by offset: Int) {
        let target = min(max(selection + offset, 0), reflection.rewrites.count - 1)
        guard target != selection else { return }
        withAnimation(.snappy(duration: 0.2)) { selection = target }
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

    /// Dots to move between alternatives. The model produced three, and one of
    /// them is usually closer to how the user actually talks.
    ///
    /// The dot is 6pt but its tap target is padded to 22×22 — a 6pt target is
    /// unhittable, especially on a keyboard panel where the thumb is nowhere
    /// near where the eyes are.
    private var pager: some View {
        HStack(spacing: 0) {
            ForEach(reflection.rewrites.indices, id: \.self) { index in
                Circle()
                    .fill(index == selection ? Color.primary.opacity(0.7) : Color.primary.opacity(0.18))
                    .frame(width: 6, height: 6)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .onTapGesture { page(by: index - selection) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rewrite \(selection + 1) of \(reflection.rewrites.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: page(by: 1)
            case .decrement: page(by: -1)
            @unknown default: break
            }
        }
    }
}
