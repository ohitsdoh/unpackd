//
//  Pill.swift
//  UnpackdKeyboard
//
//  The small tinted capsule under a message — the detected emotion on the
//  original, the tone label on a rewrite.
//

import SwiftUI

struct Pill: View {

    private let text: String
    private let tint: Color

    init(_ text: String, tint: Color) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}
