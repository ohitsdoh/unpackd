//
//  KeyboardViewController.swift
//  UnpackdKeyboard
//

import KeyboardKit
import SwiftUI
import UIKit

class KeyboardViewController: KeyboardInputViewController {

    /// The reflection engine. Swap for `StubReflectionEngine()` to develop the
    /// panel in the simulator — Foundation Models does not run there.
    private let engine: ReflectionEngine = FoundationModelsRewriter()

    private var session: ReflectSession!
    private var heightConstraint: NSLayoutConstraint?

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

        // Haptics default to OFF in KeyboardKit, so granting Full Access alone
        // would still produce no vibration on the hold-space capture. Both
        // switches are needed: this one, and the user's Full Access grant.
        state.feedbackContext.settings.isHapticFeedbackEnabled = true

        let handler = HoldSpaceActionHandler(controller: self)
        handler.onTrigger = { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.beginReflection() }
        }
        services.actionHandler = handler

        // Pay the 1-2s model cold start now, at keyboard launch, rather than
        // when the user is holding space waiting for the panel to appear.
        engine.prewarm()

        super.viewDidLoad()
    }

    override func viewWillSetupKeyboardView() {
        setupKeyboardView { [weak self] controller in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(
                KeyboardRootView(
                    session: self.session,
                    onHeightChange: { [weak self] height in
                        self?.setKeyboardHeight(height)
                    },
                    onApplyRewrite: { [weak self] text in
                        self?.applyRewrite(text)
                    },
                    keyboardView: {
                        // The ~48pt above the keys is the autocomplete toolbar
                        // that `KeyboardView(services:)` builds for us, now fed
                        // by TextCheckerAutocompleteService.
                        KeyboardView(services: controller.services)
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
        let proxy = textDocumentProxy
        let before = proxy.documentContextBeforeInput ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        session.begin(draft: (before + after).trimmingCharacters(in: .whitespacesAndNewlines))
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

    // MARK: - Height

    /// Grow the keyboard to fit the panel.
    ///
    /// A keyboard extension cannot draw outside its own frame, so the panel
    /// cannot float over the conversation the way the mockups show. Expanding
    /// the keyboard's own height is the closest achievable thing: the panel
    /// sits above the keys and pushes the host app's content up. There is no
    /// hard height cap, but the system dock (globe/mic) stays on top of us.
    private func setKeyboardHeight(_ height: CGFloat) {
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
    // appGroupId is nil while signing with a free Apple ID — personal teams
    // cannot provision App Groups, and passing an id we hold no entitlement
    // for makes KeyboardKit reach for a container that does not exist. The
    // group is only used to sync settings between app and extension, which
    // nothing here does yet. Restore "group.com.unpackd.app" here and in both
    // .entitlements files when moving to a paid team.
    static var unpackd: KeyboardApp {
        .init(
            name: "Unpackd",
            locales: [.english]
        )
    }
}
