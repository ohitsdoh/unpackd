//
//  HoldSpaceActionHandler.swift
//  UnpackdKeyboard
//
//  Claims the space long-press for "create space".
//

import Foundation
import KeyboardKit
import QuartzCore

enum KeyboardPracticeAction {
    case breathe
    /// Hold R — show one of the user's own saved thoughts.
    ///
    /// R USED TO MEAN REWRITE, AND DELIBERATELY NO LONGER DOES.
    /// Rewrite was reachable two ways: this key, and the "Rewrite" secondary
    /// action on the hold-space panel. Only the shortcut was dropped — the
    /// panel route is untouched, and is where the design puts Rewrite anyway
    /// (it is reached from the Create Space menu). That frees R for Remember,
    /// which the design brief assigns to it and which has no other entry
    /// point at all.
    case remember
}

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

    var practiceTrigger: (Keyboard.Gesture, KeyboardAction) -> KeyboardPracticeAction? = { gesture, action in
        guard gesture == .longPress else { return nil }
        guard case .character(let value) = action else { return nil }

        switch value.uppercased() {
        case "B" where KeyboardPracticeSettings.isEnabled("B"):
            return .breathe
        case "R" where KeyboardPracticeSettings.isEnabled("R"):
            return .remember
        default:
            return nil
        }
    }

    /// Which gesture/key begins the *ramp* that `trigger` eventually completes.
    ///
    /// WHY A SECOND PREDICATE
    /// KeyboardKit only tells us about discrete gestures — there is no
    /// "still holding, 300ms in" callback. But stages 03 and 04 of the design
    /// need continuous feedback while the finger is down and before anything
    /// has been committed to, so the ramp is timed locally: `.press` starts a
    /// display link, `.release` cancels it. Kept as data for the same reason
    /// as `trigger` — rebinding the feature moves both together.
    var rampTrigger: (Keyboard.Gesture, KeyboardAction) -> Bool = { gesture, action in
        gesture == .press && action == .space
    }

    /// Called when the trigger fires.
    var onTrigger: (() -> Void)?
    var onPracticeTrigger: ((KeyboardPracticeAction) -> Void)?

    /// Called every frame while the finger is down, with 0...1 progress toward
    /// the open. Returns the stage newly entered, if any, so we can haptic it.
    var onHoldProgress: ((Double) -> ReflectSession.HoldStage?)?

    /// Called when the finger lifts before the gesture completed.
    var onHoldCancelled: (() -> Void)?

    /// Called after a gesture that may have changed the document text.
    ///
    /// WHY THIS EXISTS — AND WHY IT IS A TRIGGER, NOT A FILTER
    /// `textDidChange`/`textDidChangeAsync` only fire when the HOST app
    /// notifies the input system. When this keyboard inserts a character
    /// through `textDocumentProxy`, the host frequently does not round-trip a
    /// notification back to us: the keyboard changed the text, so UIKit sees
    /// no reason to tell the keyboard about it. Measured on device — 39
    /// characters typed produced ZERO `textDidChange` calls, and the only
    /// callback in the whole session arrived when the user tapped elsewhere,
    /// 5.5 seconds later. That is why the nudge appeared to require "clicking
    /// off": the tap was the only event that ever reached the controller.
    ///
    /// An earlier version of this file had the same callback and used it the
    /// other way round — as evidence that a *received* `textDidChange` was a
    /// real edit. That solved the wrong half of the problem: the events it
    /// filtered were the only ones arriving at all. Here it DRIVES the check,
    /// so typing is what schedules detection and the host's notifications are
    /// merely a supplement.
    ///
    /// Fired on `.release`/`.end` rather than `.press`, because `super.handle`
    /// is what performs the insert — the proxy has not been updated yet at
    /// press time.
    var onTextMayHaveChanged: (() -> Void)?

    /// Set when `trigger` fires, cleared by the release that ends that press.
    private var didTriggerOnCurrentPress = false

    /// Drives the 0...1 ramp between `.press` and the long-press.
    ///
    /// A CADisplayLink rather than a Timer: this animates the spacebar every
    /// frame, and a Timer's default tolerance produces visible stutter in the
    /// ripple. It is invalidated on release, so it never runs while idle —
    /// a display link left spinning in a keyboard extension is a battery and
    /// footprint problem, not just an aesthetic one.
    private var rampLink: CADisplayLink?
    private var rampStart: CFTimeInterval = 0

    /// Weak indirection between the run loop and this handler.
    ///
    /// `CADisplayLink` retains its target, and an added link is retained by the
    /// run loop — so `CADisplayLink(target: self, ...)` builds
    /// `runloop -> link -> handler` and this object cannot deallocate while a
    /// ramp is live. `deinit` would then be unreachable for precisely the
    /// window it exists to cover: a teardown mid-hold, when the user swaps
    /// keyboards or the host dismisses the field with a finger still down.
    /// A leaked handler drags the controller, services and autocomplete
    /// service with it, which a 60MB-capped extension cannot afford.
    private final class RampProxy {
        weak var owner: HoldSpaceActionHandler?

        @objc func step() {
            owner?.stepRamp()
        }
    }

    override func handle(
        _ gesture: Keyboard.Gesture,
        on action: KeyboardAction,
        replaced: Bool
    ) {
        if rampTrigger(gesture, action) {
            startRamp()
            // Deliberately falls through to `super`: `.press` still needs its
            // standard handling (press feedback, state bookkeeping). We are
            // only observing it, not claiming it.
        }

        if trigger(gesture, action) {
            didTriggerOnCurrentPress = true
            // The ramp has arrived; hand the visuals a clean 1.0 rather than
            // whatever fraction the last frame happened to land on, so the
            // spacebar is at full iridescence in the frame the panel opens.
            stopRamp(completing: true)

            // No haptic here: the ramp's `.activate` stage already fired the
            // medium impact at the moment the gesture was confirmed, which is
            // a frame or two earlier and matches the design's "04 ACTIVATE"
            // beat. Firing again here reads as a stutter.
            onTrigger?()
            return  // Deliberately no `super` — this swallows cursor drag
                    // (tryUpdateSpaceDragState) and the locale menu.
        }

        if let practiceAction = practiceTrigger(gesture, action) {
            didTriggerOnCurrentPress = true
            triggerHapticFeedback(.mediumImpact)
            onPracticeTrigger?(practiceAction)
            return
        }

        // The end of a press, whichever way it went.
        //
        // `.end` exists in the Gesture enum but its rawValue is absent from the
        // shipped binary's strings, so it may never be emitted for the
        // spacebar; `.release` is the one we know arrives. Matching either
        // means the latch cannot stick open and swallow a subsequent real
        // space.
        if gesture == .release || gesture == .end {
            if didTriggerOnCurrentPress {
                // Swallow the tail of the gesture that opened the panel — this
                // release is the one that would otherwise insert a space.
                didTriggerOnCurrentPress = false
                return
            }
            // A release that did NOT follow a completed trigger is an abandoned
            // hold: pressed, held partway, let go. The ramp has to be wound
            // back or the spacebar stays part-lit forever. Before `super`, so
            // the visual reset lands in the same frame as the inserted space.
            stopRamp(completing: false)
        }

        super.handle(gesture, on: action, replaced: replaced)

        // AFTER `super`, which is what actually performs the insert or delete.
        // Reading the proxy before this point returns the pre-edit text, which
        // is the staleness that made an earlier attempt classify every
        // keystroke against the draft as it was one character ago.
        if gesture == .release || gesture == .end, mutatesText(action) {
            onTextMayHaveChanged?()
        }
    }

    /// Applying an autocomplete suggestion replaces a word, so it changes the
    /// draft as surely as a keystroke does — and it arrives through a separate
    /// overload that the gesture path above never sees. Without this, tapping
    /// a suggestion leaves the heat check running on the pre-correction text.
    override func handle(_ suggestion: AutocompleteSuggestion) {
        super.handle(suggestion)
        onTextMayHaveChanged?()
    }

    /// Whether performing this action changes the document text.
    ///
    /// Cases verified against KeyboardKit's `.swiftinterface` rather than
    /// written from memory. The distinction that matters: `moveCursorBackward`
    /// / `moveCursorForward` are real actions that change the cursor while
    /// editing nothing, so they are excluded — a caret move must not schedule
    /// a heat check. Everything not listed (shift, keyboardType, nextKeyboard,
    /// settings, dictation, …) leaves the text alone.
    private func mutatesText(_ action: KeyboardAction) -> Bool {
        switch action {
        case .character, .characterMargin, .diacritic, .emoji,
             .space, .backspace, .primary, .pasteFromClipboard:
            true
        default:
            false
        }
    }

    // MARK: - Hold ramp

    private func startRamp() {
        stopRamp(completing: false)
        rampStart = CACurrentMediaTime()
        let proxy = RampProxy()
        proxy.owner = self
        let link = CADisplayLink(target: proxy, selector: #selector(RampProxy.step))
        // .common so the ramp keeps running during the scroll/tracking run
        // loop mode a host app may push while the finger is down.
        link.add(to: .main, forMode: .common)
        rampLink = link
    }

    fileprivate func stepRamp() {
        let elapsed = CACurrentMediaTime() - rampStart
        let progress = elapsed / HoldTiming.holdDuration
        guard let stage = onHoldProgress?(progress) else { return }

        // One haptic per stage, weighted to match the design: 03 is "keep
        // holding" (light), 04 is "space created" (a firmer, more resolved
        // acknowledgement). The `.mediumImpact` that used to fire on trigger
        // is now this `.activate` beat — firing both would double-tap.
        switch stage {
        case .threshold: triggerHapticFeedback(.lightImpact)
        case .activate: triggerHapticFeedback(.mediumImpact)
        case .none: break
        }
    }

    private func stopRamp(completing: Bool) {
        rampLink?.invalidate()
        rampLink = nil
        if !completing { onHoldCancelled?() }
    }

    deinit {
        rampLink?.invalidate()
    }
}
