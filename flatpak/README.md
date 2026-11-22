# Deck Flatpak

Build locally (x86_64):

```bash
flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y flathub org.gnome.Platform//48 org.gnome.Sdk//48 \
  org.freedesktop.Sdk.Extension.rust-stable//24.08
flatpak-builder --user --repo=repo --force-clean --install-deps-from=flathub \
  build-dir io.github.haqaliz.deck.yml
flatpak build-bundle repo deck.flatpak io.github.haqaliz.deck
```

The manifest builds `gtk4-layer-shell`, `wl-clipboard`, `curl` and `git` in
addition to Deck, so the widget providers and GitBox work inside the sandbox.
`deckd` is installed as `/app/bin/deckd`; run it with:

```bash
flatpak run --command=deckd io.github.haqaliz.deck --interval 60
```

Autostart and shortcut installers detect Flatpak and write
`flatpak run io.github.haqaliz.deck` entries.

The sandbox grants home-directory access because GitBox scans configured
repositories and OpenBox reads the local opencode database. Tray support
depends on the host exposing a StatusNotifierWatcher.
