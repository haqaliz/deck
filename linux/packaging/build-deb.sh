#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
linux="$(cd "$here/.." && pwd)"
cd "$linux"

version="${VERSION:-0.1.3}"
arch="${ARCH:-$(dpkg --print-architecture)}"
target_dir="${CARGO_TARGET_DIR:-target}/release"
cargo_args=(--release -p deck-gui -p deckd -p deck-cli)
if [[ -n "${TARGET:-}" ]]; then
    target_dir="target/${TARGET}/release"
    cargo_args+=(--target "$TARGET")
fi

cargo build "${cargo_args[@]}"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

install -Dm0755 "$target_dir/deck-gui" "$stage/usr/bin/deck-gui"
install -Dm0755 "$target_dir/deck" "$stage/usr/bin/deck"
install -Dm0755 "$target_dir/deckd" "$stage/usr/bin/deckd"
install -Dm0644 "$here/io.github.haqaliz.deck.desktop" \
    "$stage/usr/share/applications/io.github.haqaliz.deck.desktop"
for size in 16 24 32 48 64 128 256 512; do
    install -Dm0644 "$linux/assets/icons/deck-${size}.png" \
        "$stage/usr/share/icons/hicolor/${size}x${size}/apps/deck.png"
done
install -Dm0644 "$here/deckd.service" "$stage/usr/lib/systemd/user/deckd.service"
install -Dm0644 "$linux/README.md" "$stage/usr/share/doc/deck/README.md"
install -Dm0644 "$here/deb/copyright" "$stage/usr/share/doc/deck/copyright"

size="$(du -sk "$stage" | cut -f1)"
mkdir -p "$stage/DEBIAN"
sed -e "s/@VERSION@/$version/" \
    -e "s/@ARCH@/$arch/" \
    -e "s/@SIZE@/$size/" \
    "$here/deb/control" >"$stage/DEBIAN/control"
install -m0755 "$here/deb/postinst" "$stage/DEBIAN/postinst"
install -m0755 "$here/deb/postrm" "$stage/DEBIAN/postrm"

mkdir -p "$linux/dist"
output="$linux/dist/deck_${version}_${arch}.deb"
dpkg-deb --build --root-owner-group "$stage" "$output"
sha256sum "$output" >"$output.sha256"
echo "built $output"
