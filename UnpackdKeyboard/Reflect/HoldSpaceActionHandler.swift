//
//  HoldSpaceActionHandler.swift
//  UnpackdKeyboard
//
//  Claims the space long-press for "create space".
//

import Foundation
import KeyboardKit

/// Intercepts long-press on the space key and opens the reflect panel
/// instead of performing KeyboardKit's default behaviour.
///
/// WHAT WE ARE TAKING FROM THE USER
/// Hold-space natively means "move the cursor", and that muscle memory is
/// strong and old. Two things make the override defensible:
///   1. `spaceLongPressBehavior` is set to `.openLocaleContextMenu` in the
///      controller, which is what actually disables cursor drag — see
///      `isSpaceCursorDragEnabled` in KeyboardKit. We then swallow the
///      long-press before any locale menu appears.
///   2. The glow + haptic fire at the moment of capture, so the gesture
///      announces that it is doing something different.
///
/// If user testing says the cursor loss hurts, rebinding is a one-line change
/// at the call site: assign a different `trigger`. `ReflectSession` never knew
/// what opened it.
final class HoldSpaceActionHandler: KeyboardAction.StandardActionHandler {

    /// Which gesture/key combination opens the reflect panel.
    ///
    /// Data rather than an overridden method body, so moving the feature off
    /// the spacebar doesn't mean writing a second handler subclass and
    /// relearning KeyboardKit's swallow/`super` semantics.
    var trigger: (Keyboard.Gesture, KeyboardAction) -> Bool = { gesture, action in
        gesture == .longPress && action == .space
    }

    /// Called when the trigger fires.
    var onTrigger: (() -> Void)?

    override func handle(
        _ gesture: Keyboard.Gesture,
        on action: KeyboardAction,
        replaced: Bool
    ) {
        if trigger(gesture, action) {
            // Feedback still fires: the user must feel the capture, otherwise
            // a held space that does nothing for 300ms reads as a dropped key.
            triggerFeedback(for: gesture, on: action)
            onTrigger?()
            return  // Deliberately no `super` — this swallows cursor drag
                    // (tryUpdateSpaceDragState) and the locale menu.
        }
        super.handle(gesture, on: action, replaced: replaced)
    }
}
