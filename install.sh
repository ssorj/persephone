#!/bin/sh

if [ -n "$BASH" ]; then
    set -Eeuo pipefail
fi

BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/artemis"
DIST_DIR="$HOME/.local/share/artemis"
INSTANCE_DIR="$HOME/.local/state/artemis"

TEMP_DIR=`mktemp -d`
BACKUP_DIR="$HOME/artemis-backup"
LOG_FILE="$HOME/artemis-install.log"

if [ -e "$BACKUP_DIR" ]; then
    mv "$BACKUP_DIR" "$BACKUP_DIR"-`date +%Y-%m-%d-%H-%m-%S` >> "$LOG_FILE" 2>&1
fi

if [ -e "$LOG_FILE" ]; then
    mv "$LOG_FILE" "$LOG_FILE"-`date +%Y-%m-%d-%H-%m-%S` >> "$LOG_FILE" 2>&1
fi

echo
echo "# Checking for required tools"
echo

# XXX Check for which and tee

for tool in curl grep sed tar java; do
    echo "-- Checking for $tool" >> "$LOG_FILE"

    if ! which "$tool" >> "$LOG_FILE" 2>&1; then
        echo "ERROR: Required tool $tool is not available" | tee -a "$LOG_FILE"
        exit 1
    fi
done

echo "  Result: OK"

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
echo "# Saving existing installation to a backup location"
echo

echo "-- Saving the previous config dir" >> "$LOG_FILE"

if [ -e "$CONFIG_DIR" ]; then
    mkdir -p "$BACKUP_DIR/config" >> "$LOG_FILE" 2>&1
    mv "$CONFIG_DIR" "$BACKUP_DIR/config" >> "$LOG_FILE" 2>&1
fi

echo "-- Saving the previous dist dir" >> "$LOG_FILE"

if [ -e "$DIST_DIR" ]; then
    mkdir -p "$BACKUP_DIR/share" >> "$LOG_FILE" 2>&1
    mv "$DIST_DIR" "$BACKUP_DIR/share" >> "$LOG_FILE" 2>&1
fi

echo "-- Saving the previous instance dir" >> "$LOG_FILE"

if [ -e "$INSTANCE_DIR" ]; then
    mkdir -p "$BACKUP_DIR/state" >> "$LOG_FILE" 2>&1
    mv "$INSTANCE_DIR" "$BACKUP_DIR/state" >> "$LOG_FILE" 2>&1
fi

# XXX Also save the scripts

if [ -e "$BACKUP_DIR" ]; then
    echo "  Result: OK"
    echo "  Backup: $BACKUP_DIR"
else
    echo "  Result: No existing installation"
fi

echo
echo "# Installing ActiveMQ Artemis"
echo

echo "-- Moving the dist dir to its standard location" >> "$LOG_FILE"

mkdir -p `dirname "$DIST_DIR"`
mv "$TEMP_DIR/dist" "$DIST_DIR"

echo "-- Creating the broker instance" >> "$LOG_FILE"

"$DIST_DIR/bin/artemis" create "$INSTANCE_DIR" \
                        --user example --password example \
                        --host localhost --allow-anonymous \
                        --no-hornetq-acceptor \
                        --etc "$CONFIG_DIR" >> "$LOG_FILE" 2>&1

echo "-- Burning the instance dir into the scripts" >> "$LOG_FILE"

sed -i.backup "18a\\
ARTEMIS_INSTANCE=$INSTANCE_DIR
" "$INSTANCE_DIR/bin/artemis"

sed -i.backup "18a\\
ARTEMIS_INSTANCE=$INSTANCE_DIR
" "$INSTANCE_DIR/bin/artemis-service"

echo "-- Creating symlinks to the scripts" >> "$LOG_FILE"

(
    mkdir -p "$BIN_DIR"
    cd "$BIN_DIR"

    ln -sf "$INSTANCE_DIR/bin/artemis"
    ln -sf "$INSTANCE_DIR/bin/artemis-service"
)

echo "  Result: OK"

echo
echo "# Testing the installation"
echo

echo "-- Testing the artemis command" >> "$LOG_FILE"

PATH="$BIN_DIR:$PATH" artemis version >> "$LOG_FILE" 2>&1

echo "-- Checking that the required ports are available" >> "$LOG_FILE"

if which lsof > /dev/null 2>&1; then
    for port in 61616 5672 61613 1883 8161; do
        if lsof -PiTCP -sTCP:LISTEN 2>> "$LOG_FILE" | grep "$port" > /dev/null; then
            echo "ERROR: Required port $port is in use by something else" >> "$LOG_FILE"
            exit 1
        fi
    done
fi

echo "-- Testing the server" >> "$LOG_FILE"

PATH="$BIN_DIR:$PATH" artemis-service start >> "$LOG_FILE" 2>&1

if which lsof > /dev/null 2>&1; then
    for i in `seq 10`; do
        if lsof -PiTCP -sTCP:LISTEN 2>> "$LOG_FILE" | grep 61616 > /dev/null; then
            break;
        fi

        sleep 1
    done
else
    sleep 2
fi

PATH="$BIN_DIR:$PATH" artemis check node --verbose >> "$LOG_FILE" 2>&1

# The 'artemis-service stop' command times out too quickly for CI, so
# I take an alternate approach.

kill `cat "$INSTANCE_DIR/data/artemis.pid"` >> "$LOG_FILE" 2>&1

echo "  Result: OK"

echo
echo "# Summary"
echo

echo "  ActiveMQ Artemis is now installed.  Use 'artemis run' to start the broker."

echo
echo "# Log"
echo

cat ~/artemis-install.log | sed 's/^/  /'

# XXX Path stuff!
