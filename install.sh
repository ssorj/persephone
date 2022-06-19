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

enable_strict_mode() {
    # No clobber, exit on error, and fail on unbound variables
    set -Ceu

    # Request POSIX behavior from child processes
    export POSIXLY_CORRECT=1

    if [ -n "${BASH:-}" ]
    then
        # Inherit traps and fail fast in pipes
        # shellcheck disable=SC3040,SC3041 # We know this is Bash in this case
        set -E -o pipefail -o posix
        # XXX -o posix might be a posix thing
    fi
}

enable_debug_mode() {
    # Print the input commands and their expanded form to the console
    set -vx

    if [ -n "${BASH:-}" ]
    then
        # Bash offers more details
        export PS4='\033[0;33m${BASH_SOURCE}:${LINENO}:\033[0m ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    fi
}

init_script() {
    enable_strict_mode

    if [ -n "${DEBUG:-}" ]
    then
        enable_debug_mode
    fi

    # This is required to preserve the Windows drive letter in the
    # path to HOME
    case "$(uname)" in
        CYGWIN*)
            HOME="$(cygpath --mixed --windows "${HOME}")"
            ;;
        *)
            ;;
    esac

    script_dir="${HOME}/.cache/artemis-install-script"
    log_file="${script_dir}/install.log"

    mkdir -p "${script_dir}"

    if [ -e "${log_file}" ]
    then
        mv "${log_file}" "${log_file}.$(date +%Y-%m-%d).$$"
    fi
}

assert() {
    if ! [ "$@" ]
    then
        echo "ASSERTION FAILED: \"${@}\"" >> "${log_file}"
        exit 1
    fi
}

log() {
    echo "-- ${1} --" >> "${log_file}"
}

print_section() {
    echo "== ${1} =="
    echo

    log "${1}"
}

print_result() {
    echo "   Result: ${1}"
    echo
}

check_program() {
    log "Checking for ${1}"

    if ! command -v "${1}" >> "${log_file}" 2>&1
    then
        echo "ERROR: Required program ${tool} is not available"
        log "ERROR: Required program ${tool} is not available" # XXX
        exit 1
    fi
}

handle_exit() {
    # shellcheck disable=SC2181 # This is intentionally indirect
    if [ $? != 0 ]
    then
        echo
        echo "TROUBLE!"
        echo

        cat "${log_file}" || :
    fi
}

trap handle_exit EXIT

main() {
    init_script

    bin_dir="${HOME}/.local/bin"
    artemis_config_dir="${HOME}/.config/artemis"
    artemis_home_dir="${HOME}/.local/share/artemis"
    artemis_instance_dir="${HOME}/.local/state/artemis"
    artemis_backup_dir="${HOME}/artemis-backup"

    if [ -e "${artemis_backup_dir}" ]
    then
        mv "${artemis_backup_dir}" "${artemis_backup_dir}.$(date +%Y-%m-%d).$$" >> "${log_file}" 2>&1
    fi

    print_section "Checking for required tools"

    for program in awk curl grep java sed sort tail tar uname; do
        check_program "${program}"
    done

    print_result "OK"

    # XXX Check for needed free ports here, and if they aren't free,
    # propose freeing them or running the script with the precondition
    # and related testing skipped

    print_section "Determining the latest version"

    {
        version="$(curl --no-progress-meter -fL https://dlcdn.apache.org/activemq/activemq-artemis/ \
                   | awk 'match($0, /[0-9]+\.[0-9]+\.[0-9]+/) { print substr($0, RSTART, RLENGTH) }' \
                   | sort -t . -k1n -k2n -k3n \
                   | tail -n 1)"
    } >> "${log_file}" 2>&1

    print_result "${version}"

    print_section "Fetching the release archive"

    {
        release_archive="${script_dir}/apache-artemis-${version}-bin.tar.gz"
        release_dir="${script_dir}/apache-artemis-${version}"

        if [ ! -e "${release_archive}" ]
        then
            log "Downloading the latest release archive"

            # XXX Want a way to log command *and* run it

            curl --no-progress-meter -fLo "${release_archive}" "https://www.apache.org/dyn/closer.cgi?filename=activemq/activemq-artemis/${version}/apache-artemis-${version}-bin.tar.gz&action=download"

            log "Downloaded ${release_archive}"
        else
            log "Using the cached release archive"
        fi

        gzip -dc "${release_archive}" | (cd "$(dirname "${release_dir}")" && tar xf -)

        assert -d "${release_dir}"
    } >> "${log_file}" 2>&1

    print_result "OK"

    if [ -e "${artemis_config_dir}" ] || [ -e "${artemis_home_dir}" ] || [ -e "${artemis_instance_dir}" ]
    then
        print_section "Saving the existing installation to a backup" | tee -a "${log_file}"

        {
            log "Saving the previous config dir"

            if [ -e "${artemis_config_dir}" ]
            then
                mkdir -p "${artemis_backup_dir}/config"
                mv "${artemis_config_dir}" "${artemis_backup_dir}/config"
            fi

            log "Saving the previous dist dir"

            if [ -e "${artemis_home_dir}" ]
            then
                mkdir -p "${artemis_backup_dir}/share"
                mv "${artemis_home_dir}" "${artemis_backup_dir}/share"
            fi

            log "Saving the previous instance dir"

            if [ -e "${artemis_instance_dir}" ]
            then
                mkdir -p "${artemis_backup_dir}/state"
                mv "${artemis_instance_dir}" "${artemis_backup_dir}/state"
            fi

            assert -d "${artemis_backup_dir}"
        } >> "${log_file}" 2>&1

        print_result "${artemis_backup_dir}"
    fi

    print_section "Installing the broker"

    {
        log "Moving the release dir to its install location"

        assert ! -e "${artemis_home_dir}"

        mkdir -p "$(dirname "${artemis_home_dir}")"
        mv "${release_dir}" "${artemis_home_dir}"

        log "Burning the Artemis home dir into the admin script"

        sed -i.backup "18a\\
ARTEMIS_HOME=${artemis_home_dir}
" "${artemis_home_dir}/bin/artemis"

        log "Creating the broker instance"

        "${artemis_home_dir}/bin/artemis" create "${artemis_instance_dir}" \
                                        --user example --password example \
                                        --host localhost --allow-anonymous \
                                        --no-autotune \
                                        --no-hornetq-acceptor \
                                        --etc "${artemis_config_dir}" \
                                        --verbose

        log "Burning the instance dir into the instance scripts"

        sed -i.backup "18a\\
ARTEMIS_INSTANCE=${artemis_instance_dir}
" "${artemis_instance_dir}/bin/artemis"

        sed -i.backup "18a\\
ARTEMIS_INSTANCE=${artemis_instance_dir}
" "${artemis_instance_dir}/bin/artemis-service"

        # if [ -n "${cygwin:-}" ]
        # then
        #     log "Patching problem 1"

        #     # This bit of the Artemis instance script uses a cygpath --unix,
        #     # cygpath --windows sequence that ends up stripping out the drive
        #     # letter and replacing it with whatever the current drive is. If your
        #     # current drive is different from the Artemis install drive, trouble.
        #     #
        #     # For the bug: Annotate the current code.  Suggest --absolute.

        #     # XXX Try patching for --absolute instead

        #     sed -i.backup2 "77,82d" "${artemis_instance_dir}/bin/artemis"

        #     log "Patching problem 2"

        #     # And this bit replaces a colon with a semicolon in the
        #     # bootclasspath.  Windows requires a semicolon.

        #     # shellcheck disable=SC2016 # I don't want these expanded
        #     sed -i.backup3 's/\$LOG_MANAGER:\$WILDFLY_COMMON/\$LOG_MANAGER;\$WILDFLY_COMMON/' "${artemis_instance_dir}/bin/artemis"
        # fi

        log "Creating symlinks to the scripts"

        mkdir -p "${bin_dir}"

        (
            cd "${bin_dir}"

            ln -sf "${artemis_instance_dir}/bin/artemis" .
            ln -sf "${artemis_instance_dir}/bin/artemis-service" .
        )
    } >> "${log_file}" 2>&1

    print_result "OK"

    print_section "Testing the installation"

    {
        log "Testing the artemis command"

        "${bin_dir}/artemis" version

        if command -v lsof
        then
            # XXX Consider making this a pre-installation check

            log "Checking that the required ports are available"

            for port in 61616 5672 61613 1883 8161; do
                if lsof -PiTCP -sTCP:LISTEN | grep "${port}"
                then
                    echo "ERROR: Required port ${port} is in use by something else"
                    log "ERROR: Required port ${port} is in use by something else" # XXX
                    exit 1
                fi
            done
        fi

        log "Testing the server"

        "${bin_dir}/artemis-service" start

        if command -v lsof
        then
            i=100

            while [ "${i}" -gt 0 ]
            do
                if lsof -PiTCP -sTCP:LISTEN | grep 61616
                then
                    break;
                fi

                sleep 2

                i=$((i - 1))
            done
        else
            sleep 30
        fi

        "${bin_dir}/artemis" check node --verbose

        # The 'artemis-service stop' command times out too quickly for CI, so
        # I take an alternate approach.

        kill "$(cat "${artemis_instance_dir}/data/artemis.pid")"
    } >> "${log_file}" 2>&1

    print_result "OK"

    print_section "Summary"

    echo "   ActiveMQ Artemis is now installed.  Use 'artemis run' to start the broker."

    # If you are learning about ActiveMQ Artemis, see XXX.  (getting started)
    # If you are deploying and configuring ActiveMQ Artemis, see XXX.  (config next steps)

    # XXX Path stuff!

    # XXX details as properties
}

main "$@"
