# Homebrew cask for Deck. This file is the source of truth; the published tap is
# a separate repo, haqaliz/homebrew-deck, where it goes as Casks/deck.rb. After a
# release builds the DMG, copy the sha256 out of SHA256SUMS.txt, bump the version,
# and commit it to the tap.
#
#   brew install --cask haqaliz/deck/deck
#   xattr -dr com.apple.quarantine /Applications/Deck.app   # BEFORE first launch
#
# Deck is signed with an Apple Development certificate, which Gatekeeper rejects
# for downloaded apps, so the quarantine flag has to come off. Two things about
# that, both measured on Homebrew 6.0.19 / macOS 15 (2026-08-26):
#
#   * `--no-quarantine` no longer exists. Homebrew removed the flag; passing it
#     now fails with "Error: invalid option". Older docs telling users to pass
#     it are giving them a command that cannot run.
#   * The order matters, and getting it wrong is destructive. Launching the app
#     while it is still quarantined does not merely warn — Gatekeeper *removes
#     /Applications/Deck.app*, and not to the Trash. Strip the attribute first
#     and the same bits launch fine.
#
# All of this goes away the day notarization lands; drop it from here, the tap
# and the README then.
cask "deck" do
  version "1.35"
  sha256 "eed92f778e09be5a516d4c6aa6f64bae053141d16b2d92ad5861518150ad0b64"

  url "https://github.com/haqaliz/deck/releases/download/v#{version}/Deck-v#{version}.dmg"
  name "Deck"
  desc "Fourteen desktop widgets in one WidgetKit extension"
  homepage "https://github.com/haqaliz/deck"

  # WidgetKit APIs Deck relies on, and the deployment target in project.yml.
  # A bare symbol is the minimum, and the only form Homebrew still accepts —
  # the `">= :sequoia"` string form it replaced is deprecated and warns on
  # every `brew info`.
  depends_on macos: :sequoia

  app "Deck.app"

  # Deck registers two launch agents via SMAppService on first run; a plain
  # `brew uninstall` that left them running would keep relaunching a deleted
  # binary every 60s. Removing the app bundle tears down the SMAppService
  # registrations with it; the bootout + legacy-plist lines below are belt and
  # suspenders for pre-SMAppService installs (a no-op when absent) and can be
  # dropped once no such installs remain.
  #
  # The key order here is Homebrew's, enforced by `brew style`, and it is not
  # the execution order: Homebrew runs uninstall directives in a fixed sequence
  # of its own regardless of how they are written. Reordering them changes
  # nothing but the linter's opinion.
  uninstall launchctl: [
              "com.deck.agent",
              "com.deck.agent.processes",
            ],
            quit:      "com.deck.app",
            # `trash:`, not `delete:`. Homebrew's uninstall_delete hardcodes
            # `sudo: true` — it is the directive for files outside the user's
            # control — so
            # using it on two plists in ~/Library made `brew upgrade` and
            # `brew uninstall` die on a password prompt they cannot answer,
            # after they had already unloaded the agents and quit the app.
            # Measured 2026-08-26. These files are the user's own; trashing
            # them needs no privilege and is recoverable.
            trash:     [
              "~/Library/LaunchAgents/com.deck.agent.plist",
              "~/Library/LaunchAgents/com.deck.agent.processes.plist",
            ]

  # Settings, snapshots and the clipboard history live in the widget container.
  # Only `zap` removes them, because they hold the user's tokens and history and
  # a reinstall should normally find them intact.
  #
  # Note the container directory itself is deliberately NOT listed: its metadata
  # plist is SIP-protected and survives deletion, after which containermanagerd
  # never rebuilds the skeleton and every widget renders blank.
  zap trash: [
    "~/Library/Containers/com.deck.app.widgets/Data/Library/Application Support/Deck",
    "~/Library/Logs/Deck",
  ]

  # Printed after install, which is the one moment it can still help: the user
  # has the app and has not launched it yet.
  caveats <<~EOS
    Deck is not notarized yet. Run this BEFORE opening it for the first time:

      xattr -dr com.apple.quarantine /Applications/Deck.app

    Opening it first does not just warn you — macOS deletes the app, and not
    to the Trash. If that already happened, reinstall and run the line above.

    Then add the widgets: right-click the desktop -> Edit Widgets... -> "Deck".
  EOS
end
