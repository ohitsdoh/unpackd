//
//  KeyboardViewController.swift
//  UnpackdKeyboard
//

import KeyboardKit
import QuartzCore
import SwiftUI
import UIKit

class KeyboardViewController: KeyboardInputViewController {

    /// The reflection engine. Swap for `StubReflectionEngine()` to develop the
    /// panel in the simulator — Foundation Models does not run there.
    private let engine: ReflectionEngine = FoundationModelsRewriter()

    private var session: ReflectSession!
    private var heightConstraint: NSLayoutConstraint?

    /// Decides when the spacebar should quietly come to life.
    private let heatDetector = HeatDetector()

    /// The draft the detector last ran on, so it does not run again on an
    /// event that did not change the text.
    ///
    /// WHY THIS EXISTS
    /// `textDidChange` is called for far more than typing: moving the cursor,
    /// changing the selection, and gaining or losing focus all fire it. The
    /// draft string is identical across every one of those — `currentDraft()`
    /// is `before + after`, and a cursor tap only moves the boundary between
    /// them — but without this the classifier still re-ran and `setPresence`
    /// still saw a change, because presence had been reset to `.rest` in the
    /// meantime. The visible symptom was the nudge firing when the user
    /// tapped somewhere in the field rather than when they typed.
    ///
    /// `nil` rather than `""` so the first check after launch always runs;
    /// an empty field is a legitimate draft value, not "not yet read".
    private var lastCheckedDraft: String?


    // MARK: - Lifecycle

    override func viewDidLoad() {
        // setupKeyboardKit(for:) builds `state` and `services`, so it has to
        // come before we replace the action handler or touch settings.
        setupKeyboardKit(for: .unpackd)

        session = ReflectSession(engine: engine)

        // Disables KeyboardKit's space cursor drag (see isSpaceCursorDragEnabled).
        // Our action handler swallows the long-press before the locale menu can
        // appear; the nil menus below make sure nothing else claims the key.
        state.keyboardContext.settings.spacebarLongPressBehavior = .openLocaleContextMenu
        state.keyboardContext.settings.spacebarMenuLeading = KeyboardKit.Keyboard.SpacebarMenuType.none
        state.keyboardContext.settings.spacebarMenuTrailing = KeyboardKit.Keyboard.SpacebarMenuType.none

        // Autocomplete has to be installed before the action handler, because
        // StandardKeyboardActionHandler captures `autocompleteService` at init.
        // Assigning it afterwards leaves the handler holding the disabled one.
        services.autocompleteService = TextCheckerAutocompleteService(
            locale: state.keyboardContext.locale
        )

        // Autocorrect is opt-in per keyboard, and defaults off in a fresh
        // install. The pipeline in StandardKeyboardActionHandler checks these
        // before it will apply anything, so without them the service runs and
        // its suggestions are silently discarded.
        state.autocompleteContext.settings.isAutocompleteEnabled = true
        state.autocompleteContext.settings.isAutocorrectEnabled = true

        // Smart punctuation (`--` -> em dash) is NOT registered here.
        // `autocompleteContext.autocorrectDictionary` is only read by
        // KeyboardKit's Pro-gated StandardAutocompleteService, which we cannot
        // construct — so replacements written there are stored and never
        // consulted. It lives in TextCheckerAutocompleteService instead, which
        // is the code path this target actually owns.

        // Haptics default to OFF in KeyboardKit, and this flag is what makes
        // the feedback engine available at all.
        //
        // Enabling it does NOT mean every key buzzes. The per-gesture haptics
        // are a separate, declarative layer, and every gesture is set to
        // `.none` below — so ordinary typing feels exactly like the native
        // keyboard, which is silent to the touch unless the user opts in.
        //
        // Stating it as configuration rather than by overriding
        // `shouldTriggerHapticFeedback` matters: the policy lives in one place
        // next to the flag it qualifies, instead of being split across two
        // files where reading either alone is misleading. It also leaves
        // KeyboardKit's own pipeline usable — a future per-key haptic is
        // `registerCustomHapticFeedback(_:for:on:)`, not another bypass.
        //
        // Unpackd's own moments are not gestures: the hold's two beats come
        // from a display-link tick and the quiet nudge from a debounced text
        // change. They call `triggerHapticFeedback` directly because there is
        // no gesture for them to hang off. The visual state carries them when
        // haptics are unavailable in this extension context, so nothing is
        // announced by touch alone.
        state.feedbackContext.settings.isHapticFeedbackEnabled = true
        state.feedbackContext.hapticConfiguration = .init(
            press: .none,
            release: .none,
            doubleTap: .none,
            longPress: .none,
            repeat: .none
        )

        let handler = HoldSpaceActionHandler(controller: self)
        handler.onTrigger = { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.beginReflection() }
        }
        handler.onPracticeTrigger = { [weak self] practice in
            guard let self else { return }
            Task { @MainActor in self.beginPractice(practice) }
        }
        // Called from the display link, which runs on the main thread, so the
        // MainActor state is touched synchronously rather than hopped onto —
        // a Task per frame would both arrive late and allocate 60 times a
        // second inside a footprint-constrained extension.
        handler.onHoldProgress = { [weak self] progress in
            guard let self else { return nil }
            return MainActor.assumeIsolated {
                self.session.updateHold(progress: progress)
            }
        }
        handler.onHoldCancelled = { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.session.cancelHold()
            }
        }
        services.actionHandler = handler

        #if DEBUG
        // Says whether Inter actually registered. `Font.custom` falls back to
        // San Francisco silently, so without this the only symptom is "the
        // wordmark looks a bit off" — which is not a symptom anyone can act on.
        Typography.audit()
        #endif

        // Pay the 1-2s model cold start now, at keyboard launch, rather than
        // when the user is holding space waiting for the panel to appear.
        engine.prewarm()

        // Same reasoning, much cheaper: ~58ms to load the emotion classifier,
        // paid here instead of on the user's first keystroke.
        heatDetector.prewarm()

        super.viewDidLoad()
    }

    override func viewWillSetupKeyboardView() {
        setupKeyboardView { [weak self] controller in
            guard let self else { return AnyView(EmptyView()) }
            // Bound before the view builders below so `buttonContent` captures
            // the session and not `self`. That closure is escaping and
            // KeyboardKit retains it for the life of the view tree, so a
            // captured controller would pin the whole graph behind it — the
            // warmed LanguageModelSession and the NLTagger included — across
            // rebuilds. The other callbacks take `[weak self]` because they
            // genuinely need the controller (proxy access, height constraint).
            let session = self.session!
            return AnyView(
                KeyboardRootView(
                    session: session,
                    onHeightChange: { [weak self] height in
                        self?.setKeyboardHeight(height)
                    },
                    onApplyRewrite: { [weak self] text in
                        self?.applyRewrite(text)
                    },
                    keyboardView: { reportKeyFrame, spacebarPhase in
                        // The ~48pt above the keys is the autocomplete toolbar
                        // that `KeyboardView(services:)` builds for us, now fed
                        // by TextCheckerAutocompleteService.
                        //
                        // `buttonContent` replaces only the space key's caption
                        // and hands every other key back the standard view. This
                        // is the supported seam for it — the alternative was
                        // overlaying our own label on top of KeyboardKit's,
                        // which means guessing the spacebar's frame and leaves
                        // the locale name visible underneath during the fade
                        // KeyboardKit runs on it.
                        KeyboardView(
                            services: controller.services,
                            buttonContent: { params in
                                if params.item.action == .space {
                                    SpacebarWordmark(
                                        intensity: session.spacebarIntensity,
                                        phase: spacebarPhase,
                                        onFrameChange: reportKeyFrame
                                    )
                                } else {
                                    params.view
                                }
                            },
                            buttonView: { $0.view }
                        )
                    }
                )
            )
        }
    }

    // MARK: - Draft handling

    /// Read what the user has typed so far and open the panel.
    ///
    /// LIMITATION: `documentContextBeforeInput` is not the whole field. iOS
    /// hands a keyboard extension only the text around the cursor, and how
    /// much varies by host app — some give a sentence, some a paragraph. For
    /// a one-message draft this is usually the full text, but for long drafts
    /// it will be truncated at the front. (KeyboardKit Pro ships a full
    /// document reader that walks the proxy to reconstruct everything; it is
    /// slow and jumpy, and not worth it for this feature.)
    @MainActor
    private func beginReflection() {
        session.begin(draft: currentDraft())
        // `begin` drops presence back to `.rest` while the draft text is
        // unchanged. The cache would then treat the next check as a no-op and
        // the key could never nudge again for this message, so the dedupe is
        // invalidated wherever presence is reset behind its back.
        lastCheckedDraft = nil
    }

    @MainActor
    private func beginPractice(_ practice: KeyboardPracticeAction) {
        switch practice {
        case .breathe:
            session.beginBreathe()
        case .rewrite:
            session.beginRewrite(draft: currentDraft())
        }
        // `beginBreathe` and `beginRewrite` both reset presence; see
        // `beginReflection` for why the cache has to be dropped with it.
        lastCheckedDraft = nil
    }

    @MainActor
    private func currentDraft() -> String {
        let proxy = textDocumentProxy
        let before = proxy.documentContextBeforeInput ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        return (before + after).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replace the user's draft with the chosen rewrite.
    @MainActor
    private func applyRewrite(_ text: String) {
        let proxy = textDocumentProxy

        // Move the cursor to the end so the deletion below covers the draft.
        if let after = proxy.documentContextAfterInput, !after.isEmpty {
            proxy.adjustTextPosition(byCharacterOffset: after.count)
        }

        // There is no "clear field" API for keyboard extensions — deletion is
        // one grapheme at a time, which is why draft length matters here.
        // KeyboardKit's deleteBackward(times:) batches this for us.
        let existing = proxy.documentContextBeforeInput ?? ""
        deleteBackward(times: existing.count)

        proxy.insertText(text)

        // The rewrite is finished prose, not a word in progress. Without this
        // the toolbar keeps showing suggestions computed from the draft we
        // just deleted, and a following space could autocorrect the rewrite's
        // last word against that stale state.
        resetAutocomplete()

        session.dismiss()
    }

    // MARK: - Quiet nudge

    /// Re-evaluate how heated the draft looks.
    ///
    /// `textDidChangeAsync`, NOT `textDidChange`.
    ///
    /// This is the whole reason detection appeared not to work while typing and
    /// then suddenly fired when the cursor moved. `textDidChange` runs *before*
    /// the text document proxy has caught up, so `documentContextBeforeInput`
    /// still returns the draft as it was BEFORE the keystroke that triggered
    /// the callback. Detection was therefore always one character stale — and
    /// since the deciding character is usually the last one typed, the verdict
    /// only became correct on the next event, which in practice was the user
    /// tapping elsewhere.
    ///
    /// KeyboardKit's `textDidChangeAsync` exists precisely for this: it is
    /// called after the proxy has settled, so the draft read here is the one
    /// on screen.
    ///
    /// Still not the action handler, for the original reason: the draft also
    /// changes in ways the handler never sees — autocorrect applying, the user
    /// tapping to move the cursor, dictation, or a paste.
    override func textDidChangeAsync(_ textInput: UITextInput?) {
        super.textDidChangeAsync(textInput)
        scheduleHeatCheck()
    }

    /// Also hooked, deliberately.
    ///
    /// `textDidChangeAsync` is the one whose draft is trustworthy, but it is
    /// KeyboardKit's own addition and nothing in the shipped binary proves it
    /// fires in every host app. This one always fires. Reading a stale draft
    /// here is harmless — the async call corrects it a moment later — whereas
    /// relying solely on a hook that might not fire is how this bug happened
    /// in the first place. Both cost 4ms.
    ///
    /// NOTE: this hook also fires on events that change no text at all —
    /// cursor moves, selection changes, focus. `updatePresence` dedupes on the
    /// draft string to absorb those; an earlier comment here claimed
    /// `setPresence` was enough, which was wrong, because presence has usually
    /// been reset to `.rest` by then and every such event looked like a rise.
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        scheduleHeatCheck()
    }

    private func scheduleHeatCheck() {
        // NO DEBOUNCE. The check runs on every text change.
        //
        // MEASURED, NOT ASSUMED
        // Both classifiers together cost 4.4ms warm (58ms once, on the first
        // call, to load the emotion model). At that price there is nothing to
        // debounce — a keystroke costs a fraction of a frame, and every scheme
        // for spreading the cost out only adds latency to a feature whose
        // entire value is being timely.
        //
        // The history here is worth keeping: this began as a 0.45s trailing
        // debounce, which meant the detector never ran *while* someone was
        // typing — only after they stopped. Angry messages are typed fast and
        // without pausing, so the feature was slowest exactly when it mattered.
        // Replacing it with a leading edge plus a 0.5s throttle helped and was
        // still solving a problem that does not exist.
        updatePresence()
    }

    @MainActor
    private func updatePresence() {
        // While the panel is open the spacebar is not the interface any more,
        // and re-reading a draft that is about to be replaced would raise the
        // presence again the moment it was reset.
        guard !session.isOpen else { return }

        let draft = currentDraft()

        // Nothing the user wrote has changed, so the verdict cannot have
        // changed either — this is a cursor move, a selection change or a
        // focus event. Skipping here is what keeps the nudge tied to typing
        // rather than to tapping around the field. It also means the two
        // hooks below can both call in freely: whichever arrives second is
        // a no-op instead of a second classifier run.
        guard draft != lastCheckedDraft else { return }
        lastCheckedDraft = draft

        let level = heatDetector.presence(for: draft)
        #if DEBUG
        print("[Unpackd] fullAccess=\(hasFullAccess) draft=\"\(draft.prefix(60))\" len=\(draft.count) -> \(level) (was \(session.presence))")
        #endif
        if session.setPresence(level) {
            // Exactly one subtle pulse on arriving at NUDGE — "visual + haptic,
            // never disruptive". `setPresence` returns true only on the way up,
            // so cooling back down is silent.
            //
            // `triggerHapticFeedback` rather than `triggerFeedback(for:on:)`:
            // the latter also plays the key *click*, and an unprompted click
            // from a key nobody touched is precisely the disruption this is
            // supposed to avoid. `.selectionChanged` is the lightest tick the
            // enum offers — the nudge should be noticed, not felt.
            services.actionHandler.triggerHapticFeedback(.selectionChanged)
        }
    }

    // MARK: - Height

    /// Grow the keyboard to fit the panel.
    ///
    /// A keyboard extension cannot draw outside its own frame, so the panel
    /// cannot float over the conversation the way the mockups show. Expanding
    /// the keyboard's own height is the closest achievable thing: the panel
    /// sits above the keys and pushes the host app's content up. There is no
    /// hard height cap, but the system dock (globe/mic) stays on top of us.
    private func setKeyboardHeight(_ height: CGFloat) {
        #if DEBUG
        print("[Unpackd] height -> \(height)")
        #endif
        if let constraint = heightConstraint {
            guard constraint.constant != height else { return }
            constraint.constant = height
        } else {
            let constraint = view.heightAnchor.constraint(equalToConstant: height)
            // Below required, so we lose to the system's own layout pass rather
            // than throwing unsatisfiable-constraint errors during launch (iOS
            // sets the frame to 0x0, then full-screen, then settles).
            constraint.priority = .defaultHigh
            constraint.isActive = true
            heightConstraint = constraint
        }
    }
}

// MARK: - App config

extension KeyboardApp {

    // No licenseKey: this is the MIT open-source KeyboardKit, not Pro.
    //
    // appGroupId must stay in sync with the `com.apple.security.application-groups`
    // entitlement in BOTH targets. If the id here names a group the build holds
    // no entitlement for, KeyboardKit reaches for a container that does not
    // exist — so change all three together, or none. The group only syncs
    // settings between app and extension, which nothing reads yet.
    static var unpackd: KeyboardApp {
        .init(
            name: "Unpackd",
            appGroupId: "group.com.hoamedigital.unpackd",
            locales: [.english]
        )
    }
}
