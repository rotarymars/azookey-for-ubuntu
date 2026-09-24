#!/usr/bin/env bash
# Build a signed APT repository holding one .deb, for GitHub Pages. Users add
# it with `deb [signed-by=<key.asc>] <url> ./` (a flat repository):
#
#   OUT_DIR/InRelease, Release, Release.gpg   the signed index
#   OUT_DIR/Packages, Packages.gz
#   OUT_DIR/key.asc                            the public key users give apt
#   OUT_DIR/pool/<deb>
#
# Signs with the only secret key in GnuPG's keyring; CI imports it from the
# APT_SIGNING_KEY secret into an empty GNUPGHOME. Then apt itself checks the
# result, with its own temporary state (nothing on the system changes): it must
# accept the signature and download exactly this package.
#
# Usage: scripts/build-apt-repo.sh OUT_DIR DEB
set -euo pipefail
export LC_ALL=C

OUT="$1"
DEB="$2"
NAME="$(dpkg-deb --field "$DEB" Package)"
VERSION="$(dpkg-deb --field "$DEB" Version)"
ARCH="$(dpkg-deb --field "$DEB" Architecture)"

# Refusing a keyring with several keys keeps a personal keyring (and its
# public keys, which key.asc would carry) out of the repository.
KEYS="$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "sec" {s = 1} $1 == "fpr" && s {print $10; s = 0}')"
if [ "$(printf '%s' "$KEYS" | grep -c .)" -ne 1 ]; then
    echo "Need exactly one secret key in GnuPG's keyring; point GNUPGHOME at the signing key's." >&2
    exit 1
fi
KEY="$KEYS"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
rm -rf "$OUT"
mkdir -p "$OUT/pool"
OUT="$(cd "$OUT" && pwd)"
cp "$DEB" "$OUT/pool/"

# Filename: fields are relative to the repository URL, so scan from its root.
(cd "$OUT" && apt-ftparchive packages pool) > "$OUT/Packages"
gzip -9nk "$OUT/Packages"
# Written outside OUT_DIR, or apt-ftparchive lists the half-written Release in itself.
apt-ftparchive -o APT::FTPArchive::Release::Origin=ibus-azookey \
    -o APT::FTPArchive::Release::Label=ibus-azookey \
    release "$OUT" > "$WORK/Release"
mv "$WORK/Release" "$OUT/Release"
gpg --batch --yes --local-user "$KEY" --digest-algo SHA512 \
    --armor --detach-sign --output "$OUT/Release.gpg" "$OUT/Release"
gpg --batch --yes --local-user "$KEY" --digest-algo SHA512 \
    --clearsign --output "$OUT/InRelease" "$OUT/Release"
gpg --batch --armor --export-options export-minimal --export "$KEY" > "$OUT/key.asc"

# Check it the way a user's apt sees it.
mkdir -p "$WORK/apt/lists/partial" "$WORK/apt/cache/archives/partial" "$WORK/apt/empty" "$WORK/download"
touch "$WORK/apt/status"
echo "deb [signed-by=$OUT/key.asc] file:$OUT ./" > "$WORK/apt/sources.list"
APT_OPTIONS=(
    -o Dir::Etc::SourceList="$WORK/apt/sources.list"
    -o Dir::Etc::SourceParts="$WORK/apt/empty"
    -o Dir::Etc::Preferences="$WORK/apt/preferences"
    -o Dir::Etc::PreferencesParts="$WORK/apt/empty"
    -o Dir::State::Lists="$WORK/apt/lists"
    -o Dir::State::status="$WORK/apt/status"
    -o Dir::Cache="$WORK/apt/cache"
    -o Debug::NoLocking=1
    -o APT::Architecture="$ARCH"
    -o APT::Architectures="$ARCH"
)
apt-get "${APT_OPTIONS[@]}" --error-on=any update
CANDIDATE="$(apt-cache "${APT_OPTIONS[@]}" policy "$NAME" | sed -n 's/^ *Candidate: //p')"
if [ "$CANDIDATE" != "$VERSION" ]; then
    echo "apt offers $NAME ${CANDIDATE:-(nothing)} from the repository, expected $VERSION" >&2
    exit 1
fi
(cd "$WORK/download" && apt-get "${APT_OPTIONS[@]}" download "$NAME")
cmp "$DEB" "$WORK/download/"*.deb

echo ">> $OUT: $NAME $VERSION ($ARCH), signed by $KEY"
