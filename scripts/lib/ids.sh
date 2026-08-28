# Deck's bundle identifiers, for shell.
#
# The Swift half is native/Shared/DeckBundle.swift and the build half is
# native/project.yml; DeckBundleTests asserts all three agree, so changing one
# without the others fails the suite rather than drifting silently.
#
# Source it from a script in scripts/:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/ids.sh"

DECK_APP_ID="com.deck.app"
DECK_WIDGETS_ID="${DECK_APP_ID}.widgets"
DECK_AGENT_LABEL="com.deck.agent"
DECK_FAST_AGENT_LABEL="${DECK_AGENT_LABEL}.processes"

# The pre-rename ids. Permanent, not "the previous values": they name a
# container that still exists on upgraded machines (and must never be deleted —
# its metadata plist is SIP-protected), the keychain service the tokens stay
# under, and two BTM records the rename orphans.
DECK_LEGACY_APP_ID="com.deck.app"
DECK_LEGACY_WIDGETS_ID="com.deck.app.widgets"
DECK_LEGACY_AGENT_LABEL="com.deck.agent"
DECK_LEGACY_FAST_AGENT_LABEL="com.deck.agent.processes"

DECK_CONTAINER="$HOME/Library/Containers/${DECK_WIDGETS_ID}"
DECK_LEGACY_CONTAINER="$HOME/Library/Containers/${DECK_LEGACY_WIDGETS_ID}"
DECK_DATA="${DECK_CONTAINER}/Data/Library/Application Support/Deck"
