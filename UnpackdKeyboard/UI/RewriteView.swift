//
//  RewriteView.swift
//  UnpackdKeyboard
//

import SwiftUI

struct RewriteView: View {

    let original: String
    let reflection: Reflection
    @Binding var selection: Int
    let onUse: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            originalSummary
            rewriteCard

            if reflection.rewrites.count > 1 {
                pager
            }

            Button {
                if let text = currentRewrite?.text { onUse(text) }
            } label: {
                Text("Use this message")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KeyboardTheme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        Capsule()
                            .fill(KeyboardTheme.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    page(by: value.translation.width < 0 ? 1 : -1)
                }
        )
    }

    private var currentRewrite: Rewrite? {
        reflection.rewrites.indices.contains(selection) ? reflection.rewrites[selection] : reflection.rewrites.first
    }

    private var originalSummary: some View {
        HStack(spacing: 8) {
            Pill(reflection.detectedEmotion.label, tint: Color(red: 0.710, green: 0.305, blue: 0.305))
            Text(original.isEmpty ? "No draft text found." : original)
                .font(.system(size: 12))
                .foregroundStyle(KeyboardTheme.mutedInk)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private var rewriteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(currentRewrite?.toneLabel ?? "Rewrite")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(KeyboardTheme.mutedInk)
                Spacer()
                Text("\(selection + 1)/\(max(reflection.rewrites.count, 1))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(KeyboardTheme.mutedInk)
            }

            Text(currentRewrite?.text ?? "")
                .font(.system(size: 15))
                .foregroundStyle(KeyboardTheme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .cardChrome(.roomy)
    }

    private func page(by offset: Int) {
        let target = min(max(selection + offset, 0), reflection.rewrites.count - 1)
        guard target != selection else { return }
        withAnimation(.snappy(duration: 0.2)) { selection = target }
    }

    private var pager: some View {
        HStack(spacing: 0) {
            ForEach(reflection.rewrites.indices, id: \.self) { index in
                Circle()
                    .fill(index == selection ? KeyboardTheme.ink.opacity(0.72) : KeyboardTheme.ink.opacity(0.18))
                    .frame(width: 6, height: 6)
                    .frame(width: 22, height: 18)
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
