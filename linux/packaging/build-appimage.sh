#!/usr/bin/env bash
# Builds the x86_64 AppImage on a Linux host with GTK4 dev packages.
# CI runs this inside a Debian Trixie container; see .github/workflows/linux-appimage.yml.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
linux="$(cd "$here/.." && pwd)"
cd "$linux"

version="${VERSION:-1.1.2}"
tools="$linux/dist/appimage-tools"
appdir="$linux/dist/AppDir"
mkdir -p "$tools" "$linux/dist"

cargo build --release -p deck-gui -p deckd -p deck-cli

fetch() {
    local url="$1" output="$2"
    if [[ ! -x "$output" ]]; then
        curl -fL --retry 3 -o "$output" "$url"
        chmod +x "$output"
    fi
}
fetch \
    "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage" \
    "$tools/linuxdeploy"
fetch \
    "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh" \
    "$tools/linuxdeploy-plugin-gtk.sh"

rm -rf "$appdir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" \
    "$appdir/usr/share/icons/hicolor/scalable/apps" \
    "$appdir/usr/share/icons/hicolor/256x256/apps"
install -m0755 target/release/deck-gui "$appdir/usr/bin/deck-gui"
install -m0755 target/release/deck "$appdir/usr/bin/deck"
install -m0755 target/release/deckd "$appdir/usr/bin/deckd"
install -m0644 "$here/io.github.haqaliz.deck.desktop" \
    "$appdir/usr/share/applications/io.github.haqaliz.deck.desktop"
install -m0644 "$linux/assets/icons/deck-256.png" "$appdir/deck.png"
install -m0644 "$linux/assets/icons/deck-256.png" \
    "$appdir/usr/share/icons/hicolor/256x256/apps/deck.png"

export ARCH=x86_64
export APPIMAGE_EXTRACT_AND_RUN=1
export DEPLOY_GTK_VERSION=4
export PATH="$tools:$PATH"

# linuxdeploy's GTK plugin treats these as system libraries; bundle them so a
# clean desktop does not need GTK's transitive X11/font stack preinstalled.
extra_libraries=()
for library in \
    libX11.so.6 libxcb.so.1 libwayland-client.so.0 \
    libfontconfig.so.1 libfreetype.so.6 libfribidi.so.0 libharfbuzz.so.0 libexpat.so.1; do
    path="$(ldconfig -p | awk -v library="$library" '$1 == library { print $NF; exit }')"
    if [[ -n "$path" ]]; then
        extra_libraries+=(--library "$path")
    fi
done

"$tools/linuxdeploy" \
    --appdir "$appdir" \
    --desktop-file "$here/io.github.haqaliz.deck.desktop" \
    --icon-file "$appdir/deck.png" \
    --plugin gtk \
    "${extra_libraries[@]}" \
    --output appimage

built="$(find . -maxdepth 1 -name '*.AppImage' -print -quit)"
if [[ -z "$built" ]]; then
    echo "linuxdeploy produced no AppImage" >&2
    exit 1
fi
output="$linux/dist/deck_${version}_x86_64.AppImage"
mv "$built" "$output"
(cd "$(dirname "$output")" && sha256sum "$(basename "$output")") >"$output.sha256"
echo "built $output"
