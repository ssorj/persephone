#!/bin/sh

if [ -n "$BASH" ]; then
    set -Eeuo pipefail
fi

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/artemis"
DIST_DIR="$HOME/.local/share/artemis"
INSTANCE_DIR="$HOME/.local/state/artemis"

# XXX First, backups

if [ -e "$BIN_DIR/artemis" ]; then
    rm "$BIN_DIR/artemis"
fi

if [ -e "$BIN_DIR/artemis-service" ]; then
    rm "$BIN_DIR/artemis-service"
fi

if [ -e "$HOME/bin/artemis" ]; then
    rm "$HOME/bin/artemis"
fi

if [ -e "$HOME/bin/artemis-service" ]; then
    rm "$HOME/bin/artemis-service"
fi

if [ -e "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
fi

if [ -e "$DIST_DIR" ]; then
    rm -rf "$DIST_DIR"
fi

if [ -e "$INSTANCE_DIR" ]; then
    rm -rf "$INSTANCE_DIR"
fi
