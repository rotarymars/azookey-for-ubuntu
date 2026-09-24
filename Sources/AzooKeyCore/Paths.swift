import Foundation

/// File locations, following the XDG base directory spec.
///
/// Installed layout (see Makefile):
///   /usr/lib/ibus-azookey/ibus-engine-azookey       the engine
///   /usr/lib/ibus-azookey/*.resources               dictionaries (SwiftPM bundles)
///   /usr/lib/ibus-azookey/lib/                      llama.cpp libraries
///   /usr/share/ibus-azookey/models/<id>/            bundled Zenzai model
///   /usr/share/ibus-azookey/models.json             model catalog
///   ~/.local/share/ibus-azookey/models/<id>/        models downloaded in settings
public enum Paths {
    static let appName = "ibus-azookey"

    private static var environment: [String: String] {
        ProcessInfo.processInfo.environment
    }

    private static func xdgDirectory(_ variable: String, fallback: String) -> URL {
        if let value = environment[variable], value.hasPrefix("/") {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(fallback, isDirectory: true)
    }

    /// `$XDG_CONFIG_HOME/ibus-azookey`
    public static var configDirectory: URL {
        if let override = environment["AZOOKEY_IBUS_CONFIG_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return xdgDirectory("XDG_CONFIG_HOME", fallback: ".config").appendingPathComponent(appName, isDirectory: true)
    }

    /// `$XDG_DATA_HOME/ibus-azookey`
    public static var dataDirectory: URL {
        if let override = environment["AZOOKEY_IBUS_DATA_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return xdgDirectory("XDG_DATA_HOME", fallback: ".local/share").appendingPathComponent(appName, isDirectory: true)
    }

    public static var settingsFile: URL {
        configDirectory.appendingPathComponent("config.json", isDirectory: false)
    }

    /// Learning data written by the converter.
    public static var memoryDirectory: URL {
        dataDirectory.appendingPathComponent("memory", isDirectory: true)
    }

    /// Created by the settings window to ask the engine to reset learning;
    /// the engine handles it the next time a text field gets focus.
    public static var resetLearningRequestFile: URL {
        dataDirectory.appendingPathComponent("reset-learning-request", isDirectory: false)
    }

    /// `/usr/lib/ibus-azookey` when installed (from /proc/self/exe).
    public static var executableDirectory: URL {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return executable.resolvingSymlinksInPath().deletingLastPathComponent()
    }

    /// `/usr/share/ibus-azookey` when installed, derived from the executable's
    /// location so a staged tree under build/ behaves like the installed one.
    public static var sharedDataDirectory: URL {
        if let override = environment["AZOOKEY_IBUS_SHARE_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return executableDirectory
            .deletingLastPathComponent()  // lib
            .deletingLastPathComponent()  // prefix
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
    }

    /// Directory holding `ggml-model-Q5_K_M.gguf` for a model id: the user's
    /// downloads first, then the models installed with the package. When
    /// neither has it, the installed location (for error messages).
    public static func modelDirectory(for id: String) -> URL {
        if let override = environment["AZOOKEY_IBUS_MODEL_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let candidates = [dataDirectory, sharedDataDirectory].map {
            $0.appendingPathComponent("models", isDirectory: true).appendingPathComponent(id, isDirectory: true)
        }
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent(modelFileName).path)
        } ?? candidates[1]
    }

    public static let modelFileName = "ggml-model-Q5_K_M.gguf"
}
