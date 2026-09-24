import Foundation
import KanaKanjiConverterModule

/// User settings, stored as JSON in `~/.config/ibus-azookey/config.json`.
///
/// Every key is optional in the file; missing or invalid keys take the
/// defaults below, so a hand-written file only needs the values to change.
public struct Settings: Equatable, Sendable {
    /// How the converter learns from what you type (azooKey's `LearningType`).
    public enum Learning: String, Codable, CaseIterable, Sendable {
        /// Learn from conversions and use what was learned.
        case inputAndOutput
        /// Use what was learned so far, but stop learning.
        case onlyOutput
        /// Ignore learning data entirely.
        case nothing

        public var learningType: LearningType {
            switch self {
            case .inputAndOutput: .inputAndOutput
            case .onlyOutput: .onlyOutput
            case .nothing: .nothing
            }
        }
    }

    public enum InputStyle: String, Codable, CaseIterable, Sendable {
        case roman
        case azik
        case kanaUS
        case kanaJIS

        public var inputStyle: KanaKanjiConverterModule.InputStyle {
            switch self {
            case .roman: .mapped(id: .defaultRomanToKana)
            case .azik: .mapped(id: .defaultAZIK)
            case .kanaUS: .mapped(id: .defaultKanaUS)
            case .kanaJIS: .mapped(id: .defaultKanaJIS)
            }
        }
    }

    /// Characters typed for "." and "," in Japanese mode.
    public enum PunctuationStyle: String, Codable, CaseIterable, Sendable {
        /// 。、
        case kutenAndToten
        /// 。，
        case kutenAndComma
        /// ．、
        case periodAndToten
        /// ．，
        case periodAndComma
    }

    public var learning: Learning = .inputAndOutput
    /// Show the top conversion in the preedit while typing (azooKey's ライブ変換).
    /// Off means classic Space-to-convert.
    public var liveConversion = false
    /// Neural conversion with the zenz model.
    public var zenzaiEnabled = true
    /// A model id from models.json; the settings window downloads others on demand.
    public var zenzaiModel = ModelCatalog.defaultModelID
    /// Upper bound of model evaluations per conversion (azooKey default: 5).
    public var zenzaiInferenceLimit = 5
    /// Short self-description that steers Zenzai, e.g. "エンジニア/Swift開発者".
    public var zenzaiProfile = ""
    /// Give Zenzai the text around the cursor as context.
    public var useSurroundingText = true
    public var inputStyle: InputStyle = .roman
    public var punctuationStyle: PunctuationStyle = .kutenAndToten
    /// Backslash key types "\" (on) or "¥" (off) in Japanese mode.
    public var typeBackSlash = true
    /// Space types a half-width space in Japanese mode (Shift+Space inverts).
    public var typeHalfSpace = false
    /// Candidates shown per page in the candidate window.
    public var candidatePageSize = 9

    public init() {}
}

extension Settings: Codable {
    enum CodingKeys: String, CodingKey {
        case learning, liveConversion, zenzaiEnabled, zenzaiModel, zenzaiInferenceLimit, zenzaiProfile
        case useSurroundingText, inputStyle, punctuationStyle, typeBackSlash, typeHalfSpace, candidatePageSize
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        self.learning = value(.learning, defaults.learning)
        self.liveConversion = value(.liveConversion, defaults.liveConversion)
        self.zenzaiEnabled = value(.zenzaiEnabled, defaults.zenzaiEnabled)
        self.zenzaiModel = ModelCatalog.normalizedID(value(.zenzaiModel, defaults.zenzaiModel))
        self.zenzaiInferenceLimit = max(1, min(value(.zenzaiInferenceLimit, defaults.zenzaiInferenceLimit), 50))
        self.zenzaiProfile = value(.zenzaiProfile, defaults.zenzaiProfile)
        self.useSurroundingText = value(.useSurroundingText, defaults.useSurroundingText)
        self.inputStyle = value(.inputStyle, defaults.inputStyle)
        self.punctuationStyle = value(.punctuationStyle, defaults.punctuationStyle)
        self.typeBackSlash = value(.typeBackSlash, defaults.typeBackSlash)
        self.typeHalfSpace = value(.typeHalfSpace, defaults.typeHalfSpace)
        self.candidatePageSize = max(1, min(value(.candidatePageSize, defaults.candidatePageSize), 10))
    }
}

/// Loads and saves `Settings`, reloading when the file changes on disk (for
/// example after the settings window saved it).
public final class SettingsStore {
    public let fileURL: URL
    public private(set) var settings: Settings
    private var loadedModificationDate: Date?

    public init(fileURL: URL = Paths.settingsFile) {
        self.fileURL = fileURL
        self.settings = Settings()
        self.reloadIfChanged()
    }

    /// Returns true when the settings changed.
    @discardableResult
    public func reloadIfChanged() -> Bool {
        let modificationDate = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
        guard modificationDate != loadedModificationDate else {
            return false
        }
        loadedModificationDate = modificationDate
        let previous = settings
        if let data = try? Data(contentsOf: fileURL) {
            do {
                settings = try JSONDecoder().decode(Settings.self, from: data)
            } catch {
                Log.error("ignoring unreadable \(fileURL.path): \(error)")
                settings = Settings()
            }
        } else {
            settings = Settings()
        }
        return settings != previous
    }

    public func update(_ change: (inout Settings) -> Void) {
        change(&settings)
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: fileURL, options: .atomic)
            loadedModificationDate = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
        } catch {
            Log.error("could not save \(fileURL.path): \(error)")
        }
    }
}
