#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
swift build -c release --package-path "$DIR"
"$DIR/.build/release/LiveBox" "$@"
