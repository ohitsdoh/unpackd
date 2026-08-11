# Unpackd

An iOS keyboard where **holding the spacebar creates space** — a pause before you
send something you'll regret, with an on-device rewrite that turns
*"I can't believe you never responded"* into *"I felt hurt when I didn't hear back."*

Built on [KeyboardKit](https://github.com/KeyboardKit/KeyboardKit) 10.7.3 (MIT) and
Apple's **Foundation Models** framework (iOS 26+).

---

## Build

Nothing here has been compiled — it was written on Linux without a Swift toolchain,
and an iOS keyboard extension needs Xcode plus a physical device regardless. The
KeyboardKit and Foundation Models API surfaces were both verified against source
and Apple's documentation rather than written from memory (see *Known limitations*),
but treat first build as a debugging session, not a formality.

```bash
brew install xcodegen
xcodegen generate
open Unpackd.xcodeproj
```

Then set `DEVELOPMENT_TEAM` in `project.yml`, and register the
`group.com.unpackd.app` App Group for both targets.

**You need a physical iPhone 15 Pro or newer.** Foundation Models does not run in
the simulator. To develop the panel UI without one, swap the engine in
`KeyboardViewController.swift`:

```swift
private let engine: ReflectionEngine = StubReflectionEngine()
```

---

## Why Foundation Models, and not a bundled model

A keyboard extension gets **~60MB of `phys_footprint`**. Cross it and jetsam kills
the process — no crash log, no signal, no exception. iOS silently switches the user
back to their previous keyboard, which is close to the worst debugging surface on
the platform.

That budget rules out bundling llama.cpp, MLX, or a Core ML LLM. Memory-mapped
weights are nearly free, but KV cache and activation buffers are dirty heap and get
charged to you. One developer got their keyboard's *baseline* from 52MB to 27MB
purely by mmap-ing word lists — there is no room left for inference.

Foundation Models sidesteps this entirely, because the model runs **out of process**:

> "The on-device foundation model and the inference resources are managed centrally
> by the operating system and shared by all Apple Intelligence system features, so
> the increase to your app's memory usage will be very minimal."
> — [Apple Developer Forums](https://developer.apple.com/forums/thread/795044)

The ~1.2GB of weights live in a system daemon. We hold a session handle and pay
almost nothing. It also means **no network and no "Allow Full Access" prompt** —
`RequestsOpenAccess` is `false`, which matters a lot for a keyboard that reads
what you type at your worst moments.

---

## ⚠️ The open risk: extension rate limiting

**Verify this on a device before building further.**

Apple rate-limits Foundation Models when the process is *on battery* **and**
*running in the background*. One developer hit the limit after
[4 requests spaced 30 seconds apart](https://developer.apple.com/forums/thread/789788).
The error thrown is misleading — `"Safety guardrail was triggered after consecutive
failures during streaming"` is a **rate limit**, not a content filter. Apple has
acknowledged a bug (#153216632) where it throttles even while plugged in.

Whether a **keyboard extension** counts as "background" is not documented anywhere
I could find. It's plausibly foreground — the user is actively looking at it — but
Safari extensions are explicitly background, so it isn't safe to assume.

**The spike:** install on a device, unplug it, hold space and rewrite ~10 times in
a row at realistic intervals, and watch for the guardrail error on innocuous input.

Mitigations already in the code:
- `respond()`, never `streamResponse()` — [Apple's explicit guidance](https://developer.apple.com/forums/thread/789788),
  since streaming burns more power and trips the limit sooner. A ~30-token rewrite
  gains nothing from streaming anyway.
- `prewarm()` at `viewDidLoad`, not on space-hold — avoids the 1–2s cold start
  landing while the user waits.
- Every failure mode maps to its own message (`ReflectionUnavailable`), so a
  throttle reads as "give it a moment" rather than "this feature is broken".

If the spike fails, the fallback is a deterministic rewriter (`NLTagger` sentiment
+ I-statement templates) behind the same `ReflectionEngine` protocol — the panel
and gesture code don't change.

---

## Two things the mockups can't do as drawn

**1. The panel can't float over the conversation.** A keyboard extension cannot
draw outside its own frame. Slides 20–22 show the reflect card overlapping the
message transcript; what's implemented instead grows the keyboard's own height
constraint so the panel sits above the keys and pushes the host app's content up.
There's no hard height cap, but the system dock (globe/mic) always stays on top.
Visually close, structurally different — worth confirming before design sign-off.

**2. Hold-space already means "move the cursor."** That's old, strong muscle
memory, and Unpackd takes it. `spaceLongPressBehavior` is set to
`.openLocaleContextMenu` (which is what actually disables cursor drag in
KeyboardKit), and `HoldSpaceActionHandler` swallows the long-press before any
locale menu appears. The glow and haptic fire at the moment of capture so the
gesture announces itself.

If testing says losing cursor-drag hurts, the binding is data, not a method body:
assign `handler.trigger` a different `(Keyboard.Gesture, KeyboardAction) -> Bool`
in `viewDidLoad`. Nothing in `ReflectSession` knows what opened it.

---

## Known limitations in this scaffold

- **Draft reading is partial.** `documentContextBeforeInput` gives only the text
  around the cursor, and how much varies by host app. Fine for a single message,
  truncated for long drafts. KeyboardKit Pro has a full-document reader; it's slow
  and jumpy and probably not worth it here.
- **Replacing text is `deleteBackward()` in a loop.** There's no "clear field" API
  for keyboard extensions. Long drafts will be visibly slow.
- **Foundation Models API surface is verified against Apple's documentation**
  (not from memory): all nine `LanguageModelSession.GenerationError` cases,
  the three `SystemLanguageModel.Availability` unavailable reasons,
  `respond(to:generating:options:)`, `prewarm()`, and `GenerationGuide.count(_:)`.
  `map(_:)` switches exhaustively with an `@unknown default` for future additions.
- **The 4096-token window** covers instructions + prompt + output combined. The
  instructions are kept deliberately short for this reason.

---

## Layout

```
project.yml                     XcodeGen spec (app + keyboard extension)
Unpackd/                        Container app — onboarding + availability check
UnpackdKeyboard/
  KeyboardViewController.swift  Setup, prewarm, height, draft read/replace
  Reflect/
    ReflectionEngine.swift      Protocol + models + preview stub
    FoundationModelsRewriter.swift   On-device inference, @Generable output
    HoldSpaceActionHandler.swift     Claims the trigger gesture (rebindable)
    ReflectSession.swift        State machine
  UI/
    KeyboardRootView.swift      Panel + keyboard composition, height reporting
    ReflectPanel.swift          The card: chips, Breathe/Reflect/Rewrite/Save
    RewriteView.swift           Original vs rewrite, pager, "Use this message"
    Pill.swift                  Shared capsule for emotion chips + tone badges
    ReflectionUnavailable+Copy.swift   Product copy for every failure case
```
