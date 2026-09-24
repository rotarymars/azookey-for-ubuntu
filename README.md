# ibus-azookey: azooKey Japanese input for Ubuntu (unofficial)

An IBus input method that brings [azooKey](https://github.com/azooKey/azooKey)'s
kana-kanji conversion to Ubuntu and Debian desktops:

- **AzooKeyKanaKanjiConverter**, azooKey's conversion engine, with its dictionary
  and learning
- **Zenzai** neural conversion with the **zenz-v3.2** model (Apache-2.0), running on
  the CPU through llama.cpp
- **azooKey-Desktop's input logic** (state machine, segment editing, key
  bindings), so it behaves like azooKey on the Mac

It is an unofficial port and is not affiliated with or endorsed by the azooKey
project. Everything used is MIT or Apache-2.0 and the model may be
redistributed; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Developed on Ubuntu 24.04 (GNOME on Wayland, IBus 1.5.29) and tested with unit
tests plus an end-to-end test that types through a real (private) ibus-daemon.

## Build

```sh
scripts/install-swift.sh   # Swift 6.3.3 into ~/.local/share/swift-toolchains (no root, no PATH changes)
make                       # llama.cpp, model download, engine -> build/stage
make test                  # unit tests
make e2e                   # types through a private ibus-daemon (your running IBus is not touched)
```

`make` builds the azooKey fork of llama.cpp (tag b4846, the version the
converter's headers expect), downloads zenz-v3.2-small from Hugging Face pinned by
commit and SHA-256, and links the Swift runtime statically so the installed engine
does not depend on the toolchain. `make MODEL=xsmall` uses the smaller model.

Build dependencies (Ubuntu package names): `git cmake ninja-build g++ pkg-config
curl gpg libibus-1.0-dev libglib2.0-dev`, plus what Swift itself needs
(see <https://www.swift.org/install/linux/>).

## Install

Either build a package, which `apt` can remove cleanly later:

```sh
make deb
sudo apt install ./build/ibus-azookey_0.1.0_amd64.deb   # remove: sudo apt remove ibus-azookey
```

or copy the staged files directly:

```sh
sudo make install        # remove: sudo make uninstall
```

Then, as your user:

```sh
ibus restart
```

and add the input source in **Settings → Keyboard → Input Sources → + →
Japanese → azooKey**. Ctrl+Space (or Super+Space, depending on your GNOME
shortcut) switches between azooKey and your other layouts.

## Typing

| Key | While typing | While converting |
|---|---|---|
| letters | romaji → hiragana, the top conversion is previewed below | commit and keep typing |
| Space | convert | next candidate (Shift+Space: previous) |
| Space twice | open the candidate list | |
| 1–9 | | pick a candidate from the page |
| ↓ / ↑ | open the list | move in the list |
| Enter | commit as typed | commit the selection |
| Esc | cancel the input | step back (list → first conversion → hiragana) |
| Shift+← / Shift+→ (Ctrl+I / Ctrl+O) | | shrink / extend the segment |
| → | | commit the first segment, convert the rest |
| F6 / F7 / F8 / F9 / F10 | hiragana / katakana / half-width katakana / full-width / half-width alphanumerics (also Ctrl+J / K / ; / L / :) | |
| Ctrl+Backspace | | forget what was learned for this candidate |
| Ctrl+Shift+U | Unicode input (U+XXXX) | |

JIS keyboards: 英数/無変換 switch to direct input and かな/変換 back to Japanese;
半角/全角 toggles. The top bar shows あ or A.

## Settings

Click the あ indicator for quick toggles (input mode, live conversion, Zenzai,
learning) or choose **設定…** for the settings window, also reachable from the
input source's Preferences in GNOME Settings. Settings are stored in
`~/.config/ibus-azookey/config.json` and apply the next time a text field gets
focus.

| Key | Default | Meaning |
|---|---|---|
| `learning` | `inputAndOutput` | `inputAndOutput` learns and uses learning, `onlyOutput` uses existing learning only, `nothing` ignores it |
| `liveConversion` | `false` | show kanji while typing instead of converting on Space |
| `zenzaiEnabled` | `true` | neural conversion |
| `zenzaiModel` | `small` | `small` or `xsmall` (must be installed) |
| `zenzaiInferenceLimit` | `5` | more is slower but can be more accurate |
| `zenzaiProfile` | `""` | a short self-description that steers conversion, e.g. `エンジニア` |
| `useSurroundingText` | `true` | give Zenzai the text around the cursor as context |
| `inputStyle` | `roman` | `roman`, `azik`, `kanaUS`, `kanaJIS` |
| `punctuationStyle` | `kutenAndToten` | `kutenAndToten` 。、 / `kutenAndComma` 。， / `periodAndToten` ．、 / `periodAndComma` ．， |
| `typeBackSlash` | `true` | the backslash key types \ (false: ¥) |
| `typeHalfSpace` | `false` | Space types a half-width space in Japanese mode |
| `candidatePageSize` | `9` | candidates per page |

### Learning

Learning is on by default. Candidates you choose are remembered in
`~/.local/share/ibus-azookey/memory` and move up next time. With Zenzai on, a
learned word gets a boost but the model still has the final say on the top
conversion when context clearly favors another word (azooKey's design); it is
always ranked higher in the candidate list. With Zenzai off, the learned word
becomes the first conversion. Reset learning from the settings window.

## Performance

On a Ryzen 7 7735HS, with zenz-v3.2-small, Zenzai on and 8 CPU threads, a keystroke
takes about 20 ms on average and about 50 ms at worst through IBus. The first
keystroke after login loads the dictionary and the model (about 0.2 s). The
engine uses about 140 MB of memory.

## Layout

```
Sources/AzooKeyCore/Upstream   azooKey-Desktop's input logic (MIT, origin in each file)
Sources/AzooKeyCore            Linux key table, settings, sessions
Sources/AzooKeyIBusShim        the IBusEngine GObject subclass (C)
Sources/ibus-engine-azookey    the engine: IBus callbacks, rendering, status menu
Sources/azookey-cli            conversion and latency tool (azookey-cli --help in main.swift)
tools/ibus-setup-azookey       settings window (GTK4/libadwaita)
tests/                         unit tests and the IBus end-to-end test
scripts/                       toolchain, llama.cpp, model and .deb helpers
```

The engine logs to the user journal through GNOME's IBus service:
`journalctl --user -b -u org.freedesktop.IBus.session.GNOME.service | grep ibus-azookey`.

## Limitations

- No user dictionary editor yet.
- Zenzai personalization (azooKey-Desktop's personal n-gram model) is not available.
- GNOME Shell does not forward preedit colors to Wayland apps, so the segment
  being converted is marked by the cursor position rather than highlighting
  (X11 and Qt apps show the highlight).
- CPU inference only.

## License

MIT for this repository's code; see [LICENSE](LICENSE). Third-party components
and their licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
