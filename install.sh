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

random_number() {
    echo "$(date +%s)$$"
}

port_is_open() {
    # if lsof -PiTCP -sTCP:LISTEN | grep ":${1}"
    # if netstat -an | grep LISTEN | grep ":${1}"
    if nc -z localhost "${1}"
    then
        echo "Port ${1} is open"
        return 1
    else
        echo "Port ${1} is closed"
        return 0
    fi
}

file_append_lines_at() {
    file="${1}"

    shift

    script="${1}a\\
"

    shift

    for arg in "$@"
    do
        script="${script}${arg}\n"
    done

    run sed -i.backup -e "${script}" "${file}"

    echo 111
    head -n 30 "${file}"
    echo 222

    rm "${file}.backup"
}

assert() {
    if ! [ "$@" ]
    then
        echo "ASSERTION FAILED: \"${@}\""
        exit 1
    fi
}

log() {
    echo "-- ${1} --"
}

log_section() {
    echo "== ${1} =="
}

run() {
    echo "-- Running '$@' --"
    "$@"
}

start_red='\033[0;31m'
start_green='\033[0;32m'
end_color='\033[0m'

print() {
    printf "$@" >&3
}

print_section() {
    print "== ${1} ==\n\n"
    log_section "${1}"
}

print_result() {
    print "   ${start_green}${1}${end_color}\n\n"
    log "Result: ${1}"
}

fail() {
    print "   ${start_red}ERROR:${end_color} ${1}\n\n"
    log "ERROR: ${1}"

    suppress_trouble_report=1

    exit 1
}

enable_strict_mode() {
    # No clobber, exit on error, and fail on unbound variables
    set -Ceu

    if [ -n "${BASH:-}" ]
    then
        # Inherit traps, fail fast in pipes, enable POSIX mode, and
        # disable brace expansion
        #
        # shellcheck disable=SC3040,SC3041 # We know this is Bash in this case
        set -E -o pipefail -o posix +o braceexpand

        assert -n "${POSIXLY_CORRECT}"

        # Restrict echo behavior
        shopt -s xpg_echo

    fi

    if [ -n "${ZSH_VERSION:-}" ]
    then
        # Get standard POSIX behavior for appends
        set -o append_create
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

handle_exit() {
    exit_code=$?

    # Restore stdout and stderr
    exec 1>&7
    exec 2>&8

    # shellcheck disable=SC2181 # This is intentionally indirect
    if [ "${exit_code}" != 0 ] && [ -z "${suppress_trouble_report:-}" ]
    then
        if [ -n "${VERBOSE:-}" ]
        then
            echo "${start_red}TROUBLE!${end_color} Something went wrong."
        else
            print "   ${start_red}TROUBLE!${end_color} Something went wrong.\n\n"
            print "== Log ==\n\n"

            cat "${log_file}" | sed -e "s/^/  /"
            echo
        fi
    fi
}

# Takes the name of this script, which it uses to define a work dir
init() {
    enable_strict_mode

    if [ -n "${DEBUG:-}" ]
    then
        enable_debug_mode
    fi

    trap handle_exit EXIT

    # This is required to preserve the Windows drive letter in the
    # path to HOME
    case "$(uname)" in
        CYGWIN*)
            HOME="$(cygpath --mixed --windows "${HOME}")"
            ;;
        *)
            ;;
    esac

    script_name="${1}"
    script_dir="${HOME}/.cache/${script_name}"
    log_file="${script_dir}/install.log"

    mkdir -p "${script_dir}"

    if [ -e "${log_file}" ]
    then
        mv "${log_file}" "${log_file}.$(date +%Y-%m-%d).$(random_number)"
    fi

    # Use file descriptor 3 for the default display output
    exec 3>&1

    # Use file descriptor 4 for logging and command output
    exec 4>&2

    # Save stdout and stderr before redirection
    exec 7>&1
    exec 8>&2

    # If verbose, suppress the default display output and log
    # everything to the console. Otherwise, capture logging and
    # command output to the log file.
    #
    # XXX Use tee to capture to the log file at the same time?
    if [ -n "${VERBOSE:-}" ]
    then
        exec 3> /dev/null
    else
        exec 4> "${log_file}"
    fi
}

main() {
    init artemis-install-script

    {
        bin_dir="${HOME}/.local/bin"
        artemis_config_dir="${HOME}/.config/artemis"
        artemis_home_dir="${HOME}/.local/share/artemis"
        artemis_instance_dir="${HOME}/.local/state/artemis"
        artemis_backup_dir="${HOME}/artemis-backup"

        if [ -e "${artemis_backup_dir}" ]
        then
            mv "${artemis_backup_dir}" "${artemis_backup_dir}.$(date +%Y-%m-%d).$(random_number)"
        fi

        print_section "Checking for required tools and ports"

        # artemis-service requires ps
        for program in awk curl grep java nc ps sed tar
        do
            log "Checking program '${program}'"

            if ! command -v "${program}"
            then
                missing="${missing:-}${program}, "
            fi
        done

        log "Checking for either 'sha512sum' or 'shasum'"

        if ! command -v sha512sum && ! command -v shasum
        then
            missing="${missing:-}, sha512sum (or shasum)"
        fi

        # XXX Test with java --version to make sure it is set up

        if [ -n "${missing:-}" ]
        then
            fail "Some required programs are not available: ${missing%, }"
            # XXX Guidance
        fi

        for port in 1883 5672 8161 61613 61616; do
            log "Checking port ${port}"

            if ! port_is_open "${port}"
            then
                occupied="${occupied:-}${port}, "
            fi
        done

        if [ -n "${occupied:-}" ]
        then
            fail "Some required ports are in use by something else: ${occupied%, }"
            # XXX Guidance
        fi

        print_result "OK"

        print_section "Downloading and verifying the latest release"

        log "Determining the latest version"

        # XXX run curl ...

        version="$(curl -fL https://dlcdn.apache.org/activemq/activemq-artemis/ \
                   | awk 'match($0, /[0-9]+\.[0-9]+\.[0-9]+/) { print substr($0, RSTART, RLENGTH) }' \
                   | sort -t . -k1n -k2n -k3n \
                   | tail -n 1)"

        log "Version: ${version}"

        release_archive_name="apache-artemis-${version}-bin.tar.gz"
        release_archive_file="${script_dir}/${release_archive_name}"
        release_dir="${script_dir}/apache-artemis-${version}"

        if [ ! -e "${release_archive_file}" ]
        then
            log "Downloading the latest release archive"

            run curl -fLo "${release_archive_file}" \
                "https://www.apache.org/dyn/closer.cgi?filename=activemq/activemq-artemis/${version}/${release_archive_name}&action=download"
        else
            log "Using the cached release archive"
        fi

        log "Archive file: ${release_archive_file}"

        log "Downloading the checksum file"

        # XXX Decide if this is a "known" error
        run curl -fo "${release_archive_file}.sha512" \
            "https://downloads.apache.org/activemq/activemq-artemis/${version}/${release_archive_name}.sha512"

        log "Checksum file: ${release_archive_file}.sha512"

        log "Verifying the release archive"

        (
            cd "${script_dir}"

            if command -v sha512sum
            then
                run sha512sum --check "${release_archive_file}.sha512"
            elif command -v shasum
            then
                run shasum -a 512 -c "${release_archive_file}.sha512"
            else
                assert ! ever
            fi
        )

        # XXX Move this down?
        gzip -dc "${release_archive_file}" | (cd "$(dirname "${release_dir}")" && tar xf -)

        assert -d "${release_dir}"

        print_result "OK"

        if [ -e "${artemis_config_dir}" ] || [ -e "${artemis_home_dir}" ] || [ -e "${artemis_instance_dir}" ]
        then
            print_section "Saving the existing installation to a backup"

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

            print_result "${artemis_backup_dir}"
        fi

        print_section "Installing the broker"

        log "Moving the release dir to its install location"

        assert ! -e "${artemis_home_dir}"

        mkdir -p "$(dirname "${artemis_home_dir}")"
        mv "${release_dir}" "${artemis_home_dir}"

        log "Burning the Artemis home dir into the admin script"

        file_append_lines_at "${artemis_home_dir}/bin/artemis" 18 "ARTEMIS_HOME=${artemis_home_dir}"

        log "Creating the broker instance"

        run "${artemis_home_dir}/bin/artemis" create "${artemis_instance_dir}" \
            --user example --password example \
            --host localhost --allow-anonymous \
            --no-autotune \
            --no-hornetq-acceptor \
            --etc "${artemis_config_dir}" \
            --verbose

        log "Burning the instance dir into the instance scripts"

        file_append_lines_at "${artemis_instance_dir}/bin/artemis" 18 "ARTEMIS_INSTANCE=${artemis_instance_dir}"
        file_append_lines_at "${artemis_instance_dir}/bin/artemis-service" 18 "ARTEMIS_INSTANCE=${artemis_instance_dir}"

        case "$(uname)" in
            CYGWIN*)
                # log "Patching problem 1"

                # # This bit of the Artemis instance script uses a cygpath --unix,
                # # cygpath --windows sequence that ends up stripping out the drive
                # # letter and replacing it with whatever the current drive is. If your
                # # current drive is different from the Artemis install drive, trouble.
                # #
                # # For the bug: Annotate the current code.  Suggest --absolute.

                # # XXX Try patching for --absolute instead

                # sed -i.backup2 -e "77,82d" "${artemis_instance_dir}/bin/artemis"

                log "Patching problem 2"

                # And this bit replaces a colon with a semicolon in the
                # bootclasspath.  Windows requires a semicolon.

                # shellcheck disable=SC2016 # I don't want these expanded
                sed -i.backup3 -e 's/\$LOG_MANAGER:\$WILDFLY_COMMON/\$LOG_MANAGER;\$WILDFLY_COMMON/' "${artemis_instance_dir}/bin/artemis"
                ;;
            *)
                ;;
        esac

        log "Creating symlinks to the scripts"

        mkdir -p "${bin_dir}"

        (
            run cd "${bin_dir}"

            run ln -sf "${artemis_instance_dir}/bin/artemis" .
            run ln -sf "${artemis_instance_dir}/bin/artemis-service" .
        )

        print_result "OK"

        print_section "Testing the installation"

        log "Testing the artemis command"

        run "${bin_dir}/artemis" version

        log "Testing the broker"

        run "${bin_dir}/artemis-service" start

        while port_is_open 61616
        do
            log "Waiting for the broker to start"
            sleep 2
        done

        run "${bin_dir}/artemis" producer --silent --verbose --message-count 1
        run "${bin_dir}/artemis" consumer --silent --verbose --message-count 1

        # cat "${artemis_instance_dir}/log/artemis.log"

        # The 'artemis-service stop' command times out too quickly for
        # CI, so I tolerate a failure here
        run "${bin_dir}/artemis-service" stop || :

        # The kill -0 variant fails because zombies, but only in CI
        # (and perhaps only in containers), not on my local machine
        #
        # while kill -0 "${artemis_pid}"
        while ! port_is_open 61616
        do
            log "Waiting for the broker to exit"
            sleep 2
        done

        print_result "OK"

        print_section "Summary"

        print "   ActiveMQ Artemis is now installed.  Use 'artemis run' to start the broker.\n\n"

        # If you are learning about ActiveMQ Artemis, see XXX.  (getting started)
        # If you are deploying and configuring ActiveMQ Artemis, see XXX.  (config next steps)

        # XXX Path stuff!

        # XXX details as properties
    } >&4 2>&4
}

main "$@"
