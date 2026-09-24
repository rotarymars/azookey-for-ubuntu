import Foundation

/// A Zenzai model listed in data/models.json (installed next to the models).
public struct ModelInfo: Decodable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var license: String
    /// Trained on the right-side-context prompt (zenz-v3.2 and later).
    public var rightContext: Bool
}

public enum ModelCatalog {
    /// Bundled with the package.
    public static let defaultModelID = "zenz-v3.2-small"

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
}
