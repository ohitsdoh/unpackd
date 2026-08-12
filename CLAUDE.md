# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An iOS custom keyboard extension where **holding the spacebar opens a "reflect" panel** that rewrites an angry draft into an I-statement, using Apple's **Foundation Models** framework (iOS 26+) entirely on-device. Built on KeyboardKit 10.7.3 (MIT, not Pro).

## Build

There is no Xcode project checked in — `project.yml` is an [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec and the `.xcodeproj` is generated:

```bash
brew install xcodegen
xcodegen generate          # regenerate after adding/removing files or changing project.yml
open Unpackd.xcodeproj
```

`DEVELOPMENT_TEAM` in `project.yml` is intentionally blank — set it locally, and register the `group.com.unpackd.app` App Group for both targets.

**No test target exists**, and no code in this repo has ever been compiled — it was written on Linux without a Swift toolchain. Treat any first build as a debugging session. If you are asked to "verify" a change, be explicit that you cannot compile or run it here.

**A physical iPhone 15 Pro or newer is required.** Foundation Models does not run in the simulator. To work on panel UI without one, swap the engine in `UnpackdKeyboard/KeyboardViewController.swift`:

```swift
private let engine: ReflectionEngine = StubReflectionEngine()
```

## Architecture

Two targets, both depending on KeyboardKit:

- **`Unpackd/`** — container app. Onboarding only (Settings deep link + `SystemLanguageModel.availability` status). A custom keyboard is useless until installed in Settings, and that's where custom keyboards lose users.
- **`UnpackdKeyboard/`** — the app extension, where all real logic lives.

Inside the extension there is one seam that matters:

```
KeyboardViewController      UIKit host: setup, prewarm, height constraint, draft read/replace
  └─ ReflectSession         @Observable @MainActor state machine (Phase enum) — the single source of truth
       └─ ReflectionEngine  protocol boundary: everything above is UI, everything below is inference
            ├─ FoundationModelsRewriter   real on-device inference
            └─ StubReflectionEngine       canned data for simulator/preview work
```

`ReflectSession.Phase` (`idle / choosing / breathing / thinking / reviewing / unavailable`) drives the whole panel. `ReflectPanel` switches on it; no view holds duplicate state. The session is owned by the controller and passed down as a plain `let` (or `@Bindable`) — **never `@State`**, which would capture the first instance and ignore later ones.

### Constraints that shaped the code

Changes that violate these will fail in ways that are hard to debug, so read the rationale in the file before working around them:

- **~60MB `phys_footprint` cap.** Crossing it gets the extension jetsam-killed with no crash log — iOS silently swaps the user back to their previous keyboard. This is why the model is *not* bundled: Foundation Models runs the ~1.2GB model in a shared system process, so our footprint barely moves. Do not introduce a bundled LLM, large in-memory assets, or anything holding a big dirty heap.
- **Extension rate limiting is an open, unverified risk.** Apple throttles Foundation Models for background processes; whether a keyboard extension counts as background is undocumented. The throttle surfaces as a *misleading* `guardrailViolation` ("Safety guardrail was triggered after consecutive failures"), not `rateLimited`. Hence: `respond()` and never `streamResponse()`, and `prewarm()` at `viewDidLoad` rather than on space-hold. See the README's "spike" section — this needs on-device verification before building further on the feature.
- **`RequestsOpenAccess` is `false` and must stay false.** Everything is on-device; there is no network. Never add a networked dependency or a call that would require Full Access — that prompt is a product-level dealbreaker for a keyboard that reads what you type at your worst moments.
- **The panel cannot float over the conversation.** An extension can't draw outside its own frame, so `KeyboardRootView` measures panel + keyboard height with `onGeometryChange` and the controller grows a `.defaultHigh` height constraint. Mockups showing the card overlapping the message transcript are not achievable as drawn.
- **Draft reading is partial.** `documentContextBeforeInput` gives only text near the cursor, and how much varies by host app. Replacing the draft is `deleteBackward(times:)` in a loop — there is no clear-field API, so long drafts are visibly slow.
- **4096-token window** covers instructions + prompt + output combined, which is why `FoundationModelsRewriter.instructions` is kept terse.

### Conventions worth preserving

- **`ReflectionUnavailable` has nine distinct cases and each maps to its own user-facing message.** Collapsing them into "something went wrong" is the main way this feature reads as broken rather than unavailable. Retry semantics (`isRetryable`) live with the type in `Reflect/ReflectionEngine.swift`; product copy lives separately in `UI/ReflectionUnavailable+Copy.swift` because it gets reworded far more often than the logic changes.
- **Model output is constrained-decoded, not parsed.** `@Generable` / `@Guide` in `FoundationModelsRewriter` pin the emotion to a closed enum the UI can actually render. Adding an emotion means changing `Emotion`, `EmotionOutput`, and the chips together.
- **`FoundationModelsRewriter` hands out a warmed session and immediately arms a replacement** (`takeWarmedSession()`). One fresh session per reflection — reusing a session would carry one message's tone into the next.
- **The trigger gesture is data, not a method body.** `HoldSpaceActionHandler.trigger` is a `(Keyboard.Gesture, KeyboardAction) -> Bool` assigned at the call site, so moving the feature off the spacebar is a one-line change. `spaceLongPressBehavior = .openLocaleContextMenu` is what actually disables KeyboardKit's cursor drag; the handler then swallows the long-press without calling `super`.
- **Swift 6 strict concurrency.** `ReflectionEngine` is `@MainActor`-isolated on purpose (implementations hold non-Sendable `LanguageModelSession` state). Height is reported via `onGeometryChange` rather than a `PreferenceKey`, whose `@Sendable` closure can't capture the non-Sendable callback.
- **Foundation Models and KeyboardKit API surfaces here were verified against source/docs, not written from memory.** Keep that standard — check before changing a call signature or adding an enum case. KeyboardKit 10.x ships as a *binary* framework, so there is no `Sources/` to grep. The authoritative API surface is the `.swiftinterface`:
  `~/Library/Developer/Xcode/DerivedData/Unpackd-*/SourcePackages/artifacts/keyboardkit/KeyboardKit/KeyboardKit.xcframework/ios-arm64/KeyboardKit.framework/Modules/KeyboardKit.swiftmodule/arm64-apple-ios.swiftinterface`

- **Autocomplete is Pro-gated, but only the *service* is.** `autocomplete` is a case in KeyboardKit's `ProFeature` enum. `StandardAutocompleteService` is fully present in the MIT binary, but its `init` is `throws` precisely so it can reject an unlicensed caller (`licenseFeatureOrTierRequired`), leaving `DisabledAutocompleteService`, which returns no suggestions. Everything *around* it is unlicensed and already runs: `StandardKeyboardActionHandler.tryApplyAutocorrectSuggestion`, the inserted/removed-space bookkeeping, and the `AutocompleteToolbar` that `KeyboardView(services:)` builds. So `TextCheckerAutocompleteService` only has to answer "what are the suggestions for this text" and the rest of the pipeline works. Do not "fix" this by reaching for `StandardAutocompleteService`.

- **`AutocompleteService` is *not* `@MainActor`-isolated**, unlike `ReflectionEngine` — it is a bare `AnyObject` protocol, and `AutocompleteResult` is not `Sendable`. Marking an implementation `@MainActor` fails to build under Swift 6 ("conformance crosses into main actor-isolated code"), and `await`-hopping is impossible because the non-Sendable result cannot cross an actor boundary. `UITextChecker`'s `guesses`/`completions` are themselves main-actor-isolated, so the calls use `MainActor.assumeIsolated` with the checker bound to a local (capturing `self` fails — it is not Sendable).

## Other agent configs

An OpenAI Codex config exists at `~/.codex/` (including `AGENTS.md`, skills, prompts and rules). If you want its user-level items (MCP servers, slash commands, subagents, skills, instructions) available in Claude Code, reply `/import` and it will scan and list what's importable, then `/import --yes=<digest>` to apply.
