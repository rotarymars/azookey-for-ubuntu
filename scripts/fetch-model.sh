#!/usr/bin/env bash
# Download a Zenzai model listed in data/models.json, from its "url" or else
# from Hugging Face pinned to a repository commit, and verify it by SHA-256.
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

# "URL SHA256 LICENSE", then the text of the SOURCE file, from the catalog
INFO="$(python3 - "$ROOT/data/models.json" "$ID" <<'EOF'
import json, sys
catalog, wanted = sys.argv[1], sys.argv[2]
for m in json.load(open(catalog, encoding="utf-8")):
    if m["id"] == wanted:
        if m.get("url"):
            url, origin = m["url"], f"URL:      {m['url']}"
        else:
            url = f"https://huggingface.co/{m['repo']}/resolve/{m['revision']}/{m['file']}"
            origin = f"Model:    {m['repo']}\nRevision: {m['revision']}"
        print(url, m["sha256"], m["license"])
        print(origin)
        print(f"File:     {m['file']} (SHA-256 {m['sha256']})")
        print(f"Author:   {m.get('author', 'Miwa Keita (https://huggingface.co/Miwa-Keita)')}")
        print(f"License:  {m['license']} (see LICENSE)")
        print(f"Changes:  {m.get('changes', 'none; redistributed unmodified.')}")
        break
else:
    sys.exit(f"unknown model {wanted}; see data/models.json")
EOF
)"
read -r URL SHA256 LICENSE <<<"$(head -n 1 <<<"$INFO")"

DEST="$ROOT/build/models/$ID"
TARGET="$DEST/ggml-model-Q5_K_M.gguf"   # the name the engine loads

if [ -f "$TARGET" ] && echo "$SHA256  $TARGET" | sha256sum -c --status; then
    echo ">> $TARGET is up to date"
    exit 0
fi

mkdir -p "$DEST"
echo ">> downloading $URL"
curl -fL --retry 3 -o "$TARGET.part" "$URL"
echo "$SHA256  $TARGET.part" | sha256sum -c -
mv "$TARGET.part" "$TARGET"

# The model files only carry a license tag, so ship the license and the
# provenance next to the weights.
if [ "$LICENSE" = Apache-2.0 ]; then
    cp "$ROOT/data/licenses/Apache-2.0.txt" "$DEST/LICENSE"
else
    echo "$LICENSE: https://creativecommons.org/licenses/by-sa/4.0/" > "$DEST/LICENSE"
fi
tail -n +2 <<<"$INFO" > "$DEST/SOURCE"
echo ">> saved $TARGET"
