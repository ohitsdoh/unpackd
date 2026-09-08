//
//  AvailabilityBanner.swift
//  Unpackd
//

import SwiftUI
import FoundationModels

struct AvailabilityBanner: View {
    private var intelligence: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    var body: some View {
        BrandSurface {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(Typography.inter(18, .medium))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(Typography.inter(16, .semibold))
                    Text(message)
                        .font(Typography.inter(14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var icon: String {
        switch intelligence {
        case .available: "checkmark.circle.fill"
        case .unavailable(.appleIntelligenceNotEnabled): "gear"
        case .unavailable(.modelNotReady): "arrow.down.circle"
        case .unavailable: "exclamationmark.circle"
        }
    }

    private var tint: Color {
        switch intelligence {
        case .available: .green
        case .unavailable(.modelNotReady): .blue
        case .unavailable: .orange
        }
    }

    private var title: String {
        switch intelligence {
        case .available:
            "Rewrite is ready"
        case .unavailable(.deviceNotEligible):
            "Rewrite is unavailable on this iPhone"
        case .unavailable(.appleIntelligenceNotEnabled):
            "Apple Intelligence is off"
        case .unavailable(.modelNotReady):
            "Rewrite model is downloading"
        case .unavailable:
            "Rewrite is unavailable"
        }
    }

    private var message: String {
        switch intelligence {
        case .available:
            "Rewrite runs on-device."
        case .unavailable(.deviceNotEligible):
            "The keyboard and breathing tool still work."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Turn it on in Settings to enable rewrite."
        case .unavailable(.modelNotReady):
            "Try again after the on-device model finishes downloading."
        case .unavailable:
            "You can still use the keyboard without rewrite."
        }
    }
}
