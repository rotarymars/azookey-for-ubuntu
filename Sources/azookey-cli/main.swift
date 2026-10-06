import AzooKeyCore
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

// Converts each argument (romaji or hiragana) and prints the top candidates.
// Usage: azookey-cli [--model PATH] [--limit N] [--no-zenzai] [--typing] [--delay MS]
//                    [--session [--live]] [--typo [--typo-final] [--typo-beam N]] TEXT...
//   --typing  feed the input one character at a time, as an IME does, and
//             report the per-keystroke conversion latency
//   --delay   pause between simulated keystrokes (not counted), like a typist
//   --session type through the engine's InputSession (same code path as IBus);
//             a space in TEXT presses Space
//   --live    live conversion (with --session)
//   --typo    typo correction. With --session it is turned on (otherwise off, to
//             compare) and what it found and cost is printed after each input.
//             Without --session TEXT is only scored for typos, as typed so far
//             or, with --typo-final, as after Space. --typo-beam sets the beam
//             width of the search in either case.

var modelPath: String?
var inferenceLimit = 1
var simulateTyping = false
var keystrokeDelay: UInt32 = 0
var useSession = false
var liveConversion = false
var typo = false
var typoFinal = false
var typoBeam: Int?
var inputs: [String] = []
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--model":
        modelPath = arguments.popFirst()
    case "--limit":
        inferenceLimit = arguments.popFirst().flatMap(Int.init) ?? inferenceLimit
    case "--no-zenzai":
        modelPath = nil
    case "--typing":
        simulateTyping = true
    case "--delay":
        keystrokeDelay = arguments.popFirst().flatMap(UInt32.init) ?? 0
    case "--session":
        useSession = true
    case "--live":
        liveConversion = true
    case "--typo":
        typo = true
    case "--typo-final":
        typoFinal = true
    case "--typo-beam":
        typoBeam = arguments.popFirst().flatMap(Int.init)
    default:
        inputs.append(argument)
    }
}

let workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("azookey-cli-\(getpid())")
try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: workDirectory) }

func milliseconds(since start: Date) -> Double {
    Date().timeIntervalSince(start) * 1000
}

func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}

func summary(_ values: [Double]) -> String {
    guard let last = values.last else {
        return "none"
    }
    return String(format: "n=%d avg=%.1fms max=%.1fms last=%.1fms", values.count, values.reduce(0, +) / Double(values.count), values.max()!, last)
}

func describe(_ hypothesis: TypoCorrector.Hypothesis, typed: Bool) -> String {
    String(format: "  %@ %@ score=%.2f lm=%.2f typo=%.2f%@", hypothesis.input, hypothesis.reading,
           hypothesis.score, hypothesis.lmScore, hypothesis.channelCost, typed ? " (typed)" : "")
}

if useSession {
    MainActor.assumeIsolated {
        typeThroughSession()
    }
    try? FileManager.default.removeItem(at: workDirectory)
    exit(0)
}

/// Types each input through `InputSession`, exactly as the IBus engine does.
@MainActor
func typeThroughSession() {
    setenv("AZOOKEY_IBUS_DATA_DIR", workDirectory.path, 1)
    var settings = Settings()
    settings.zenzaiEnabled = modelPath != nil
    settings.zenzaiModel = ModelCatalog.localModelID
    settings.zenzaiLocalModelPath = modelPath.map { URL(fileURLWithPath: $0).path } ?? ""
    settings.zenzaiInferenceLimit = inferenceLimit
    settings.liveConversion = liveConversion
    settings.typoCorrection = typo
    Config.settings = settings
    TypoCorrector.default.configuration.beamSize = typoBeam ?? TypoCorrector.default.configuration.beamSize
    let session = ConverterHost().makeSession()
    for input in inputs {
        var latencies: [Double] = []
        var searches: [Double] = []
        var conversions: [Double] = []
        for scalar in input.unicodeScalars {
            if keystrokeDelay > 0 {
                usleep(keystrokeDelay * 1000)
            }
            let start = Date()
            _ = session.handleKey(LinuxKeyEvent(keyval: scalar.value))
            latencies.append(milliseconds(since: start))
            if let report = session.typoCorrectionReport {
                searches.append(milliseconds(report.searchTime))
                if report.conversionTime > .zero {
                    conversions.append(milliseconds(report.conversionTime))
                }
            }
        }
        print("\(input): keystrokes " + summary(latencies))
        let snapshot = session.snapshot()
        if typo {
            print("  typo search " + summary(searches) + "; converting corrections " + summary(conversions))
            if let report = session.typoCorrectionReport, let result = report.result {
                let margin = result.margin.map { String(format: "margin %.2f", $0) } ?? "no correction"
                let placement = report.placement.map { " (\($0))" } ?? ""
                print("  typo \(result.original.reading): \(margin)\(placement)" + (report.candidateText.map { " -> \($0)" } ?? ""))
                for hypothesis in result.hypotheses.prefix(4) {
                    print(describe(hypothesis, typed: hypothesis == result.original))
                }
            }
        }
        let window = switch snapshot.candidateWindow {
        case .hidden:
            "(no candidate window)"
        case .preview(let candidate):
            "preview: \(candidate.text)"
        case .selecting(let candidates, let selected):
            candidates.prefix(6).enumerated().map { $0.offset == selected ? "[\($0.element.text)]" : $0.element.text }.joined(separator: " / ")
        }
        print("  \(snapshot.preedit.text) -> \(window)")
        session.reset()
    }
}

let converter = KanaKanjiConverter.withDefaultDictionary()
let options = ConvertRequestOptions(
    requireJapanesePrediction: .disabled,
    requireEnglishPrediction: .disabled,
    keyboardLanguage: .ja_JP,
    learningType: .nothing,
    memoryDirectoryURL: workDirectory,
    sharedContainerURL: workDirectory,
    textReplacer: .withDefaultEmojiDictionary(),
    specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
    zenzaiMode: modelPath.map {
        .on(weight: URL(fileURLWithPath: $0), inferenceLimit: inferenceLimit, personalizationMode: nil)
    } ?? .off,
    metadata: .init(versionString: "ibus-azookey azookey-cli")
)

if typo {
    var configuration = TypoCorrector.Configuration()
    configuration.beamSize = typoBeam ?? configuration.beamSize
    let corrector = TypoCorrector(configuration: configuration)
    for input in inputs {
        var composingText = ComposingText()
        var latencies: [Double] = []
        var result: TypoCorrector.Result?
        // Pieces as the engine makes them: the key plus its full-width intention ("-" -> "ー").
        let keys = input.map { ComposingText.InputElement(piece: .key(intention: KeyMap.h2zMap($0), input: $0, modifiers: []), inputStyle: .mapped(id: .defaultRomanToKana)) }
        let separator = ComposingText.InputElement(piece: .compositionSeparator, inputStyle: .mapped(id: .defaultRomanToKana))
        let steps = (simulateTyping ? keys.map { [$0] } : [keys]) + (typoFinal ? [[separator]] : [])
        for step in steps {
            composingText.insertAtCursorPosition(step)
            let start = Date()
            result = corrector.correct(composingText, leftSideContext: "", converter: converter, options: options)
            latencies.append(milliseconds(since: start))
        }
        let margin = result?.margin.map { String(format: "%.2f", $0) } ?? "-"
        print("\(input) (\(composingText.convertTarget)): margin=\(margin) calls " + summary(latencies))
        for hypothesis in result?.hypotheses.prefix(4) ?? [] {
            print(describe(hypothesis, typed: hypothesis == result?.original))
        }
        converter.stopComposition()
    }
    exit(0)
}

for input in inputs {
    var composingText = ComposingText()
    var result: ConversionResult
    if simulateTyping {
        var latencies: [Double] = []
        repeat {
            let index = input.index(input.startIndex, offsetBy: composingText.input.count)
            composingText.insertAtCursorPosition(String(input[index]), inputStyle: .mapped(id: .defaultRomanToKana))
            if keystrokeDelay > 0 {
                usleep(keystrokeDelay * 1000)
            }
            let start = Date()
            result = converter.requestCandidates(composingText, options: options)
            latencies.append(milliseconds(since: start))
        } while composingText.input.count < input.count
        let average = latencies.reduce(0, +) / Double(latencies.count)
        print(String(format: "keystrokes=%d avg=%.1fms max=%.1fms last=%.1fms",
                     latencies.count, average, latencies.max()!, latencies.last!))
    } else {
        composingText.insertAtCursorPosition(input, inputStyle: .mapped(id: .defaultRomanToKana))
        let start = Date()
        result = converter.requestCandidates(composingText, options: options)
        print(String(format: "[%.1f ms]", milliseconds(since: start)))
    }
    let top = result.mainResults.prefix(5).map(\.text).joined(separator: " / ")
    print("\(composingText.convertTarget) -> \(top)")
    converter.stopComposition()
}
