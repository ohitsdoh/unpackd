//
//  DesignSystem.swift
//  Unpackd
//

import SwiftUI

enum UnpackdStyle {
    static let canvas = Color(red: 0.976, green: 0.976, blue: 0.969)
    static let paper = Color.white
    static let ink = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let muted = Color(red: 0.541, green: 0.541, blue: 0.510)
    static let border = Color(red: 0.890, green: 0.890, blue: 0.870)
    static let keyboardBackground = Color(red: 0.804, green: 0.820, blue: 0.839)
    static let specialKey = Color(red: 0.678, green: 0.710, blue: 0.753)

    static let iris = [
        Color(red: 0.855, green: 0.824, blue: 1.000),
        Color(red: 0.765, green: 0.886, blue: 1.000),
        Color(red: 0.961, green: 0.878, blue: 1.000),
        Color(red: 1.000, green: 0.824, blue: 0.925),
        Color(red: 1.000, green: 0.894, blue: 0.792)
    ]

    static func accent(for key: String) -> PracticeAccent {
        switch key.uppercased() {
        case "B":
            PracticeAccent(
                tint: Color(red: 0.345, green: 0.455, blue: 0.804),
                glow: Color(red: 0.753, green: 0.808, blue: 1.000),
                background: Color(red: 0.675, green: 0.745, blue: 1.000).opacity(0.13)
            )
        case "R":
            PracticeAccent(
                tint: Color(red: 0.596, green: 0.408, blue: 0.682),
                glow: Color(red: 0.925, green: 0.808, blue: 0.980),
                background: Color(red: 0.863, green: 0.737, blue: 0.941).opacity(0.14)
            )
        default:
            PracticeAccent(
                tint: Color(red: 0.298, green: 0.557, blue: 0.392),
                glow: Color(red: 0.698, green: 0.871, blue: 0.761),
                background: Color(red: 0.620, green: 0.824, blue: 0.686).opacity(0.13)
            )
        }
    }
}

struct PracticeAccent {
    let tint: Color
    let glow: Color
    let background: Color
}

extension Image {
    /// Scale brand art to a fixed height, keeping its aspect ratio and
    /// letting `foregroundStyle` tint it. The catalog marks these assets as
    /// template-rendered, but `.renderingMode` is set here too so the helper
    /// works regardless of how a given asset was configured.
    func renderable(height: CGFloat) -> some View {
        self
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(height: height)
    }
}

struct BrandSpacebar: View {
    var isPressed = false
    var height: CGFloat = 54
    var cornerRadius: CGFloat = 14

    var body: some View {
        HStack {
            // The real spacebar mark, replacing the "sparkles" placeholder.
            Image("SpacebarMark")
                .renderable(height: height * 0.30)
                .opacity(isPressed ? 0.54 : 0.34)
            Spacer()
            Image("Wordmark")
                .renderable(height: height * 0.20)
                .opacity(isPressed ? 0.48 : 0.32)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, height * 0.30)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: UnpackdStyle.iris,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    LinearGradient(
                        colors: [.white.opacity(0.58), .white.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.70), lineWidth: 1)
        )
        .scaleEffect(y: isPressed ? 0.955 : 1, anchor: .bottom)
        .shadow(color: Color(red: 0.765, green: 0.706, blue: 1.0).opacity(isPressed ? 0.34 : 0.14), radius: isPressed ? 22 : 10, y: isPressed ? 8 : 3)
    }
}

struct BrandSurface<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(UnpackdStyle.paper)
                    .shadow(color: .black.opacity(0.035), radius: 12, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(UnpackdStyle.border, lineWidth: 0.75)
            )
    }
}

struct SectionEyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(Typography.inter(11, .semibold))
            .tracking(1.6)
            .foregroundStyle(UnpackdStyle.muted)
    }
}

/// Swipe-left-to-delete for a row inside a `BrandSurface` card.
///
/// WHY THIS IS HAND-ROLLED
/// `.swipeActions` requires a `List`, and these rows live in cards inside the
/// page's own `ScrollView` — nesting a `List` there would fight the page for
/// scrolling. So the gesture is ours.
///
/// WHY IT IS A MODIFIER RATHER THAN A COPY PER ROW
/// Both saved-item lists in the app (moments and remembered thoughts) need the
/// same affordance. Written twice, the thresholds and the reveal width drift,
/// and only one of them gets the next fix — the single-open-row rule, say, or
/// VoiceOver actions, neither of which a hand-rolled swipe gets for free.
///
/// The row keeps its own accessibility route to deletion: a swipe is invisible
/// to VoiceOver, so `deleteLabel` is also exposed as a custom action.
struct SwipeToDelete: ViewModifier {
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0

    /// How far left the row sits when the action is showing.
    private let revealed: CGFloat = -76

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(UnpackdStyle.paper)
                    .frame(width: 60, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.red)
                    )
            }
            .buttonStyle(.plain)
            .opacity(offset < -12 ? 1 : 0)
            .accessibilityHidden(true)

            content
                .background(UnpackdStyle.paper)
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { value in
                            // Left only, and never past the action's width — a
                            // row that can be flung off-screen reads as a bug
                            // rather than an affordance.
                            offset = max(revealed, min(0, value.translation.width))
                        }
                        .onEnded { value in
                            withAnimation(.snappy(duration: 0.22)) {
                                offset = value.translation.width < revealed / 2 ? revealed : 0
                            }
                        }
                )
                // The swipe itself is unreachable without sight of it.
                .accessibilityAction(named: "Delete", onDelete)
        }
    }
}

extension View {
    /// See `SwipeToDelete`.
    func swipeToDelete(perform onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(onDelete: onDelete))
    }
}
