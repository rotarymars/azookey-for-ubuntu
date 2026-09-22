import Foundation
import KanaKanjiConverterModule

/// A key event as IBus delivers it: `keyval` is an X11 keysym and `state` an
/// IBus modifier mask.
public struct LinuxKeyEvent: Sendable, Equatable {
    public var keyval: UInt32
    public var keycode: UInt32
    public var state: UInt32
    /// The character the key produces (`ibus_keyval_to_unicode`), 0 if none.
    public var unicode: UInt32

    public init(keyval: UInt32, keycode: UInt32 = 0, state: UInt32 = 0, unicode: UInt32? = nil) {
        self.keyval = keyval
        self.keycode = keycode
        self.state = state
        self.unicode = unicode ?? Keysym.latin1Unicode(keyval)
    }

    public var isRelease: Bool {
        state & ModifierMask.release != 0
    }

    public var character: Character? {
        guard unicode >= 0x20, unicode != 0x7f, let scalar = Unicode.Scalar(unicode) else {
            return nil
        }
        return Character(scalar)
    }

    /// Alt, Super, Hyper and Meta are shortcut modifiers on Linux, so they map
    /// to `.command`, which the input state machine passes to the application.
    /// AltGr (Mod5) only selects characters and is not reported.
    public var modifierFlags: KeyEventCore.ModifierFlag {
        var flags: KeyEventCore.ModifierFlag = []
        if state & ModifierMask.shift != 0 {
            flags.insert(.shift)
        }
        if state & ModifierMask.control != 0 {
            flags.insert(.control)
        }
        if state & (ModifierMask.mod1 | ModifierMask.mod4 | ModifierMask.superMask | ModifierMask.hyper | ModifierMask.meta) != 0 {
            flags.insert(.command)
        }
        return flags
    }

    public var isModifierKey: Bool {
        Keysym.modifierKeys.contains(keyval)
    }

    public var keyEventCore: KeyEventCore {
        let text = character.map { String($0) }
        return KeyEventCore(
            modifierFlags: modifierFlags,
            characters: text,
            charactersIgnoringModifiers: text,
            keyCode: UInt16(truncatingIfNeeded: keycode)
        )
    }
}

public enum ModifierMask {
    public static let shift: UInt32 = 1 << 0
    public static let lock: UInt32 = 1 << 1
    public static let control: UInt32 = 1 << 2
    public static let mod1: UInt32 = 1 << 3
    public static let mod4: UInt32 = 1 << 6
    public static let mod5: UInt32 = 1 << 7
    public static let superMask: UInt32 = 1 << 26
    public static let hyper: UInt32 = 1 << 27
    public static let meta: UInt32 = 1 << 28
    public static let release: UInt32 = 1 << 30
}

/// X11 keysyms used by the key table (from X11/keysymdef.h).
public enum Keysym {
    public static let space: UInt32 = 0x0020
    public static let backslash: UInt32 = 0x005c
    public static let yen: UInt32 = 0x00a5
    public static let isoLeftTab: UInt32 = 0xfe20
    public static let backSpace: UInt32 = 0xff08
    public static let tab: UInt32 = 0xff09
    public static let clear: UInt32 = 0xff0b
    public static let returnKey: UInt32 = 0xff0d
    public static let escape: UInt32 = 0xff1b
    public static let muhenkan: UInt32 = 0xff22
    public static let henkan: UInt32 = 0xff23
    public static let hiragana: UInt32 = 0xff25
    public static let katakana: UInt32 = 0xff26
    public static let hiraganaKatakana: UInt32 = 0xff27
    public static let zenkaku: UInt32 = 0xff28
    public static let hankaku: UInt32 = 0xff29
    public static let zenkakuHankaku: UInt32 = 0xff2a
    public static let eisuShift: UInt32 = 0xff2f
    public static let eisuToggle: UInt32 = 0xff30
    /// LANG1, the かな key of Apple JIS keyboards.
    public static let hangul: UInt32 = 0xff31
    /// LANG2, the 英数 key of Apple JIS keyboards.
    public static let hangulHanja: UInt32 = 0xff34
    public static let home: UInt32 = 0xff50
    public static let left: UInt32 = 0xff51
    public static let up: UInt32 = 0xff52
    public static let right: UInt32 = 0xff53
    public static let down: UInt32 = 0xff54
    public static let pageUp: UInt32 = 0xff55
    public static let pageDown: UInt32 = 0xff56
    public static let end: UInt32 = 0xff57
    public static let insert: UInt32 = 0xff63
    public static let kpSpace: UInt32 = 0xff80
    public static let kpTab: UInt32 = 0xff89
    public static let kpEnter: UInt32 = 0xff8d
    public static let kpHome: UInt32 = 0xff95
    public static let kpLeft: UInt32 = 0xff96
    public static let kpUp: UInt32 = 0xff97
    public static let kpRight: UInt32 = 0xff98
    public static let kpDown: UInt32 = 0xff99
    public static let kpPageUp: UInt32 = 0xff9a
    public static let kpPageDown: UInt32 = 0xff9b
    public static let kpEnd: UInt32 = 0xff9c
    public static let kpBegin: UInt32 = 0xff9d
    public static let kpInsert: UInt32 = 0xff9e
    public static let kpDelete: UInt32 = 0xff9f
    public static let kpSeparator: UInt32 = 0xffac
    public static let kpDecimal: UInt32 = 0xffae
    public static let kpDivide: UInt32 = 0xffaf
    public static let f6: UInt32 = 0xffc3
    public static let f7: UInt32 = 0xffc4
    public static let f8: UInt32 = 0xffc5
    public static let f9: UInt32 = 0xffc6
    public static let f10: UInt32 = 0xffc7
    public static let delete: UInt32 = 0xffff

    static let modifierKeys: Set<UInt32> = [
        0xffe1, 0xffe2,  // Shift_L, Shift_R
        0xffe3, 0xffe4,  // Control_L, Control_R
        0xffe5, 0xffe6,  // Caps_Lock, Shift_Lock
        0xffe7, 0xffe8,  // Meta_L, Meta_R
        0xffe9, 0xffea,  // Alt_L, Alt_R
        0xffeb, 0xffec,  // Super_L, Super_R
        0xffed, 0xffee,  // Hyper_L, Hyper_R
        0xfe03, 0xfe11,  // ISO_Level3_Shift, ISO_Level5_Shift
        0xff7e, 0xff7f,  // Mode_switch, Num_Lock
    ]

    /// Printable Latin-1 keysyms equal their code point. Used when no
    /// `ibus_keyval_to_unicode` result is supplied (tests).
    static func latin1Unicode(_ keyval: UInt32) -> UInt32 {
        (0x20...0x7e).contains(keyval) || (0xa0...0xff).contains(keyval) ? keyval : 0
    }
}

extension UserAction {
    /// The Linux counterpart of azooKey-Desktop's macOS
    /// `getUserAction(eventCore:inputLanguage:typeBackSlash:)`: the same
    /// shortcuts, with keysyms instead of macOS virtual key codes.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public static func getUserAction(
        linuxEvent event: LinuxKeyEvent,
        inputLanguage: InputLanguage,
        typeBackSlash: Bool,
        typeHalfSpace: Bool
    ) -> UserAction {
        let modifiers = event.modifierFlags
        func keyMap(_ string: String) -> [InputPiece] {
            UserAction.keyMap(string, inputLanguage: inputLanguage)
        }

        if let logicalKey = event.character.map({ String($0).lowercased() }) {
            switch (logicalKey, modifiers) {
            case ("h", [.control]):
                return .backspace
            case ("p", [.control]):
                return .navigation(.up)
            case ("m", [.control]):
                return .enter
            case ("n", [.control]):
                return .navigation(.down)
            case ("f", [.control]):
                return .navigation(.right)
            case ("i", [.control]):
                return .editSegment(-1)
            case ("o", [.control]):
                return .editSegment(1)
            case ("l", [.control]):
                return .function(.nine)
            case ("j", [.control]):
                return .function(.six)
            case ("k", [.control]):
                return .function(.seven)
            case (";", [.control]):
                return .function(.eight)
            // ":" needs Shift on US layouts.
            case (":", [.control]), (":", [.control, .shift]), ("'", [.control]):
                return .function(.ten)
            case ("s", [.control]):
                return .suggest
            case ("u", [.control, .shift]):
                return .startUnicodeInput
            case ("\\", [.shift]), ("¥", [.shift]):
                return .input(keyMap("|"))
            case ("\\", []):
                return .input(keyMap(typeBackSlash ? "\\" : "¥"))
            case ("¥", []):
                // Unlike a Mac, a Linux JIS keyboard has separate ¥ and \ keys.
                return .input(keyMap("¥"))
            default:
                break
            }
        }

        if modifiers.contains(.control), event.keyval != Keysym.backSpace {
            // Unknown Control shortcuts belong to the application; Ctrl+BackSpace
            // is handled below as "forget this conversion".
            return .unknown
        }

        switch event.keyval {
        case Keysym.returnKey, Keysym.kpEnter:
            return .enter
        case Keysym.tab, Keysym.isoLeftTab, Keysym.kpTab:
            return .tab
        case Keysym.space, Keysym.kpSpace:
            let shift = modifiers.contains(.shift)
            return .space(prefersFullWidthWhenInput: typeHalfSpace == shift)
        case Keysym.backSpace:
            return modifiers.contains(.control) ? .forget : .backspace
        case Keysym.escape:
            return .escape
        case Keysym.f6:
            return .function(.six)
        case Keysym.f7:
            return .function(.seven)
        case Keysym.f8:
            return .function(.eight)
        case Keysym.f9:
            return .function(.nine)
        case Keysym.f10:
            return .function(.ten)
        case Keysym.eisuToggle, Keysym.eisuShift, Keysym.muhenkan, Keysym.hangulHanja:
            return .英数
        case Keysym.hiraganaKatakana, Keysym.hiragana, Keysym.katakana, Keysym.henkan, Keysym.hangul:
            return .かな
        case Keysym.zenkakuHankaku, Keysym.zenkaku, Keysym.hankaku:
            return inputLanguage == .japanese ? .英数 : .かな
        case Keysym.left, Keysym.kpLeft:
            return .navigation(.left)
        case Keysym.right, Keysym.kpRight:
            return .navigation(.right)
        case Keysym.down, Keysym.kpDown:
            return .navigation(.down)
        case Keysym.up, Keysym.kpUp:
            return .navigation(.up)
        case Keysym.kpDivide:
            return .input([.character("/")])
        case Keysym.kpSeparator:
            return .input([.character(",")])
        case Keysym.kpDecimal:
            return .input([.character(".")])
        case Keysym.home, Keysym.end, Keysym.pageUp, Keysym.pageDown, Keysym.insert, Keysym.delete, Keysym.clear,
             Keysym.kpHome, Keysym.kpEnd, Keysym.kpPageUp, Keysym.kpPageDown, Keysym.kpInsert, Keysym.kpDelete, Keysym.kpBegin:
            return .unknown
        case 0x30...0x39 where modifiers.isDisjoint(with: [.shift, .control, .command]):
            let numbers: [UserAction.Number] = [.zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine]
            return .number(numbers[Int(event.keyval - 0x30)])
        default:
            if let character = event.character, isPrintable(character) {
                return .input(keyMap(String(character)))
            }
            return .unknown
        }
    }

    private static func isPrintable(_ character: Character) -> Bool {
        let printable = CharacterSet.alphanumerics
            .union(.symbols)
            .union(.punctuationCharacters)
        return character.unicodeScalars.allSatisfy(printable.contains)
    }
}
