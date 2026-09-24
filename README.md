# ibus-azookey

Japanese input for Ubuntu with [azooKey](https://github.com/azooKey/azooKey)'s
conversion engine and its Zenzai neural model: an **unofficial** IBus port.

[日本語版 README](README.ja.md)

- Accurate kana-kanji conversion: azooKey's dictionary plus the zenz-v3.2 model,
  which chooses words from context
- Learns the words you pick
- Same keys and conversion flow as azooKey on the Mac
- Runs entirely on your computer: no network, no GPU needed

This project is not affiliated with or endorsed by the azooKey project.

## Requirements

- Ubuntu 24.04 with GNOME (it uses IBus, Ubuntu's standard input method framework)
- A 64-bit x86 CPU with AVX2: most PCs from the last ten years. Check with
  `grep -c avx2 /proc/cpuinfo`; any number above 0 is fine.
- About 180 MB of disk space and 140 MB of memory

## Install

1. Add the package repository, install ibus-azookey and restart IBus:
   ```sh
   sudo wget -qO /etc/apt/keyrings/ibus-azookey.asc https://rotarymars.github.io/azookey-for-ubuntu/key.asc
   echo "deb [signed-by=/etc/apt/keyrings/ibus-azookey.asc] https://rotarymars.github.io/azookey-for-ubuntu ./" | sudo tee /etc/apt/sources.list.d/ibus-azookey.list
   sudo apt update
   sudo apt install ibus-azookey
   ibus restart
   ```
   New versions then come with your other updates (see [Updating](#updating)).
   To install without adding a repository, download
   `ibus-azookey_<version>_amd64.deb` from [Releases](../../releases/latest)
   and run `sudo apt install ./ibus-azookey_*_amd64.deb` and `ibus restart`
   instead; you then install each new version the same way.
2. Open **Settings → Keyboard → Input Sources → + Add Input Source…**, search
   `azoo`, select **Japanese (azooKey)** and click **Add**.
   If Settings was already open, quit it first (see [Troubleshooting](#troubleshooting)).
3. Switch to azooKey with **Super+Space** (or your own input-source shortcut).
   The top bar shows **あ**.

## Typing

Type in romaji. It appears as hiragana, with the top conversion shown below.

| Key | Action |
|---|---|
| Space | Convert. Press again to open the candidate list |
| Space / ↓ / ↑ | Move through candidates (Shift+Space goes back) |
| 1–9 | Pick a candidate from the list |
| Enter | Commit |
| Esc | Step back: list → conversion → hiragana → cancel |
| Shift+← / Shift+→ | Make the segment being converted shorter / longer |
| → | Commit the first segment and convert the rest |
| F6 / F7 / F8 | Hiragana / katakana / half-width katakana |
| F9 / F10 | Full-width / half-width letters |
| Ctrl+Backspace | In the list: forget what was learned for that candidate |

While typing, Emacs-style keys work too: Ctrl+H (backspace), Ctrl+N / Ctrl+P
(down / up), Ctrl+I / Ctrl+O (resize the segment), Ctrl+J / K / ; / L / : (F6–F10).

On a Japanese (JIS) keyboard, 英数 or 無変換 switches to direct input, かな or 変換
switches back to Japanese, and 半角/全角 toggles.

## Settings

Click **あ** in the top bar for quick switches: input mode, live conversion,
Zenzai and learning. **設定…** in that menu opens the settings window. The
same window opens from **⋮ → Preferences** next to azooKey in
**Settings → Keyboard**. It covers:

- **Learning**: learn from your choices, only use what was learned, or off; reset learning
- **Live conversion**: show kanji as you type instead of converting with Space
- **Input method**: romaji, AZIK, or kana input (US or JIS layout)
- **Punctuation** (。、 or ．，), space width, the backslash/yen key, candidates per page
- **Zenzai**: on or off, the model, accuracy versus speed, a short
  self-description (e.g. エンジニア) that steers conversions, and use of the text
  around the cursor

zenz-v3.2-small comes with the package. Choosing another model (the lighter
zenz-v3.2-xsmall, or the older v3.1 models) downloads it from Hugging Face into
`~/.local/share/ibus-azookey/models` after asking.

Changes apply the next time you click into a text field.

<details>
<summary>Editing the settings file directly</summary>

Settings are stored in `~/.config/ibus-azookey/config.json`. Missing keys use
the defaults below.

| Key | Default | Meaning |
|---|---|---|
| `learning` | `inputAndOutput` | `inputAndOutput` learns and uses learning, `onlyOutput` only uses it, `nothing` turns it off |
| `liveConversion` | `false` | show kanji while typing instead of converting on Space |
| `zenzaiEnabled` | `true` | neural conversion |
| `zenzaiModel` | `zenz-v3.2-small` | `zenz-v3.2-small`, `zenz-v3.2-xsmall`, `zenz-v3.1-small` or `zenz-v3.1-xsmall`; others than the bundled one must be downloaded in the settings window first |
| `zenzaiInferenceLimit` | `5` | higher is slower but can be more accurate |
| `zenzaiProfile` | `""` | a short self-description that steers conversion |
| `useSurroundingText` | `true` | give Zenzai the text around the cursor as context |
| `inputStyle` | `roman` | `roman`, `azik`, `kanaUS`, `kanaJIS` |
| `punctuationStyle` | `kutenAndToten` | `kutenAndToten` 。、 / `kutenAndComma` 。， / `periodAndToten` ．、 / `periodAndComma` ．， |
| `typeBackSlash` | `true` | the backslash key types \ (`false`: ¥) |
| `typeHalfSpace` | `false` | Space types a half-width space in Japanese mode |
| `candidatePageSize` | `9` | candidates per page |

</details>

### How learning works

Learning is on by default, so words you pick rank higher next time. With
Zenzai on, a learned word gets a boost, but the model still decides the top
conversion when the context clearly calls for another word (this is how
azooKey itself works); your word still moves up the candidate list. With
Zenzai off, a learned word becomes the first conversion. Learning data lives in
`~/.local/share/ibus-azookey`.

## Troubleshooting

**azooKey is not in the Add Input Source list.** Run `ibus restart`, then
quit Settings completely and open it again. Closing the window is not always
enough; `pkill gnome-control-center` makes sure.

**Typing does not produce Japanese.** Check that the top bar shows **あ**. If it
shows **A**, click it and choose ひらがな.

**The first key after logging in is slow.** The dictionary and the model load
on first use (about 0.2 seconds).

**Conversion feels slow.** In the settings window, lower the Zenzai inference
limit or turn Zenzai off.

**Anything else.** Please open an issue with the version (shown at the bottom
of the settings window) and the log from
`journalctl --user -b -u org.freedesktop.IBus.session.GNOME.service | grep ibus-azookey`.

## Updating

With the package repository, new versions arrive through Software Updater or
`sudo apt upgrade`. With a downloaded `.deb`, install the newer file the same
way as the first one. Your settings, learning data and downloaded models are
kept.

The new version starts the next time you log in, or right away after
`ibus restart`. Until then, the version at the bottom of the settings window
says that an update is waiting.

## Uninstall

Remove **Japanese (azooKey)** under **Settings → Keyboard → Input Sources**, then:

```sh
sudo apt remove ibus-azookey
ibus restart
sudo rm -f /etc/apt/sources.list.d/ibus-azookey.list /etc/apt/keyrings/ibus-azookey.asc   # the package repository
rm -rf ~/.config/ibus-azookey ~/.local/share/ibus-azookey   # optional: settings and learning data
```

## Building from source

See [docs/building.md](docs/building.md).

## License

This repository's code is MIT licensed ([LICENSE](LICENSE)). It builds on
AzooKeyKanaKanjiConverter and parts of azooKey-Desktop (MIT), azooKey's
dictionary and the zenz-v3.2 model (Apache-2.0), and llama.cpp (MIT). See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.
