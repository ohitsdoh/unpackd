//
//  Pill.swift
//  UnpackdKeyboard
//
//  Text in a capsule. Used for the emotion chips on the reflect panel and the
//  tone badges on a rewrite — two things that should look like one family.
//

import SwiftUI

struct Pill: View {

    /// The two places a pill appears, at the two sizes the mockups use.
    enum Size {
        /// Tappable emotion chip on the reflect panel.
        case chip
        /// Small read-only tone badge under a message.
        case badge

        var font: CGFloat { self == .chip ? 14 : 11 }
        var weight: Font.Weight { self == .chip ? .regular : .medium }
        var horizontal: CGFloat { self == .chip ? 14 : 8 }
        var vertical: CGFloat { self == .chip ? 8 : 3 }
    }

    private let text: String
    private let size: Size
    private let fill: AnyShapeStyle
    private let foreground: AnyShapeStyle
    private let stroked: Bool

    init(
        _ text: String,
        size: Size,
        fill: AnyShapeStyle = AnyShapeStyle(.clear),
        foreground: AnyShapeStyle = AnyShapeStyle(.primary),
        stroked: Bool = false
    ) {
        self.text = text
        self.size = size
        self.fill = fill
        self.foreground = foreground
        self.stroked = stroked
    }

    /// Tinted badge — the common case for tone labels.
    init(_ text: String, tint: Color) {
        self.init(
            text,
            size: .badge,
            fill: AnyShapeStyle(tint.opacity(0.12)),
            foreground: AnyShapeStyle(tint)
        )
    }

    var body: some View {
        Text(text)
            .font(.system(size: size.font, weight: size.weight))
            .foregroundStyle(foreground)
            .padding(.horizontal, size.horizontal)
            .padding(.vertical, size.vertical)
            .background(Capsule().fill(fill))
            .overlay {
                if stroked { Capsule().stroke(.quaternary, lineWidth: 1) }
            }
    }
}
