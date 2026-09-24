#!/usr/bin/env bash
# Download a Zenzai model listed in data/models.json from Hugging Face, pinned
# to a repository commit and verified by SHA-256.
#
# Usage: scripts/fetch-model.sh [MODEL_ID]   (default: zenz-v3.2-small;
#        "small" and "xsmall" mean the zenz-v3.2 models)
# Output: build/models/<MODEL_ID>/ggml-model-Q5_K_M.gguf plus LICENSE and SOURCE
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ID="${1:-${ZENZ_MODEL:-zenz-v3.2-small}}"
case "$ID" in
    small | xsmall) ID="zenz-v3.2-$ID" ;;
esac

# REPO REVISION FILE SHA256 LICENSE from the catalog
read -r REPO REVISION FILE SHA256 LICENSE < <(python3 - "$ROOT/data/models.json" "$ID" <<'EOF'
import json, sys
catalog, wanted = sys.argv[1], sys.argv[2]
for model in json.load(open(catalog, encoding="utf-8")):
    if model["id"] == wanted:
        print(model["repo"], model["revision"], model["file"], model["sha256"], model["license"])
        break
else:
    sys.exit(f"unknown model {wanted}; see data/models.json")
EOF
)

DEST="$ROOT/build/models/$ID"
TARGET="$DEST/$FILE"

if [ -f "$TARGET" ] && echo "$SHA256  $TARGET" | sha256sum -c --status; then
    echo ">> $TARGET is up to date"
    exit 0
fi

mkdir -p "$DEST"
echo ">> downloading $REPO@$REVISION"
curl -fL --retry 3 -o "$TARGET.part" "https://huggingface.co/$REPO/resolve/$REVISION/$FILE"
echo "$SHA256  $TARGET.part" | sha256sum -c -
mv "$TARGET.part" "$TARGET"

# The model repositories only carry a license tag, so ship the license and the
# provenance next to the weights.
if [ "$LICENSE" = Apache-2.0 ]; then
    cp "$ROOT/data/licenses/Apache-2.0.txt" "$DEST/LICENSE"
else
    echo "$LICENSE: https://creativecommons.org/licenses/by-sa/4.0/" > "$DEST/LICENSE"
fi
cat > "$DEST/SOURCE" <<EOF
Model:    $REPO
Revision: $REVISION
File:     $FILE (SHA-256 $SHA256)
Author:   Miwa Keita (https://huggingface.co/Miwa-Keita)
License:  $LICENSE (see LICENSE)
Changes:  none; redistributed unmodified.
EOF
echo ">> saved $TARGET"
