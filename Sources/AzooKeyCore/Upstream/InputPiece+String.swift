// Adapted from azooKey-Desktop (https://github.com/azooKey/azooKey-Desktop),
// Core/Sources/Core/Extensions/InputPiece+String.swift at b7ec0e4f27cf19d6a3aefa77d4b5ea7f2ebe5376.
// Copyright (c) 2025 Miwa Keita. MIT License; see THIRD_PARTY_NOTICES.md.
// Unmodified.

import KanaKanjiConverterModule

public extension Sequence where Element == InputPiece {
    func inputString(preferIntention: Bool = true) -> String {
        String(self.compactMap {
            switch $0 {
            case .character(let c):
                c
            case .key(intention: let intention, input: let input, modifiers: _):
                preferIntention ? (intention ?? input) : input
            case .compositionSeparator:
                nil
            }
        })
    }
}
