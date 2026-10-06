import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

/// Finds what was meant when romaji input has a small typo: an extra key, a
/// wrong key next to the intended one, or two neighboring keys swapped.
///
/// The search is the converter's experimental LM-based corrector
/// (`KanaKanjiConverter.experimentalRequestTypoCorrection`), a noisy-channel
/// beam search over the typed keys whose readings are scored by the zenz model
/// that Zenzai uses. Its channel never drops a key that repeats the previous
/// one (a key is not its own neighbor), the most common slip on a hardware
/// keyboard (senseii, sennnsei, ssensei), so those readings are made here and
/// scored by the same model.
public struct TypoCorrector {
    public struct Configuration: Sendable, Equatable {
        public init() {}
        /// Beam width of the upstream search. Its cost grows with the width;
        /// 2 finds as many single typos as 4 (see `correct`).
        public var beamSize = 2
        /// Channel cost of a key pressed twice. Upstream charges 3 per key
        /// unit for skipping an extra key next to the previous one.
        public var repeatedKeyCost: Float = 3.0
        /// Corrections may assume at most this many typos.
        public var maxEdits = 1
        /// Shorter inputs ("ee", "uun") are left alone: they say too little
        /// about what was meant.
        public var minimumKeys = 4
        /// Readings made here (a key pressed twice, one typo split from
        /// several) are compared with the typed input only up to this many keys
        /// past the typo. Later keys are the same in both; scoring them again
        /// after every keystroke would mean recomputing the model's cache,
        /// which follows one reading at a time.
        public var scoringWindow = 8
    }

    /// A reading the input may stand for, scored as log P(reading) under the
    /// model minus the cost of the typos it assumes.
    public struct Hypothesis: Sendable, Equatable {
        /// The keys, lowercased, as the corrector sees them.
        public var input: String
        /// Katakana, with any trailing romaji that is not a kana yet.
        public var reading: String
        public var score: Float
        public var lmScore: Float
        public var channelCost: Float
    }

    public struct Result: Sendable {
        /// The input as typed, without `pendingInput`.
        public var original: Hypothesis
        /// Everything scored, best first; contains `original`.
        public var hypotheses: [Hypothesis]
        /// Trailing keys that are not a kana yet while typing ("k" of
        /// "senseik"). They may still become anything, so they are left out of
        /// the search and kept as typed.
        public var pendingInput: [ComposingText.InputElement]
        /// The input was completed with Space (it ends with a composition
        /// separator): its last keys were searched too, and corrections near
        /// the end were scored as ending the input.
        public var isFinal: Bool

        /// The best hypothesis when its reading differs from the typed one.
        public var correction: Hypothesis? {
            guard let best = hypotheses.first, best.reading != original.reading, best.score > original.score else {
                return nil
            }
            return best
        }

        /// How much more likely the correction is than the input as typed,
        /// typo cost included (natural log; upstream's `prominence` of the
        /// typed input is exp(-margin)).
        public var margin: Float? {
            correction.map { $0.score - original.score }
        }

        /// What the user meant to type, as romaji input to convert.
        public func composingText(for hypothesis: Hypothesis) -> ComposingText {
            var text = ComposingText()
            text.insertAtCursorPosition(hypothesis.input.map { .init(character: $0, inputStyle: .mapped(id: .defaultRomanToKana)) })
            text.insertAtCursorPosition(pendingInput)
            if isFinal {
                text.insertAtCursorPosition([.init(piece: .compositionSeparator, inputStyle: .mapped(id: .defaultRomanToKana))])
            }
            return text
        }
    }

    public var configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// The corrector the input sessions use (azookey-cli changes it to
    /// compare settings). Only touched from the main thread.
    nonisolated(unsafe) public static var `default` = TypoCorrector()

    /// zenz reads its input up to this tag and the conversion after it, so the
    /// model's probability of the tag is that of the input ending there.
    static let endOfInput: Character = "\u{EE01}"

    /// Romaji pieces in the converter's default table; the corrector supports
    /// nothing else.
    public static func isRomajiInput(_ composingText: ComposingText) -> Bool {
        composingText.input.allSatisfy {
            $0.piece == .compositionSeparator || $0.inputStyle == .mapped(id: .defaultRomanToKana) || $0.inputStyle == .roman2kana
        }
    }

    /// Scores `composingText` and its likely typo corrections. Runs in the
    /// converter's current session, whose typo cache keeps what the model
    /// computed, so calling this again after each keystroke costs only the new
    /// keys. Returns nil when there is nothing to correct or the model is
    /// unavailable.
    ///
    /// Measured with zenz-v3.2-small (fine-tuned) and a fine-tuned
    /// zenz-v3.1-xsmall on 31 mistyped and 76 correctly typed inputs, a beam of
    /// 2 fixed as many typos after Space as a beam of 4 (29 to 30 of the 31) at
    /// about half the cost. One typo is assumed at most.
    public func correct(
        _ composingText: ComposingText,
        leftSideContext: String,
        converter: KanaKanjiConverter,
        options: ConvertRequestOptions
    ) -> Result? {
        let isFinal = composingText.input.last?.piece == .compositionSeparator
        var input = composingText.input
        if isFinal {
            input.removeLast()
        }
        // While typing, trailing romaji is the start of the next kana.
        var pendingInput: [ComposingText.InputElement] = []
        if !isFinal {
            let pending = Self.pendingRomaji(composingText.convertTarget)
            guard Self.observedKeys(input.suffix(pending.count)) == pending.lowercased() else {
                return nil
            }
            pendingInput = Array(input.suffix(pending.count))
            input.removeLast(pending.count)
        }
        let typed = Self.observedKeys(input)
        guard typed.count >= configuration.minimumKeys, typed.count == input.count else {
            return nil
        }
        let keys = Array(typed)

        // `.roman2kana` makes the corrector use its Mac keyboard layout, which
        // matches a hardware keyboard, instead of the iOS one.
        let style: InputStyle = .roman2kana
        let beamSize = max(1, configuration.beamSize)
        var text = ComposingText()
        text.insertAtCursorPosition(keys.map { .init(character: $0, inputStyle: .mapped(id: .defaultRomanToKana)) })
        // nBest only trims the output; beam + 1 keeps the typed input in it.
        var hypotheses = converter.experimentalRequestTypoCorrection(
            leftSideContext: leftSideContext,
            composingText: text,
            options: options,
            inputStyle: style,
            config: .init(languageModel: .zenz, beamSize: beamSize, nBest: beamSize + 1)
        ).map {
            Hypothesis(
                input: $0.correctedInput,
                reading: Self.reading(of: Array($0.correctedInput), isFinal: isFinal),
                score: $0.score,
                lmScore: $0.lmScore,
                channelCost: $0.channelCost
            )
        }
        guard let original = hypotheses.first(where: { $0.input == typed }) else {
            return nil
        }

        /// log P(reading), optionally followed by the end of the input. Given
        /// as kana, a reading is barely varied by the search (a beam of one,
        /// only the model's likeliest kana as an alternative). Readings scored
        /// this way share the model's cached states with each other, though
        /// not always with the romaji search, whose kana come in chunks that
        /// the tokenizer may merge (キョ).
        func lmScore(_ reading: String, endsInput: Bool = false) -> Float? {
            let observed = reading + (endsInput ? String(Self.endOfInput) : "")
            var text = ComposingText()
            text.insertAtCursorPosition(observed, inputStyle: .direct)
            return converter.experimentalRequestTypoCorrection(
                leftSideContext: leftSideContext,
                composingText: text,
                options: options,
                inputStyle: .direct,
                config: .init(languageModel: .zenz, beamSize: 1, topK: 1, nBest: 2)
            ).first { $0.correctedInput == observed }?.lmScore
        }

        var seen = Set(hypotheses.map(\.input))
        /// Scores the typed input with one typo fixed that the search did not
        /// assume alone.
        func scored(_ edit: Edit, cost: Float) -> Hypothesis? {
            let edited = edit.applied(to: keys)
            guard seen.insert(String(edited)).inserted else {
                return nil
            }
            let ends = edit.ends
            let reading = Self.reading(of: edited, isFinal: isFinal)
            let window = ends.typed + configuration.scoringWindow < keys.count
            let typedEnd = window ? ends.typed + configuration.scoringWindow : keys.count
            let editedEnd = window ? ends.edited + configuration.scoringWindow : edited.count
            guard let typedScore = lmScore(Self.reading(of: Array(keys[..<typedEnd]), isFinal: isFinal && !window)),
                  let editedScore = lmScore(Self.reading(of: Array(edited[..<editedEnd]), isFinal: isFinal && !window)) else {
                return nil
            }
            let delta = editedScore - typedScore
            return Hypothesis(
                input: String(edited),
                reading: reading,
                score: original.score + delta - cost,
                lmScore: original.lmScore + delta,
                channelCost: cost
            )
        }

        for index in Self.repeatedKeyIndices(keys) {
            if let hypothesis = scored(.delete(index), cost: configuration.repeatedKeyCost) {
                hypotheses.append(hypothesis)
            }
        }
        // The search never drops the last key; after Space it may be an extra
        // key next to the one before it.
        if isFinal, keys.count >= 2, let cost = cost(of: .delete(keys.count - 1), in: keys),
           let hypothesis = scored(.delete(keys.count - 1), cost: cost) {
            hypotheses.append(hypothesis)
        }
        // The beam keeps the best paths so far, so it can fill up with readings
        // that fix the typo and also change a word typed correctly. Split the
        // best of those into single typos and score each alone.
        let crowded = hypotheses.filter { $0.score > original.score && Self.editCount(typed, $0.input) > configuration.maxEdits }
        for hypothesis in crowded.prefix(2) {
            for edit in Self.edits(from: keys, to: Array(hypothesis.input)) {
                if let cost = cost(of: edit, in: keys), let hypothesis = scored(edit, cost: cost) {
                    hypotheses.append(hypothesis)
                }
            }
        }

        let pending = Self.pendingRomaji(original.reading)
        hypotheses = hypotheses.filter { hypothesis in
            if hypothesis == original {
                return true
            }
            // No romaji may be left dangling where the typed input had none
            // (dropping the second "n" of "nn" does not mean "ん"), and none
            // may stay unconverted before the end ("awatshi" is no fix).
            let dangling = Self.pendingRomaji(hypothesis.reading)
            let settled = hypothesis.reading.dropLast(dangling.count)
            return (dangling.isEmpty || dangling == pending)
                && !settled.contains { $0.isASCII && $0.isLetter }
                && Self.editCount(typed, hypothesis.input) <= configuration.maxEdits
        }
        hypotheses.sort { $0.score > $1.score }

        // After Space the input ends where it ends. That favors a reading
        // that can end there (センセイ over センセイイ, ス over sy), which
        // matters for corrections near the end; farther from it both readings
        // end alike. Scoring the end costs a model evaluation along a new path
        // (about 50-130 ms with zenz-v3.2-small), so it is only done when it
        // may decide whether a correction comes first.
        if isFinal {
            let unresolved = !Self.pendingRomaji(original.reading).isEmpty
            func endScore(_ reading: String) -> Float? {
                guard let ended = lmScore(reading, endsInput: true), let open = lmScore(reading) else {
                    return nil
                }
                return ended - open
            }
            var endOfOriginal: Float??
            var readings: Set<String> = [original.reading]
            for (index, hypothesis) in hypotheses.enumerated() where readings.count <= 2 {
                let margin = hypothesis.score - original.score
                guard readings.insert(hypothesis.reading).inserted,
                      unresolved || (0..<TypoCorrectionPlacement.clearMargin + 2).contains(margin),
                      let edit = Self.edits(from: keys, to: Array(hypothesis.input)).last,
                      edit.ends.typed + configuration.scoringWindow >= keys.count else {
                    continue
                }
                if endOfOriginal == nil {
                    endOfOriginal = endScore(original.reading)
                }
                guard let endOfOriginal = endOfOriginal ?? nil, let end = endScore(hypothesis.reading) else {
                    continue
                }
                hypotheses[index].score += end - endOfOriginal
                hypotheses[index].lmScore += end - endOfOriginal
            }
            hypotheses.sort { $0.score > $1.score }
        }
        return Result(original: original, hypotheses: hypotheses, pendingInput: pendingInput, isFinal: isFinal)
    }

    // MARK: - Keys and typos

    /// The key as the corrector observes it (`canonicalCharacter` upstream).
    static func observedKey(_ element: ComposingText.InputElement) -> Character? {
        let raw: Character? = switch element.piece {
        case .character(let character): character
        case .key(let intention, let input, _): intention ?? input
        case .compositionSeparator: nil
        }
        return raw.map { String($0).lowercased().first ?? $0 }
    }

    static func observedKeys(_ input: some Sequence<ComposingText.InputElement>) -> String {
        String(input.compactMap(observedKey))
    }

    /// Indices of keys that repeat the key before them; dropping one gives the
    /// input without that double press. One per run ("iii" and "ii" each drop
    /// a single "i"), and only letters: "100" and "。。" mean what they say.
    static func repeatedKeyIndices(_ keys: [Character]) -> [Int] {
        var result: [Int] = []
        for index in keys.indices.dropFirst() where keys[index] == keys[index - 1] && keys[index].isASCII && keys[index].isLetter {
            if result.last != index - 1 {
                result.append(index)
            }
        }
        return result
    }

    /// The reading of romaji keys, as the corrector shows it: katakana and any
    /// romaji that is not a kana yet (after Space, a final "n" is "ン").
    static func reading(of keys: [Character], isFinal: Bool) -> String {
        var text = ComposingText()
        text.insertAtCursorPosition(keys.map { .init(character: $0, inputStyle: .mapped(id: .defaultRomanToKana)) })
        if isFinal {
            text.insertAtCursorPosition([.init(piece: .compositionSeparator, inputStyle: .mapped(id: .defaultRomanToKana))])
        }
        return text.convertTarget.toKatakana()
    }

    /// Trailing ASCII letters: romaji that has not become kana yet.
    static func pendingRomaji(_ text: String) -> Substring {
        text[(text.lastIndex { !($0.isASCII && $0.isLetter) }.map(text.index(after:)) ?? text.startIndex)...]
    }

    /// One typo, as an edit of the typed keys.
    enum Edit: Equatable {
        /// The key at the index was meant to be this one.
        case substitute(Int, Character)
        /// The key at the index is extra.
        case delete(Int)
        /// A key is missing before the index (the corrector never assumes this).
        case insert(Int, Character)
        /// The keys at the index and the next one are swapped.
        case swap(Int)

        /// Index just past the edit in the typed keys and in the edited ones.
        var ends: (typed: Int, edited: Int) {
            switch self {
            case .substitute(let index, _): (index + 1, index + 1)
            case .delete(let index): (index + 1, index)
            case .insert(let index, _): (index, index + 1)
            case .swap(let index): (index + 2, index + 2)
            }
        }

        func applied(to keys: [Character]) -> [Character] {
            var keys = keys
            switch self {
            case .substitute(let index, let key): keys[index] = key
            case .delete(let index): keys.remove(at: index)
            case .insert(let index, let key): keys.insert(key, at: index)
            case .swap(let index): keys.swapAt(index, index + 1)
            }
            return keys
        }
    }

    /// The typos that turn `typed` into `meant`, from an optimal string
    /// alignment (Damerau-Levenshtein without overlapping edits).
    static func edits(from typed: [Character], to meant: [Character]) -> [Edit] {
        let a = typed, b = meant
        var table = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { table[i][0] = i }
        for j in 0...b.count { table[0][j] = j }
        func swapped(_ i: Int, _ j: Int) -> Bool {
            i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] && a[i - 1] != a[i - 2]
        }
        for i in a.indices.map({ $0 + 1 }) {
            for j in b.indices.map({ $0 + 1 }) {
                table[i][j] = min(table[i - 1][j] + 1, table[i][j - 1] + 1, table[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if swapped(i, j) {
                    table[i][j] = min(table[i][j], table[i - 2][j - 2] + 1)
                }
            }
        }
        var result: [Edit] = []
        var i = a.count, j = b.count
        while i > 0 || j > 0 {
            if swapped(i, j), table[i][j] == table[i - 2][j - 2] + 1 {
                result.append(.swap(i - 2))
                i -= 2
                j -= 2
            } else if i > 0, j > 0, table[i][j] == table[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1) {
                if a[i - 1] != b[j - 1] {
                    result.append(.substitute(i - 1, b[j - 1]))
                }
                i -= 1
                j -= 1
            } else if i > 0, table[i][j] == table[i - 1][j] + 1 {
                result.append(.delete(i - 1))
                i -= 1
            } else {
                result.append(.insert(i, b[j - 1]))
                j -= 1
            }
        }
        return result.reversed()
    }

    static func editCount(_ a: String, _ b: String) -> Int {
        edits(from: Array(a), to: Array(b)).count
    }

    /// Key positions of a Mac keyboard in key widths, as the converter's
    /// corrector uses them for `.roman2kana`; keys up to 1.65 apart are
    /// neighbors. Copied from AzooKeyKanaKanjiConverter's
    /// `KeyTopology.macOSStandardQwerty` (MIT, Copyright (c) 2023 Miwa / Ensan).
    private static let keyPositions: [Character: (x: Float, y: Float)] = [
        "1": (-1.0, 0), "2": (0.25, 0), "3": (1.25, 0), "4": (2.25, 0), "5": (3.25, 0), "6": (4.25, 0), "7": (5.25, 0), "8": (6.25, 0), "9": (7.25, 0), "0": (8.25, 0), "-": (9.25, 0), "^": (10.25, 0),
        "q": (0.00, 1), "w": (1.00, 1), "e": (2.00, 1), "r": (3.00, 1), "t": (4.00, 1), "y": (5.00, 1), "u": (6.00, 1), "i": (7.00, 1), "o": (8.00, 1), "p": (9.00, 1), "@": (10.00, 1), "[": (11.00, 1),
        "a": (0.25, 2), "s": (1.25, 2), "d": (2.25, 2), "f": (3.25, 2), "g": (4.25, 2), "h": (5.25, 2), "j": (6.25, 2), "k": (7.25, 2), "l": (8.25, 2), ";": (9.25, 2), "]": (10.25, 2),
        "z": (0.80, 3), "x": (1.80, 3), "c": (2.80, 3), "v": (3.80, 3), "b": (4.80, 3), "n": (5.80, 3), "m": (6.80, 3), ",": (7.80, 3), ".": (8.80, 3), "/": (9.80, 3), "_": (10.80, 3),
    ]

    /// Distance between two neighboring keys, nil when they are not neighbors.
    static func neighborDistance(_ a: Character, _ b: Character) -> Float? {
        guard a != b, let p = keyPositions[a], let q = keyPositions[b] else {
            return nil
        }
        let distance = ((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)).squareRoot()
        return distance <= 1.65 ? distance : nil
    }

    /// What the corrector's channel charges for one typo (its default alpha 2,
    /// beta 3 and gamma 2), or nil for a typo it never assumes.
    func cost(of edit: Edit, in keys: [Character]) -> Float? {
        switch edit {
        case .substitute(let index, let key):
            return Self.neighborDistance(keys[index], key).map { 2.0 * $0 }
        case .delete(let index):
            guard index > 0 else {
                return nil
            }
            if keys[index] == keys[index - 1] {
                return configuration.repeatedKeyCost
            }
            return Self.neighborDistance(keys[index - 1], keys[index]).map { 3.0 * $0 }
        case .swap:
            return 2.0
        case .insert:
            return nil
        }
    }
}
