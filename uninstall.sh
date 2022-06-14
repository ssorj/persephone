#!/bin/sh

if [ -n "$BASH" ]; then
    set -Eeuo pipefail
fi

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/artemis"
DIST_DIR="$HOME/.local/share/artemis"
INSTANCE_DIR="$HOME/.local/state/artemis"

# XXX First, backups

rm "$BIN_DIR/artemis" || :
rm "$BIN_DIR/artemis-service" || :
rm -rf "$CONFIG_DIR" || :
rm -rf "$DIST_DIR" || :
rm -rf "$INSTANCE_DIR" || :
