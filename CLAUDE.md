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

**No test target exists.** The code now compiles — both targets build clean against the iOS 26 SDK:

```bash
xcodebuild -project Unpackd.xcodeproj -scheme Unpackd -sdk iphoneos \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Compiling is not running: Foundation Models needs a physical iPhone 15 Pro or newer, and nothing in the reflect path or the spacebar's timing has been seen on a device. "Builds" and "works" are still different claims here — say which one you have checked.

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
- **The keys are native, and must stay native.** `KeyboardTheme.style(for:)` returns `params.standardStyle()` untouched for every action except `.space`, and `KeyboardRootView` applies no `.keyboardViewStyle(...)` at all so `KeyboardViewStyle.standard` holds. An earlier version overrode colours, font, corner radius, border and shadow with hardcoded RGB — reimplementing the system keyboard by hand and getting it subtly wrong. `standardStyle()` tracks light/dark, the `keyboardButtonBackgroundForColorSchemeBug` workaround extensions need, Liquid Glass and per-device metrics; literal values track none of that. The design brief is the rule: *"Preserve the conventions people already know. Change only what creates value."* The spacebar is the only key that creates value, so it is the only key changed — and even it only overrides `background` and `shadow`, inheriting the system's geometry. If a key colour looks wrong, fix it via KeyboardKit's `Color.keyboard*` tokens, never a private copy.
- **`isHapticFeedbackEnabled = true` does not mean every key buzzes.** The flag only makes the feedback engine available. Which gestures actually fire is a separate declarative layer — `feedbackContext.hapticConfiguration` sets every gesture to `.none`, so ordinary typing feels native (iOS keyboards are silent-to-touch unless the user opts in). Keep this as configuration rather than overriding `shouldTriggerHapticFeedback`: the policy stays next to the flag it qualifies, and KeyboardKit's own pipeline stays usable, so a future per-key haptic is `registerCustomHapticFeedback(_:for:on:)` rather than another bypass. Unpackd's moments aren't gestures at all (a display-link tick, a debounced text change) and call `triggerHapticFeedback` directly. Audio feedback is deliberately never configured — KeyboardKit's default is the native behaviour.
- **The spacebar has two independent intensity axes, and they are not the same thing.** `SpacebarPresence` (rest/aware/nudge/engaged) is where the key *sits* between gestures, moved by `HeatDetector` reading the draft on a debounce; `ReflectSession.holdProgress` is the 0...1 ramp of one press-and-hold, driven by a `CADisplayLink` in `HoldSpaceActionHandler`. Rendering reads `spacebarIntensity`, which composes them. Collapsing them into one number loses the distinction between "this draft looks heated" and "the user is halfway through holding" — which want different haptics and different decay.
- **`HeatDetector` is lexical *plus* a sentiment veto, and must stay off the language model.** It runs on a 0.45s debounce after every text change; a Foundation Models call there would cost 1-2s per keystroke-burst, arrive after the sentence is finished, and burn the extension's undocumented rate limit on a decision about gradient saturation. It is also tuned to be shy — a false nudge on an ordinary message is far worse than missing a heated one. It keeps no history and writes nothing to disk; do not add persistence or telemetry to it.
- **The nudge haptic is `triggerHapticFeedback(.selectionChanged)`, never `triggerFeedback(for:on:)`.** The latter also plays the key click, and an unprompted click from a key nobody touched is exactly the disruption the design forbids.
- **The trigger gesture is data, not a method body.** `HoldSpaceActionHandler.trigger` is a `(Keyboard.Gesture, KeyboardAction) -> Bool` assigned at the call site, so moving the feature off the spacebar is a one-line change. `spaceLongPressBehavior = .openLocaleContextMenu` is what actually disables KeyboardKit's cursor drag; the handler then swallows the long-press without calling `super`.
- **Swift 6 strict concurrency.** `ReflectionEngine` is `@MainActor`-isolated on purpose (implementations hold non-Sendable `LanguageModelSession` state). Height is reported via `onGeometryChange` rather than a `PreferenceKey`, whose `@Sendable` closure can't capture the non-Sendable callback.
- **Foundation Models and KeyboardKit API surfaces here were verified against source/docs, not written from memory.** Keep that standard — check before changing a call signature or adding an enum case. KeyboardKit 10.x ships as a *binary* framework, so there is no `Sources/` to grep. The authoritative API surface is the `.swiftinterface`:
  `~/Library/Developer/Xcode/DerivedData/Unpackd-*/SourcePackages/artifacts/keyboardkit/KeyboardKit/KeyboardKit.xcframework/ios-arm64/KeyboardKit.framework/Modules/KeyboardKit.swiftmodule/arm64-apple-ios.swiftinterface`

- **Autocomplete is Pro-gated, but only the *service* is.** `autocomplete` is a case in KeyboardKit's `ProFeature` enum. `StandardAutocompleteService` is fully present in the MIT binary, but its `init` is `throws` precisely so it can reject an unlicensed caller (`licenseFeatureOrTierRequired`), leaving `DisabledAutocompleteService`, which returns no suggestions. Everything *around* it is unlicensed and already runs: `StandardKeyboardActionHandler.tryApplyAutocorrectSuggestion`, the inserted/removed-space bookkeeping, and the `AutocompleteToolbar` that `KeyboardView(services:)` builds. So `TextCheckerAutocompleteService` only has to answer "what are the suggestions for this text" and the rest of the pipeline works. Do not "fix" this by reaching for `StandardAutocompleteService`.

- **`AutocompleteService` is *not* `@MainActor`-isolated**, unlike `ReflectionEngine` — it is a bare `AnyObject` protocol, and `AutocompleteResult` is not `Sendable`. Marking an implementation `@MainActor` fails to build under Swift 6 ("conformance crosses into main actor-isolated code"), and `await`-hopping is impossible because the non-Sendable result cannot cross an actor boundary. `UITextChecker`'s `guesses`/`completions` are themselves main-actor-isolated, so the calls use `MainActor.assumeIsolated` with the checker bound to a local (capturing `self` fails — it is not Sendable).

### Typography

Inter is bundled from `Resources/Fonts/`, referenced by **both** targets (an extension cannot read its container app's bundle) and declared in both `Info.plist`s under `UIAppFonts`. The `.ttf` files are **not checked in** — see `Resources/Fonts/README.md`. The resource entry is `optional: true`, so a checkout without them still builds and silently renders in San Francisco; `Typography.isAvailable` is the check.

Scope is deliberate and asymmetric:
- **Container app** — Inter throughout, via `Unpackd/Typography.swift`. Large serif headings stay serif (`Typography.display`): the editorial contrast between heading and body is the point.
- **Keyboard extension** — Inter for the spacebar wordmark *only*. The panel and keys stay on the system font; they render text the user is reading at a bad moment, and San Francisco is what every other keyboard on the device uses.

Two things fail silently here, and both have already bitten once — see `Resources/Fonts/README.md` before touching any of it:

- **The family name is not "Inter".** The bundled files are Google Fonts' 18pt optical cut, whose family is `Inter 18pt`, and each weight registers as its *own* family. `Font.custom("Inter", ...)` matches nothing and falls back to San Francisco with no error. Faces are addressed by **PostScript name** (`Inter18pt-Medium`) instead.
- **XcodeGen has no top-level `resources:` key.** Resources are a `sources:` entry with `buildPhase: resources`; a `resources:` block is silently ignored, yielding a project with zero references to the fonts. The build still succeeds.

So "it builds" proves nothing about fonts. Verify the **bundle**: `ls $APP/*.ttf` and `ls $APP/PlugIns/UnpackdKeyboard.appex/*.ttf` under DerivedData — not the stale `./build/` directory in the repo root, which `xcodebuild` does not write to. `Typography.audit()` prints which faces resolved on device.

Use the **static** `.ttf` files, not the variable ones — `Font.custom(_:size:).weight(_:)` cannot address a variable font's `wght` axis, so the wordmark's 300→400 step would silently do nothing.

## Other agent configs

An OpenAI Codex config exists at `~/.codex/` (including `AGENTS.md`, skills, prompts and rules). If you want its user-level items (MCP servers, slash commands, subagents, skills, instructions) available in Claude Code, reply `/import` and it will scan and list what's importable, then `/import --yes=<digest>` to apply.
