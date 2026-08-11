//
//  ReflectPanel.swift
//  UnpackdKeyboard
//
//  The card that appears above the keys when the user holds space.
//

import SwiftUI

struct ReflectPanel: View {

    /// `@Bindable`, not `@State`: the session is owned by the controller, and
    /// this view needs to derive `$session.selectedRewrite` for the pager.
    @Bindable var session: ReflectSession
    let onApplyRewrite: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            Spacer()
            Text(title)
                .font(.system(size: 15, weight: .medium))
            Spacer()
            Button {
                session.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var title: String {
        switch session.phase {
        case .idle, .choosing, .unavailable: "Take a moment to reflect"
        case .breathing: "Breathe"
        case .thinking: "Finding the words"
        case .reviewing: "Rewrite with clarity"
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .idle:
            EmptyView()
        case .choosing:
            chooser
        case .breathing:
            BreathingView { session.dismiss() }
        case .thinking:
            ThinkingView()
        case .reviewing(let reflection):
            RewriteView(
                original: session.draft,
                reflection: reflection,
                selection: $session.selectedRewrite,
                onUse: onApplyRewrite
            )
        case .unavailable(let reason):
            UnavailableView(reason: reason) { session.rewrite() }
        }
    }

    // MARK: Chooser

    private var chooser: some View {
        VStack(spacing: 20) {
            // Emotion chips are a self-report, not a diagnosis — the model's
            // own guess is shown only after a rewrite, so the keyboard never
            // tells the user how they feel before they've said anything.
            //
            // Tapping one is optional and steers the rewrite (see
            // ReflectSession.selfReportedEmotion). Tapping the selected chip
            // again clears it.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Emotion.allCases) { emotion in
                        let isSelected = session.selfReportedEmotion == emotion
                        Button {
                            session.selfReportedEmotion = isSelected ? nil : emotion
                        } label: {
                            Pill(
                                emotion.label,
                                size: .chip,
                                fill: isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                                stroked: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 2)
            }

            HStack(spacing: 0) {
                action("Breathe", icon: "wind", tint: .blue) { session.breathe() }
                action("Reflect", icon: "circle.circle", tint: .indigo) { session.breathe() }
                action("Rewrite", icon: "pencil.line", tint: .orange) { session.rewrite() }
                action("Save for later", icon: "bookmark", tint: .gray) { session.dismiss() }
            }
        }
    }

    private func action(
        _ label: String,
        icon: String,
        tint: Color,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(tint)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(tint.opacity(0.12)))
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Breathing

/// A paced breath. Four seconds in, four out — slow enough that following it
/// actually settles the user, which is the entire point of the feature.
private struct BreathingView: View {
    let onDone: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 18) {
            Circle()
                .fill(.tint.opacity(0.15))
                .overlay(Circle().stroke(.tint.opacity(0.35), lineWidth: 1))
                .frame(width: expanded ? 120 : 68, height: expanded ? 120 : 68)
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: expanded)
            Text(expanded ? "Breathe out" : "Breathe in")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
            Button("I'm ready", action: onDone)
                .font(.system(size: 14, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onAppear { expanded = true }
    }
}

// MARK: - Thinking

private struct ThinkingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Reading what you wrote…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

// MARK: - Unavailable

private struct UnavailableView: View {
    let reason: ReflectionUnavailable
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(reason.title)
                .font(.system(size: 15, weight: .medium))
            Text(reason.message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if reason.isRetryable {
                Button("Try again", action: onRetry)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}
