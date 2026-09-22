// Adapted from azooKey-Desktop (https://github.com/azooKey/azooKey-Desktop),
// Core/Sources/Core/InputUtils/KeyEventCore.swift at b7ec0e4f27cf19d6a3aefa77d4b5ea7f2ebe5376.
// Copyright (c) 2025 Miwa Keita. MIT License; see THIRD_PARTY_NOTICES.md.
// Unmodified.

public struct KeyEventCore: Codable, Sendable, Equatable {
    public struct ModifierFlag: OptionSet, Codable, Sendable, Hashable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let shift   = ModifierFlag(rawValue: 1 << 0)
        public static let control = ModifierFlag(rawValue: 1 << 1)
        public static let option  = ModifierFlag(rawValue: 1 << 2)
        public static let command = ModifierFlag(rawValue: 1 << 3)
    }

    public init(modifierFlags: ModifierFlag, characters: String?, charactersIgnoringModifiers: String?, keyCode: UInt16) {
        self.modifierFlags = modifierFlags
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.keyCode = keyCode
    }
    public var modifierFlags: ModifierFlag
    public var characters: String?
    public var charactersIgnoringModifiers: String?
    public var keyCode: UInt16
}
