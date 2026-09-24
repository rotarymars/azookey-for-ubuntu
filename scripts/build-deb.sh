#!/usr/bin/env bash
# Package the staged tree (make stage) as build/ibus-azookey_<version>_<arch>.deb.
# Installing it through the package manager lets `apt remove ibus-azookey`
# undo everything later.
#
# Usage: scripts/build-deb.sh VERSION STAGE_DIR
set -euo pipefail

VERSION="$1"
STAGE="$(cd "$2" && pwd)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="$(dpkg --print-architecture)"
OUTPUT="$ROOT/build/ibus-azookey_${VERSION}_${ARCH}.deb"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PACKAGE="$WORK/package"
mkdir -p "$PACKAGE/DEBIAN" "$WORK/source/debian"
cp -r "$STAGE/." "$PACKAGE/"
chmod -R u+rwX,go=rX "$PACKAGE"

# System libraries the engine and the bundled llama.cpp need. The llama.cpp
# libraries themselves are private (lib/ next to the engine, found via RPATH).
printf 'Source: ibus-azookey\n\nPackage: ibus-azookey\nArchitecture: any\n' > "$WORK/source/debian/control"
LIBDIR="$PACKAGE/usr/lib/ibus-azookey"
SHLIBS="$(cd "$WORK/source" && dpkg-shlibdeps -O --ignore-missing-info -l"$LIBDIR/lib" \
    -e"$LIBDIR/ibus-engine-azookey" "$LIBDIR"/lib/*.so 2>/dev/null | sed -n 's/^shlibs:Depends=//p')"
[ -n "$SHLIBS" ] || { echo "dpkg-shlibdeps found no dependencies" >&2; exit 1; }

# DEB_MAINTAINER="Name <email>" overrides the git identity (CI has none).
MAINTAINER="${DEB_MAINTAINER:-$(git -C "$ROOT" config user.name 2>/dev/null || echo "$USER") <$(git -C "$ROOT" config user.email 2>/dev/null || echo "$USER@localhost")>}"
cat > "$PACKAGE/DEBIAN/control" <<EOF
Package: ibus-azookey
Version: $VERSION
Architecture: $ARCH
Maintainer: $MAINTAINER
Installed-Size: $(du -sk --exclude=DEBIAN "$PACKAGE" | cut -f1)
Depends: $SHLIBS, ibus, python3, python3-gi, gir1.2-gtk-4.0, gir1.2-adw-1
Section: utils
Priority: optional
Description: Japanese input method for IBus using azooKey's converter (unofficial)
 An unofficial Linux port of the azooKey Japanese input method. It uses
 AzooKeyKanaKanjiConverter with the Zenzai neural model (zenz-v3.2) running
 on the CPU through llama.cpp, and azooKey-Desktop's input logic.
 .
 Not affiliated with or endorsed by the azooKey project. See
 /usr/share/doc/ibus-azookey for licenses.
EOF

dpkg-deb --root-owner-group -Zxz --build "$PACKAGE" "$OUTPUT" >/dev/null
echo ">> built $OUTPUT"
dpkg-deb --info "$OUTPUT" | sed -n '/Package:/,/Depends:/p'
