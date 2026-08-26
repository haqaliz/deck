# Homebrew cask for Deck. This file is the source of truth; the published tap is
# a separate repo, haqaliz/homebrew-deck, where it goes as Casks/deck.rb. After a
# release builds the DMG, copy the sha256 out of SHA256SUMS.txt, bump the version,
# and commit it to the tap.
#
#   brew install --cask --no-quarantine haqaliz/deck/deck
#
# --no-quarantine is required until Deck is notarized: it is signed with an Apple
# Development certificate, which Gatekeeper rejects for downloaded apps. The flag
# is what saves users from running `xattr -dr com.apple.quarantine` by hand. Drop
# this note from the README and the tap the day notarization lands.
cask "deck" do
  version "1.30"
  sha256 "f37a29b3e6b3e7a511618be14edb3493152bb809079cc734eb651edf2dc79eca"

  url "https://github.com/haqaliz/deck/releases/download/v#{version}/Deck-v#{version}.dmg"
  name "Deck"
  desc "Fourteen native macOS desktop widgets in one WidgetKit extension"
  homepage "https://github.com/haqaliz/deck"

  # WidgetKit APIs Deck relies on, and the deployment target in project.yml.
  depends_on macos: ">= :sequoia"

  app "Deck.app"

  # Deck installs two LaunchAgents on first run; a plain `brew uninstall` that
  # left them running would keep relaunching a deleted binary every 60s.
  uninstall quit:      "com.deck.app",
            launchctl: [
              "com.deck.agent",
              "com.deck.agent.processes",
            ],
            delete:    [
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

  caveats <<~EOS
    Deck is not notarized yet, so it must be installed with --no-quarantine:

      brew install --cask --no-quarantine haqaliz/deck/deck

    Then add the widgets: right-click the desktop -> Edit Widgets... -> "Deck".
  EOS
end
