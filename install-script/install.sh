#!/bin/sh

set -e

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config"
LIB_DIR="$HOME/.local/lib"
TEMP_DIR=`mktemp -d`
BACKUP_DIR="$HOME/activemq-artemis-backup"
LOG_FILE="$HOME/activemq-artemis-install.log"

if [ -e "$BACKUP_DIR" ]; then
    mv "$BACKUP_DIR" "$BACKUP_DIR"-`date +%Y-%m-%d-%H-%m-%S`
fi

if [ -e "$LOG_FILE" ]; then
    mv "$LOG_FILE" "$LOG_FILE"-`date +%Y-%m-%d-%H-%m-%S`
fi

echo
echo "# Downloading ActiveMQ Artemis"
echo

(
    cd "$TEMP_DIR"

    curl -sfLo dist.tar.gz "https://www.apache.org/dyn/closer.cgi?filename=activemq/activemq-artemis/2.22.0/apache-artemis-2.22.0-bin.tar.gz&action=download"

    tar -xf dist.tar.gz

    mv apache-artemis-2.22.0 dist
)

echo "  Result: OK"

echo
echo "# Saving any existing installation to a backup location"
echo

# Save the previous dist dir

if [ -e "$LIB_DIR/activemq-artemis" ]; then
    mkdir -p "$BACKUP_DIR/lib"
    mv "$LIB_DIR/activemq-artemis" "$BACKUP_DIR/lib"
fi

# Save the previous instance dir

if [ -e "$LIB_DIR/activemq-artemis-instance" ]; then
    mkdir -p "$BACKUP_DIR/lib"
    mv "$LIB_DIR/activemq-artemis-instance" "$BACKUP_DIR/lib"
fi

# Save the previous config dir

if [ -e "$CONFIG_DIR/activemq-artemis" ]; then
    mkdir -p "$BACKUP_DIR/config"
    mv "$CONFIG_DIR/activemq-artemis" "$BACKUP_DIR/config"
fi

if [ -e "$BACKUP_DIR" ]; then
    echo "  Result: OK"
    echo "  Backup location: $BACKUP_DIR"
else
    echo "  Result: No existing installation"
fi

echo
echo "# Installing ActiveMQ Artemis"
echo

# Move the dist dir into its standard location

mkdir -p "$LIB_DIR"
mv "$TEMP_DIR/dist" "$LIB_DIR/activemq-artemis"

# Create the broker instance

"$LIB_DIR/activemq-artemis/bin/artemis" create "$LIB_DIR/activemq-artemis-instance" \
                                        --user example --password example \
                                        --host localhost --allow-anonymous \
                                        --etc "$CONFIG_DIR/activemq-artemis" >> "$LOG_FILE" 2>&1

# Burn the instance location into the scripts

sed -i.backup "18aARTEMIS_INSTANCE=$LIB_DIR/activemq-artemis-instance" "$LIB_DIR/activemq-artemis-instance/bin/artemis"
sed -i.backup "18aARTEMIS_INSTANCE=$LIB_DIR/activemq-artemis-instance" "$LIB_DIR/activemq-artemis-instance/bin/artemis-service"

# Create symlinks to the scripts

(
    mkdir -p "$BIN_DIR"
    cd "$BIN_DIR"

    ln -sf ../lib/activemq-artemis-instance/bin/artemis
    ln -sf ../lib/activemq-artemis-instance/bin/artemis-service
)

# PATH="$BIN_DIR:$PATH" artemis version | sed 's/^/  /'

echo "  Result: OK"

echo
echo "# Testing the installation"
echo

PATH="$BIN_DIR:$PATH" artemis-service start >> "$LOG_FILE" 2>&1
PATH="$BIN_DIR:$PATH" artemis check node >> "$LOG_FILE" 2>&1

# The 'artemis-service stop' command times out too quickly for CI, so
# I take an alternate approach.
#
# PATH="$BIN_DIR:$PATH" artemis-service stop "$LOG_FILE" 2>&1

kill `cat "$LIB_DIR/activemq-artemis-instance/data/artemis.pid"` >> "$LOG_FILE" 2>&1

echo "  Result: OK"

echo
echo "# The broker is now ready"
echo

echo "  Command: artemis run"
echo

# XXX Path stuff!
