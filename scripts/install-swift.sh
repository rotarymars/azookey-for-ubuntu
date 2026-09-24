#!/usr/bin/env bash
# Install a Swift toolchain from swift.org into ~/.local/share/swift-toolchains
# without root, PATH or shell-profile changes (the Makefile finds it there).
# The download is checked against swift.org's release signing keys, using a
# throwaway GnuPG home so your own keyring is not touched.
#
# Usage: scripts/install-swift.sh [VERSION]   (default: 6.3.3)
set -euo pipefail

SWIFT_VERSION="${1:-6.3.3}"
# Read the distribution in a subshell: os-release defines its own VERSION.
ID="$(. /etc/os-release && echo "$ID")"
VERSION_ID="$(. /etc/os-release && echo "$VERSION_ID")"
case "${ID}-${VERSION_ID}" in
    ubuntu-24.04) PLATFORM=ubuntu2404 ; SUFFIX=ubuntu24.04 ;;
    ubuntu-22.04) PLATFORM=ubuntu2204 ; SUFFIX=ubuntu22.04 ;;
    debian-12)    PLATFORM=debian12   ; SUFFIX=debian12 ;;
    *) echo "no swift.org toolchain mapping for ${ID} ${VERSION_ID}; see https://www.swift.org/install/" >&2; exit 1 ;;
esac
[ "$(uname -m)" = x86_64 ] || { PLATFORM="${PLATFORM}-aarch64"; SUFFIX="${SUFFIX}-aarch64"; }

NAME="swift-${SWIFT_VERSION}-RELEASE-${SUFFIX}"
URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/${PLATFORM}/swift-${SWIFT_VERSION}-RELEASE/${NAME}.tar.gz"
DEST="$HOME/.local/share/swift-toolchains"

if [ -x "$DEST/$NAME/usr/bin/swift" ]; then
    echo ">> $DEST/$NAME is already installed"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo ">> downloading $URL"
curl -fL --retry 3 -o "$WORK/swift.tar.gz" "$URL"
curl -fsSL -o "$WORK/swift.tar.gz.sig" "$URL.sig"
curl -fsSL --compressed -o "$WORK/keys.asc" https://www.swift.org/keys/all-keys.asc

export GNUPGHOME="$WORK/gnupg"
mkdir -m 700 "$GNUPGHOME"
gpg --quiet --import "$WORK/keys.asc"
# Release keys expire after signing, so an expired-key warning is expected;
# the signature itself must be good.
gpg --verify "$WORK/swift.tar.gz.sig" "$WORK/swift.tar.gz" 2>&1 | tee "$WORK/verify.log"
grep -q "Good signature" "$WORK/verify.log" || { echo "signature check failed" >&2; exit 1; }

mkdir -p "$DEST"
tar -xzf "$WORK/swift.tar.gz" -C "$DEST"
"$DEST/$NAME/usr/bin/swift" --version
echo ">> installed into $DEST/$NAME"
