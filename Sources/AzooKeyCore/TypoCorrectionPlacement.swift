import KanaKanjiConverterModuleWithDefaultDictionary

/// Where the conversion of a typo correction goes among the candidates.
public enum TypoCorrectionPlacement: Equatable, Sendable {
    /// Before the conversion of the typed input: live conversion shows it and
    /// Space selects it.
    case first
    /// Right after the first candidate.
    case second

    /// A correction this much more likely than the input as typed (natural
    /// log, typo cost included; see `TypoCorrector.Result.margin`) comes first.
    ///
    /// Measured with zenz-v3.2-small (fine-tuned) and a fine-tuned
    /// zenz-v3.1-xsmall on 31 mistyped and 76 correctly typed inputs: the typos
    /// scored 4.0 or more, apart from a key pressed twice at the very end
    /// (`senseii`: 1.4 to 4.4). No correctly typed input of 4 or more keys scored
    /// above 0.3; shorter ones, which scored up to 3.6, are not corrected at all.
    public static let clearMargin: Float = 4.0

    public init(margin: Float) {
        self = margin >= Self.clearMargin ? .first : .second
    }

    /// `candidates` with `correction` added at this place. Nothing is added
    /// when the first candidate already reads the same for the whole input; a
    /// first candidate reading the same for only part of it (the first clause)
    /// is replaced. Later candidates that read the same are dropped.
    public func inserting(
        _ correction: Candidate,
        into candidates: [Candidate],
        coversWholeInput: (Candidate) -> Bool
    ) -> [Candidate] {
        if let first = candidates.first, first.text == correction.text {
            if coversWholeInput(first) {
                return candidates
            }
            return [correction] + candidates.dropFirst().filter { $0.text != correction.text }
        }
        var result = candidates.filter { $0.text != correction.text }
        result.insert(correction, at: self == .first ? 0 : min(1, result.count))
        return result
    }
}
