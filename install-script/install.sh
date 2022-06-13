#!/bin/sh

set -e -u -o pipefail

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config"
LIB_DIR="$HOME/.local/lib"

TEMP_DIR=`mktemp -d`
BACKUP_DIR="$HOME/activemq-artemis-backup"
LOG_FILE="$HOME/activemq-artemis-install.log"

if [ -e "$BACKUP_DIR" ]; then
    mv "$BACKUP_DIR" "$BACKUP_DIR"-`date +%Y-%m-%d-%H-%m-%S` >> "$LOG_FILE" 2>&1
fi

if [ -e "$LOG_FILE" ]; then
    mv "$LOG_FILE" "$LOG_FILE"-`date +%Y-%m-%d-%H-%m-%S` >> "$LOG_FILE" 2>&1
fi

echo
echo "# Downloading ActiveMQ Artemis"
echo

(
    cd "$TEMP_DIR"

    echo "-- Fetching the latest dist tarball" >> "$LOG_FILE"

    curl --no-progress-meter -fLo dist.tar.gz "https://www.apache.org/dyn/closer.cgi?filename=activemq/activemq-artemis/2.22.0/apache-artemis-2.22.0-bin.tar.gz&action=download" >> "$LOG_FILE" 2>&1

    echo "-- Extracting files from the tarball " >> "$LOG_FILE"

    tar -xf dist.tar.gz >> "$LOG_FILE" 2>&1
    mv apache-artemis-2.22.0 dist >> "$LOG_FILE" 2>&1
)

echo "  Result: OK"

echo
echo "# Saving any existing installation to a backup location"
echo

echo "-- Saving the previous dist dir" >> "$LOG_FILE"

if [ -e "$LIB_DIR/activemq-artemis" ]; then
    mkdir -p "$BACKUP_DIR/lib" >> "$LOG_FILE" 2>&1
    mv "$LIB_DIR/activemq-artemis" "$BACKUP_DIR/lib" >> "$LOG_FILE" 2>&1
fi

echo "-- Saving the previous instance dir" >> "$LOG_FILE"

if [ -e "$LIB_DIR/activemq-artemis-instance" ]; then
    mkdir -p "$BACKUP_DIR/lib" >> "$LOG_FILE" 2>&1
    mv "$LIB_DIR/activemq-artemis-instance" "$BACKUP_DIR/lib" >> "$LOG_FILE" 2>&1
fi

echo "-- Saving the previous config dir" >> "$LOG_FILE"

if [ -e "$CONFIG_DIR/activemq-artemis" ]; then
    mkdir -p "$BACKUP_DIR/config" >> "$LOG_FILE" 2>&1
    mv "$CONFIG_DIR/activemq-artemis" "$BACKUP_DIR/config" >> "$LOG_FILE" 2>&1
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

echo "-- Moving the dist dir to its standard location" >> "$LOG_FILE"

mkdir -p "$LIB_DIR"
mv "$TEMP_DIR/dist" "$LIB_DIR/activemq-artemis"

echo "-- Creating the broker instance" >> "$LOG_FILE"

"$LIB_DIR/activemq-artemis/bin/artemis" create "$LIB_DIR/activemq-artemis-instance" \
                                        --user example --password example \
                                        --host localhost --allow-anonymous \
                                        --etc "$CONFIG_DIR/activemq-artemis" >> "$LOG_FILE" 2>&1

echo "-- Burning the instance dir into to the scripts" >> "$LOG_FILE"

sed -i.backup "18aARTEMIS_INSTANCE=$LIB_DIR/activemq-artemis-instance" "$LIB_DIR/activemq-artemis-instance/bin/artemis"
sed -i.backup "18aARTEMIS_INSTANCE=$LIB_DIR/activemq-artemis-instance" "$LIB_DIR/activemq-artemis-instance/bin/artemis-service"

echo "-- Creating symlinks to the scripts" >> "$LOG_FILE"

(
    mkdir -p "$BIN_DIR"
    cd "$BIN_DIR"

    ln -sf ../lib/activemq-artemis-instance/bin/artemis
    ln -sf ../lib/activemq-artemis-instance/bin/artemis-service
)

echo "  Result: OK"

echo
echo "# Testing the installation"
echo

echo "-- Testing the artemis command" >> "$LOG_FILE"

PATH="$BIN_DIR:$PATH" artemis version >> "$LOG_FILE" 2>&1

echo "-- Checking that the required ports are available" >> "$LOG_FILE"

# XXX 5445
for port in 61616 5672 61613 5445 1883 8161; do
    if lsof -PiTCP -sTCP:LISTEN | grep $port; then
        echo "ERROR: Required port 61616 is in use by something else" >> "$LOG_FILE"
        exit 1
    fi
done

echo "-- Testing the server" >> "$LOG_FILE"

PATH="$BIN_DIR:$PATH" artemis-service start >> "$LOG_FILE" 2>&1
PATH="$BIN_DIR:$PATH" artemis check node >> "$LOG_FILE" 2>&1

# The 'artemis-service stop' command times out too quickly for CI, so
# I take an alternate approach.
#
# PATH="$BIN_DIR:$PATH" artemis-service stop "$LOG_FILE" 2>&1

kill `cat "$LIB_DIR/activemq-artemis-instance/data/artemis.pid"` >> "$LOG_FILE" 2>&1

echo "  Result: OK"

echo
echo "# Summary"
echo

echo "  ActiveMQ Artemis is now installed.  Use 'artemis run' to start the broker."
echo

# XXX Path stuff!
