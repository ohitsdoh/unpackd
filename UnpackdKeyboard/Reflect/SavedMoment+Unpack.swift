//
//  SavedMoment+Unpack.swift
//  UnpackdKeyboard
//
//  Bridges the keyboard's flow types to the shared `SavedMoment`.
//  Extension-only: `SavedMoment` itself is compiled into the container app,
//  which has no reason to know what an `UnpackContext` is.
//

import Foundation

extension SavedMoment {
    init(context: UnpackContext, savedAt: Date = .now) {
        self.init(
            draft: context.draft,
            answers: context.answers.map {
                SavedAnswer(question: $0.question, response: $0.response)
            },
            savedAt: savedAt
        )
    }
}
