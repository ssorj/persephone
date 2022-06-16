#!/bin/sh

if [ -n "$BASH" ]; then
    set -Eeuo pipefail
fi

case "`uname`" in
    CYGWIN*)
        HOME=`cygpath --mixed --windows "$HOME"`
        ;;
esac

BIN_DIR="$HOME/.local/bin"
ARTEMIS_CONFIG_DIR="$HOME/.config/artemis"
ARTEMIS_HOME_DIR="$HOME/.local/share/artemis"
ARTEMIS_INSTANCE_DIR="$HOME/.local/state/artemis"

TEMP_DIR=`mktemp -d`
BACKUP_DIR="$HOME/artemis-backup"
LOG_FILE="$HOME/artemis-install.log"

if [ -n "$BASH" ]; then
    trouble() {
        echo
        echo "TROUBLE! Things didn't go to plan. Here's the log:"
        echo

        cat "$LOG_FILE" || :
    }

    trap trouble ERR
fi

if [ -e "$BACKUP_DIR" ]; then
    mv "$BACKUP_DIR" "$BACKUP_DIR"-`date +%Y-%m-%d-%H-%m-%S` >> "$LOG_FILE" 2>&1
fi

if [ -e "$LOG_FILE" ]; then
    mv "$LOG_FILE" "$LOG_FILE"-`date +%Y-%m-%d-%H-%m-%S` >> "$LOG_FILE" 2>&1
fi

echo
echo "== Checking for required tools" | tee -a "$LOG_FILE"
echo

# XXX Check for tee

for tool in curl grep sed tar java; do
    echo "-- Checking for $tool" >> "$LOG_FILE"

    if ! command -v "$tool" >> "$LOG_FILE" 2>&1; then
        echo "ERROR: Required tool $tool is not available" | tee -a "$LOG_FILE"
        exit 1
    fi
done

echo "   Result: OK"

echo
echo "== Downloading ActiveMQ Artemis" | tee -a "$LOG_FILE"
echo

(
    cd "$TEMP_DIR"

    echo "-- Fetching the latest dist tarball" >> "$LOG_FILE"

    curl --no-progress-meter -fLo dist.tar.gz "https://www.apache.org/dyn/closer.cgi?filename=activemq/activemq-artemis/2.22.0/apache-artemis-2.22.0-bin.tar.gz&action=download" >> "$LOG_FILE" 2>&1

    echo "-- Extracting files from the tarball " >> "$LOG_FILE"

    tar -xf dist.tar.gz >> "$LOG_FILE" 2>&1
    mv apache-artemis-2.22.0 dist >> "$LOG_FILE" 2>&1
)

echo "   Result: OK"

echo
echo "== Saving existing installation to a backup location" | tee -a "$LOG_FILE"
echo

echo "-- Saving the previous config dir" >> "$LOG_FILE"

if [ -e "$ARTEMIS_CONFIG_DIR" ]; then
    mkdir -p "$BACKUP_DIR/config" >> "$LOG_FILE" 2>&1
    mv "$ARTEMIS_CONFIG_DIR" "$BACKUP_DIR/config" >> "$LOG_FILE" 2>&1
fi

echo "-- Saving the previous dist dir" >> "$LOG_FILE"

if [ -e "$ARTEMIS_HOME_DIR" ]; then
    mkdir -p "$BACKUP_DIR/share" >> "$LOG_FILE" 2>&1
    mv "$ARTEMIS_HOME_DIR" "$BACKUP_DIR/share" >> "$LOG_FILE" 2>&1
fi

echo "-- Saving the previous instance dir" >> "$LOG_FILE"

if [ -e "$ARTEMIS_INSTANCE_DIR" ]; then
    mkdir -p "$BACKUP_DIR/state" >> "$LOG_FILE" 2>&1
    mv "$ARTEMIS_INSTANCE_DIR" "$BACKUP_DIR/state" >> "$LOG_FILE" 2>&1
fi

if [ -e "$BACKUP_DIR" ]; then
    echo "   Result: OK"
    echo "   Backup: $BACKUP_DIR"
else
    echo "   Result: No existing installation"
fi

echo
echo "== Installing ActiveMQ Artemis" | tee -a "$LOG_FILE"
echo

echo "-- Moving the downloaded dist dir to its install location" >> "$LOG_FILE"

mkdir -p `dirname "$ARTEMIS_HOME_DIR"`
mv "$TEMP_DIR/dist" "$ARTEMIS_HOME_DIR"

echo "-- Burning the Artemis home dir into the admin script" >> "$LOG_FILE"

# XXX -e ?
sed -i.backup "18a\\
ARTEMIS_HOME=$ARTEMIS_HOME_DIR
" "$ARTEMIS_HOME_DIR/bin/artemis" >> "$LOG_FILE" 2>&1

# XXX Consider just setting this in the env when I invoke stuff (and for instance dir as well)

echo "-- Creating the broker instance" >> "$LOG_FILE"

echo java_home ${JAVA_HOME:-}
echo classpath ${CLASSPATH:-}

"$ARTEMIS_HOME_DIR/bin/artemis" create "$ARTEMIS_INSTANCE_DIR" \
                                --user example --password example \
                                --host localhost --allow-anonymous \
                                --no-autotune \
                                --no-hornetq-acceptor \
                                --etc "$ARTEMIS_CONFIG_DIR" \
                                --verbose \
                                >> "$LOG_FILE" 2>&1

echo "-- Burning the instance dir into the instance scripts" >> "$LOG_FILE"

sed -i.backup "18a\\
ARTEMIS_INSTANCE=$ARTEMIS_INSTANCE_DIR
" "$ARTEMIS_INSTANCE_DIR/bin/artemis" >> "$LOG_FILE" 2>&1

sed -i.backup "18a\\
ARTEMIS_INSTANCE=$ARTEMIS_INSTANCE_DIR
" "$ARTEMIS_INSTANCE_DIR/bin/artemis-service" >> "$LOG_FILE" 2>&1

echo "-- Patching out a problem XXX" >> "$LOG_FILE"

# This bit of the Artemis instance script uses a cygpath --unix,
# cygpath --windows sequence that ends up stripping out the drive
# letter and replacing it with whatever the current drive is. If your
# current drive is different from the Artemis install drive, trouble.
#
# For the bug: Annotate the current code.  Suggest --absolute.

sed -i.backup2 -e "77,82d" "$ARTEMIS_INSTANCE_DIR/bin/artemis"

echo "-- Creating symlinks to the scripts" >> "$LOG_FILE"

(
    mkdir -p "$BIN_DIR"
    cd "$BIN_DIR"

    ln -sf "$ARTEMIS_INSTANCE_DIR/bin/artemis"
    ln -sf "$ARTEMIS_INSTANCE_DIR/bin/artemis-service"
)

echo "   Result: OK"

echo
echo "== Testing the installation" | tee -a "$LOG_FILE"
echo

echo "-- Testing the artemis command" >> "$LOG_FILE"


case "`uname`" in
    CYGWIN*)
        echo 111
        ls -l 'C:\cygwin\home\runneradmin\.local\share\artemis/lib/' || :
        ls -l 'C:/cygwin/home/runneradmin/.local/share/artemis/lib/' || :
        echo 222
        ;;
esac


sh -x "$BIN_DIR/artemis" version >> "$LOG_FILE" 2>&1

echo "-- Checking that the required ports are available" >> "$LOG_FILE"

if command -v lsof > /dev/null 2>&1; then
    for port in 61616 5672 61613 1883 8161; do
        if lsof -PiTCP -sTCP:LISTEN 2>> "$LOG_FILE" | grep "$port" > /dev/null; then
            echo "ERROR: Required port $port is in use by something else" >> "$LOG_FILE"
            exit 1
        fi
    done
fi

echo "-- Testing the server" >> "$LOG_FILE"

"$BIN_DIR/artemis-service" start >> "$LOG_FILE" 2>&1

if command -v lsof > /dev/null 2>&1; then
    for i in `seq 15`; do
        if lsof -PiTCP -sTCP:LISTEN 2>> "$LOG_FILE" | grep 61616 > /dev/null; then
            break;
        fi

        sleep 2
    done
else
    # XXX log that we don't have lsof so can't do it
    sleep 30
fi

"$BIN_DIR/artemis" check node --verbose >> "$LOG_FILE" 2>&1

# The 'artemis-service stop' command times out too quickly for CI, so
# I take an alternate approach.

kill `cat "$ARTEMIS_INSTANCE_DIR/data/artemis.pid"` >> "$LOG_FILE" 2>&1

echo "   Result: OK"

echo
echo "== Summary" | tee -a "$LOG_FILE"
echo

echo "   ActiveMQ Artemis is now installed.  Use 'artemis run' to start the broker."

# XXX Path stuff!

# XXX details as properties
