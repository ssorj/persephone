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

if [ -n "${BASH}" ]
then
    set -Eeuo pipefail
    export POSIXLY_CORRECT=1
fi

cygwin=

case "$(uname)" in
    CYGWIN*)
        HOME="$(cygpath --mixed --windows "${HOME}")"
        cygwin=1
        ;;
esac

bin_dir="${HOME}/.local/bin"
artemis_config_dir="${HOME}/.config/artemis"
artemis_home_dir="${HOME}/.local/share/artemis"
artemis_instance_dir="${HOME}/.local/state/artemis"

backup_dir="${HOME}/artemis-backup"
cache_dir="${HOME}/.cache/artemis-install-script"
log_file="${cache_dir}/install.log"

mkdir -p "${cache_dir}"

trouble() {
    if [ $? != 0 ]
    then
        echo
        echo "TROUBLE! Things didn't go to plan. Here's the log:"
        echo

        cat "${log_file}" || :
    fi
}

trap trouble EXIT

if [ -e "${backup_dir}" ]
then
    mv "${backup_dir}" "${backup_dir}-$(date +%Y-%m-%d-%H-%m-%S)" >> "${log_file}" 2>&1
fi

if [ -e "${log_file}" ]
then
    mv "${log_file}" "${log_file}-$(date +%Y-%m-%d-%H-%m-%S)" >> "${log_file}" 2>&1
fi

assert() {
    if ! [ $1 ]
    then
        echo "ASSERTION FAILED! \"$1\"" >> "${log_file}"
        exit 1
    fi
}

# XXX Logging about what shell we have
if [ -n "$BASH" ]
then
    :
else
    :
fi

echo "== Checking for required tools" | tee -a "${log_file}"
echo

# XXX Check for tee

for tool in awk curl grep java sed sort tail tar uname; do
    echo "-- Checking for $tool" >> "${log_file}"

    if ! command -v "$tool" >> "${log_file}" 2>&1
    then
        echo "ERROR: Required tool $tool is not available" | tee -a "${log_file}"
        exit 1
    fi
done

# XXX Check the network

echo "   Result: OK"
echo

echo "== Determining the latest version" | tee -a "${log_file}"
echo

# XXX I wonder if there's a cleaner way to achieve this

version="$( (curl --no-progress-meter -fL https://dlcdn.apache.org/activemq/activemq-artemis/ \
             | awk 'match($0, /[0-9]+\.[0-9]+\.[0-9]+/) { print substr($0, RSTART, RLENGTH) }' \
             | sort -t . -k1n -k2n -k3n \
             | tail -n 1) 2>> ${log_file} )"

echo "   Result: $version"
echo

echo "== Downloading the release archive" | tee -a "${log_file}"
echo

release_archive="${cache_dir}/apache-artemis-$version-bin.tar.gz"
release_dir="${cache_dir}/apache-artemis-$version"

if [ ! -e "${release_archive}" ]
then
    echo "-- Fetching the latest release archive" >> "${log_file}"

    # XXX Want a way to log command *and* run it

    curl --no-progress-meter -fLo "${release_archive}" "https://www.apache.org/dyn/closer.cgi?filename=activemq/activemq-artemis/$version/apache-artemis-$version-bin.tar.gz&action=download" >> "${log_file}" 2>&1

    echo "Fetched ${release_file}"
else
    echo "Using the cached release archive" >> "${log_file}"
fi

gzip -dc "${release_archive}" | (cd "$(dirname "${release_dir}")" && tar xf -)

assert "-d ${release_dir}"

echo "   Result: OK"
echo

if [ -e "${artemis_config_dir}" -o -e "${artemis_home_dir}" -o -e "${artemis_instance_dir}" ]
then
    echo "== Saving the existing installation to a backup" | tee -a "${log_file}"
    echo

    echo "-- Saving the previous config dir" >> "${log_file}"

    if [ -e "${artemis_config_dir}" ]
    then
        mkdir -p "${backup_dir}/config" >> "${log_file}" 2>&1
        mv "${artemis_config_dir}" "${backup_dir}/config" >> "${log_file}" 2>&1
    fi

    echo "-- Saving the previous dist dir" >> "${log_file}"

    if [ -e "${artemis_home_dir}" ]
    then
        mkdir -p "${backup_dir}/share" >> "${log_file}" 2>&1
        mv "${artemis_home_dir}" "${backup_dir}/share" >> "${log_file}" 2>&1
    fi

    echo "-- Saving the previous instance dir" >> "${log_file}"

    if [ -e "${artemis_instance_dir}" ]
    then
        mkdir -p "${backup_dir}/state" >> "${log_file}" 2>&1
        mv "${artemis_instance_dir}" "${backup_dir}/state" >> "${log_file}" 2>&1
    fi

    assert "-d ${backup_dir}"

    echo "   Result: OK"
    echo "   Backup: ${backup_dir}"
    echo
fi

echo "== Installing the broker" | tee -a "${log_file}"
echo

echo "-- Moving the release dir to its install location" >> "${log_file}"

assert "! -e ${artemis_home_dir}"

mkdir -p "$(dirname "${artemis_home_dir}")"
mv "${release_dir}" "${artemis_home_dir}"

echo "-- Burning the Artemis home dir into the admin script" >> "${log_file}"

sed -i.backup "18a\\
ARTEMIS_HOME=${artemis_home_dir}
" "${artemis_home_dir}/bin/artemis" >> "${log_file}" 2>&1

echo "-- Creating the broker instance" >> "${log_file}"

"${artemis_home_dir}/bin/artemis" create "${artemis_instance_dir}" \
                                --user example --password example \
                                --host localhost --allow-anonymous \
                                --no-autotune \
                                --no-hornetq-acceptor \
                                --etc "${artemis_config_dir}" \
                                --verbose \
                                >> "${log_file}" 2>&1

echo "-- Burning the instance dir into the instance scripts" >> "${log_file}"

sed -i.backup "18a\\
ARTEMIS_INSTANCE=${artemis_instance_dir}
" "${artemis_instance_dir}/bin/artemis" >> "${log_file}" 2>&1

sed -i.backup "18a\\
ARTEMIS_INSTANCE=${artemis_instance_dir}
" "${artemis_instance_dir}/bin/artemis-service" >> "${log_file}" 2>&1

if [ -n "$cygwin" ]
then
    echo "-- Patching problem 1" >> "${log_file}"

    # This bit of the Artemis instance script uses a cygpath --unix,
    # cygpath --windows sequence that ends up stripping out the drive
    # letter and replacing it with whatever the current drive is. If your
    # current drive is different from the Artemis install drive, trouble.
    #
    # For the bug: Annotate the current code.  Suggest --absolute.

    # XXX Try patching for --absolute instead

    sed -i.backup2 "77,82d" "${artemis_instance_dir}/bin/artemis"

    echo "-- Patching problem 2" >> "${log_file}"

    # And this bit replaces a colon with a semicolon in the
    # bootclasspath.  Windows requires a semicolon.

    sed -i.backup3 's/\$LOG_MANAGER:\$WILDFLY_COMMON/\$LOG_MANAGER;\$WILDFLY_COMMON/' "${artemis_instance_dir}/bin/artemis"
fi

echo "-- Creating symlinks to the scripts" >> "${log_file}"

(
    mkdir -p "${bin_dir}"
    cd "${bin_dir}"

    ln -sf "${artemis_instance_dir}/bin/artemis"
    ln -sf "${artemis_instance_dir}/bin/artemis-service"
)

echo "   Result: OK"
echo

echo "== Testing the installation" | tee -a "${log_file}"
echo

echo "-- Testing the artemis command" >> "${log_file}"

"${bin_dir}/artemis" version >> "${log_file}" 2>&1

if command -v lsof > /dev/null 2>&1
then
    echo "-- Checking that the required ports are available" >> "${log_file}"

    for port in 61616 5672 61613 1883 8161; do
        if lsof -PiTCP -sTCP:LISTEN 2>> "${log_file}" | grep "$port" > /dev/null
        then
            echo "ERROR: Required port $port is in use by something else" >> "${log_file}"
            exit 1
        fi
    done
fi

echo "-- Testing the server" >> "${log_file}"

"${bin_dir}/artemis-service" start >> "${log_file}" 2>&1

if command -v lsof > /dev/null 2>&1
then
    i=100

    while [ "$i" -gt 0 ]
    do
        if lsof -PiTCP -sTCP:LISTEN 2>> "${log_file}" | grep 61616 > /dev/null
        then
            break;
        fi

        sleep 2

        i=$(($i - 1))
    done
else
    sleep 30
fi

"${bin_dir}/artemis" check node --verbose >> "${log_file}" 2>&1

# The 'artemis-service stop' command times out too quickly for CI, so
# I take an alternate approach.

kill "$(cat "${artemis_instance_dir}/data/artemis.pid")" >> "${log_file}" 2>&1

echo "   Result: OK"
echo

echo "== Summary" | tee -a "${log_file}"
echo

echo "   ActiveMQ Artemis is now installed.  Use 'artemis run' to start the broker."

# If you are learning about ActiveMQ Artemis, see XXX.  (getting started)
# If you are deploying and configuring ActiveMQ Artemis, see XXX.  (config next steps)

# XXX Path stuff!

# XXX details as properties
