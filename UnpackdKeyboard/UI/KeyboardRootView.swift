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

    /// Height of the keys plus the autocomplete toolbar above them. Measured
    /// rather than assumed, because it varies with device and orientation.
    @State private var keyboardHeight: CGFloat = 0
    @State private var panelHeight: CGFloat = 0

    var body: some View {
        // ZStack, not a plain VStack: the wash has to draw over the panel *and*
        // the keys to reach the keyboard's edges. As a transition on the panel
        // it could only ever mask the panel's own bounds. See RadialWash.
        ZStack {
            VStack(spacing: 0) {
                if session.isOpen {
                    ReflectPanel(session: session, onApplyRewrite: onApplyRewrite)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height }
                            action: { panelHeight = $0 }
                        // Just a fade. The panel arriving is the *result* of the
                        // wash passing over it, not a second animation competing
                        // with it, so it gets no movement of its own.
                        .transition(.opacity)
                }

                keyboardView()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height }
                        action: { keyboardHeight = $0 }
            }

            // Spans the whole stack, so the circle sweeps across the keys on
            // its way to the corners.
            RadialWash(progress: session.isOpen ? 1 : 0)
        }
        // Slow and linear-ish rather than eased. `easeOut` front-loads the
        // motion, which is exactly what made the old version read as a snap;
        // this is meant to be watched expanding. Not a spring either — an
        // expanding circle that overshoots reads as a wobble.
        .animation(.easeInOut(duration: 0.6), value: session.isOpen)
        // Height keeps its own faster spring: this drives the keyboard frame
        // growing, and a little softness there is what stops the host app's
        // content from snapping upward. Deliberately quicker than the wash, so
        // the panel has settled into place by the time the circle reaches it.
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: panelHeight)
        .onChange(of: keyboardHeight + (session.isOpen ? panelHeight : 0)) { _, total in
            guard total > 0 else { return }
            onHeightChange(total)
        }
    }
}

// Height is measured with `onGeometryChange` rather than a PreferenceKey.
// Under Swift 6, `onPreferenceChange` takes a `@Sendable` closure, so the old
// helper could not capture a non-Sendable `(CGFloat) -> Void` callback without
// a concurrency error. `onGeometryChange` is also a single pass rather than a
// preference walk, which matters inside a 60MB extension.
