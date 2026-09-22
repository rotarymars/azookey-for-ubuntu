// Adapted from azooKey-Desktop (https://github.com/azooKey/azooKey-Desktop),
// Core/Sources/Core/InputUtils/Actions/UserAction.swift at b7ec0e4f27cf19d6a3aefa77d4b5ea7f2ebe5376.
// Copyright (c) 2025 Miwa Keita. MIT License; see THIRD_PARTY_NOTICES.md.
// Changes: macOS keyCode table (getUserAction) removed; its keyMap helper extracted.
// The Linux key table lives in ../UserAction+Linux.swift.

import Foundation
import KanaKanjiConverterModule

public enum UserAction {
    case input([InputPiece])
    case backspace
    case enter
    case space(prefersFullWidthWhenInput: Bool)
    case escape
    case tab
    case unknown
    case かな
    case 英数
    case navigation(NavigationDirection)
    case function(Function)
    case number(Number)
    case editSegment(Int)
    case suggest
    case forget
    case transformSelectedText
    case deadKey(String)
    case startUnicodeInput

    public enum NavigationDirection: Sendable, Equatable, Hashable {
        case up, down, right, left
    }

    public enum Function: Sendable, Equatable, Hashable {
        case six, seven, eight, nine, ten
    }

    public enum Number: Sendable, Equatable, Hashable {
        case one, two, three, four, five, six, seven, eight, nine, zero, shiftZero
        public var intValue: Int {
            switch self {
            case .one: 1
            case .two: 2
            case .three: 3
            case .four: 4
            case .five: 5
            case .six: 6
            case .seven: 7
            case .eight: 8
            case .nine: 9
            case .zero: 0
            case .shiftZero: 0
            }
        }

        public var inputPiece: InputPiece {
            switch self {
            case .one: .character("1")
            case .two: .character("2")
            case .three: .character("3")
            case .four: .character("4")
            case .five: .character("5")
            case .six: .character("6")
            case .seven: .character("7")
            case .eight: .character("8")
            case .nine: .character("9")
            case .zero: .character("0")
            case .shiftZero: .key(intention: "0", input: "0", modifiers: [.shift])
            }
        }

        public var inputString: String {
            switch self {
            case .one: "1"
            case .two: "2"
            case .three: "3"
            case .four: "4"
            case .five: "5"
            case .six: "6"
            case .seven: "7"
            case .eight: "8"
            case .nine: "9"
            case .zero: "0"
            case .shiftZero: "0"
            }
        }
    }

    private static func intention(_ c: Character, invertPunctuation: Bool) -> Character? {
        switch c {
        case ",":
            let normal: Character = switch Config.PunctuationStyle().value {
            case .kutenAndComma, .periodAndComma: "，"
            default: KeyMap.h2zMap(c) ?? "、"
            }
            if invertPunctuation {
                return normal == "，" ? "、" : "，"
            }
            return normal
        case ".":
            let normal: Character = switch Config.PunctuationStyle().value {
            case .periodAndToten, .periodAndComma: "．"
            default: KeyMap.h2zMap(c) ?? "。"
            }
            if invertPunctuation {
                return normal == "．" ? "。" : "．"
            }
            return normal
        default:
            return KeyMap.h2zMap(c)
        }
    }

    /// Turns typed characters into input pieces. In Japanese mode each piece
    /// carries its full-width "intention" (e.g. "." -> "。", "-" -> "ー") so the
    /// romaji table can still see the raw key.
    ///
    /// Extracted from the macOS `getUserAction(eventCore:inputLanguage:typeBackSlash:)`,
    /// whose keyCode table is replaced on Linux by `UserAction+Linux.swift`.
    static func keyMap(_ string: String, inputLanguage: InputLanguage, invertPunctuation: Bool = false) -> [InputPiece] {
        switch inputLanguage {
        case .english:
            return string.map { .character($0) }
        case .japanese:
            return string.map {
                .key(intention: intention($0, invertPunctuation: invertPunctuation), input: $0, modifiers: [])
            }
        }
    }
}
