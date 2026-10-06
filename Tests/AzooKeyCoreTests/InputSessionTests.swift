import AzooKeyCore
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

/// A zenz model fetched by `make` into build/models, for the tests that need
/// Zenzai; they are skipped without one.
private let zenzTestModel: URL? = {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return ["zenz-v3.2-xsmall", "zenz-v3.2-small"]
        .map { root.appendingPathComponent("build/models/\($0)/\(Paths.modelFileName)") }
        .first { FileManager.default.fileExists(atPath: $0.path) }
}()

/// Drives an `InputSession` with key events the way the IBus engine does.
@MainActor
final class Typist {
    let session: InputSession
    private(set) var committed = ""

    init(_ session: InputSession) {
        self.session = session
    }

    @discardableResult
    func press(_ keyval: UInt32, _ state: UInt32 = 0) -> Bool {
        let result = session.handleKey(LinuxKeyEvent(keyval: keyval, state: state))
        committed += result.commits.joined()
        return result.handled
    }

    func type(_ text: String) {
        for scalar in text.unicodeScalars {
            press(scalar.value)
        }
    }

    func submit(candidate text: String) throws {
        guard case .selecting(let candidates, _) = session.snapshot().candidateWindow else {
            Issue.record("candidate window is not open")
            return
        }
        let index = try #require(candidates.firstIndex { $0.text == text }, "\(text) not in \(candidates.map(\.text))")
        committed += session.submitCandidate(at: index).commits.joined()
    }

    var preedit: String {
        session.snapshot().preedit.text
    }

    var candidates: [String] {
        if case .selecting(let candidates, _) = session.snapshot().candidateWindow {
            return candidates.map(\.text)
        }
        return []
    }
}

@Suite(.serialized) @MainActor final class InputSessionTests {
    /// Learning directories created by this test; removed when it finishes.
    private var directories: [URL] = []

    deinit {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Fresh settings and learning directory; Zenzai is off so the dictionary
    /// alone decides and results are deterministic.
    func makeHost(_ configure: (inout Settings) -> Void = { _ in }, dataDirectory: URL? = nil) -> ConverterHost {
        let directory = dataDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("azookey-tests-\(UUID().uuidString)", isDirectory: true)
        directories.append(directory)
        setenv("AZOOKEY_IBUS_DATA_DIR", directory.path, 1)
        var settings = Settings()
        settings.zenzaiEnabled = false
        configure(&settings)
        Config.settings = settings
        return ConverterHost()
    }

    @Test func composingShowsHiraganaAndAPreview() {
        let typist = Typist(makeHost().makeSession())
        typist.type("kyouhaiitenki")
        let snapshot = typist.session.snapshot()
        #expect(snapshot.preedit.text == "きょうはいいてんき")
        #expect(snapshot.candidateWindow == .preview(.init(text: "今日はいい天気", annotation: nil)))
        #expect(typist.committed.isEmpty)
    }

    @Test func spaceConvertsAndEnterCommits() {
        let typist = Typist(makeHost().makeSession())
        typist.type("kyouhaiitenki")
        typist.press(Keysym.space)
        #expect(typist.session.inputState == .previewing)
        #expect(typist.preedit == "今日はいい天気")
        typist.press(Keysym.returnKey)
        #expect(typist.committed == "今日はいい天気")
        #expect(typist.session.inputState == .none)
        #expect(typist.session.snapshot() == .empty)
    }

    @Test func secondSpaceOpensTheCandidateList() {
        let typist = Typist(makeHost().makeSession())
        typist.type("kisha")
        typist.press(Keysym.space)
        typist.press(Keysym.space)
        #expect(typist.session.inputState == .selecting)
        #expect(typist.candidates.contains("記者"))
        #expect(typist.candidates.contains("汽車"))
    }

    @Test func numberKeySelectsFromTheList() throws {
        let typist = Typist(makeHost().makeSession())
        typist.type("kisha")
        typist.press(Keysym.space)
        typist.press(Keysym.space)
        let second = try #require(typist.candidates.dropFirst().first)
        typist.press(0x32)  // "2"
        #expect(typist.committed == second)
    }

    @Test func enterWhileComposingCommitsHiragana() {
        let typist = Typist(makeHost().makeSession())
        typist.type("kyou.")
        #expect(typist.preedit == "きょう。")
        typist.press(Keysym.returnKey)
        #expect(typist.committed == "きょう。")
    }

    @Test func backspaceAndEscapeEdit() {
        let typist = Typist(makeHost().makeSession())
        typist.type("ka")
        #expect(typist.preedit == "か")
        #expect(typist.press(Keysym.backSpace))
        #expect(typist.session.inputState == .none)
        // With nothing composed, BackSpace belongs to the application.
        #expect(!typist.press(Keysym.backSpace))

        typist.type("abc")
        typist.press(Keysym.escape)
        #expect(typist.preedit.isEmpty)
        #expect(typist.committed.isEmpty)
    }

    @Test func functionKeysCommitKatakana() {
        let typist = Typist(makeHost().makeSession())
        typist.type("kyou")
        typist.press(Keysym.f7)
        #expect(typist.committed == "キョウ")
    }

    @Test func navigationKeysAreSwallowedWhileComposing() {
        let typist = Typist(makeHost().makeSession())
        #expect(!typist.press(Keysym.home))
        typist.type("ka")
        #expect(typist.press(Keysym.home))
        #expect(typist.press(Keysym.delete))
        #expect(typist.preedit == "か")
        // Alt shortcuts still reach the application.
        #expect(!typist.press(0x66, ModifierMask.mod1))
    }

    @Test func englishModePassesKeysThrough() {
        let session = makeHost().makeSession()
        let typist = Typist(session)
        typist.type("ka")
        let result = session.setInputLanguage(.english)
        #expect(result.commits == ["か"])
        #expect(!typist.press(0x61))
        #expect(typist.press(Keysym.henkan))
        #expect(session.inputLanguage == .japanese)
    }

    @Test func liveConversionShowsKanjiWhileTyping() {
        let typist = Typist(makeHost { $0.liveConversion = true }.makeSession())
        typist.type("kyouhaiitenki")
        #expect(typist.preedit == "今日はいい天気")
        #expect(typist.session.snapshot().candidateWindow == .hidden)
    }

    @Test func fullWidthSpaceWhenIdle() {
        let typist = Typist(makeHost().makeSession())
        #expect(typist.press(Keysym.space))
        #expect(typist.committed == "　")
    }

    // MARK: Learning

    @Test func learningPromotesChosenCandidateAcrossRestarts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("azookey-learning-\(UUID().uuidString)")
        let host = makeHost({ $0.learning = .inputAndOutput }, dataDirectory: directory)
        let typist = Typist(host.makeSession())
        typist.type("kisha")
        typist.press(Keysym.space)
        #expect(typist.preedit == "記者")
        typist.press(Keysym.space)
        try typist.submit(candidate: "汽車")
        #expect(typist.committed == "汽車")

        // Learned immediately...
        typist.type("kisha")
        typist.press(Keysym.space)
        #expect(typist.preedit == "汽車")
        typist.press(Keysym.escape)
        host.commitLearningData()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("memory").path)
        #expect(!files.isEmpty)

        // ...and after reloading the learning data from disk.
        let restarted = Typist(makeHost({ $0.learning = .inputAndOutput }, dataDirectory: directory).makeSession())
        restarted.type("kisha")
        restarted.press(Keysym.space)
        #expect(restarted.preedit == "汽車")
    }

    @Test func learningCanBeTurnedOff() throws {
        let host = makeHost { $0.learning = .nothing }
        let typist = Typist(host.makeSession())
        typist.type("kisha")
        typist.press(Keysym.space)
        typist.press(Keysym.space)
        try typist.submit(candidate: "汽車")
        typist.type("kisha")
        typist.press(Keysym.space)
        #expect(typist.preedit == "記者")
    }

    // MARK: Typo correction

    func makeZenzaiHost(_ configure: (inout Settings) -> Void = { _ in }) -> ConverterHost {
        makeHost {
            $0.zenzaiEnabled = true
            $0.zenzaiModel = ModelCatalog.localModelID
            $0.zenzaiLocalModelPath = zenzTestModel?.path ?? ""
            $0.zenzaiInferenceLimit = 1
            configure(&$0)
        }
    }

    @Test(.enabled(if: zenzTestModel != nil, "needs a zenz model in build/models"))
    func typoCorrectionComesFirstAndConsumesTheTypo() {
        let typist = Typist(makeZenzaiHost { $0.liveConversion = true }.makeSession())
        typist.type("gakkouniiiku")
        // Live conversion already shows what was meant.
        #expect(typist.preedit == "学校に行く")
        typist.press(Keysym.space)
        #expect(typist.candidates.first == "学校に行く")
        typist.press(Keysym.returnKey)
        #expect(typist.committed == "学校に行く")
        // The extra い went with it.
        #expect(typist.session.snapshot() == .empty)
    }

    @Test(.enabled(if: zenzTestModel != nil, "needs a zenz model in build/models"))
    func typoCorrectionLeavesCorrectInputAlone() throws {
        let typist = Typist(makeZenzaiHost().makeSession())
        typist.type("gakkouniiku")
        typist.press(Keysym.space)
        let report = try #require(typist.session.typoCorrectionReport)
        #expect(report.result?.correction == nil)
        #expect(report.candidateText == nil)
        #expect(typist.preedit == "学校に行く")
    }

    @Test(.enabled(if: zenzTestModel != nil, "needs a zenz model in build/models"))
    func typoCorrectionCanBeTurnedOff() {
        let typist = Typist(makeZenzaiHost {
            $0.liveConversion = true
            $0.typoCorrection = false
        }.makeSession())
        typist.type("gakkouniiiku")
        #expect(typist.preedit != "学校に行く")
        #expect(typist.session.typoCorrectionReport == nil)
    }

    @Test func noTypoCorrectionWithoutZenzai() {
        let typist = Typist(makeHost { $0.liveConversion = true }.makeSession())
        typist.type("gakkouniiiku")
        #expect(typist.session.typoCorrectionReport == nil)
    }

    @Test(.enabled(if: zenzTestModel != nil, "needs a zenz model in build/models"))
    func choosingTheCorrectionLearnsTheCorrectedReading() throws {
        let host = makeZenzaiHost()
        let model = try #require(zenzTestModel)
        let manager = SegmentsManager(
            kanaKanjiConverter: host.converter,
            applicationDirectoryURL: Paths.memoryDirectory,
            containerURL: nil,
            context: .init(
                useZenzai: true,
                resourcesDirectoryURL: model.deletingLastPathComponent(),
                zenzaiWeightURL: model,
                typoCorrectionSessionID: host.converter.createSession()
            )
        )
        let roman = InputStyle.mapped(id: .defaultRomanToKana)
        manager.insertAtCursorPosition("gakkouniiiku", inputStyle: roman)
        manager.insertCompositionSeparator(inputStyle: roman, skipUpdate: true)
        manager.update(requestRichCandidates: true)
        manager.requestSelectingRow(0)
        let candidate = try #require(manager.selectedCandidate)
        #expect(candidate.text == "学校に行く")
        // Committing learns `candidate.data`: the corrected reading, not the typo.
        #expect(candidate.data.map(\.ruby).joined() == "ガッコウニイク")
        manager.prefixCandidateCommited(candidate, leftSideContext: "")
        #expect(manager.isEmpty)
    }

    // MARK: Models

    // Here rather than in ModelCatalogTests: it sets AZOOKEY_IBUS_DATA_DIR, which
    // only this serialized suite may touch.
    @Test func downloadedModelsTakePriority() throws {
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("azookey-models-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: data) }
        setenv("AZOOKEY_IBUS_DATA_DIR", data.path, 1)
        let downloaded = data.appendingPathComponent("models/zenz-v3.1-xsmall", isDirectory: true)
        #expect(Paths.modelDirectory(for: "zenz-v3.1-xsmall") != downloaded)

        try FileManager.default.createDirectory(at: downloaded, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: downloaded.appendingPathComponent(Paths.modelFileName).path, contents: Data())
        #expect(Paths.modelDirectory(for: "zenz-v3.1-xsmall").standardizedFileURL == downloaded.standardizedFileURL)
    }
}
