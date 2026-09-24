#!/usr/bin/env bash
# Build the azooKey fork of llama.cpp as CPU-only shared libraries.
#
# AzooKeyKanaKanjiConverter vendors the llama.cpp headers of tag b4846 and, on
# Linux, links against a system-provided libllama. The library we link must
# therefore be built from exactly that tag so the C ABI matches the headers.
#
# Output: build/lib/{libllama,libggml,libggml-base,libggml-cpu}.so, plus a
#         build/lib/.llama-<mode> marker naming the CPU target they were built for.
# Env:    LLAMA_PORTABLE=1  build for any x86-64 CPU with AVX2 (x86-64-v3), for
#                           packages that run on other machines; the default
#                           targets this machine's CPU (-march=native)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA_REPO="${LLAMA_REPO:-https://github.com/azooKey/llama.cpp.git}"
LLAMA_COMMIT="10131b23ee0dbd9d03dfc618cec9fe3402919277" # tag b4846
SRC="$ROOT/.deps/llama.cpp"
OUT="$ROOT/build/lib"

MODE=native
CPU_FLAGS=(-DGGML_NATIVE=ON)
if [ "${LLAMA_PORTABLE:-0}" = 1 ]; then
    MODE=portable
    CPU_FLAGS=(-DGGML_NATIVE=OFF)
    if [ "$(uname -m)" = x86_64 ]; then
        CPU_FLAGS+=(-DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_AVX512=OFF)
    fi
fi
# One build tree per mode: ggml derives its instruction-set options from
# GGML_NATIVE only on first configure, so flipping it in an existing tree
# would keep the old (cached) choices.
BUILD="$ROOT/.deps/llama-build-$MODE"

if [ ! -d "$SRC/.git" ]; then
    mkdir -p "$SRC"
    git -C "$SRC" init -q
    git -C "$SRC" remote add origin "$LLAMA_REPO"
fi
if [ "$(git -C "$SRC" rev-parse -q --verify HEAD 2>/dev/null || true)" != "$LLAMA_COMMIT" ]; then
    echo ">> fetching llama.cpp $LLAMA_COMMIT"
    git -C "$SRC" fetch -q --depth 1 origin "$LLAMA_COMMIT"
    git -C "$SRC" checkout -q --detach FETCH_HEAD
fi

# GGML_BACKEND_DL must stay OFF: the converter looks the CPU backend up with
# ggml_backend_dev_by_type() right after llama_backend_init() and never calls
# ggml_backend_load_all(), so the CPU backend has to be linked in.
# OpenMP is disabled so idle inference threads sleep instead of spin-waiting
# inside a process that stays resident for the whole desktop session.
cmake -S "$SRC" -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_INSTALL_RPATH='$ORIGIN' \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
    -DLLAMA_CURL=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_SERVER=OFF \
    "${CPU_FLAGS[@]}" \
    -DGGML_OPENMP=OFF \
    -DGGML_BACKEND_DL=OFF
cmake --build "$BUILD" --target llama -j"$(nproc)"

mkdir -p "$OUT"
rm -f "$OUT"/lib*.so* "$OUT"/.llama-*
find "$BUILD" -name 'lib*.so*' \( -type f -o -type l \) -exec cp -a {} "$OUT"/ \;
touch "$OUT/.llama-$MODE"
echo ">> llama.cpp libraries ($MODE) staged in $OUT:"
ls -l "$OUT"
