import Foundation

/// azooKey-Desktop reads its preferences as `Config.<Item>().value`, backed by
/// UserDefaults on macOS. The adapted upstream code keeps that API; here the
/// items read the `Settings` the engine loaded from config.json.
public enum Config {
    /// The settings in effect. Only touched from the main thread.
    nonisolated(unsafe) public static var settings = Settings()
}

extension Config {
    public struct LiveConversion {
        public init() {}
        public var value: Bool { Config.settings.liveConversion }
    }

    public struct Learning {
        public typealias Value = Settings.Learning
        public init() {}
        public var value: Value { Config.settings.learning }
    }

    public struct PunctuationStyle {
        public typealias Value = Settings.PunctuationStyle
        public init() {}
        public var value: Value { Config.settings.punctuationStyle }
    }

    public struct ZenzaiInferenceLimit {
        public init() {}
        public var value: Int { Config.settings.zenzaiInferenceLimit }
    }

    public struct ZenzaiProfile {
        public init() {}
        public var value: String { Config.settings.zenzaiProfile }
    }

    /// Zenzai personalization mixes in n-gram models that azooKey-Desktop
    /// trains from the macOS user's typing history. They don't exist here.
    public struct ZenzaiPersonalizationLevel {
        public enum Value: Sendable {
            case off
            public var alpha: Float { 0 }
        }
        public init() {}
        public var value: Value { .off }
    }

    /// Debug-only features of azooKey-Desktop that are not offered on Linux.
    public struct DebugTypoCorrection {
        public init() {}
        public var value: Bool { false }
    }

    public struct DebugPredictiveTyping {
        public init() {}
        public var value: Bool { false }
    }
}
