#!/usr/bin/env bash
#
# Build the signed apt repository that ships next to the static site.
#
# The package itself is the same arm64 .deb the Linux release workflow already
# publishes. This script only adds the apt index and its signature; it never
# builds or modifies the .deb.
#
# Required in CI:
#   GITHUB_REPOSITORY  owner/repo
#   GH_TOKEN           token that can read the release
#   APT_GPG_PRIVATE_KEY  ASCII-armored signing key
#
# Optional:
#   RELEASE_TAG        linux-vX.Y.Z (defaults to the newest linux tag)
#   DEB_PATH           local .deb for a dry run instead of downloading
#
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$repo_root/.site-build/apt}"
tag="${RELEASE_TAG:-}"

if [[ "$tag" != linux-v* ]]; then
  tag="$(git -C "$repo_root" tag -l 'linux-v*' | sort -V | tail -1)"
fi
[ -n "$tag" ] || { echo "build-apt-repo: no linux-v* tag found" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

deb="${DEB_PATH:-}"
if [ -z "$deb" ]; then
  : "${GITHUB_REPOSITORY:?set GITHUB_REPOSITORY}"
  : "${GH_TOKEN:?set GH_TOKEN}"
  echo "build-apt-repo: downloading $tag"
  for attempt in $(seq 1 20); do
    if gh release download "$tag" \
      --repo "$GITHUB_REPOSITORY" \
      --pattern 'deck-desktop_*_arm64.deb' \
      --dir "$tmp" >/dev/null 2>&1; then
      break
    fi
    [ "$attempt" -eq 20 ] && {
      echo "build-apt-repo: $tag has no arm64 .deb after 20 attempts" >&2
      exit 1
    }
    sleep 15
  done
  deb="$(find "$tmp" -name 'deck-desktop_*_arm64.deb' -print -quit)"
fi
[ -n "$deb" ] && [ -f "$deb" ] || { echo "build-apt-repo: no .deb" >&2; exit 1; }

arch="$(dpkg-deb -f "$deb" Architecture)"
version="$(dpkg-deb -f "$deb" Version)"
rm -rf "$out"
mkdir -p "$out/pool/main/d/deck-desktop" "$out/dists/stable/main/binary-$arch"
cp "$deb" "$out/pool/main/d/deck-desktop/"

(
  cd "$out"
  apt-ftparchive packages pool > "dists/stable/main/binary-$arch/Packages"
  gzip -9c "dists/stable/main/binary-$arch/Packages" \
    > "dists/stable/main/binary-$arch/Packages.gz"
  cd dists/stable
  apt-ftparchive \
    -o APT::FTPArchive::Release::Origin=Deck \
    -o APT::FTPArchive::Release::Label=Deck \
    -o APT::FTPArchive::Release::Suite=stable \
    -o APT::FTPArchive::Release::Codename=stable \
    -o APT::FTPArchive::Release::Architectures="$arch" \
    -o APT::FTPArchive::Release::Components=main \
    release . > Release
)

export GNUPGHOME="$tmp/gnupg"
mkdir -m 700 "$GNUPGHOME"
printf '%s' "${APT_GPG_PRIVATE_KEY:?set APT_GPG_PRIVATE_KEY}" | gpg --batch --import >/dev/null 2>&1
fingerprint="$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')"
[ -n "$fingerprint" ] || { echo "build-apt-repo: no signing key" >&2; exit 1; }
gpg --batch --yes --pinentry-mode loopback --local-user "$fingerprint" \
  --clearsign -o "$out/dists/stable/InRelease" "$out/dists/stable/Release"
gpg --batch --yes --pinentry-mode loopback --local-user "$fingerprint" \
  --armor --detach-sign -o "$out/dists/stable/Release.gpg" "$out/dists/stable/Release"
cp "$repo_root/linux/packaging/deck-archive-keyring.asc" "$out/key.asc"

echo "build-apt-repo: $tag $version $arch -> $out"
