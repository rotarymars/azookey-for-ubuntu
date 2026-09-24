# Building ibus-azookey

This guide is for building from source, testing and making releases. For
installing and using the input method, see the [README](../README.md).

## Requirements

Ubuntu 24.04 on x86-64 (other setups are untested).

```sh
# build tools and IBus headers
sudo apt install git cmake ninja-build g++ pkg-config curl gpg libibus-1.0-dev libglib2.0-dev
# what the Swift toolchain needs (from swift.org's Ubuntu 24.04 image)
sudo apt install binutils unzip gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
    libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libncurses-dev libz3-dev tzdata zlib1g-dev
# for `make e2e` and the settings window
sudo apt install ibus dbus-daemon python3-gi gir1.2-ibus-1.0 gir1.2-gtk-4.0 gir1.2-adw-1
```

Swift 6.1 or newer is required. `scripts/install-swift.sh` installs Swift 6.3.3
from swift.org into `~/.local/share/swift-toolchains`, checking the download
against swift.org's signing keys. It needs no root and does not change your
PATH; the Makefile finds it there. A `swift` already on your PATH is used
instead if present.

## Build and test

```sh
scripts/install-swift.sh
make        # llama.cpp, the zenz-v3.2-small model and the engine, staged into build/stage/usr
make test   # unit tests
make e2e    # end-to-end test through a private ibus-daemon
```

- `make` builds the azooKey fork of llama.cpp for this machine's CPU,
  downloads the model from Hugging Face (pinned by commit and checked by
  SHA-256), and builds the engine with the Swift runtime linked in statically.
- `make MODEL=xsmall` bundles the smaller, faster model instead.
- `make e2e` starts its own ibus-daemon on a private D-Bus session with
  temporary config and cache directories, then types into the engine through a
  real IBus input context. Your desktop's IBus is not touched. It fails on any
  GLib assertion in the daemon or engine log.
- `AZOOKEY_IBUS_DEBUG=1 KEEP_E2E_TMP=1 make e2e` keeps the test's temporary
  directory, whose `daemon.log` has the engine's debug log with per-key timings.

## Installing your build

```sh
make deb
sudo apt install ./build/ibus-azookey_*_amd64.deb   # or: sudo make install
ibus restart
```

`sudo make install` only copies the staged tree, so run `make` as your user
first. `sudo make uninstall` removes it again.

## Making a release

1. Bump `VERSION` in the `Makefile` and `PackageMetadata.version` in
   `Sources/AzooKeyCore/Support.swift`.
2. `make release` builds `build/ibus-azookey_<version>_amd64.deb`. It is the
   same as `make deb`, except that llama.cpp is built for any x86-64 CPU with
   AVX2 (x86-64-v3) rather than `-march=native`, so the package also runs on
   other machines. It is as fast as the native build on a Ryzen 7 7735HS.
3. `make LLAMA_PORTABLE=1 e2e` tests that build. A plain `make e2e` would switch
   back to the native llama.cpp first.
4. Create a GitHub release and attach the `.deb`.

Before publishing binaries, read the note on the emoji dictionary in
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md): its repository has no
license file.

## How it fits together

```
ibus-daemon ── D-Bus ── ibus-engine-azookey
                          ├─ AzooKeyIBusShim (C): the IBusEngine GObject subclass
                          ├─ EngineController (Swift): preedit, candidate list, status menu
                          └─ AzooKeyCore
                               ├─ UserAction+Linux: X11 keysyms → azooKey actions
                               ├─ InputSession: azooKey-Desktop's input state machine
                               │    and SegmentsManager, one per input context
                               └─ AzooKeyKanaKanjiConverter ── llama.cpp (Zenzai)

tools/ibus-setup-azookey (Python, GTK4) ── config.json ── read by the engine on focus
```

| Path | Contents |
|---|---|
| `Sources/AzooKeyCore/Upstream` | azooKey-Desktop's input logic (MIT); each file notes its origin and any changes |
| `Sources/AzooKeyCore` | Linux key table, settings, conversion sessions |
| `Sources/AzooKeyIBusShim` | the IBusEngine GObject subclass (C) |
| `Sources/ibus-engine-azookey` | the engine: IBus callbacks, rendering, status menu |
| `Sources/azookey-cli` | conversion and latency tool |
| `tools/ibus-setup-azookey` | settings window (GTK4/libadwaita) |
| `data/` | IBus component, GNOME Settings entry, icon, license texts |
| `tests/` | unit tests and the IBus end-to-end test |
| `scripts/` | Swift installer, llama.cpp build, model download, `.deb` packaging |

## Pinned upstream versions

| Component | Pinned at | Where |
|---|---|---|
| AzooKeyKanaKanjiConverter | `ad714fe`, with the `ZenzaiCPU` trait | `Package.swift`, `Package.resolved` |
| azooKey-Desktop input logic | `b7ec0e4` | `Sources/AzooKeyCore/Upstream` |
| llama.cpp (azooKey fork) | tag `b4846` | `scripts/build-llama.sh` |
| zenz-v3.2-small / xsmall | Hugging Face commit and SHA-256 | `scripts/fetch-model.sh` |

The llama.cpp tag must match the `llama.h` that AzooKeyKanaKanjiConverter
vendors, and the AzooKeyKanaKanjiConverter revision is the one azooKey-Desktop
`b7ec0e4` builds against, so move them together.

## Performance

On a Ryzen 7 7735HS with zenz-v3.2-small and Zenzai on (8 inference threads),
a keystroke takes 10–20 ms on average and about 50 ms at worst through IBus.
The engine uses about 140 MB of memory. To measure the conversion path
without IBus (with the toolchain's `usr/bin` on your PATH):

```sh
swift build -c release --product azookey-cli
LD_LIBRARY_PATH=build/lib .build/release/azookey-cli --session --delay 50 --limit 5 \
    --model build/models/zenz-v3.2-small/ggml-model-Q5_K_M.gguf kyouhaiitenkidesune
```

## Notes for contributors

- **Why Swift:** azooKey's conversion engine and its macOS input logic are
  Swift libraries. Writing the engine in Swift reuses both in one process,
  instead of reimplementing them or talking to a separate Swift conversion
  server over IPC. Only the GObject subclass that IBus requires is in C.
- **Static Swift runtime:** with C++ interoperability, `libswiftCxx*.a` are only
  in the toolchain's dynamic runtime directory (swiftlang/swift#78003); the
  Makefile adds it to the linker path.
- **IBus component file:** every component-level element in
  `data/azookey.xml.in` must be present and non-empty, because ibus-daemon
  writes them into its registry cache without NULL checks.
- **GNOME Settings** finds an engine's preferences through
  `ibus-setup-<engine>.desktop`, not the component's `<setup>` element.
- **Wayland:** GNOME Shell does not pass preedit colors to Wayland apps, so the
  segment being converted is marked by the cursor position there.
