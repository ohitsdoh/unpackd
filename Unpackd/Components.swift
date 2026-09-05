//
//  Components.swift
//  Unpackd
//

import SwiftUI

struct KeyboardPreview: View {
    let isHoldingSpace: Bool
    var highlightedKeys: Set<String> = []

    var body: some View {
        VStack(spacing: 7) {
            KeyRow(["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"], highlightedKeys: highlightedKeys)
            KeyRow(["a", "s", "d", "f", "g", "h", "j", "k", "l"], highlightedKeys: highlightedKeys)
                .padding(.horizontal, 15)
            HStack(spacing: 4) {
                SpecialKey(systemName: "shift")
                KeyRow(["z", "x", "c", "v", "b", "n", "m"], highlightedKeys: highlightedKeys)
                SpecialKey(systemName: "delete.left")
            }
            HStack(spacing: 4) {
                SpecialKey(text: "123")
                BrandSpacebar(isPressed: isHoldingSpace, height: 40, cornerRadius: 6)
                    .frame(height: 40)
                SpecialKey(text: "return", width: 78)
            }
        }
        .padding(.horizontal, 5)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(Color(red: 0.80, green: 0.82, blue: 0.84))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct KeyRow: View {
    let keys: [String]
    var highlightedKeys: Set<String> = []

    init(_ keys: [String], highlightedKeys: Set<String> = []) {
        self.keys = keys
        self.highlightedKeys = highlightedKeys
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                let upper = key.uppercased()
                let accent = UnpackdStyle.accent(for: upper)
                let highlighted = highlightedKeys.contains(upper)
                Text(key)
                    .font(.system(size: 15, weight: highlighted ? .semibold : .regular))
                    .foregroundStyle(highlighted ? accent.tint : .black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(highlighted ? accent.background : .white)
                    )
                    .overlay(alignment: .bottom) {
                        if highlighted {
                            Circle()
                                .fill(accent.tint.opacity(0.65))
                                .frame(width: 4, height: 4)
                                .padding(.bottom, 3)
                        }
                    }
                    .shadow(color: highlighted ? accent.glow.opacity(0.42) : .black.opacity(0.22), radius: highlighted ? 8 : 0, y: 1)
            }
        }
    }
}

struct SpecialKey: View {
    var systemName: String?
    var text: String?
    var width: CGFloat = 42

    var body: some View {
        Group {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 14))
            } else {
                Text(text ?? "")
                    .font(.system(size: 12))
            }
        }
        .foregroundStyle(.black)
        .frame(width: width, height: 40)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(red: 0.68, green: 0.71, blue: 0.75)))
        .shadow(color: .black.opacity(0.22), radius: 0, y: 1)
    }
}

struct ChecklistRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary))

            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 11)
    }
}
