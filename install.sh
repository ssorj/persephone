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

# func <port>
port_is_taken() {
    # if lsof -PiTCP -sTCP:LISTEN | grep ":${1}"
    # if netstat -an | grep LISTEN | grep ":${1}"
    if nc -z localhost "${1}"
    then
        echo "Port ${1} is taken"
        return 0
    else
        echo "Port ${1} is free"
        return 1
    fi
}

assert() {
    if ! [ "$@" ]
    then
        echo "ASSERTION FAILED: \"${@}\""
        exit 1
    fi
}

log() {
    echo "-- ${1}"
}

run() {
    echo "-- Running '$@'" >&2
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
    echo "== ${1}"
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

# init <module-name> <script-name>
init() {
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

    module_name="${1}"
    script_name="${2}"
    work_dir="${HOME}/.cache/${module_name}"
    log_file="${work_dir}/${script_name}.log"

    mkdir -p "${work_dir}"
    cd "${work_dir}"

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

usage() {
    if [ "${#}" != 0 ]
    then
        printf "${start_red}ERROR:${end_color} ${@}\n\n"
    fi

    cat <<EOF
Usage: ${0} [-sym]

A script that installs ActiveMQ Artemis

Options:
  -s <scheme>   Select an installation scheme (default "home")
  -v            Print detailed logging to the console
  -y            Operate in non-interactive mode

Installation schemes:
  home          Install to ~/.local and ~/.config
  opt           Install to /opt, /var/opt, and /etc/opt
EOF

    exit 1
}

# func <script> <artemis-instance-dir>
create_artemis_instance_script() {
    cat > "${1}" <<EOF
#!/bin/sh

export ARTEMIS_INSTANCE=${2}

exec "\${ARTEMIS_INSTANCE}/bin/$(basename "${1}")" "\$@"
EOF

    chmod +x "${1}"
}

main() {
    enable_strict_mode

    scheme="home"
    non_interactive=1

    while getopts :s:vy option
    do
        case "${option}" in
            s)
                scheme="${OPTARG}"
                ;;
            v)
                VERBOSE=1
                ;;
            y)
                non_interactive=1
                ;;
            *)
                usage "Option \"${OPTARG}\" is unknown"
                ;;
        esac
    done

    case "${scheme}" in
        home)
            bin_dir="${HOME}/.local/bin"
            artemis_config_dir="${HOME}/.config/artemis"
            artemis_home_dir="${HOME}/.local/share/artemis"
            artemis_instance_dir="${HOME}/.local/state/artemis"
            artemis_backup_dir="${HOME}/artemis-backup"
            ;;
        opt)
            bin_dir="/opt/artemis/bin"
            artemis_config_dir="/etc/opt/artemis"
            artemis_home_dir="/opt/artemis"
            artemis_instance_dir="/var/opt/artemis"
            ;;
        *)
            usage "Installation scheme \"${scheme}\" is unknown"
            ;;
    esac

    init artemis-install-script install

    {
        if [ -e "${artemis_backup_dir}" ]
        then
            mv "${artemis_backup_dir}" "${artemis_backup_dir}.$(date +%Y-%m-%d).$(random_number)"
        fi

        print_section "Checking for required tools and resources"

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

        if [ -n "${missing:-}" ]
        then
            fail "Some required programs are not available: ${missing%??}"
            # XXX Guidance - Use your OS's package manager to lookup and install things
        fi

        log "Checking the Java installation"

        if ! java --version
        then
            fail "The program 'java' is installed, but it isn't working"
            # XXX Guidance - This seems to be a problem on Mac OS - Suggest Temurin via brew
        fi

        for port in 1883 5672 8161 61613 61616; do
            log "Checking port ${port}"

            if port_is_taken "${port}"
            then
                taken="${taken:-}${port}, "
            fi
        done

        if [ -n "${taken:-}" ]
        then
            fail "Some required ports are in use by something else: ${taken%??}"
            # XXX Guidance - Use lsof or netstat to find out what's using these ports and terminate it
        fi

        # log "Checking permission to write to the install location"

        # if run mkdir "$(dirname "${artemis_home_dir}")/artemis-install-script-test-dir"
        # then
        #     rmdir "$(dirname "${artemis_home_dir}")/artemis-install-script-test-dir"
        # else
        #     fail "I don't have permission to write to the install location"
        #     # XXX Guidance
        # fi

        # XXX Check network access

        print_result "OK"

        print_section "Downloading and verifying the latest release"

        log "Determining the latest release version"

        release_version_file="${work_dir}/release-version.txt"

        run curl -fL https://dlcdn.apache.org/activemq/activemq-artemis/ \
            | awk 'match($0, /[0-9]+\.[0-9]+\.[0-9]+/) { print substr($0, RSTART, RLENGTH) }' \
            | sort -t . -k1n -k2n -k3n \
            | tail -n 1 >| "${release_version_file}"

        release_version="$(cat "${release_version_file}")"

        log "Release version: ${release_version}"

        release_archive_name="apache-artemis-${release_version}-bin.tar.gz"
        release_archive_file="${work_dir}/${release_archive_name}"
        release_archive_checksum="${work_dir}/${release_archive_name}.sha512"

        if [ ! -e "${release_archive_file}" ]
        then
            log "Downloading the latest release archive"

            run curl -fLo "${release_archive_file}" \
                "https://www.apache.org/dyn/closer.cgi?filename=activemq/activemq-artemis/${release_version}/${release_archive_name}&action=download"
        else
            log "Using the cached release archive"
        fi

        log "Archive file: ${release_archive_file}"

        log "Downloading the checksum file"

        run curl -fo "${release_archive_checksum}" \
            "https://downloads.apache.org/activemq/activemq-artemis/${release_version}/${release_archive_name}.sha512"

        log "Checksum file: ${release_archive_checksum}"

        log "Verifying the release archive"

        (
            cd "${work_dir}"

            if command -v sha512sum
            then
                if ! run sha512sum -c "${release_archive_checksum}"
                then
                    fail "The checksum does not match the downloaded release archive"
                    # XXX Guidance - Try blowing away the cached download
                fi
            elif command -v shasum
            then
                if ! run shasum -a 512 -c "${release_archive_checksum}"
                then
                    fail "The checksum does not match the downloaded release archive"
                    # XXX Guidance - Try blowing away the cached download
                fi
            else
                assert ! ever
            fi
        )

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

        log "Extracting the release dir from the release archive"

        release_dir="${work_dir}/apache-artemis-${release_version}"

        gzip -dc "${release_archive_file}" | (cd "$(dirname "${release_dir}")" && tar xf -)

        assert -d "${release_dir}"

        log "Moving the release dir to its install location"

        assert ! -e "${artemis_home_dir}"

        mkdir -p "$(dirname "${artemis_home_dir}")"
        mv "${release_dir}" "${artemis_home_dir}"

        log "Creating the broker instance"

        run "${artemis_home_dir}/bin/artemis" create "${artemis_instance_dir}" \
            --user example --password example \
            --host localhost --allow-anonymous \
            --no-autotune \
            --no-hornetq-acceptor \
            --etc "${artemis_config_dir}" \
            --verbose

        case "$(uname)" in
            CYGWIN*)
                log "Patching a problem with the artemis script on Windows"

                # This bit replaces a colon with a semicolon in the
                # bootclasspath.  Windows requires a semicolon.

                # shellcheck disable=SC2016 # I don't want these expanded
                sed -i.backup -e 's/\$LOG_MANAGER:\$WILDFLY_COMMON/\$LOG_MANAGER;\$WILDFLY_COMMON/' "${artemis_instance_dir}/bin/artemis"
                rm "${artemis_instance_dir}/bin/artemis.backup"
                ;;
            *)
                ;;
        esac

        log "Creating wrapper scripts"

        # XXX What if you already have artemis in one of the bin dirs?

        mkdir -p "${bin_dir}"

        rm -f "${bin_dir}/artemis"
        rm -f "${bin_dir}/artemis-service"

        create_artemis_instance_script "${bin_dir}/artemis" "${artemis_instance_dir}"
        create_artemis_instance_script "${bin_dir}/artemis-service" "${artemis_instance_dir}"

        if [ -d "${HOME}/bin" ]
        then
            rm -f "${HOME}/bin/artemis"
            rm -f "${HOME}/bin/artemis-service"

            create_artemis_instance_script "${HOME}/bin/artemis" "${artemis_instance_dir}"
            create_artemis_instance_script "${HOME}/bin/artemis-service" "${artemis_instance_dir}"
        fi

        print_result "OK"

        print_section "Testing the installation"

        log "Testing the artemis command"

        # XXX Consider printing the log on failure
        # cat "${artemis_instance_dir}/log/artemis.log"
        run "${bin_dir}/artemis" version

        log "Testing the broker"

        run "${bin_dir}/artemis-service" start

        while ! port_is_taken 61616
        do
            log "Waiting for the broker to start"
            sleep 2
        done

        # XXX Consider printing the log on failure
        # cat "${artemis_instance_dir}/log/artemis.log"
        run "${bin_dir}/artemis" producer --silent --verbose --message-count 1
        run "${bin_dir}/artemis" consumer --silent --verbose --message-count 1

        # The 'artemis-service stop' command times out too quickly for
        # CI, so I tolerate a failure here
        run "${bin_dir}/artemis-service" stop || :

        while port_is_taken 61616
        do
            log "Waiting for the broker to exit"
            sleep 2
        done

        print_result "OK"

        print_section "Summary"

        print_result "SUCCESS"

        print "   ActiveMQ Artemis is now installed.  Use 'artemis run' to start the broker.\n\n"

        # XXX Path stuff!

        print "   Version:       ${release_version}\n"
        print "   Config files:  ${artemis_config_dir}\n"
        print "   Log files:     ${artemis_instance_dir}/log\n"
        print "   Data files:    ${artemis_instance_dir}/data\n"
        print "\n"

        print "   If you are learning about Artemis, see the getting started guide:\n\n"
        print "     https://github.com/ssorj/persephone/blob/main/getting-started.md\n\n"

        print "   If you are preparing Artemis for production use, see the deployment guide:\n\n"
        print "     https://github.com/ssorj/persephone/blob/main/deployment.md\n\n"
    } >&4 2>&4
}

main "$@"
