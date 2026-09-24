import AzooKeyCore
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

// Converts each argument (romaji or hiragana) and prints the top candidates.
// Usage: azookey-cli [--model PATH] [--limit N] [--no-zenzai] [--typing] [--delay MS] TEXT...
//   --typing  feed the input one character at a time, as an IME does, and
//             report the per-keystroke conversion latency
//   --delay   pause between simulated keystrokes (not counted), like a typist
//   --session type through the engine's InputSession (same code path as IBus)

var modelPath: String?
var inferenceLimit = 1
var simulateTyping = false
var keystrokeDelay: UInt32 = 0
var useSession = false
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
    default:
        inputs.append(argument)
    }
}

let workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("azookey-cli-\(getpid())")
try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: workDirectory) }

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
    if let modelPath {
        setenv("AZOOKEY_IBUS_MODEL_DIR", URL(fileURLWithPath: modelPath).deletingLastPathComponent().path, 1)
    }
    var settings = Settings()
    settings.zenzaiEnabled = modelPath != nil
    settings.zenzaiInferenceLimit = inferenceLimit
    Config.settings = settings
    let session = ConverterHost().makeSession()
    for input in inputs {
        var latencies: [Double] = []
        for scalar in input.unicodeScalars {
            if keystrokeDelay > 0 {
                usleep(keystrokeDelay * 1000)
            }
            let start = Date()
            _ = session.handleKey(LinuxKeyEvent(keyval: scalar.value))
            latencies.append(Date().timeIntervalSince(start) * 1000)
        }
        let average = latencies.reduce(0, +) / Double(latencies.count)
        print(String(format: "keystrokes=%d avg=%.1fms max=%.1fms last=%.1fms",
                     latencies.count, average, latencies.max()!, latencies.last!))
        print("\(session.snapshot().preedit.text) -> \(session.snapshot().candidateWindow)")
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

func milliseconds(since start: Date) -> Double {
    Date().timeIntervalSince(start) * 1000
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
