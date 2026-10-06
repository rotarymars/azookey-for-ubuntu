@testable import AzooKeyCore
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

@Suite struct TypoCorrectionPlacementTests {
    /// The typed input has 7 keys; candidates covering all of them convert the whole input.
    func candidate(_ text: String, covering count: Int = 7) -> Candidate {
        Candidate(text: text, value: 0, composingCount: .inputCount(count), lastMid: 0, data: [])
    }

    func coversWholeInput(_ candidate: Candidate) -> Bool {
        candidate.composingCount == .inputCount(7)
    }

    func insert(_ correction: String, _ placement: TypoCorrectionPlacement, into texts: [Candidate]) -> [String] {
        placement.inserting(candidate(correction), into: texts, coversWholeInput: coversWholeInput).map(\.text)
    }

    @Test func clearlyBetterCorrectionsComeFirst() {
        // Margins measured with zenz-v3.2-small (fine-tuned): senseii after Space,
        // gakkouniiiku, and an ordinary typo in a sentence.
        #expect(TypoCorrectionPlacement(margin: 4.41) == .first)
        #expect(TypoCorrectionPlacement(margin: 6.08) == .first)
        #expect(TypoCorrectionPlacement(margin: 21.2) == .first)
        #expect(TypoCorrectionPlacement(margin: TypoCorrectionPlacement.clearMargin) == .first)
    }

    @Test func weakerCorrectionsComeSecond() {
        // senseii with a fine-tuned zenz-v3.1-xsmall, and the best-scoring
        // correction of a correctly typed input (arigatougozaimasu).
        #expect(TypoCorrectionPlacement(margin: 1.41) == .second)
        #expect(TypoCorrectionPlacement(margin: 0.23) == .second)
        #expect(TypoCorrectionPlacement(margin: TypoCorrectionPlacement.clearMargin - 0.01) == .second)
    }

    @Test func firstGoesBeforeEverything() {
        #expect(insert("先生", .first, into: [candidate("先生い"), candidate("先生位")]) == ["先生", "先生い", "先生位"])
        #expect(insert("先生", .first, into: []) == ["先生"])
    }

    @Test func secondGoesRightAfterTheFirstCandidate() {
        #expect(insert("先生", .second, into: [candidate("先生い"), candidate("先生位")]) == ["先生い", "先生", "先生位"])
        #expect(insert("先生", .second, into: [candidate("先生い")]) == ["先生い", "先生"])
        #expect(insert("先生", .second, into: []) == ["先生"])
    }

    @Test func nothingIsAddedWhenTheFirstCandidateAlreadyReadsTheSame() {
        let candidates = [candidate("学校に行く"), candidate("学校にいいく")]
        #expect(insert("学校に行く", .first, into: candidates) == ["学校に行く", "学校にいいく"])
        #expect(insert("学校に行く", .second, into: candidates) == ["学校に行く", "学校にいいく"])
    }

    @Test func aFirstCandidateForPartOfTheInputIsReplaced() {
        // "先生" for せんせい of せんせいい would leave い behind; the correction
        // converts all of it.
        let candidates = [candidate("先生", covering: 6), candidate("先生い"), candidate("先生位")]
        let result = TypoCorrectionPlacement.second.inserting(candidate("先生"), into: candidates, coversWholeInput: coversWholeInput)
        #expect(result.map(\.text) == ["先生", "先生い", "先生位"])
        #expect(result.first.map(coversWholeInput) == true)
    }

    @Test func laterCandidatesReadingTheSameAreDropped() {
        let candidates = [candidate("先生い"), candidate("先生位"), candidate("先生", covering: 6)]
        #expect(insert("先生", .first, into: candidates) == ["先生", "先生い", "先生位"])
        #expect(insert("先生", .second, into: candidates) == ["先生い", "先生", "先生位"])
    }
}

@Suite struct TypoCorrectorTests {
    @Test func keysPressedTwice() {
        #expect(TypoCorrector.repeatedKeyIndices(Array("senseii")) == [6])
        // One variant per run of the same key.
        #expect(TypoCorrector.repeatedKeyIndices(Array("sennnsei")) == [3])
        #expect(TypoCorrector.repeatedKeyIndices(Array("ssensei")) == [1])
        #expect(TypoCorrector.repeatedKeyIndices(Array("gakkouniiiku")) == [3, 8])
        // Digits and punctuation mean what they say.
        #expect(TypoCorrector.repeatedKeyIndices(Array("100。。")).isEmpty)
    }

    @Test func typosBetweenTypedAndMeantKeys() {
        #expect(TypoCorrector.edits(from: Array("arigaotu"), to: Array("arigatou")) == [.swap(5)])
        #expect(TypoCorrector.edits(from: Array("arigatoi"), to: Array("arigatou")) == [.substitute(7, "u")])
        let doubled = TypoCorrector.edits(from: Array("senseii"), to: Array("sensei"))
        #expect(doubled.count == 1)
        #expect(doubled.first.map { String($0.applied(to: Array("senseii"))) } == "sensei")
        // A correction that also rewrites 何時 into 何 assumes two typos.
        #expect(TypoCorrector.editCount("kaogihananji", "kaigihanani") == 2)
        #expect(TypoCorrector.editCount("sensei", "sensei") == 0)
    }

    @Test func typoCostsFollowTheKeyboard() {
        let corrector = TypoCorrector()
        // i and u are neighbors one key apart; a is far from i.
        #expect(corrector.cost(of: .substitute(7, "u"), in: Array("arigatoi")) == 2)
        #expect(corrector.cost(of: .substitute(7, "a"), in: Array("arigatoi")) == nil)
        #expect(corrector.cost(of: .delete(6), in: Array("senseii")) == corrector.configuration.repeatedKeyCost)
        #expect(corrector.cost(of: .swap(5), in: Array("arigaotu")) == 2)
        // Nothing before the first key makes it an extra press.
        #expect(corrector.cost(of: .delete(0), in: Array("qatashi")) == nil)
        #expect(corrector.cost(of: .insert(2, "a"), in: Array("arigatou")) == nil)
    }

    @Test func readingsAsTheCorrectorShowsThem() {
        #expect(TypoCorrector.reading(of: Array("sensei"), isFinal: false) == "センセイ")
        // While typing a final n may still become な; after Space it is ン.
        #expect(TypoCorrector.reading(of: Array("sen"), isFinal: false) == "セn")
        #expect(TypoCorrector.reading(of: Array("sen"), isFinal: true) == "セン")
        #expect(TypoCorrector.pendingRomaji("センセイk") == "k")
        #expect(TypoCorrector.pendingRomaji("センセイ").isEmpty)
    }

    @Test func correctedInputKeepsWhatIsStillBeingTyped() {
        let roman = InputStyle.mapped(id: .defaultRomanToKana)
        let original = TypoCorrector.Hypothesis(input: "senseii", reading: "センセイイ", score: -13, lmScore: -13, channelCost: 0)
        let corrected = TypoCorrector.Hypothesis(input: "sensei", reading: "センセイ", score: -9, lmScore: -6, channelCost: 3)
        let typing = TypoCorrector.Result(
            original: original, hypotheses: [corrected, original], pendingInput: [.init(character: "h", inputStyle: roman)], isFinal: false
        )
        #expect(typing.correction == corrected)
        #expect(typing.margin == 4)
        #expect(typing.composingText(for: corrected).convertTarget == "せんせいh")
        let final = TypoCorrector.Result(original: original, hypotheses: [corrected, original], pendingInput: [], isFinal: true)
        #expect(final.composingText(for: corrected).input.last?.piece == .compositionSeparator)
        // The typed input itself is no correction.
        let none = TypoCorrector.Result(original: original, hypotheses: [original, corrected], pendingInput: [], isFinal: true)
        #expect(none.correction == nil)
        #expect(none.margin == nil)
    }

    @Test func onlyRomajiInputIsCorrected() {
        var romaji = ComposingText()
        romaji.insertAtCursorPosition("sensei", inputStyle: .mapped(id: .defaultRomanToKana))
        romaji.insertAtCursorPosition([.init(piece: .compositionSeparator, inputStyle: .mapped(id: .defaultRomanToKana))])
        #expect(TypoCorrector.isRomajiInput(romaji))
        var azik = ComposingText()
        azik.insertAtCursorPosition("sensei", inputStyle: .mapped(id: .defaultAZIK))
        #expect(!TypoCorrector.isRomajiInput(azik))
        var direct = ComposingText()
        direct.insertAtCursorPosition("せんせい", inputStyle: .direct)
        #expect(!TypoCorrector.isRomajiInput(direct))
    }

    @Test func onByDefaultAndSavedInSettings() throws {
        #expect(Settings().typoCorrection)
        #expect(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)).typoCorrection)
        let off = try JSONDecoder().decode(Settings.self, from: Data(#"{"typoCorrection": false}"#.utf8))
        #expect(!off.typoCorrection)
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(off)) as? [String: Any]
        #expect(saved?["typoCorrection"] as? Bool == false)
    }

    @Test func searchBreadthIsASettingWithinLimits() throws {
        #expect(Settings().typoCorrectionBeamSize == TypoCorrector.Configuration().beamSize)
        let wide = try JSONDecoder().decode(Settings.self, from: Data(#"{"typoCorrectionBeamSize": 6}"#.utf8))
        #expect(wide.typoCorrectionBeamSize == 6)
        let tooWide = try JSONDecoder().decode(Settings.self, from: Data(#"{"typoCorrectionBeamSize": 99}"#.utf8))
        #expect(tooWide.typoCorrectionBeamSize == 8)
        let zero = try JSONDecoder().decode(Settings.self, from: Data(#"{"typoCorrectionBeamSize": 0}"#.utf8))
        #expect(zero.typoCorrectionBeamSize == 1)
    }
}
