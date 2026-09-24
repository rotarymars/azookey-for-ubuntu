import AzooKeyCore
import AzooKeyIBusShim
import Foundation

/// Process-wide state shared by all engine instances.
@MainActor
final class App {
    static let shared = App()

    let settingsStore = SettingsStore()
    /// Loads the dictionary on first use rather than at process start.
    private(set) lazy var host = ConverterHost()
    private var controllers: [ObjectIdentifier: EngineController] = [:]
    private var learningCommitSource: UInt32 = 0

    private init() {
        Config.settings = settingsStore.settings
    }

    func register(_ controller: EngineController) {
        controllers[ObjectIdentifier(controller)] = controller
    }

    func unregister(_ controller: EngineController) {
        controllers[ObjectIdentifier(controller)] = nil
    }

    /// Picks up edits and requests from the settings window.
    func reloadSettingsIfChanged() {
        if settingsStore.reloadIfChanged() {
            settingsDidChange()
        }
        let resetRequest = Paths.resetLearningRequestFile
        if FileManager.default.fileExists(atPath: resetRequest.path) {
            try? FileManager.default.removeItem(at: resetRequest)
            cancelLearningCommit()
            host.resetLearningData()
            Log.info("learning data reset")
        }
    }

    func updateSettings(_ change: (inout Settings) -> Void) {
        settingsStore.update(change)
        settingsDidChange()
    }

    private func settingsDidChange() {
        Config.settings = settingsStore.settings
        Log.info("settings reloaded")
        for controller in controllers.values {
            controller.settingsDidChange()
        }
    }

    /// Learning data is written to disk shortly after the last commit, or
    /// right away when focus leaves or the process exits.
    func scheduleLearningCommit() {
        guard learningCommitSource == 0 else {
            return
        }
        learningCommitSource = azk_timeout_add(2000, { _ in
            MainActor.assumeIsolated {
                App.shared.learningCommitSource = 0
                App.shared.commitLearningData()
            }
        }, nil)
    }

    func commitLearningData() {
        cancelLearningCommit()
        host.commitLearningData()
    }

    private func cancelLearningCommit() {
        if learningCommitSource != 0 {
            azk_source_remove(learningCommitSource)
            learningCommitSource = 0
        }
    }

    var setupCommand: String? {
        let path = Paths.executableDirectory.appendingPathComponent("ibus-setup-azookey").path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
}

/// Drives one IBus engine instance (IBus creates one per input context).
@MainActor
final class EngineController {
    private let engine: OpaquePointer
    private let session: InputSession
    private var contentPurpose: UInt32 = 0
    private var lastSnapshot: InputSession.Snapshot?

    /// IBus input purposes (ibustypes.h) where conversion must stay off.
    private static let passwordPurposes: Set<UInt32> = [8, 9]  // PASSWORD, PIN

    init(engine: OpaquePointer) {
        self.engine = engine
        self.session = App.shared.host.makeSession()
        App.shared.register(self)
    }

    func destroy() {
        session.close()
        App.shared.unregister(self)
    }

    // MARK: IBus callbacks

    func processKey(keyval: UInt32, keycode: UInt32, state: UInt32, unicode: UInt32) -> Bool {
        let event = LinuxKeyEvent(keyval: keyval, keycode: keycode, state: state, unicode: unicode)
        if event.isRelease || event.isModifierKey || Self.passwordPurposes.contains(contentPurpose) {
            return false
        }
        let start = ContinuousClock.now
        updateTextContext()
        let languageBefore = session.inputLanguage
        let result = session.handleKey(event)
        let converted = ContinuousClock.now
        apply(result)
        if session.inputLanguage != languageBefore {
            registerProperties()
        }
        Log.debug("key \(String(keyval, radix: 16)): convert \(converted - start), render \(ContinuousClock.now - converted)")
        return result.handled
    }

    func focusIn() {
        App.shared.reloadSettingsIfChanged()
        session.activate()
        registerProperties()
        render(force: true)
    }

    func focusOut() {
        // The client commits the visible preedit itself (preedit mode COMMIT).
        session.reset()
        lastSnapshot = nil
        azk_engine_hide_lookup(engine)
        azk_engine_set_auxiliary_text(engine, nil)
        App.shared.commitLearningData()
    }

    func reset() {
        session.reset()
        render(force: true)
    }

    func enable() {
        // Tells the client we want surrounding text (see ibus_engine_get_surrounding_text).
        var cursor: UInt32 = 0
        var anchor: UInt32 = 0
        azk_free(azk_engine_dup_surrounding_text(engine, &cursor, &anchor))
        registerProperties()
    }

    func disable() {
        // Leave the preedit alone: ibus-daemon commits it when the engine is
        // switched away (preedit mode COMMIT), and clearing it here could race.
        session.reset()
        lastSnapshot = nil
        azk_engine_hide_lookup(engine)
        azk_engine_set_auxiliary_text(engine, nil)
        App.shared.commitLearningData()
    }

    func setContentType(purpose: UInt32, hints: UInt32) {
        contentPurpose = purpose
    }

    func propertyActivate(name: String, state: UInt32) {
        let checked = state == 1  // PROP_STATE_CHECKED
        switch name {
        case "InputMode.Hiragana" where checked:
            apply(session.setInputLanguage(.japanese))
            registerProperties()
        case "InputMode.Direct" where checked:
            apply(session.setInputLanguage(.english))
            registerProperties()
        case "LiveConversion":
            App.shared.updateSettings { $0.liveConversion = checked }
        case "Zenzai":
            App.shared.updateSettings { $0.zenzaiEnabled = checked }
        case let name where name.hasPrefix("Learning.") && checked:
            if let learning = Settings.Learning(rawValue: String(name.dropFirst("Learning.".count))) {
                App.shared.updateSettings { $0.learning = learning }
            }
        case "Setup":
            if let command = App.shared.setupCommand {
                _ = azk_spawn_command_line(command)
            }
        default:
            break
        }
    }

    func candidateClicked(index: UInt32) {
        guard case .selecting(_, let selected) = lastSnapshot?.candidateWindow else {
            return
        }
        let pageSize = Config.settings.candidatePageSize
        apply(session.submitCandidate(at: selected / pageSize * pageSize + Int(index)))
    }

    func moveSelection(by offset: Int) {
        session.moveCandidateSelection(by: offset)
        render()
    }

    var pageSize: Int {
        Config.settings.candidatePageSize
    }

    func settingsDidChange() {
        session.applySettings()
        registerProperties()
        render()
    }

    // MARK: Output

    private func apply(_ result: InputSession.KeyResult) {
        for text in result.commits {
            azk_engine_commit_text(engine, text)
        }
        if !result.commits.isEmpty, Config.settings.learning == .inputAndOutput {
            App.shared.scheduleLearningCommit()
        }
        render(force: !result.commits.isEmpty)
    }

    private func updateTextContext() {
        var cursor: UInt32 = 0
        var anchor: UInt32 = 0
        guard let pointer = azk_engine_dup_surrounding_text(engine, &cursor, &anchor) else {
            session.setTextContext(left: nil, right: nil)
            return
        }
        let scalars = Array(String(cString: pointer).unicodeScalars)
        azk_free(pointer)
        let split = min(Int(cursor), scalars.count)
        var left = String.UnicodeScalarView()
        left.append(contentsOf: scalars[..<split])
        var right = String.UnicodeScalarView()
        right.append(contentsOf: scalars[split...])
        session.setTextContext(left: String(left), right: String(right))
    }

    private func render(force: Bool = false) {
        let snapshot = session.snapshot()
        if !force, snapshot == lastSnapshot {
            return
        }
        lastSnapshot = snapshot

        if snapshot.preedit.segments.isEmpty {
            azk_engine_hide_preedit(engine)
        } else {
            azk_engine_preedit_begin(engine)
            for segment in snapshot.preedit.segments {
                azk_engine_preedit_append(engine, segment.text, segment.style == .focused ? AZK_PREEDIT_HIGHLIGHT : AZK_PREEDIT_UNDERLINE)
            }
            azk_engine_preedit_end(engine, UInt32(snapshot.preedit.cursor))
        }

        switch snapshot.candidateWindow {
        case .hidden:
            azk_engine_hide_lookup(engine)
            azk_engine_set_auxiliary_text(engine, nil)
        case .preview(let candidate):
            azk_engine_lookup_begin(engine, 1, false)
            azk_engine_lookup_append(engine, candidate.text, nil)
            azk_engine_lookup_end(engine, 0, false)
            azk_engine_set_auxiliary_text(engine, nil)
        case .selecting(let candidates, let selected):
            azk_engine_lookup_begin(engine, UInt32(pageSize), true)
            for candidate in candidates {
                azk_engine_lookup_append(engine, candidate.text, candidate.annotation)
            }
            azk_engine_lookup_end(engine, UInt32(selected), true)
            azk_engine_set_auxiliary_text(engine, "\(selected + 1) / \(candidates.count)")
        }
    }

    private func registerProperties() {
        let settings = Config.settings
        let japanese = session.inputLanguage == .japanese
        azk_engine_props_begin(engine)
        azk_engine_props_append(engine, nil, "InputMode", AZK_PROP_MENU,
                                japanese ? "入力モード: ひらがな" : "入力モード: 英数", japanese ? "あ" : "A", "入力モード", false)
        azk_engine_props_append(engine, "InputMode", "InputMode.Hiragana", AZK_PROP_RADIO, "ひらがな", "あ", nil, japanese)
        azk_engine_props_append(engine, "InputMode", "InputMode.Direct", AZK_PROP_RADIO, "英数 (直接入力)", "A", nil, !japanese)
        azk_engine_props_append(engine, nil, "LiveConversion", AZK_PROP_TOGGLE, "ライブ変換", nil,
                                "入力中に変換結果を表示する", settings.liveConversion)
        azk_engine_props_append(engine, nil, "Zenzai", AZK_PROP_TOGGLE, "Zenzai (ニューラル変換)", nil,
                                "zenzモデルで変換精度を高める", settings.zenzaiEnabled)
        azk_engine_props_append(engine, nil, "Learning", AZK_PROP_MENU, "学習: \(settings.learning.label)", nil, "学習", false)
        for learning in Settings.Learning.allCases {
            azk_engine_props_append(engine, "Learning", "Learning.\(learning.rawValue)", AZK_PROP_RADIO,
                                    learning.label, nil, nil, settings.learning == learning)
        }
        if App.shared.setupCommand != nil {
            azk_engine_props_append(engine, nil, "Setup", AZK_PROP_NORMAL, "設定…", nil, nil, false)
        }
        azk_engine_props_register(engine)
    }
}

extension Settings.Learning {
    var label: String {
        switch self {
        case .inputAndOutput: "学習する"
        case .onlyOutput: "学習結果を使うだけ (更新しない)"
        case .nothing: "学習しない"
        }
    }
}
