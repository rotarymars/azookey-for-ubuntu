import Foundation

/// A Zenzai model listed in data/models.json (installed next to the models).
public struct ModelInfo: Decodable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var license: String
    /// Trained on the right-side-context prompt (zenz-v3.2 and later).
    public var rightContext: Bool
}

/// A model file to load, found by `ModelCatalog.resolve(_:)`.
public struct ResolvedModel: Equatable, Sendable {
    public var file: URL
    /// Whether the model may be given text after the cursor.
    public var rightContext: Bool

    public init(file: URL, rightContext: Bool) {
        self.file = file
        self.rightContext = rightContext
    }
}

public enum ModelCatalog {
    /// Bundled with the package.
    public static let defaultModelID = "zenz-v3.2-small"

    /// Selects `Settings.zenzaiLocalModelPath`, a GGUF file of your own.
    public static let localModelID = "local"

    public static let models: [ModelInfo] = {
        let url = Paths.sharedDataDirectory.appendingPathComponent("models.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        do {
            return try JSONDecoder().decode([ModelInfo].self, from: data)
        } catch {
            Log.error("ignoring unreadable \(url.path): \(error)")
            return []
        }
    }()

    /// Accepts the ids used before the catalog existed ("small", "xsmall").
    public static func normalizedID(_ id: String) -> String {
        switch id {
        case "small", "xsmall": "zenz-v3.2-\(id)"
        default: id
        }
    }

    /// Only models trained on it may be given text after the cursor; older
    /// ones would read the unknown context tag as input.
    public static func supportsRightContext(_ id: String) -> Bool {
        models.first { $0.id == id }?.rightContext ?? id.hasPrefix("zenz-v3.2")
    }

    /// The model to use under `settings`: the selected one, else the bundled
    /// one, else nil (dictionary only).
    public static func resolve(_ settings: Settings) -> ResolvedModel? {
        var selected = settings.zenzaiModel
        if selected == localModelID {
            let path = (settings.zenzaiLocalModelPath as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return ResolvedModel(file: URL(fileURLWithPath: path), rightContext: settings.zenzaiLocalModelRightContext)
            }
            Log.error("local Zenzai model \"\(settings.zenzaiLocalModelPath)\" not found; using \(defaultModelID)")
            selected = defaultModelID
        }
        for id in [selected, defaultModelID] {
            let file = Paths.modelDirectory(for: id).appendingPathComponent(Paths.modelFileName)
            if FileManager.default.fileExists(atPath: file.path) {
                if id != selected {
                    Log.error("Zenzai model \(selected) is not installed; using \(id)")
                }
                return ResolvedModel(file: file, rightContext: supportsRightContext(id))
            }
        }
        Log.error("no Zenzai model installed; using the dictionary only")
        return nil
    }
}
