// Adapted from azooKey-Desktop (https://github.com/azooKey/azooKey-Desktop),
// Core/Sources/Core/KeyMap/KeyMap+hankaku2zenkaku.swift at b7ec0e4f27cf19d6a3aefa77d4b5ea7f2ebe5376.
// Copyright (c) 2025 Miwa Keita. MIT License; see THIRD_PARTY_NOTICES.md.
// Unmodified.

//
//  hankaku2zenkaku.swift
//  azooKeyMac
//
//  Created by miwa on 2024/03/25.
//

import Foundation

extension KeyMap {
    private static let h2z: [Character: Character] = [
        "!": "！",
        "\"": "”",
        "#": "＃",
        "$": "＄",
        "%": "％",
        "&": "＆",
        "'": "’",
        "(": "（",
        ")": "）",
        "=": "＝",
        "~": "〜",
        "|": "｜",
        "`": "｀",
        "{": "『",
        "+": "＋",
        "*": "＊",
        "}": "』",
        "<": "＜",
        ">": "＞",
        "?": "？",
        "_": "＿",
        "-": "ー",
        "^": "＾",
        "\\": "＼",
        "¥": "￥",
        "@": "＠",
        "[": "「",
        ";": "；",
        ":": "：",
        "]": "」",
        ",": "、",
        ".": "。",
        "/": "・"
    ]

    public static func h2zMap(_ text: Character) -> Character? {
        h2z[text]
    }
}
