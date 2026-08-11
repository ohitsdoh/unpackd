//
//  ReflectSession.swift
//  UnpackdKeyboard
//
//  The state machine behind the reflect panel.
//

import Foundation
import Observation

@Observable
@MainActor
final class ReflectSession {

    enum Phase: Equatable {
        /// Panel closed, normal typing.
        case idle
        /// Panel open on the Breathe / Reflect / Rewrite / Save choice.
        case choosing
        /// Breathing animation running.
        case breathing
        /// Waiting on the model.
        case thinking
        /// Rewrites ready.
        case reviewing(Reflection)
        /// Could not produce a rewrite.
        case unavailable(ReflectionUnavailable)
    }

    private(set) var phase: Phase = .idle
    private(set) var draft: String = ""
    /// Which rewrite the user is currently looking at.
    var selectedRewrite: Int = 0
    /// What the user tapped on the emotion chips, if anything. Optional by
    /// design — being made to label your feeling before you can get help is
    /// its own small friction.
    var selfReportedEmotion: Emotion?

    private let engine: ReflectionEngine
    private var task: Task<Void, Never>?

    init(engine: ReflectionEngine) {
        self.engine = engine
    }

    var isOpen: Bool { phase != .idle }

    // MARK: - Entry

    /// Open the panel for the current draft.
    func begin(draft: String) {
        self.draft = draft
        self.selectedRewrite = 0
        self.selfReportedEmotion = nil
        // Availability is checked up front rather than after the user picks
        // "Rewrite" — offering an action that is going to fail is worse than
        // not offering it.
        if case .failure(let reason) = engine.availability {
            phase = .unavailable(reason)
        } else {
            phase = .choosing
        }
    }

    func dismiss() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    // MARK: - Actions

    func breathe() {
        phase = .breathing
    }

    func rewrite() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .unavailable(.emptyDraft)
            return
        }
        phase = .thinking
        task?.cancel()
        // `[weak self]`: cancelling does not abort an in-flight `respond` — the
        // model call runs to completion regardless. A strong capture would pin
        // this session, and through it the engine, for the whole of an
        // abandoned inference, which is exactly the moment footprint is
        // highest and the user has already dismissed the panel.
        task = Task { [weak self, engine, draft, selfReportedEmotion] in
            let outcome: Phase
            do {
                let reflection = try await engine.reflect(on: draft, selfReported: selfReportedEmotion)
                outcome = .reviewing(reflection)
            } catch let reason as ReflectionUnavailable {
                outcome = .unavailable(reason)
            } catch {
                outcome = .unavailable(.failed(error.localizedDescription))
            }
            guard let self, !Task.isCancelled else { return }
            phase = outcome
        }
    }

    var currentRewriteText: String? {
        guard case .reviewing(let reflection) = phase else { return nil }
        guard reflection.rewrites.indices.contains(selectedRewrite) else { return nil }
        return reflection.rewrites[selectedRewrite].text
    }
}

// User-facing copy for these failures lives in UI/ReflectionUnavailable+Copy.swift;
// retry semantics live with the type in Reflect/ReflectionEngine.swift.
