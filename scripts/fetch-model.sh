#!/usr/bin/env bash
# Download a Zenzai model (zenz-v3.2, Apache-2.0, by Miwa Keita) from Hugging
# Face, pinned to a repository commit and verified by SHA-256.
#
# Usage: scripts/fetch-model.sh [small|xsmall]   (default: small)
# Output: build/models/zenz-v3.2-<variant>/ggml-model-Q5_K_M.gguf
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VARIANT="${1:-${ZENZ_VARIANT:-small}}"

case "$VARIANT" in
    small)
        REPO="Miwa-Keita/zenz-v3.2-small-gguf"
        REVISION="c67e03e07d215c869f591b274c1631170d3e11fe"
        SHA256="29c223d4c23327b80fd13ebb5ab2555057a46317997d5da391584ffbef0db673"
        ;;
    xsmall)
        REPO="Miwa-Keita/zenz-v3.2-xsmall-gguf"
        REVISION="4f5423f0fad41a73b1242eb96fe5c12ae4fdca83"
        SHA256="00c64b3d318045a708d0cad5434faccab10f5481a49e6362864551fd0995fa58"
        ;;
    *)
        echo "unknown model variant: $VARIANT (expected small or xsmall)" >&2
        exit 2
        ;;
esac

DEST="$ROOT/build/models/zenz-v3.2-$VARIANT"
FILE="$DEST/ggml-model-Q5_K_M.gguf"

if [ -f "$FILE" ] && echo "$SHA256  $FILE" | sha256sum -c --status; then
    echo ">> $FILE is up to date"
    exit 0
fi

mkdir -p "$DEST"
echo ">> downloading $REPO@$REVISION"
curl -fL --retry 3 -o "$FILE.part" \
    "https://huggingface.co/$REPO/resolve/$REVISION/ggml-model-Q5_K_M.gguf"
echo "$SHA256  $FILE.part" | sha256sum -c -
mv "$FILE.part" "$FILE"

# The model repositories only carry a license tag, so ship the license text and
# the provenance next to the weights (Apache-2.0 section 4 requires the former).
cp "$ROOT/data/licenses/Apache-2.0.txt" "$DEST/LICENSE"
cat > "$DEST/SOURCE" <<EOF
Model:    $REPO
Revision: $REVISION
File:     ggml-model-Q5_K_M.gguf (SHA-256 $SHA256)
Author:   Miwa Keita (https://huggingface.co/Miwa-Keita)
License:  Apache-2.0 (see LICENSE)
Changes:  none; redistributed unmodified.
EOF
echo ">> saved $FILE"
