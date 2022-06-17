#!/bin/sh
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

if [ -n "$BASH" ]; then
    set -Eeuo pipefail
fi

CYGWIN=

case "`uname`" in
    CYGWIN*)
        HOME=`cygpath --mixed --windows "$HOME"`
        CYGWIN=1
        ;;
esac

BIN_DIR="$HOME/.local/bin"
ARTEMIS_CONFIG_DIR="$HOME/.config/artemis"
ARTEMIS_HOME_DIR="$HOME/.local/share/artemis"
ARTEMIS_INSTANCE_DIR="$HOME/.local/state/artemis"

BACKUP_DIR="$HOME/artemis-backup"
CACHE_DIR="$HOME/.cache/artemis-install-script"
LOG_FILE="$CACHE_DIR/install.log"

mkdir -p "$CACHE_DIR"

trouble() {
    if [ "$?" != 0 ]; then
        echo
        echo "TROUBLE! Things didn't go to plan. Here's the log:"
        echo

        cat "$LOG_FILE" || :
    fi
}

trap trouble EXIT

if [ -e "$BACKUP_DIR" ]; then
    mv "$BACKUP_DIR" "$BACKUP_DIR"-`date +%Y-%m-%d-%H-%m-%S` >> "$LOG_FILE" 2>&1
fi

if [ -e "$LOG_FILE" ]; then
    mv "$LOG_FILE" "$LOG_FILE"-`date +%Y-%m-%d-%H-%m-%S` >> "$LOG_FILE" 2>&1
fi

assert() {
    if [ ! $1 ]; then
        echo "ASSERTION FAILED! \"$1\"" >> "$LOG_FILE"
        exit 1
    fi
}

echo "== Checking for required tools" | tee -a "$LOG_FILE"
echo

# XXX Check for tee

for tool in awk curl grep java sed sort tail tar uname; do
    echo "-- Checking for $tool" >> "$LOG_FILE"

    if ! command -v "$tool" >> "$LOG_FILE" 2>&1; then
        echo "ERROR: Required tool $tool is not available" | tee -a "$LOG_FILE"
        exit 1
    fi
done

echo "   Result: OK"
echo

echo "== Determining the latest version" | tee -a "$LOG_FILE"
echo

VERSION=`(curl --no-progress-meter -fL https://dlcdn.apache.org/activemq/activemq-artemis/ \
          | awk 'match($0, /[0-9]+\.[0-9]+\.[0-9]+/) { print substr($0, RSTART, RLENGTH) }' \
          | sort -t . -k1n -k2n -k3n \
          | tail -n 1) 2>> "$LOG_FILE"`

echo "   Result: $VERSION"
echo

echo "== Downloading the release archive" | tee -a "$LOG_FILE"
echo

RELEASE_ARCHIVE="$CACHE_DIR/apache-artemis-$VERSION-bin.tar.gz"
RELEASE_DIR="$CACHE_DIR/apache-artemis-$VERSION"

if [ ! -e "$RELEASE_ARCHIVE" ]; then
    echo "-- Fetching the latest release archive" >> "$LOG_FILE"

    curl --no-progress-meter -fLo "$CACHE_DIR/apache-artemis-$VERSION-bin.tar.gz" "https://www.apache.org/dyn/closer.cgi?filename=activemq/activemq-artemis/$VERSION/apache-artemis-$VERSION-bin.tar.gz&action=download" >> "$LOG_FILE" 2>&1
else
    echo "-- Using the cached release archive" >> "$LOG_FILE"
fi

if [ "$CYGWIN" ]; then
    tar --force-local -C "$CACHE_DIR" -xf "$RELEASE_ARCHIVE" >> "$LOG_FILE" 2>&1
else
    tar -C "$CACHE_DIR" -xf "$RELEASE_ARCHIVE" >> "$LOG_FILE" 2>&1
fi

assert "-d $RELEASE_DIR"

echo "   Result: OK"
echo

if [ -e "$ARTEMIS_CONFIG_DIR" -o -e "$ARTEMIS_HOME_DIR" -o -e "$ARTEMIS_INSTANCE_DIR" ]; then
    echo "== Saving the existing installation to a backup" | tee -a "$LOG_FILE"
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

    assert "-d $BACKUP_DIR"

    echo "   Result: OK"
    echo "   Backup: $BACKUP_DIR"
    echo
fi

echo "== Installing the broker" | tee -a "$LOG_FILE"
echo

echo "-- Moving the release dir to its install location" >> "$LOG_FILE"

assert "! -e $ARTEMIS_HOME_DIR"

mkdir -p `dirname "$ARTEMIS_HOME_DIR"`
mv "$RELEASE_DIR" "$ARTEMIS_HOME_DIR"

echo "-- Burning the Artemis home dir into the admin script" >> "$LOG_FILE"

sed -i.backup "18a\\
ARTEMIS_HOME=$ARTEMIS_HOME_DIR
" "$ARTEMIS_HOME_DIR/bin/artemis" >> "$LOG_FILE" 2>&1

echo "-- Creating the broker instance" >> "$LOG_FILE"

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

if [ -n "$CYGWIN" ]; then
    echo "-- Patching problem 1" >> "$LOG_FILE"

    # This bit of the Artemis instance script uses a cygpath --unix,
    # cygpath --windows sequence that ends up stripping out the drive
    # letter and replacing it with whatever the current drive is. If your
    # current drive is different from the Artemis install drive, trouble.
    #
    # For the bug: Annotate the current code.  Suggest --absolute.

    sed -i.backup2 "77,82d" "$ARTEMIS_INSTANCE_DIR/bin/artemis"

    echo "-- Patching problem 2" >> "$LOG_FILE"

    # And this bit replaces a colon with a semicolon in the
    # bootclasspath.  Windows requires a semicolon.

    sed -i.backup3 's/\$LOG_MANAGER:\$WILDFLY_COMMON/\$LOG_MANAGER;\$WILDFLY_COMMON/' "$ARTEMIS_INSTANCE_DIR/bin/artemis"
fi

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

"$BIN_DIR/artemis" version >> "$LOG_FILE" 2>&1

if command -v lsof > /dev/null 2>&1; then
    echo "-- Checking that the required ports are available" >> "$LOG_FILE"

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
