//
//  UnpackdApp.swift
//  Unpackd
//
//  The container app. Its only real job is onboarding: a keyboard extension
//  is useless until the user installs it in Settings, and that flow is
//  where most custom keyboards lose people.
//

import SwiftUI
import FoundationModels

@main
struct UnpackdApp: App {
    var body: some Scene {
        WindowGroup {
            SetupView()
        }
    }
}

struct SetupView: View {

    private var intelligence: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hold space.\nCreate space.")
                            .font(.system(size: 30, weight: .semibold))
                        Text("Press and hold the spacebar to pause before you send. A moment of reflection, on your device.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("Set up") {
                    step(1, "Open Settings › General › Keyboard › Keyboards")
                    step(2, "Tap Add New Keyboard and choose Unpackd")
                    // No "Allow Full Access" step: everything runs on-device,
                    // so we never ask for it.
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("Rewrite") {
                    switch intelligence {
                    case .available:
                        Label("Ready — runs entirely on this iPhone", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .unavailable(.deviceNotEligible):
                        Label("This iPhone can't run on-device rewrite. Breathe and Reflect still work.", systemImage: "exclamationmark.circle")
                    case .unavailable(.appleIntelligenceNotEnabled):
                        Label("Turn on Apple Intelligence in Settings to enable rewrite.", systemImage: "gear")
                    case .unavailable(.modelNotReady):
                        Label("The on-device model is still downloading.", systemImage: "arrow.down.circle")
                    case .unavailable:
                        Label("Rewrite is unavailable on this device.", systemImage: "exclamationmark.circle")
                    }
                }

                Section {
                    Text("Nothing you type is ever sent anywhere. The rewrite runs on your iPhone, and Unpackd requires no network access at all.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Unpackd")
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.quaternary))
            Text(text)
        }
    }
}
