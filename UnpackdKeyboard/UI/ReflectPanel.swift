//
//  ReflectPanel.swift
//  UnpackdKeyboard
//

import KeyboardKit
import SwiftUI

/// The surface that emerges from the keyboard when the user holds space.
///
/// LAYOUT IS FIXED; CONTENT IS NOT.
/// Every screen here is the same shape — a grab handle, one thing to read, one
/// primary action, and quieter alternatives under it. The design brief calls
/// this "static structure, dynamic content": the questions and options are all
/// model output, so the only thing keeping the panel from feeling like a
/// different app on every step is that its skeleton never moves.
///
/// There is no title bar and no close button, which is deliberate. An ✕ in the
/// corner is the affordance of a modal that has interrupted you; this panel is
/// something the user summoned, and it is dismissed the same way every sheet on
/// iOS is — by the handle, or by choosing one of the things it offers.
struct ReflectPanel: View {

    @Bindable var session: ReflectSession
    let onApplyRewrite: (String) -> Void

    /// Passed explicitly from the controller, NOT read via
    /// `@EnvironmentObject`.
    ///
    /// Nothing in this extension injects a `KeyboardContext` into the SwiftUI
    /// environment — `setupKeyboardView` hands the controller to the builder
    /// and no `.environmentObject(...)` is applied anywhere. An
    /// `@EnvironmentObject` here therefore compiles and then traps the moment
    /// the composer appears, which in a keyboard extension means iOS silently
    /// swaps the user back to their previous keyboard with no crash log.
    let keyboardContext: KeyboardContext

    var body: some View {
        VStack(spacing: 0) {
            GrabHandle()
                // The handle is the ONLY way out of the panel, now that the
                // ✕ is gone — so it has to actually work, by tap as well as
                // by drag. A handle that only looks like a handle is worse
                // than the close button it replaced.
                .contentShape(Rectangle())
                .onTapGesture { session.dismiss() }
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            // Downward only: the panel sits at the bottom of
                            // the screen, so a downward flick is the direction
                            // every iOS sheet is dismissed in.
                            guard value.translation.height > 24 else { return }
                            session.dismiss()
                        }
                )
                .accessibilityElement()
                .accessibilityLabel("Close")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { session.dismiss() }
            // NOT wrapped in a ScrollView.
            //
            // A ScrollView takes whatever height it is offered rather than
            // reporting its content's — and this panel's measured height is
            // what grows the extension's own frame (see `onHeightChange` in
            // KeyboardRootView). Inside one, the panel reported a near-zero
            // content height, the frame never grew, and every screen rendered
            // as an empty card with just the grab handle showing.
            //
            // The ceiling it was protecting against is real but belongs on the
            // one thing that can actually overflow — a model-generated option
            // list — so `QuestionView` caps its own options instead. Everything
            // else here is fixed-size by construction.
            content
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(KeyboardTheme.panelBackground)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 5)
        )
        .overlay(
            // A literal white hairline read as a bright halo on the dark
            // panel; `border` is the adaptive equivalent.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(KeyboardTheme.border, lineWidth: 0.75)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        // One animation for the whole panel, driven by the phase.
        //
        // Each step is a *replacement*, not a push: the panel is one object
        // that changes what it holds, which is why there is no navigation
        // chrome anywhere in here. Crossfade rather than slide for the same
        // reason — a slide would imply a stack the user can go back through.
        .animation(.smooth(duration: 0.32), value: session.phase)
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .idle:
            EmptyView()

        case .settling:
            // Deliberately just a line of text. See `settleDuration`.
            CreateSpaceView()

        case .choosing:
            ChooserView(
                onUnpack: { session.unpack() },
                onRewrite: { session.rewrite() },
                onLater: { session.unpackLater() }
            )

        case .breathing:
            BreathingView { session.dismiss() }

        case .thinking:
            ThinkingView()

        case .asking(let question):
            QuestionView(
                question: question,
                onSelect: { session.answer($0, to: question) },
                onSomethingElse: { session.composeAnswer(to: question) }
            )

        case .composing(let question):
            ComposerView(
                question: question,
                text: $session.composedAnswer,
                keyboardContext: keyboardContext,
                onSubmit: { session.submitComposedAnswer(to: question) }
            )

        case .reflecting(let insight):
            InsightView(
                insight: insight,
                onExpress: { session.express() },
                onKeepUnpacking: { session.keepUnpacking() }
            )

        case .adjusting:
            AdjustView { session.express(style: $0) }

        case .expressing(let reflection):
            ExpressionView(
                text: reflection.rewrites.first?.text ?? "",
                onUse: onApplyRewrite,
                onTryAnother: { session.adjust() },
                onEdit: { session.edit($0) }
            )

        case .editing:
            EditView(
                text: $session.editedMessage,
                keyboardContext: keyboardContext
            ) { onApplyRewrite($0) }

        case .saved:
            SavedView { session.dismiss() }

        case .remembering(let thought):
            RememberView(thought: thought) { session.anotherThought() }

        case .nothingRemembered:
            NothingRememberedView()

        case .reviewing(let reflection):
            RewriteView(
                original: session.draft,
                reflection: reflection,
                selection: $session.selectedRewrite,
                onUse: onApplyRewrite
            )

        case .unavailable(let reason):
            // `retry()`, not `rewrite()`: resumes whichever step failed so a
            // transient failure does not discard the answers already given.
            UnavailableView(reason: reason) { session.retry() }
        }
    }
}

// MARK: - Shared pieces

extension View {

    /// The panel's card treatment: a filled continuous-rounded rect with a
    /// hairline border.
    ///
    /// The fill and the stroke must use the SAME shape or the border sits
    /// slightly off the fill, which is why this is one modifier rather than
    /// two call sites that happen to agree. Two radii are in use and they are
    /// not interchangeable: `.tight` for a tappable row, `.roomy` for a block
    /// of prose.
    func cardChrome(_ radius: CardRadius = .tight) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius.rawValue, style: .continuous)
        return background(shape.fill(KeyboardTheme.cardBackground))
            .overlay(shape.stroke(KeyboardTheme.border, lineWidth: 0.75))
    }
}

/// The two card radii the panel uses, named so a new screen picks the one
/// that matches its role rather than guessing between 12 and 16.
enum CardRadius: CGFloat {
    /// A tappable row — an option, a single-line field.
    case tight = 12
    /// A block of prose — a generated message, an editor.
    case roomy = 16
}


/// The sheet handle. Stands in for the title bar and the close button both:
/// it says "this is a surface that can be dismissed" using the one vocabulary
/// every iOS user already has.
private struct GrabHandle: View {
    var body: some View {
        // The visible capsule is 36x5, which is far below the 44pt minimum
        // target — the padding below is what makes it hittable, so it is
        // load-bearing rather than cosmetic.
        Capsule()
            .fill(KeyboardTheme.mutedInk.opacity(0.35))
            .frame(width: 36, height: 5)
            .frame(width: 88, height: 22)
            .padding(.top, 10)
            .padding(.bottom, 14)
    }
}

/// The full-width gradient pill that carries the one primary action on any
/// screen. Exactly one of these is visible at a time, which is what makes
/// "everything else recedes" true rather than aspirational.
private struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KeyboardTheme.onIris)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: KeyboardTheme.iris,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
                .overlay(Capsule().stroke(.white.opacity(0.55), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }
}

/// A quiet alternative: plain text, no fill, no border.
///
/// The contrast with `PrimaryButton` is the entire point — two filled buttons
/// side by side is a choice, and the design is explicit that these screens
/// offer one action with alternatives, not a menu.
private struct SecondaryButton: View {
    let title: String
    var icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(KeyboardTheme.mutedInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The panel's two quiet alternatives, split by a hairline.
///
/// A named unit because it is the file's structural rule made concrete —
/// "one primary action, and quieter alternatives under it" — and because the
/// hairline needs `.overlay` rather than `.background` to take a colour, which
/// is not obvious and was already written twice.
private struct SecondaryPair: View {
    let leading: (title: String, icon: String?, action: () -> Void)
    let trailing: (title: String, icon: String?, action: () -> Void)

    var body: some View {
        HStack(spacing: 0) {
            SecondaryButton(leading.title, icon: leading.icon, action: leading.action)
            Divider()
                .frame(height: 22)
                .overlay(KeyboardTheme.border)
            SecondaryButton(trailing.title, icon: trailing.icon, action: trailing.action)
        }
    }
}

/// A bordered, tappable row — one generated option, or one adjustment.
private struct OptionRow: View {
    let text: String
    var isMuted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(isMuted ? KeyboardTheme.mutedInk : KeyboardTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .cardChrome()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Phases

/// The empty beat. One line, centred, nothing to act on.
private struct CreateSpaceView: View {
    var body: some View {
        // No self-fade here. The panel already crossfades on `phase`, and a
        // nested `@State` + `.onAppear` opacity ramp on a view being inserted
        // by that same transition does not reliably resolve — it can stay at
        // zero, which reads as a panel that opened empty.
        Text("Create space.")
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(KeyboardTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
    }
}

/// One primary action, two quiet ones.
private struct ChooserView: View {
    let onUnpack: () -> Void
    let onRewrite: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("What do you need right now?")
                .font(.system(size: 14))
                .foregroundStyle(KeyboardTheme.mutedInk)

            PrimaryButton(title: "Unpack this", action: onUnpack)

            SecondaryPair(
                leading: ("Rewrite", "pencil", onRewrite),
                trailing: ("Unpack later", "clock", onLater)
            )
        }
        .padding(.top, 2)
    }
}

/// A generated question and its options.
private struct QuestionView: View {
    let question: UnpackQuestion
    let onSelect: (String) -> Void
    let onSomethingElse: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(question.prompt)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(KeyboardTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)

            // Capped here rather than by a scroll view around the whole
            // panel: this list is the only model-generated, unbounded thing
            // on any screen, so it is the only thing that needs a ceiling.
            ForEach(question.options.prefix(UnpackQuestion.maxOptions), id: \.self) { option in
                OptionRow(text: option) { onSelect(option) }
            }

            // Always last, always present. The deck's point is that the
            // generated options are guesses, and the user needs a way to say
            // so — "When we miss it, you tell us."
            OptionRow(text: "Something else…", isMuted: true, action: onSomethingElse)
        }
    }
}

/// "Something else..." — the user types one thought in their own words.
private struct ComposerView: View {
    let question: UnpackQuestion
    @Binding var text: String
    /// Needed by `KeyboardTextField` to register itself as the input proxy.
    let keyboardContext: KeyboardContext
    let onSubmit: () -> Void

    /// Matches the deck's counter. Long enough for a real thought, short
    /// enough that this stays a sentence rather than becoming a journal entry
    /// the model then has to summarise.
    private let limit = 200

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text(question.prompt)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(KeyboardTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            VStack(alignment: .trailing, spacing: 4) {
                // `KeyboardTextField`, NOT a plain SwiftUI `TextField`.
                //
                // This is the one thing about in-keyboard text entry that is
                // not obvious and fails silently in BOTH directions. A plain
                // TextField here does become first responder — but first
                // responder and proxy routing are independent inside a
                // keyboard extension, which they are nowhere else in UIKit.
                // `textDocumentProxy` still points at the HOST app's field, so
                // every key the user presses goes to the host, nothing appears
                // in this field, and — the bad half — typing into the host app
                // stays broken until the panel is dismissed.
                //
                // KeyboardKit's field fixes both by registering itself as
                // `KeyboardInputViewController.textInputProxy` on focus and
                // clearing it on blur, so our existing key handling keeps
                // working unchanged and simply routes here instead.
                //
                // Present in the MIT binary with a non-throwing init (verified
                // against the .swiftinterface). Note `ProFeature` does contain
                // a `textInput` case, so a runtime gate cannot be ruled out
                // from the interface alone — if this ever renders but refuses
                // input on device, `textInputProxy` is a plain published
                // property with no licence check and is the manual fallback.
                KeyboardTextField(
                    "In your own words…",
                    text: $text,
                    keyboardContext: keyboardContext,
                    resignOnReturn: true,
                    onSubmit: onSubmit
                )
                    .font(.system(size: 14))
                    .foregroundStyle(KeyboardTheme.ink)
                    .frame(height: 38)
                    .focused($focused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .cardChrome()
                    .onChange(of: text) { _, new in
                        // Clamp rather than reject: a paste over the limit
                        // should lose its tail, not the whole paste.
                        if new.count > limit { text = String(new.prefix(limit)) }
                    }

                Text("\(text.count)/\(limit)")
                    .font(.system(size: 11))
                    .foregroundStyle(KeyboardTheme.mutedInk)
            }

            PrimaryButton(title: "Continue", action: onSubmit)
                .opacity(text.isBlank ? 0.5 : 1)
                .disabled(text.isBlank)
        }
        .onAppear { focused = true }
    }

}

/// "It sounds like you want to..." — the reflection, before any language.
private struct InsightView: View {
    let insight: UnpackInsight
    let onExpress: () -> Void
    let onKeepUnpacking: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(insight.text)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(KeyboardTheme.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

            PrimaryButton(title: "Help me say it", action: onExpress)

            SecondaryButton("Keep unpacking", action: onKeepUnpacking)
        }
    }
}

/// "Try another" — how the next version should differ.
private struct AdjustView: View {
    let onChoose: (ExpressionStyle) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("How should it feel?")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(KeyboardTheme.ink)
                .padding(.bottom, 4)

            ForEach(ExpressionStyle.allCases) { style in
                OptionRow(text: style.label) { onChoose(style) }
            }
        }
    }
}

/// A generated message: use it, re-roll it, or edit it.
private struct ExpressionView: View {
    let text: String
    let onUse: (String) -> Void
    let onTryAnother: () -> Void
    let onEdit: (String) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(KeyboardTheme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .cardChrome(.roomy)

            PrimaryButton(title: "Use this") { onUse(text) }

            SecondaryPair(
                leading: ("Try another", nil, onTryAnother),
                trailing: ("Edit", nil, { onEdit(text) })
            )
        }
    }
}

/// The generated message, made editable in place.
private struct EditView: View {
    @Binding var text: String
    /// Needed by `KeyboardTextView` to register itself as the input proxy.
    let keyboardContext: KeyboardContext
    let onUse: (String) -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            // `KeyboardTextView` for the same reason `ComposerView` uses
            // `KeyboardTextField` — see the long note there. A plain SwiftUI
            // TextField would focus, accept nothing, and break typing in the
            // host app until dismissal.
            KeyboardTextView(
                text: $text,
                keyboardContext: keyboardContext,
                resignOnReturn: false
            )
                .font(.system(size: 15))
                .foregroundStyle(KeyboardTheme.ink)
                .frame(height: 78)
                .focused($focused)
                .padding(14)
                .cardChrome(.roomy)

            // No "Try another" here. Once the user has edited, these are their
            // words — re-rolling would throw them away, and the design's rule
            // is that the edited version is final ("Your words win").
            PrimaryButton(title: "Use this") { onUse(text) }
                .opacity(text.isBlank ? 0.5 : 1)
                .disabled(text.isBlank)
        }
        .onAppear { focused = true }
    }

}

/// "Saved for later." Confirms, then gets out of the way on its own.
private struct SavedView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(KeyboardTheme.onIris)
                .frame(width: 52, height: 52)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: KeyboardTheme.iris,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )

            Text("Saved for later.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(KeyboardTheme.ink)

            Text("Come back when you have more space.")
                .font(.system(size: 13))
                .foregroundStyle(KeyboardTheme.mutedInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        // No button. The design's point is that stepping away asks nothing
        // more of you — a "Done" to tap would be one more decision at exactly
        // the moment the user said they were out of capacity for them.
        .task {
            try? await Task.sleep(for: .milliseconds(1400))
            onDone()
        }
    }
}

/// One of the user's own saved thoughts.
///
/// NOTHING HERE IS GENERATED, AND NOTHING IS TYPED.
/// Every other screen in this panel either reads the draft or writes to it.
/// This one does neither — the design's line is "nothing is typed or sent,
/// just a moment for you". Keep it that way: a "use this" button here would
/// turn someone's private mantra into message text.
private struct RememberView: View {
    let thought: RememberedThought
    /// Used by both the button and the swipe — they mean the same thing, so
    /// they are not two parameters.
    let onAnother: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Remember")
                .font(.system(size: 12, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(KeyboardTheme.mutedInk)

            // Serif, and the only serif in the extension.
            //
            // The deck sets these in a serif face while every other panel
            // screen is system sans — the contrast is the signal that this is
            // the user's own voice rather than Unpackd's. `.serif` design
            // rather than Inter: Inter is bundled for the spacebar wordmark
            // only, and the keyboard's own text deliberately stays on system
            // faces (see the Typography note in CLAUDE.md).
            Text(thought.text)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(KeyboardTheme.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                // Crossfades between thoughts instead of snapping. `.id` is
                // what makes SwiftUI treat a new thought as a new view rather
                // than re-rendering the same one with different text.
                .id(thought.id)
                .transition(.opacity)

            // "Another" IS this screen's primary action, so it uses the same
            // pill as every other screen rather than a hand-copied one — the
            // pressed state and stroke are then decided in one place.
            PrimaryButton(title: "Another", action: onAnother)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        // "Swipe to explore" from the deck. Horizontal only, and in either
        // direction: there is no ordering to this list (it is shuffled), so a
        // left-swipe and a right-swipe both just mean "show me another".
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    onAnother()
                }
        )
        .animation(.smooth(duration: 0.3), value: thought.id)
    }
}

/// Remember, opened before anything has been saved.
///
/// Points at the app rather than offering to write one here: these are meant
/// to be composed in a calm moment, and the keyboard is by definition not
/// that moment.
private struct NothingRememberedView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Nothing saved yet.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(KeyboardTheme.ink)
            Text("Add the words you want close in the Unpackd app, and they'll be here when you need them.")
                .font(.system(size: 13))
                .foregroundStyle(KeyboardTheme.mutedInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private struct BreathingView: View {
    let onDone: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                KeyboardTheme.iris[1].opacity(0.92),
                                KeyboardTheme.iris[0].opacity(0.66),
                                KeyboardTheme.iris[3].opacity(0.28),
                                .clear
                            ],
                            center: .center,
                            startRadius: 6,
                            endRadius: 76
                        )
                    )
                    .blur(radius: 1.5)
                Circle()
                    .stroke(.white.opacity(0.70), lineWidth: 1)
            }
            .frame(width: expanded ? 122 : 72, height: expanded ? 122 : 72)
            .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: expanded)

            Text(expanded ? "Breathe out" : "Breathe in")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(KeyboardTheme.mutedInk)
                .contentTransition(.opacity)

            Button(action: onDone) {
                Text("I'm ready")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KeyboardTheme.onAccent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(KeyboardTheme.accent))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .onAppear { expanded = true }
    }
}

private struct ThinkingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(KeyboardTheme.ink)
            Text("Reading what you wrote…")
                .font(.system(size: 13))
                .foregroundStyle(KeyboardTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

private struct UnavailableView: View {
    let reason: ReflectionUnavailable
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(reason.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(KeyboardTheme.ink)
            Text(reason.message)
                .font(.system(size: 13))
                .foregroundStyle(KeyboardTheme.mutedInk)
                .multilineTextAlignment(.center)
            if reason.isRetryable {
                Button("Try again", action: onRetry)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(KeyboardTheme.ink)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}
