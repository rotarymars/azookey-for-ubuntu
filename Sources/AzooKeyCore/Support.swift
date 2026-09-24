import Foundation

public enum PackageMetadata {
    public static let version = "0.1.2"
}

/// Writes to stderr, which the engine shares with ibus-daemon; on GNOME that
/// ends up in the user journal
/// (`journalctl --user -u org.freedesktop.IBus.session.GNOME.service`).
public enum Log {
    public static let debugEnabled = ProcessInfo.processInfo.environment["AZOOKEY_IBUS_DEBUG"] == "1"

    public static func info(_ message: @autoclosure () -> String) {
        write("info", message())
    }

    public static func error(_ message: @autoclosure () -> String) {
        write("error", message())
    }

    public static func debug(_ message: @autoclosure () -> String) {
        if debugEnabled {
            write("debug", message())
        }
    }

    private static func write(_ level: String, _ message: String) {
        FileHandle.standardError.write(Data("ibus-azookey[\(level)]: \(message)\n".utf8))
    }
}

/// Where the converter looks for the user dictionary (azooKey-Desktop compiles
/// its user dictionary into this directory next to the learning data).
enum CompiledUserDictionaryStore {
    static func directoryURL(memoryDirectoryURL: URL) -> URL {
        memoryDirectoryURL.appendingPathComponent("user_dictionary", isDirectory: true)
    }
}

/// azooKey-Desktop can download an n-gram model for an experimental typo
/// correction debug feature. That feature is not offered here, so
/// SegmentsManager always sees the weights as missing.
enum DebugTypoCorrectionWeights {
    static func modelDirectoryURL(azooKeyApplicationSupportDirectoryURL: URL) -> URL {
        azooKeyApplicationSupportDirectoryURL.appendingPathComponent("downloaded/input_n5_lm_v1", isDirectory: true)
    }

    static func hasRequiredWeightFiles(modelDirectoryURL: URL) -> Bool {
        false
    }
}
