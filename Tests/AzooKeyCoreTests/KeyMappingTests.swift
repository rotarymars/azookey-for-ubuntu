import AzooKeyCore
import KanaKanjiConverterModule
import Testing

@Suite struct KeyMappingTests {
    func action(
        _ keyval: UInt32,
        _ state: UInt32 = 0,
        language: InputLanguage = .japanese,
        typeBackSlash: Bool = true,
        typeHalfSpace: Bool = false
    ) -> UserAction {
        UserAction.getUserAction(
            linuxEvent: LinuxKeyEvent(keyval: keyval, state: state),
            inputLanguage: language,
            typeBackSlash: typeBackSlash,
            typeHalfSpace: typeHalfSpace
        )
    }

    func typed(_ action: UserAction) -> [InputPiece]? {
        if case .input(let pieces) = action {
            return pieces
        }
        return nil
    }

    @Test func lettersCarryNoIntention() {
        #expect(typed(action(0x61)) == [.key(intention: nil, input: "a", modifiers: [])])
    }

    @Test func punctuationBecomesFullWidthInJapanese() {
        #expect(typed(action(0x2e)) == [.key(intention: "。", input: ".", modifiers: [])])
        #expect(typed(action(0x2c)) == [.key(intention: "、", input: ",", modifiers: [])])
        #expect(typed(action(0x2d)) == [.key(intention: "ー", input: "-", modifiers: [])])
        #expect(typed(action(0x5b)) == [.key(intention: "「", input: "[", modifiers: [])])
    }

    @Test func englishModeTypesPlainCharacters() {
        #expect(typed(action(0x2e, language: .english)) == [.character(".")])
    }

    @Test func backslashFollowsSetting() {
        #expect(typed(action(Keysym.backslash)) == [.key(intention: "＼", input: "\\", modifiers: [])])
        #expect(typed(action(Keysym.backslash, typeBackSlash: false)) == [.key(intention: "￥", input: "¥", modifiers: [])])
        #expect(typed(action(Keysym.yen)) == [.key(intention: "￥", input: "¥", modifiers: [])])
    }

    @Test func editingKeys() {
        #expect(action(Keysym.returnKey) == .enter)
        #expect(action(Keysym.kpEnter) == .enter)
        #expect(action(Keysym.backSpace) == .backspace)
        #expect(action(Keysym.backSpace, ModifierMask.control) == .forget)
        #expect(action(Keysym.escape) == .escape)
        #expect(action(Keysym.tab) == .tab)
        #expect(action(Keysym.f7) == .function(.seven))
        #expect(action(Keysym.left) == .navigation(.left))
        #expect(action(Keysym.home) == .unknown)
    }

    @Test func emacsStyleControlKeys() {
        #expect(action(0x68, ModifierMask.control) == .backspace)
        #expect(action(0x6e, ModifierMask.control) == .navigation(.down))
        #expect(action(0x6b, ModifierMask.control) == .function(.seven))
        #expect(action(0x3a, ModifierMask.control | ModifierMask.shift) == .function(.ten))
        // Anything else with Control belongs to the application.
        #expect(action(0x63, ModifierMask.control) == .unknown)
        #expect(action(Keysym.left, ModifierMask.control) == .unknown)
    }

    @Test func spaceWidthFollowsShiftAndSetting() {
        #expect(action(Keysym.space) == .space(prefersFullWidthWhenInput: true))
        #expect(action(Keysym.space, ModifierMask.shift) == .space(prefersFullWidthWhenInput: false))
        #expect(action(Keysym.space, typeHalfSpace: true) == .space(prefersFullWidthWhenInput: false))
    }

    @Test func digitsAreNumbersOnlyWithoutModifiers() {
        #expect(action(0x31) == .number(.one))
        #expect(action(0x30) == .number(.zero))
        #expect(typed(action(0x31, ModifierMask.mod1)) != nil)
    }

    @Test func japaneseKeyboardKeys() {
        #expect(action(Keysym.muhenkan) == .英数)
        #expect(action(Keysym.henkan) == .かな)
        #expect(action(Keysym.hangul) == .かな)
        #expect(action(Keysym.hangulHanja) == .英数)
        #expect(action(Keysym.zenkakuHankaku) == .英数)
        #expect(action(Keysym.zenkakuHankaku, language: .english) == .かな)
    }

    @Test func shortcutModifiersMapToCommand() {
        #expect(LinuxKeyEvent(keyval: 0x61, state: ModifierMask.mod1).modifierFlags == [.command])
        #expect(LinuxKeyEvent(keyval: 0x61, state: ModifierMask.mod4).modifierFlags == [.command])
        // AltGr and NumLock are not shortcut modifiers.
        #expect(LinuxKeyEvent(keyval: 0x61, state: ModifierMask.mod5 | (1 << 4)).modifierFlags == [])
    }

    @Test func modifierKeysAreRecognized() {
        #expect(LinuxKeyEvent(keyval: 0xffe1).isModifierKey)
        #expect(!LinuxKeyEvent(keyval: 0x61).isModifierKey)
    }
}

extension UserAction: Equatable {
    public static func == (lhs: UserAction, rhs: UserAction) -> Bool {
        String(describing: lhs) == String(describing: rhs)
    }
}
