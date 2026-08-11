//
//  KeyboardRootView.swift
//  UnpackdKeyboard
//

import SwiftUI

/// Composes the reflect panel above the keyboard and reports the total height
/// the extension needs so the controller can grow its frame.
struct KeyboardRootView<KeyboardView: View>: View {

    /// Owned by the controller, not by this view. `@State` would capture the
    /// first instance and silently ignore later ones; plain `let` is correct
    /// because @Observable tracks reads inside `body` regardless of ownership.
    let session: ReflectSession
    let onHeightChange: (CGFloat) -> Void
    let onApplyRewrite: (String) -> Void
    @ViewBuilder let keyboardView: () -> KeyboardView

    /// Height of the keys themselves. Measured rather than assumed, because it
    /// varies with device, orientation and whether an input toolbar is shown.
    @State private var keyboardHeight: CGFloat = 0
    @State private var panelHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if session.isOpen {
                ReflectPanel(session: session, onApplyRewrite: onApplyRewrite)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height }
                        action: { panelHeight = $0 }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            keyboardView()
                .onGeometryChange(for: CGFloat.self) { $0.size.height }
                    action: { keyboardHeight = $0 }
                // The soft white glow under the keys from the mockups.
                .overlay(alignment: .bottom) {
                    if session.isOpen {
                        SpaceGlow().allowsHitTesting(false)
                    }
                }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: session.isOpen)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: panelHeight)
        .onChange(of: keyboardHeight + (session.isOpen ? panelHeight : 0)) { _, total in
            guard total > 0 else { return }
            onHeightChange(total)
        }
    }
}

/// The diffuse light that blooms from the spacebar while a reflection is open.
private struct SpaceGlow: View {
    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [.white.opacity(0.9), .white.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 120
                )
            )
            .frame(height: 120)
            .blur(radius: 18)
            .padding(.bottom, 24)
    }
}

// Height is measured with `onGeometryChange` rather than a PreferenceKey.
// Under Swift 6, `onPreferenceChange` takes a `@Sendable` closure, so the old
// helper could not capture a non-Sendable `(CGFloat) -> Void` callback without
// a concurrency error. `onGeometryChange` is also a single pass rather than a
// preference walk, which matters inside a 60MB extension.
