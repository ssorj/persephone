#!/bin/sh

if [ -n "$BASH" ]; then
    set -Eeuo pipefail
fi

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/artemis"
DIST_DIR="$HOME/.local/lib/artemis"
INSTANCE_DIR="$HOME/.local/lib/artemis-instance"

# XXX First, backups

rm "$HOME/.local/bin/artemis" || :
rm "$HOME/.local/bin/artemis-service" || :
rm -rf "$CONFIG_DIR" || :
rm -rf "$DIST_DIR" || :
rm -rf "$INSTANCE_DIR" || :
