// Adapted from azooKey-Desktop (https://github.com/azooKey/azooKey-Desktop),
// Core/Sources/Core/InputUtils/CandidatePresentationContext.swift at b7ec0e4f27cf19d6a3aefa77d4b5ea7f2ebe5376.
// Copyright (c) 2025 Miwa Keita. MIT License; see THIRD_PARTY_NOTICES.md.
// Unmodified.

import KanaKanjiConverterModuleWithDefaultDictionary

public struct CandidatePresentationContext: Sendable {
    public var annotationText: String?
    public var extraValues: [String: String]

    public init(annotationText: String? = nil, extraValues: [String: String] = [:]) {
        self.annotationText = annotationText
        self.extraValues = extraValues
    }
}

public struct CandidatePresentation: Sendable {
    public var candidate: Candidate
    public var displayContext: CandidatePresentationContext

    public init(candidate: Candidate, displayContext: CandidatePresentationContext = .init()) {
        self.candidate = candidate
        self.displayContext = displayContext
    }
}
