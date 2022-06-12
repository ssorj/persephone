#!/bin/sh

set -e
set -o posix

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config"
LIB_DIR="$HOME/.local/lib"
TEMP_DIR=`mktemp -d`
BACKUP_DIR="$HOME/activemq-artemis-backup"-`date +%Y-%m-%d`

if [ -e "$BACKUP_DIR" ]; then
    mv "$BACKUP_DIR" "$BACKUP_DIR"-`date +%s`
fi

echo
echo "# Downloading and installing ActiveMQ Artemis"
echo

(
    cd "$TEMP_DIR"

    curl -sfLo apache-artemis-2.22.0.tar.gz "https://www.apache.org/dyn/closer.cgi?filename=activemq/activemq-artemis/2.22.0/apache-artemis-2.22.0-bin.tar.gz&action=download"

    tar -xf apache-artemis-2.22.0.tar.gz

    if [ -e "$LIB_DIR/activemq-artemis" ]; then
        mkdir -p "$BACKUP_DIR/lib"
        mv "$LIB_DIR/activemq-artemis" "$BACKUP_DIR/lib"
    fi

    mkdir -p "$LIB_DIR"
    mv apache-artemis-2.22.0 "$LIB_DIR/activemq-artemis"
)

if [ -e "$LIB_DIR/activemq-artemis-instance" ]; then
    mkdir -p "$BACKUP_DIR/lib"
    mv "$LIB_DIR/activemq-artemis-instance" "$BACKUP_DIR/lib"
fi

if [ -e "$CONFIG_DIR/activemq-artemis" ]; then
    mkdir -p "$BACKUP_DIR/config"
    mv "$CONFIG_DIR/activemq-artemis" "$BACKUP_DIR/config"
fi

"$LIB_DIR/activemq-artemis/bin/artemis" create "$LIB_DIR/activemq-artemis-instance" \
                                        --user example --password example \
                                        --host localhost --allow-anonymous \
                                        --etc "$CONFIG_DIR/activemq-artemis" > /dev/null

sed -i.backup "18aARTEMIS_INSTANCE=$LIB_DIR/activemq-artemis-instance" "$LIB_DIR/activemq-artemis-instance/bin/artemis"
sed -i.backup "18aARTEMIS_INSTANCE=$LIB_DIR/activemq-artemis-instance" "$LIB_DIR/activemq-artemis-instance/bin/artemis-service"

(
    mkdir -p "$BIN_DIR"
    cd "$BIN_DIR"

    ln -sf ../lib/activemq-artemis-instance/bin/artemis
    ln -sf ../lib/activemq-artemis-instance/bin/artemis-service
)

artemis version | sed 's/^/  /'

if [ -e "$BACKUP_DIR" ]; then
    echo "  Backup of previous installation: $BACKUP_DIR"
fi

echo
echo "# Testing the broker"
echo

artemis-service start > /dev/null
artemis perf client --message-count 1 > /dev/null
artemis-service stop > /dev/null

echo "  Result: OK"
echo

echo "# The broker is now ready"
echo
echo "  Command: artemis run"
echo
