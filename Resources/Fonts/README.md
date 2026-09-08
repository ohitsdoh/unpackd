# Inter

The five faces here are the **static, 18pt optical size** cut of Inter from
Google Fonts, pruned from the full 56-file download (19MB → 1.6MB, which
matters for the extension's ~60MB footprint):

    Inter_18pt-Light.ttf      (300)
    Inter_18pt-Regular.ttf    (400)
    Inter_18pt-Medium.ttf     (500)
    Inter_18pt-SemiBold.ttf   (600)
    Inter_18pt-Bold.ttf       (700)

SemiBold and Bold are here because app call sites use `.semibold` and `.bold`;
without them those weights would synthesise. Italics and the 24pt/28pt optical
sizes were removed — nothing references them.

Both targets reference this directory, so the files are copied into the app
*and* the keyboard extension. The extension cannot read its container app's
bundle, so the spacebar wordmark needs its own copy.

## Two traps, both of which fail silently

**1. The family name is not "Inter".** These files report family
`Inter 18pt`, and each weight registers as its *own* family (`Inter 18pt
Light`, `Inter 18pt Medium`, …). So `Font.custom("Inter", size:)` matches
nothing, and even `.custom("Inter 18pt", size:).weight(.medium)` cannot reach
the medium face — there is no weight axis within the family for it to select.

`Typography` therefore addresses each face by **PostScript name**
(`Inter18pt-Medium`, note: no space). If you swap these files for a different
cut of Inter, those names are what must change.

**2. Do not use the variable fonts.** `InterVariable.ttf` /
`Inter-VariableFont_opsz,wght.ttf` cannot be weighted through SwiftUI's
`Font.custom(_:size:).weight(_:)` — it has no way to address the `wght` axis,
so every weight renders at the default 400 and the wordmark's 300→400 hold
step silently does nothing.

## Wiring, and how it breaks

Fonts need three things to line up, and any one of them failing is invisible —
the build succeeds and text renders in San Francisco:

1. **The files in each target's resources.** In `project.yml` this is a
   `sources:` entry with `buildPhase: resources`. There is **no top-level
   `resources:` key** in XcodeGen; writing one is silently ignored and produces
   a project with no reference to the fonts at all. (This happened.)
2. **`UIAppFonts` in both `Info.plist`s**, listing the exact filenames.
3. **The PostScript name in code** matching the face.

## Verifying

`xcodegen generate`, build, then check the *bundle*, not the build log:

    APP=$(find ~/Library/Developer/Xcode/DerivedData/Unpackd-*/Build/Products/Debug-iphoneos \
      -maxdepth 1 -name Unpackd.app | head -1)
    ls "$APP"/*.ttf
    ls "$APP"/PlugIns/UnpackdKeyboard.appex/*.ttf

Note the stale `./build/` directory in the repo root is **not** where
`xcodebuild` writes; checking there will show old artifacts.

On device, `Typography.isAvailable` is false when nothing registered, and
`Typography.audit()` prints which faces resolved.
