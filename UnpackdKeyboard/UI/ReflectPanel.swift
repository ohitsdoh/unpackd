//
//  ReflectPanel.swift
//  UnpackdKeyboard
//

import SwiftUI

struct ReflectPanel: View {

    @Bindable var session: ReflectSession
    let onApplyRewrite: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(KeyboardTheme.panelBackground)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 5)
        )
        .overlay(
            // A literal white hairline read as a bright halo on the dark
            // panel; `border` is the adaptive equivalent.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(KeyboardTheme.border, lineWidth: 0.75)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KeyboardTheme.mutedInk)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KeyboardTheme.ink)

            Spacer()

            Button {
                session.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KeyboardTheme.mutedInk)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var title: String {
        switch session.phase {
        case .idle, .choosing, .unavailable: "What do you need?"
        case .breathing: "Breathe"
        case .thinking: "Finding clearer words"
        case .reviewing: "Choose your rewrite"
        }
    }

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

    private var chooser: some View {
        HStack(spacing: 10) {
            action(
                "Breathe",
                subtitle: "One guided breath",
                icon: "wind",
                tint: Color(red: 0.345, green: 0.455, blue: 0.804)
            ) {
                session.breathe()
            }

            action(
                "Rewrite",
                subtitle: "Say it clearer",
                icon: "pencil.line",
                tint: Color(red: 0.596, green: 0.408, blue: 0.682),
                isPrimary: true
            ) {
                session.rewrite()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func action(
        _ label: String,
        subtitle: String,
        icon: String,
        tint: Color,
        isPrimary: Bool = false,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(isPrimary ? .white.opacity(0.44) : KeyboardTheme.iconDisc))

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isPrimary ? KeyboardTheme.onIris : KeyboardTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(isPrimary ? KeyboardTheme.onIrisMuted : KeyboardTheme.mutedInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isPrimary
                        ? LinearGradient(colors: KeyboardTheme.iris, startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [KeyboardTheme.cardFillTop, KeyboardTheme.cardFillBottom], startPoint: .top, endPoint: .bottom)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isPrimary ? .white.opacity(0.62) : KeyboardTheme.border, lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct BreathingView: View {
    let onDone: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                KeyboardTheme.iris[1].opacity(0.92),
                                KeyboardTheme.iris[0].opacity(0.66),
                                KeyboardTheme.iris[3].opacity(0.28),
                                .clear
                            ],
                            center: .center,
                            startRadius: 6,
                            endRadius: 76
                        )
                    )
                    .blur(radius: 1.5)
                Circle()
                    .stroke(.white.opacity(0.70), lineWidth: 1)
            }
            .frame(width: expanded ? 122 : 72, height: expanded ? 122 : 72)
            .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: expanded)

            Text(expanded ? "Breathe out" : "Breathe in")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(KeyboardTheme.mutedInk)
                .contentTransition(.opacity)

            Button(action: onDone) {
                Text("I'm ready")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KeyboardTheme.onAccent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(KeyboardTheme.accent))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .onAppear { expanded = true }
    }
}

private struct ThinkingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(KeyboardTheme.ink)
            Text("Reading what you wrote...")
                .font(.system(size: 13))
                .foregroundStyle(KeyboardTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

private struct UnavailableView: View {
    let reason: ReflectionUnavailable
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(reason.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(KeyboardTheme.ink)
            Text(reason.message)
                .font(.system(size: 13))
                .foregroundStyle(KeyboardTheme.mutedInk)
                .multilineTextAlignment(.center)
            if reason.isRetryable {
                Button("Try again", action: onRetry)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(KeyboardTheme.ink)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}
