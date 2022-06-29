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
port_is_available() {
    if nc -z localhost "${1}"
    then
        printf "Port %s is not available\n" "${1}"
        return 1
    else
        printf "Port %s is available\n" "${1}"
        return 0
    fi
}

assert() {
    # shellcheck disable=SC2244 # We want the split args
    if ! [ "$@" ]
    then
        printf "$(red "ASSERTION FAILED:") \"%s\"\n" "${*}"
        exit 1
    fi
}

log() {
    printf -- "-- %s\n" "${1}"
}

run() {
    printf -- "-- Running '%s'\n" "${*}" >&2
    "$@"
}

red() {
    printf "\033[0;31m%s\033[0m" "${1}"
}

green() {
    printf "\033[0;32m%s\033[0m" "${1}"
}

yellow() {
    printf "\033[0;33m%s\033[0m" "${1}"
}

print() {
    if [ "${#}" = 0 ]
    then
        printf "\n" >&3
        printf -- "--\n"
        return
    fi

    if [ "${1}" = "-n" ]
    then
        shift

        printf "   %s" "${1}" >&3
        printf -- "-- %s" "${1}"
    else
        printf "   %s\n" "${1}" >&3
        printf -- "-- %s\n" "${1}"
    fi
}

print_section() {
    printf "== %s ==\n\n" "${1}" >&3
    printf "== %s\n" "${1}"
}

print_result() {
    printf "   %s\n\n" "$(green "${1}")" >&3
    log "Result: $(green "${1}")"
}

fail() {
    printf "   %s %s\n\n" "$(red "ERROR:")" "${1}" >&3
    log "$(red "ERROR:") ${1}"

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
        # shellcheck disable=SC3044 # Intentionally Bash-specific
        shopt -s xpg_echo
    fi

    if [ -n "${ZSH_VERSION:-}" ]
    then
        # Get standard POSIX behavior for appends
        # shellcheck disable=SC3040 # Intentionally Zsh-specific
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
            echo "$(red "TROUBLE!") Something went wrong."
        else
            printf "   %s Something went wrong.\n\n" "$(red "TROUBLE!")"
            printf "== Log ==\n\n"

            sed -e "s/^/  /" < "${log_file}"
            echo
        fi
    fi
}

# func <log_file>
init_logging() {
    log_file="${1}"

    trap handle_exit EXIT

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

check_writable_directories() {
    log "Checking for permission to write to the install directories"

    for dir in "$@"
    do
        log "Checking directory '${dir}'"

        base_dir="${dir}"

        while [ ! -e "${base_dir}" ]
        do
            base_dir="$(dirname "${base_dir}")"
        done

        if [ -w "${base_dir}" ]
        then
            printf "Directory '%s' is writable\n" "${base_dir}"
        else
            printf "Directory '%s' is not writeable\n" "${base_dir}"
            unwritable_dirs="${unwritable_dirs:-}${base_dir}, "
        fi
    done

    if [ -n "${unwritable_dirs:-}" ]
    then
        fail "Some directories are not writable: ${unwritable_dirs%??}"
        # XXX Guidance
    fi
}

check_required_programs() {
    log "Checking for required programs"

    for program in "$@"
    do
        log "Checking program '${program}'"

        if ! command -v "${program}"
        then
            unavailable_programs="${unavailable_programs:-}${program}, "
        fi
    done

    if [ -n "${unavailable_programs:-}" ]
    then
        fail "Some required programs are not available: ${unavailable_programs%??}"
        # XXX Guidance - Use your OS's package manager to lookup and install things
    fi
}

check_required_program_sha512sum() {
    log "Checking for either 'sha512sum' or 'shasum'"

    if ! command -v sha512sum && ! command -v shasum
    then
        fail "Some required programs are not available: sha512sum or shasum"
    fi
}

check_required_ports() {
    log "Checking for required ports"

    for port in "$@"
    do
        log "Checking port ${port}"

        if ! port_is_available "${port}"
        then
            unavailable_ports="${unavailable_ports:-}${port}, "
        fi
    done

    if [ -n "${unavailable_ports:-}" ]
    then
        fail "Some required ports are in use by something else: ${unavailable_ports%??}"
        # XXX Guidance - Use lsof or netstat to find out what's using these ports and terminate it
    fi
}

check_required_network_resources() {
    log "Checking for required network resources"

    for url in "$@"
    do
        log "Checking URL '${url}'"

        if ! curl -sf --show-error --head "${url}"
        then
            unavailable_urls="${unavailable_urls:-}${url}, "
        fi
    done

    if [ -n "${unavailable_urls:-}" ]
    then
        fail "Some required network resources are not available: ${unavailable_urls%??}"
        # XXX Guidance
    fi
}

check_java() {
    log "Checking the Java installation"

    if ! java --version
    then
        fail "The program 'java' is available, but it isn't working"
        # XXX Guidance - This seems to be a problem on Mac OS - Suggest Temurin via brew
    fi
}

# func <url-path> -> release_version=<version>, release_file=<file>
fetch_latest_apache_release() {
    _url_path="${1}"
    _release_version_file="${work_dir}/release-version.txt"

    log "Looking up the latest release version"

    run curl -sf --show-error "https://dlcdn.apache.org${_url_path}" \
        | awk 'match($0, /[0-9]+\.[0-9]+\.[0-9]+/) { print substr($0, RSTART, RLENGTH) }' \
        | sort -t . -k1n -k2n -k3n \
        | tail -n 1 >| "${_release_version_file}"

    _release_version="$(cat "${_release_version_file}")"

    printf "Release version: %s\n" "${_release_version}"
    printf "Release version file: %s\n" "${_release_version_file}"

    _release_file_name="apache-artemis-${_release_version}-bin.tar.gz"
    _release_file="${work_dir}/${_release_file_name}"
    _release_file_checksum="${_release_file}.sha512"

    if [ ! -e "${_release_file}" ]
    then
        log "Downloading the latest release"

        run curl -sf --show-error -o "${_release_file}" \
            "https://dlcdn.apache.org/activemq/activemq-artemis/${_release_version}/${_release_file_name}"
    else
        log "Using the cached release archive"
    fi

    printf "Archive file: %s\n" "${_release_file}"

    log "Downloading the checksum file"

    run curl -sf --show-error -o "${_release_file_checksum}" \
        "https://downloads.apache.org/activemq/activemq-artemis/${_release_version}/${_release_file_name}.sha512"

    printf "Checksum file: %s\n" "${_release_file_checksum}"

    log "Verifying the release archive"

    if command -v sha512sum
    then
        if ! run sha512sum -c "${_release_file_checksum}"
        then
            fail "The checksum does not match the downloaded release archive"
            # XXX Guidance - Try blowing away the cached download
        fi
    elif command -v shasum
    then
        if ! run shasum -a 512 -c "${_release_file_checksum}"
        then
            fail "The checksum does not match the downloaded release archive"
            # XXX Guidance - Try blowing away the cached download
        fi
    else
        assert ! ever
    fi

    assert -z "${release_version:-}"
    assert -z "${release_file:-}"

    release_version="${_release_version}"
    release_file="${_release_file}"
}

# func <backup-dir> <config-dir> <share-dir> <state-dir> [<bin-file>...]
save_backup() {
    _backup_dir="${1}"
    _config_dir="${2}"
    _share_dir="${3}"
    _state_dir="${4}"

    shift 4

    log "Saving the previous config dir"

    if [ -e "${_config_dir}" ]
    then
        mkdir -p "${_backup_dir}/config"
        mv "${_config_dir}" "${_backup_dir}/config"
    fi

    log "Saving the previous share dir"

    if [ -e "${_share_dir}" ]
    then
        mkdir -p "${_backup_dir}/share"
        mv "${_share_dir}" "${_backup_dir}/share"
    fi

    log "Saving the previous state dir"

    if [ -e "${_state_dir}" ]
    then
        mkdir -p "${_backup_dir}/state"
        mv "${_state_dir}" "${_backup_dir}/state"
    fi

    for _bin_file in "$@"
    do
        if [ -e "${_bin_file}" ]
        then
            mkdir -p "${_backup_dir}/bin"
            mv "${_bin_file}" "${_backup_dir}/bin"
        fi
    done

    # XXX Not quite right?
    assert -d "${_backup_dir}"
}

#
# Burly stuff above this point.  Artemis stuff below this point.
#

usage() {
    _prog="${0}"
    _error="${1:-}"

    if [ -n "${_error}" ]
    then
        printf "%b %s\n\n" "$(red "ERROR:")" "${*}"
    fi

    cat <<EOF
Usage: ${_prog} [-hvy] [-s <scheme>]

A script that installs ActiveMQ Artemis

Options:
  -h            Print this help text and exit
  -s <scheme>   Select an installation scheme (default "home")
  -v            Print detailed logging to the console
  -y            Operate in non-interactive mode

Installation schemes:
  home          Install to ~/.local and ~/.config
  opt           Install to /opt, /var/opt, and /etc/opt
EOF

    if [ -n "${_error}" ]
    then
        exit 1
    fi

    exit 0
}

# func <script-file> <artemis-instance-dir>
create_artemis_instance_script() {
    _script_file="${1}"
    _script_name="$(basename "${_script_file}")"
    _artemis_instance_dir="${2}"

    cat > "${_script_file}" <<EOF
#!/bin/sh

export ARTEMIS_INSTANCE=${_artemis_instance_dir}

exec "\${ARTEMIS_INSTANCE}/bin/${_script_name}" "\$@"
EOF

    chmod +x "${1}"
}

main() {
    enable_strict_mode

    if [ -n "${DEBUG:-}" ]
    then
        enable_debug_mode
    fi

    scheme="home"
    interactive=1

    while getopts :hs:vy option
    do
        case "${option}" in
            h)
                usage
                ;;
            s)
                scheme="${OPTARG}"
                ;;
            v)
                VERBOSE=1
                ;;
            y)
                interactive=
                ;;
            *)
                usage "Unknown option: ${OPTARG}"
                ;;
        esac
    done

    # This is required to preserve the Windows drive letter in the
    # path to HOME
    case "$(uname)" in
        CYGWIN*)
            HOME="$(cygpath --mixed --windows "${HOME}")"
            ;;
        *)
            ;;
    esac

    case "${scheme}" in
        home)
            artemis_bin_dir="${HOME}/.local/bin"
            artemis_config_dir="${HOME}/.config/artemis"
            artemis_home_dir="${HOME}/.local/share/artemis"
            artemis_instance_dir="${HOME}/.local/state/artemis"
            ;;
        opt)
            artemis_bin_dir="/opt/artemis/bin"
            artemis_config_dir="/etc/opt/artemis"
            artemis_home_dir="/opt/artemis"
            artemis_instance_dir="/var/opt/artemis"
            ;;
        *)
            usage "Unknown installation scheme: ${scheme}"
            ;;
    esac

    work_dir="${HOME}/artemis-install-script"
    log_file="${work_dir}/install.log"

    mkdir -p "${work_dir}"
    cd "${work_dir}"

    init_logging "${log_file}"

    {
        backup_dir="${work_dir}/backup"

        if [ -e "${backup_dir}" ]
        then
            mv "${backup_dir}" "${backup_dir}.$(date +%Y-%m-%d).$(random_number)"
        fi

        if [ -n "${interactive}" ]
        then
            print_section "Preparing to install"

            print "This script will install ActiveMQ Artemis to the following locations:"
            print
            print "    CLI tools:         ${artemis_bin_dir}"
            print "    Config files:      ${artemis_config_dir}"
            print "    Artemis home:      ${artemis_home_dir}"
            print "    Artemis instance:  ${artemis_instance_dir}"
            print
            print "It will save a backup of any existing installation to:"
            print
            print "    ${backup_dir}"
            print
            print "Run \"install.sh -h\" to see the installation options."
            print

            while true
            do
                print -n "Do you want to proceed? (yes or no): "
                read -r response

                case "${response}" in
                    yes)
                        break
                        ;;
                    no)
                        exit
                        ;;
                    *)
                        ;;
                esac
            done

            print
        fi

        print_section "Checking prerequisites"

        check_writable_directories "${artemis_bin_dir}" \
                                   "$(dirname "${artemis_config_dir}")" \
                                   "$(dirname "${artemis_home_dir}")" \
                                   "$(dirname "${artemis_instance_dir}")"

        check_required_programs awk curl grep gzip java nc ps sed tar

        check_required_program_sha512sum

        check_required_ports 1883 5672 8161 61613 61616

        check_required_network_resources "https://dlcdn.apache.org/" "https://downloads.apache.org/"

        check_java

        print_result "OK"

        print_section "Downloading and verifying the latest release"

        fetch_latest_apache_release "/activemq/activemq-artemis/"

        print_result "OK"

        if [ -e "${artemis_config_dir}" ] || [ -e "${artemis_home_dir}" ] || [ -e "${artemis_instance_dir}" ]
        then
            print_section "Saving the existing installation to a backup"

            save_backup "${backup_dir}" \
                        "${artemis_config_dir}" "${artemis_home_dir}" "${artemis_instance_dir}" \
                        "${artemis_bin_dir}/artemis" "${artemis_bin_dir}/artemis-service"

            print_result "OK"
        fi

        print_section "Installing the broker"

        log "Extracting the release dir from the release archive"

        release_dir="${work_dir}/apache-artemis-${release_version}"

        gzip -dc "${release_file}" | (cd "$(dirname "${release_dir}")" && tar xf -)

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

        log "Creating wrapper scripts"

        mkdir -p "${artemis_bin_dir}"

        rm -f "${artemis_bin_dir}/artemis"
        rm -f "${artemis_bin_dir}/artemis-service"

        create_artemis_instance_script "${artemis_bin_dir}/artemis" "${artemis_instance_dir}"
        create_artemis_instance_script "${artemis_bin_dir}/artemis-service" "${artemis_instance_dir}"

        print_result "OK"

        print_section "Testing the installation"

        log "Testing the artemis command"

        run "${artemis_bin_dir}/artemis" version

        log "Testing the broker"

        run "${artemis_bin_dir}/artemis-service" start

        while port_is_available 61616
        do
            log "Waiting for the broker to start"
            sleep 2
        done

        run "${artemis_bin_dir}/artemis" producer --silent --verbose --message-count 1
        run "${artemis_bin_dir}/artemis" consumer --silent --verbose --message-count 1

        # The 'artemis-service stop' command times out too quickly for
        # CI, so I tolerate a failure here
        run "${artemis_bin_dir}/artemis-service" stop || :

        while ! port_is_available 61616
        do
            log "Waiting for the broker to exit"
            sleep 2
        done

        print_result "OK"

        print_section "Summary"

        print_result "SUCCESS"

        print "ActiveMQ Artemis is now installed."
        print
        print "    Version:                ${release_version}"
        print "    Config files:           ${artemis_config_dir}"
        print "    Log files:              ${artemis_instance_dir}/log"
        print "    Data files:             ${artemis_instance_dir}/data"

        if [ -e "${backup_dir}" ]
        then
            print "    Backup:                 ${backup_dir}"
        fi

        print

        print "The artemis command is available at:"
        print
        print "    ${artemis_bin_dir}/artemis"
        print

        if [ "$(command -v artemis)" != "${artemis_bin_dir}/artemis" ]
        then
            print "$(yellow "NOTE:") The artemis command is not on your path.  To add it, use:"
            print

            if [ "${scheme}" = "home" ]
            then
                print "    export PATH=\"\$HOME/.local/bin:\$PATH\""
            else
                print "    export PATH=\"${artemis_bin_dir}:\$PATH\""
            fi

            print
        fi

        print "If you are learning about Artemis, see the getting started guide:"
        print
        print "    https://github.com/ssorj/persephone/blob/main/getting-started.md"
        print
        print "If you are preparing Artemis for production use, see the deployment guide:"
        print
        print "    https://github.com/ssorj/persephone/blob/main/deployment.md"
        print
        print "To uninstall Artemis, use:"
        print
        print "    curl -f https://github.com/ssorj/persephone/blob/main/uninstall.sh | sh"
        print
        print "To start the broker, use:"
        print
        print "    artemis run"
        print
    } >&4 2>&4
}

main "$@"
