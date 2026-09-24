import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

/// Owns the dictionary and the Zenzai model for the whole process. Each input
/// context gets its own `InputSession` with a separate conversion session on
/// this shared converter, as in azooKey-Desktop's ConverterServer.
@MainActor
public final class ConverterHost {
    public let converter: KanaKanjiConverter

    public init(converter: KanaKanjiConverter = .withDefaultDictionary()) {
        self.converter = converter
        try? FileManager.default.createDirectory(at: Paths.memoryDirectory, withIntermediateDirectories: true)
    }

    public func makeSession() -> InputSession {
        InputSession(host: self)
    }

    /// Writes pending learning data to disk.
    public func commitLearningData() {
        converter.commitUpdateLearningData()
    }

    public func resetLearningData() {
        converter.resetMemory()
        // resetMemory() only deletes files once a conversion has told the
        // converter where they live, so remove them here as well.
        let fileManager = FileManager.default
        let files = (try? fileManager.contentsOfDirectory(at: Paths.memoryDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent != "user_dictionary" {
            try? fileManager.removeItem(at: file)
        }
    }

    /// The Zenzai model to use under the current settings: the selected one,
    /// else the bundled one, else none (dictionary only).
    var zenzaiModelDirectory: URL? {
        guard Config.settings.zenzaiEnabled else {
            return nil
        }
        let selected = Config.settings.zenzaiModel
        for id in [selected, ModelCatalog.defaultModelID] {
            let directory = Paths.modelDirectory(for: id)
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(Paths.modelFileName).path) {
                if id != selected {
                    Log.error("Zenzai model \(selected) is not installed; using \(id)")
                }
                return directory
            }
        }
        Log.error("no Zenzai model installed; using the dictionary only")
        return nil
    }
}

/// The conversion state of one input context: azooKey's `InputState` machine
/// driving a `SegmentsManager`.
///
/// Adapted from azooKey-Desktop's ConverterServer (ConverterServer+KeyEvent.swift
/// and ConverterServer+Snapshot.swift at b7ec0e4, MIT, Copyright (c) 2025 Miwa
/// Keita) without the XPC transport and the AI-backed suggestion features.
@MainActor
public final class InputSession {
    public struct PreeditSegment: Equatable, Sendable {
        public enum Style: Equatable, Sendable {
            /// Text being typed.
            case plain
            /// The segment currently being converted.
            case focused
            /// Other segments while converting.
            case unfocused
        }

        public var text: String
        public var style: Style
    }

    public struct Preedit: Equatable, Sendable {
        public var segments: [PreeditSegment]
        /// Cursor offset in Unicode scalars, as IBus counts characters.
        public var cursor: Int

        public var text: String {
            segments.map(\.text).joined()
        }

        public static let empty = Preedit(segments: [], cursor: 0)
    }

    public struct Candidate: Equatable, Sendable {
        public var text: String
        /// Label such as "カタカナ" for the extra candidates above the list.
        public var annotation: String?

        public init(text: String, annotation: String? = nil) {
            self.text = text
            self.annotation = annotation
        }
    }

    public enum CandidateWindow: Equatable, Sendable {
        case hidden
        /// The top conversion, shown while typing when live conversion is off.
        case preview(Candidate)
        /// The candidates for the focused segment while converting.
        case selecting([Candidate], selectedIndex: Int)
    }

    public struct Snapshot: Equatable, Sendable {
        public var preedit: Preedit
        public var candidateWindow: CandidateWindow

        public static let empty = Snapshot(preedit: .empty, candidateWindow: .hidden)
    }

    public struct KeyResult: Equatable, Sendable {
        /// False when the key event belongs to the application.
        public var handled: Bool
        /// Text to insert into the application, in order.
        public var commits: [String]
    }

    /// Supplies the text around the cursor to Zenzai.
    private final class TextContext: SegmentManagerDelegate {
        var left: String?
        var right: String?

        func getLeftSideContext(maxCount: Int) -> String? {
            left.map { String($0.suffix(maxCount)) }
        }

        func getRightSideContext(maxCount: Int) -> String? {
            right.map { String($0.prefix(maxCount)) }
        }
    }

    public private(set) var inputState: InputState = .none
    public private(set) var inputLanguage: InputLanguage = .japanese
    private let host: ConverterHost
    private let sessionID: KanaKanjiConverter.ConversionSessionID
    private let textContext = TextContext()
    private var manager: SegmentsManager
    private var managerModelDirectory: URL?
    /// Selection in the candidate list as of the last snapshot; number keys pick
    /// from the page that contains it.
    private var lastSelectionIndex = 0

    init(host: ConverterHost) {
        self.host = host
        self.sessionID = host.converter.createSession()
        self.managerModelDirectory = host.zenzaiModelDirectory
        self.manager = Self.makeManager(host: host, modelDirectory: managerModelDirectory)
        self.manager.delegate = textContext
    }

    /// Releases the conversion session on the shared converter.
    public func close() {
        host.converter.removeSession(sessionID)
    }

    private static func makeManager(host: ConverterHost, modelDirectory: URL?) -> SegmentsManager {
        SegmentsManager(
            kanaKanjiConverter: host.converter,
            applicationDirectoryURL: Paths.memoryDirectory,
            containerURL: nil,
            context: .init(useZenzai: modelDirectory != nil, resourcesDirectoryURL: modelDirectory)
        )
    }

    private func withSession<T>(_ body: () -> T) -> T {
        do {
            return try host.converter.withSession(sessionID, operation: body)
        } catch {
            // Only thrown for unknown sessions, and this session lives as long as self.
            fatalError("conversion session lost: \(error)")
        }
    }

    public var isComposing: Bool {
        !manager.isEmpty || inputState != .none
    }

    /// Updates the text around the cursor (without the preedit) for Zenzai.
    public func setTextContext(left: String?, right: String?) {
        let enabled = Config.settings.useSurroundingText
        textContext.left = enabled ? left : nil
        textContext.right = enabled && ModelCatalog.supportsRightContext(Config.settings.zenzaiModel) ? right : nil
    }

    /// Picks up settings that need a new SegmentsManager (the Zenzai model).
    /// Deferred while composing so the current input is not lost.
    public func applySettings() {
        guard !isComposing else {
            return
        }
        let modelDirectory = host.zenzaiModelDirectory
        if modelDirectory != managerModelDirectory {
            managerModelDirectory = modelDirectory
            manager = Self.makeManager(host: host, modelDirectory: modelDirectory)
            manager.delegate = textContext
        }
    }

    public func activate() {
        withSession {
            manager.activate()
        }
    }

    /// Drops the composition without committing it. The client commits the
    /// visible preedit itself on focus changes (IBUS_ENGINE_PREEDIT_COMMIT).
    public func reset() {
        withSession {
            manager.stopComposition()
        }
        inputState = .none
        applySettings()
    }

    public func deactivate() {
        withSession {
            manager.deactivate()
        }
        inputState = .none
    }

    public func setInputLanguage(_ language: InputLanguage) -> KeyResult {
        var commits: [String] = []
        if language == .english, isComposing {
            withSession {
                let text = manager.commitMarkedText(inputState: inputState)
                if !text.isEmpty {
                    commits.append(text)
                }
            }
            inputState = .none
        }
        inputLanguage = language
        return KeyResult(handled: true, commits: commits)
    }

    // MARK: - Key events

    public func handleKey(_ event: LinuxKeyEvent) -> KeyResult {
        let settings = Config.settings
        let userAction = UserAction.getUserAction(
            linuxEvent: event,
            inputLanguage: inputLanguage,
            typeBackSlash: settings.typeBackSlash,
            typeHalfSpace: settings.typeHalfSpace
        )
        // In English mode with nothing composed, let applications receive
        // ordinary key events instead of committed text (unlike macOS).
        if inputLanguage == .english, inputState == .none {
            switch userAction {
            case .かな, .英数:
                break
            default:
                return KeyResult(handled: false, commits: [])
            }
        }

        let eventCore = event.keyEventCore
        let (clientAction, callback) = inputState.event(
            eventCore: eventCore,
            userAction: userAction,
            inputLanguage: inputLanguage,
            liveConversionEnabled: settings.liveConversion,
            enableDebugWindow: false,
            enableSuggestion: false
        )
        Log.debug("key \(String(event.keyval, radix: 16)) state=\(inputState) action=\(userAction) -> \(clientAction)")

        var commits: [String] = []
        var passToApplication = false
        withSession {
            perform(clientAction, commits: &commits, passToApplication: &passToApplication)
        }
        if passToApplication {
            // Keys such as Home or Delete would move the application's cursor
            // under the preedit, so swallow them while composing.
            if inputState != .none, case .unknown = userAction, !eventCore.modifierFlags.contains(.command) {
                return KeyResult(handled: true, commits: commits)
            }
            return KeyResult(handled: false, commits: commits)
        }
        inputState = nextState(after: callback)
        return KeyResult(handled: true, commits: commits)
    }

    private func nextState(after callback: ClientActionCallback) -> InputState {
        switch callback {
        case .fallthrough:
            inputState
        case .transition(let state):
            state
        case .basedOnBackspace(let ifIsEmpty, let ifIsNotEmpty),
             .basedOnSubmitCandidate(let ifIsEmpty, let ifIsNotEmpty):
            manager.isEmpty ? ifIsEmpty : ifIsNotEmpty
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func perform(_ action: ClientAction, commits: inout [String], passToApplication: inout Bool) {
        let inputStyle: KanaKanjiConverterModule.InputStyle = inputLanguage == .english ? .direct : Config.settings.inputStyle.inputStyle
        let leftSideContext = textContext.getLeftSideContext(maxCount: 30)
        switch action {
        case .consume:
            break
        case .fallthrough:
            passToApplication = true
        case .showCandidateWindow:
            manager.requestSetCandidateWindowState(visible: true)
        case .hideCandidateWindow:
            manager.requestSetCandidateWindowState(visible: false)
        case .appendToMarkedText(let text):
            manager.insertAtCursorPosition(text, inputStyle: inputStyle)
        case .appendPieceToMarkedText(let pieces):
            manager.insertAtCursorPosition(pieces: pieces, inputStyle: inputStyle)
        case .insertWithoutMarkedText(let text):
            commits.append(text)
        case .removeLastMarkedText:
            manager.deleteBackwardFromCursorPosition()
            manager.requestResettingSelection()
        case .commitMarkedText:
            commitMarkedText(into: &commits)
        case .editSegment(let count):
            manager.editSegment(count: count)
        case .enterFirstCandidatePreviewMode:
            manager.insertCompositionSeparator(inputStyle: inputStyle, skipUpdate: false)
            manager.requestSetCandidateWindowState(visible: false)
        case .enterCandidateSelectionMode:
            manager.insertCompositionSeparator(inputStyle: inputStyle, skipUpdate: true)
            manager.update(requestRichCandidates: true)
        case .submitSelectedCandidate:
            submitSelectedCandidate(leftSideContext: leftSideContext, into: &commits)
        case .selectNextCandidate:
            manager.requestSelectingNextCandidate()
        case .selectPrevCandidate:
            manager.requestSelectingPrevCandidate()
        case .selectNumberCandidate(let number):
            let pageSize = Config.settings.candidatePageSize
            let pageStart = lastSelectionIndex / pageSize * pageSize
            manager.requestSelectingRow(pageStart + number - 1)
            submitSelectedCandidate(leftSideContext: leftSideContext, into: &commits)
            manager.requestResettingSelection()
        case .selectInputLanguage(let language):
            inputLanguage = language
        case .commitMarkedTextAndSelectInputLanguage(let language):
            commitMarkedText(into: &commits)
            inputLanguage = language
        case .commitMarkedTextAndAppendToMarkedText(let text):
            commitMarkedText(into: &commits)
            manager.insertAtCursorPosition(text, inputStyle: inputStyle)
        case .commitMarkedTextAndAppendPieceToMarkedText(let pieces):
            commitMarkedText(into: &commits)
            manager.insertAtCursorPosition(pieces: pieces, inputStyle: inputStyle)
        case .enableDebugWindow:
            manager.requestDebugWindowMode(enabled: true)
        case .disableDebugWindow:
            manager.requestDebugWindowMode(enabled: false)
        case .forgetMemory:
            manager.forgetMemory()
        case .submitHiraganaCandidate:
            submitTransformedCandidate(.hiragana, leftSideContext: leftSideContext, into: &commits)
        case .submitKatakanaCandidate:
            submitTransformedCandidate(.katakana, leftSideContext: leftSideContext, into: &commits)
        case .submitHankakuKatakanaCandidate:
            submitTransformedCandidate(.halfWidthKatakana, leftSideContext: leftSideContext, into: &commits)
        case .submitFullWidthRomanCandidate:
            submitTransformedCandidate(.fullWidthRoman, leftSideContext: leftSideContext, into: &commits)
        case .submitHalfWidthRomanCandidate:
            submitTransformedCandidate(.halfWidthRoman, leftSideContext: leftSideContext, into: &commits)
        case .acceptPredictionCandidate:
            manager.acceptPredictionCandidate()
        case .submitUnicodeInput(let codePoint):
            if let value = UInt32(codePoint, radix: 16), let scalar = Unicode.Scalar(value) {
                commits.append(String(Character(scalar)))
            }
        case .submitSelectedCandidateAndEnterUnicodeInputMode:
            submitSelectedCandidate(leftSideContext: leftSideContext, into: &commits)
            if !manager.isEmpty {
                commits.append(manager.convertTarget)
                manager.stopComposition()
            }
        case .stopComposition:
            manager.stopComposition()
        case .enterUnicodeInputMode, .appendToUnicodeInput, .removeLastUnicodeInput, .cancelUnicodeInput:
            // The code point lives in `InputState.unicodeInput` itself.
            break
        case .requestPredictiveSuggestion, .requestReplaceSuggestion, .selectNextReplaceSuggestionCandidate,
             .selectPrevReplaceSuggestionCandidate, .submitReplaceSuggestionCandidate, .hideReplaceSuggestionWindow,
             .showPromptInputWindow, .transformSelectedText:
            // AI-backed features of azooKey-Desktop; never requested because
            // suggestions are disabled.
            break
        }
    }

    private func commitMarkedText(into commits: inout [String]) {
        let text = manager.commitMarkedText(inputState: inputState)
        if !text.isEmpty {
            commits.append(text)
        }
    }

    private func submitSelectedCandidate(leftSideContext: String?, into commits: inout [String]) {
        guard let candidate = manager.selectedCandidate else {
            return
        }
        manager.prefixCandidateCommited(candidate, leftSideContext: leftSideContext ?? "")
        commits.append(candidate.text)
    }

    private enum Transform {
        case hiragana, katakana, halfWidthKatakana, fullWidthRoman, halfWidthRoman
    }

    private func submitTransformedCandidate(_ transform: Transform, leftSideContext: String?, into commits: inout [String]) {
        let candidate = switch transform {
        case .hiragana:
            manager.getModifiedRubyCandidate(inputState: inputState) { $0.toHiragana() }
        case .katakana:
            manager.getModifiedRubyCandidate(inputState: inputState) { $0.toKatakana() }
        case .halfWidthKatakana:
            manager.getModifiedRubyCandidate(inputState: inputState) {
                $0.toKatakana().applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? $0
            }
        case .fullWidthRoman:
            manager.getModifiedRomanCandidate(inputState: inputState) {
                $0.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? $0
            }
        case .halfWidthRoman:
            manager.getModifiedRomanCandidate(inputState: inputState) {
                $0.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? $0
            }
        }
        manager.prefixCandidateCommited(candidate, leftSideContext: leftSideContext ?? "")
        commits.append(candidate.text)
    }

    // MARK: - Candidate window operations

    /// Moves the selection in the candidate list (arrow buttons, paging).
    public func moveCandidateSelection(by offset: Int) {
        guard inputState == .selecting, case .selecting(let candidates, let index) = snapshot().candidateWindow else {
            return
        }
        manager.requestSelectingRow(max(0, min(candidates.count - 1, index + offset)))
    }

    /// Commits the candidate at `index` (a click in the candidate window).
    public func submitCandidate(at index: Int) -> KeyResult {
        guard inputState == .selecting else {
            return KeyResult(handled: false, commits: [])
        }
        var commits: [String] = []
        withSession {
            manager.requestSelectingRow(index)
            submitSelectedCandidate(leftSideContext: textContext.getLeftSideContext(maxCount: 30), into: &commits)
            manager.requestResettingSelection()
        }
        inputState = nextState(after: .basedOnSubmitCandidate(ifIsEmpty: .none, ifIsNotEmpty: .previewing))
        return KeyResult(handled: true, commits: commits)
    }

    // MARK: - Snapshot

    public func snapshot() -> Snapshot {
        if manager.isEmpty, case .unicodeInput = inputState {
            // Unicode input shows "U+XXXX" from the state, not the composition.
        } else if manager.isEmpty {
            return .empty
        }
        let markedText = manager.getCurrentMarkedText(inputState: inputState)
        var segments: [PreeditSegment] = []
        for element in markedText where !element.content.isEmpty {
            let style: PreeditSegment.Style = switch element.focus {
            case .focused: .focused
            case .unfocused: .unfocused
            case .none: .plain
            }
            segments.append(PreeditSegment(text: element.content, style: style))
        }
        let text = segments.map(\.text).joined()
        let cursor = if markedText.selectionRange.location == NSNotFound {
            text.unicodeScalars.count
        } else {
            String(text.prefix(markedText.selectionRange.location)).unicodeScalars.count
        }

        let candidateWindow: CandidateWindow
        switch manager.getCurrentCandidateWindow(inputState: inputState) {
        case .hidden:
            candidateWindow = .hidden
        case .composing(let candidates, _):
            candidateWindow = candidates.first.map { .preview(Candidate(text: $0.text)) } ?? .hidden
        case .selecting(let candidates, let selectionIndex):
            let index = selectionIndex ?? 0
            lastSelectionIndex = index
            candidateWindow = .selecting(
                manager.makeCandidatePresentations(candidates).map {
                    Candidate(text: $0.candidate.text, annotation: $0.displayContext.annotationText)
                },
                selectedIndex: index
            )
        }
        return Snapshot(preedit: Preedit(segments: segments, cursor: cursor), candidateWindow: candidateWindow)
    }
}
