//
//  HomeView.swift
//  Unpackd
//

import SwiftUI

struct HomeView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainAppView()
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            }
        }
        .background(UnpackdStyle.canvas)
    }
}

private struct OnboardingView: View {
    @AppStorage("keyboardSetupAcknowledged") private var keyboardSetupAcknowledged = false
    @State private var isHoldingSpace = false
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 22) {
                        // The wordmark and tagline are template images, so
                        // they take the tint below rather than shipping their
                        // own black. The tagline art already reads
                        // "CREATE ⎵ SPACE", so no text duplicate of it here.
                        VStack(alignment: .leading, spacing: 14) {
                            Image("Wordmark")
                                .renderable(height: 34)
                                .foregroundStyle(UnpackdStyle.ink)

                            Image("Tagline")
                                .renderable(height: 13)
                                .foregroundStyle(UnpackdStyle.muted)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Communication\nIntelligence.")
                                .font(Typography.display(38, .regular))
                                .lineSpacing(2)
                                .foregroundStyle(UnpackdStyle.ink)

                            Text("For the moment before you send.")
                                .font(Typography.inter(17, .regular))
                                .foregroundStyle(UnpackdStyle.muted)
                        }
                    }
                    .padding(.top, 34)

                    BrandSurface {
                        VStack(alignment: .leading, spacing: 18) {
                            SectionEyebrow("How it works")
                            Text("Hold space to create space.")
                                .font(Typography.display(25, .regular))
                            Text("Unpackd lives inside your keyboard. It gives you a pause, a breath, or a clearer draft without sending your words to a server.")
                                .font(Typography.inter(15))
                                .foregroundStyle(UnpackdStyle.muted)
                                .lineSpacing(4)
                        }
                    }

                    SetupInstructions(isAcknowledged: keyboardSetupAcknowledged) {
                        openSettings()
                    } markAdded: {
                        keyboardSetupAcknowledged.toggle()
                    }

                    BrandSurface {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionEyebrow("Try it")
                            Text("Press and hold the spacebar.")
                                .font(Typography.inter(20, .semibold))
                            KeyboardPreview(isHoldingSpace: isHoldingSpace)
                                .contentShape(Rectangle())
                                .onLongPressGesture(minimumDuration: 0.35) {
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                        isHoldingSpace = true
                                    }
                                } onPressingChanged: { pressing in
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        isHoldingSpace = pressing
                                    }
                                }
                            if isHoldingSpace {
                                Text("This is the same gesture that opens the panel in Messages, Mail, and other text fields.")
                                    .font(Typography.inter(13))
                                    .foregroundStyle(UnpackdStyle.muted)
                                    .transition(.opacity)
                            }
                        }
                    }

                    Button {
                        if keyboardSetupAcknowledged {
                            onComplete()
                        } else {
                            openSettings()
                        }
                    } label: {
                        Text(keyboardSetupAcknowledged ? "Enter Unpackd" : "Set Up Keyboard First")
                            .font(Typography.inter(16, .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(UnpackdStyle.ink)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 34)
            }
            .background(UnpackdStyle.canvas)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct MainAppView: View {
    var body: some View {
        TabView {
            InsightsView()
                .tabItem {
                    Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
                }

            PracticesView()
                .tabItem {
                    Label("Practices", systemImage: "clock")
                }

            YouView()
                .tabItem {
                    Label("You", systemImage: "person")
                }
        }
        .tint(UnpackdStyle.ink)
        .background(UnpackdStyle.canvas)
    }
}

private struct InsightsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeader(
                        title: "Insights",
                        subtitle: "Your communication, over time."
                    )

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Your week, unpackd.")
                            .font(Typography.display(30, .regular))
                            .foregroundStyle(.white)
                        Text("Once you use the keyboard, weekly patterns will appear here.")
                            .font(Typography.inter(16))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineSpacing(3)
                    }
                    .padding(26)
                    .frame(maxWidth: .infinity, minHeight: 178, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(UnpackdStyle.ink)
                    )

                    VStack(alignment: .leading, spacing: 14) {
                        SectionEyebrow("This week")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            InsightMetric(value: "0", label: "Spaces created")
                            InsightMetric(value: "0", label: "Rewrites used")
                            InsightMetric(value: "0", label: "Breaths taken")
                            InsightMetric(value: "On", label: "Private by design")
                        }
                    }

                    BrandSurface {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionEyebrow("Unpackd moments")
                            Text("No moments yet.")
                                .font(Typography.inter(19, .semibold))
                            Text("The current build does not store message history. That keeps the first version honest while the keyboard experience is being validated.")
                                .font(Typography.inter(14))
                                .foregroundStyle(UnpackdStyle.muted)
                                .lineSpacing(3)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 34)
            }
            .background(UnpackdStyle.canvas)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct PracticesView: View {
    @State private var enabledKeys = PracticeSettings.enabledKeys()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeader(
                        title: "Practices",
                        subtitle: "Small tools for the moments around communication."
                    )

                    KeyboardPreview(
                        isHoldingSpace: false,
                        highlightedKeys: enabledKeys
                    )

                    VStack(alignment: .leading, spacing: 14) {
                        SectionEyebrow("On your keyboard")
                        ForEach(PracticeKey.allCases) { practice in
                            PracticeRow(
                                practice: practice,
                                isEnabled: enabledKeys.contains(practice.rawValue)
                            ) { isEnabled in
                                PracticeSettings.setEnabled(isEnabled, for: practice)
                                enabledKeys = PracticeSettings.enabledKeys()
                            }
                        }
                    }

                    BrandSurface {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionEyebrow("Coming later")
                            RoadmapRow(key: "S", title: "Sleep", detail: "Quiet nighttime keyboard behavior")
                            Divider()
                            RoadmapRow(key: "G", title: "Ground", detail: "A sensory reset before replying")
                            Divider()
                            RoadmapRow(key: "M", title: "Remember", detail: "Bring saved words back when needed")
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 34)
            }
            .background(UnpackdStyle.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { enabledKeys = PracticeSettings.enabledKeys() }
        }
    }
}

private struct YouView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("keyboardSetupAcknowledged") private var keyboardSetupAcknowledged = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeader(
                        title: "You",
                        subtitle: "Settings for your Unpackd keyboard."
                    )

                    SetupInstructions(isAcknowledged: keyboardSetupAcknowledged) {
                        openSettings()
                    } markAdded: {
                        keyboardSetupAcknowledged.toggle()
                    }

                    AvailabilityBanner()

                    BrandSurface {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionEyebrow("Privacy")
                            SettingsLine(icon: "hand.tap", title: "Full Access for feel", detail: "Used for haptics and shared app settings.")
                            Divider()
                            SettingsLine(icon: "iphone.gen3", title: "On-device rewrite", detail: "Apple Foundation Models power rewrite when available.")
                            Divider()
                            SettingsLine(icon: "text.bubble", title: "No server transcript", detail: "This build does not send or save message content on a server.")
                        }
                    }

                    Button("Show onboarding again") {
                        hasCompletedOnboarding = false
                    }
                    .font(Typography.inter(15, .medium))
                    .foregroundStyle(UnpackdStyle.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 34)
            }
            .background(UnpackdStyle.canvas)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.display(38, .regular))
                .foregroundStyle(UnpackdStyle.ink)
            Text(subtitle)
                .font(Typography.inter(16))
                .foregroundStyle(UnpackdStyle.muted)
        }
    }
}

private struct SetupInstructions: View {
    let isAcknowledged: Bool
    let openSettings: () -> Void
    let markAdded: () -> Void

    var body: some View {
        BrandSurface {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(Typography.inter(18, .medium))
                        .foregroundStyle(UnpackdStyle.ink)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.black.opacity(0.05)))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keyboard setup")
                            .font(Typography.inter(18, .semibold))
                        Text(isAcknowledged ? "Marked as added on this device." : "Add Unpackd and enable Full Access before using the hold-space panel.")
                            .font(Typography.inter(14))
                            .foregroundStyle(UnpackdStyle.muted)
                    }

                    Spacer(minLength: 8)
                    Text(isAcknowledged ? "Added" : "Setup")
                        .font(Typography.inter(12, .semibold))
                        .foregroundStyle(isAcknowledged ? Color(red: 0.275, green: 0.557, blue: 0.333) : UnpackdStyle.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.045)))
                }

                VStack(spacing: 0) {
                    ChecklistRow(number: 1, text: "Settings > General > Keyboard")
                    Divider().padding(.leading, 38)
                    ChecklistRow(number: 2, text: "Keyboards > Add New Keyboard")
                    Divider().padding(.leading, 38)
                    ChecklistRow(number: 3, text: "Choose Unpackd")
                    Divider().padding(.leading, 38)
                    ChecklistRow(number: 4, text: "Enable Allow Full Access")
                }

                HStack(spacing: 10) {
                    Button("Open Settings", action: openSettings)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(UnpackdStyle.ink)

                    Button(isAcknowledged ? "Mark Not Added" : "I Added It", action: markAdded)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
                .font(Typography.inter(15, .semibold))
            }
        }
    }
}

private struct InsightMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(Typography.display(28, .regular))
                .foregroundStyle(UnpackdStyle.ink)
            Text(label)
                .font(Typography.inter(13))
                .foregroundStyle(UnpackdStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(UnpackdStyle.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(UnpackdStyle.border, lineWidth: 0.75)
        )
    }
}

private struct PracticeRow: View {
    let practice: PracticeKey
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    private var accent: PracticeAccent {
        UnpackdStyle.accent(for: practice.rawValue)
    }

    var body: some View {
        BrandSurface(padding: 16) {
            HStack(alignment: .center, spacing: 14) {
                KeyBadge(key: practice.rawValue, accent: accent, isActive: isEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Text(practice.title)
                        .font(Typography.inter(17, .semibold))
                    Text(practice.description)
                        .font(Typography.inter(14))
                        .foregroundStyle(UnpackdStyle.muted)
                        .lineLimit(2)
                    Text(practice.detail)
                        .font(Typography.inter(12, .medium))
                        .foregroundStyle(accent.tint)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { value in onChange(value) }
                ))
                .labelsHidden()
                .tint(accent.tint)
            }
        }
    }
}

private struct RoadmapRow: View {
    let key: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            KeyBadge(key: key, accent: UnpackdStyle.accent(for: key), isActive: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.inter(15, .semibold))
                Text(detail)
                    .font(Typography.inter(13))
                    .foregroundStyle(UnpackdStyle.muted)
            }
            Spacer()
            Text("Later")
                .font(Typography.inter(12, .medium))
                .foregroundStyle(UnpackdStyle.muted)
        }
    }
}

private struct KeyBadge: View {
    let key: String
    let accent: PracticeAccent
    let isActive: Bool

    var body: some View {
        Text(key)
            .font(Typography.inter(20, .semibold))
            .foregroundStyle(isActive ? accent.tint : accent.tint.opacity(0.48))
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isActive ? accent.background : Color.black.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isActive ? accent.glow.opacity(0.65) : Color.black.opacity(0.06), lineWidth: 0.75)
            )
            .shadow(color: isActive ? accent.glow.opacity(0.38) : .clear, radius: 12)
    }
}

private struct SettingsLine: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(Typography.inter(17, .medium))
                .foregroundStyle(UnpackdStyle.ink)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.inter(15, .semibold))
                Text(detail)
                    .font(Typography.inter(13))
                    .foregroundStyle(UnpackdStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
