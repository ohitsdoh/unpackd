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
final class HoldSpaceActionHandler: StandardKeyboardActionHandler {

    /// Which gesture/key combination opens the reflect panel.
    ///
    /// Data rather than an overridden method body, so moving the feature off
    /// the spacebar doesn't mean writing a second handler subclass and
    /// relearning KeyboardKit's swallow/`super` semantics.
    var trigger: (Keyboard.Gesture, KeyboardAction) -> Bool = { gesture, action in
        gesture == .longPress && action == .space
    }

    /// The rest of the gesture sequence that `trigger` starts, and which must
    /// be swallowed rather than handled normally.
    ///
    /// WHY THIS IS NEEDED
    /// `longPress` and `release` are separate gestures, and KeyboardKit sends
    /// *both* for one physical press-and-hold. Swallowing only `longPress`
    /// therefore still let the `release` through, and `.space`'s standard
    /// release action inserts a space — so opening the panel typed a space
    /// into the user's draft every time.
    ///
    /// WHY IT IS DATA, LIKE `trigger`
    /// A trigger and its tail are one fact about a gesture, so they are stated
    /// the same way. Hard-coding `.release` here would quietly break the
    /// promise `trigger` makes: rebinding the feature to a different gesture
    /// would also need this method's body edited, which is exactly the
    /// relearning `trigger` exists to avoid. `.end` is included because it is
    /// in the `Gesture` enum, but `.release` is the one observed for the
    /// spacebar — matching either means the latch cannot stick open and
    /// swallow a subsequent real space.
    var triggerTail: (Keyboard.Gesture) -> Bool = { gesture in
        gesture == .release || gesture == .end
    }

    /// Called when the trigger fires.
    var onTrigger: (() -> Void)?

    /// Set when `trigger` fires, cleared by the first matching `triggerTail`.
    private var didTriggerOnCurrentPress = false

    override func handle(
        _ gesture: Keyboard.Gesture,
        on action: KeyboardAction,
        replaced: Bool
    ) {
        if trigger(gesture, action) {
            didTriggerOnCurrentPress = true

            // The capture gets its own heavier haptic rather than the standard
            // key feedback. This is the "hold to act" moment — it has to feel
            // categorically different from typing a space, or the gesture
            // reads as a key that stuck. Held space that does nothing for
            // 300ms otherwise reads as a dropped key.
            //
            // Inert unless the user granted Full Access: UIFeedbackGenerator
            // does nothing in an extension without it (RequestsOpenAccess is
            // true in Info.plist, but the user still has to allow it in
            // Settings). The visual glow carries the moment regardless, so
            // the capture is never entirely unannounced.
            triggerHapticFeedback(.mediumImpact)
            onTrigger?()
            return  // Deliberately no `super` — this swallows cursor drag
                    // (tryUpdateSpaceDragState) and the locale menu.
        }

        // Swallow the tail of the gesture that opened the panel — the release
        // is the one that would insert the space.
        //
        // Whichever of these arrives first clears the latch. `.end` exists in
        // the Gesture enum but its rawValue is absent from the shipped
        // binary's strings, so it may never be emitted for the spacebar;
        // `.release` is the one we know arrives. Clearing on either means the
        // latch cannot stick open and swallow a subsequent real space.
        if didTriggerOnCurrentPress, gesture == .release || gesture == .end {
            didTriggerOnCurrentPress = false
            return
        }

        super.handle(gesture, on: action, replaced: replaced)
    }
}
