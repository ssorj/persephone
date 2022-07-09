# Make the local keyword work with ksh93 and POSIX-style functions
case "${KSH_VERSION:-}" in
    *" 93"*)
        alias local="typeset -x"
        ;;
    *)
        ;;
esac

# Make zsh emulate the Bourne shell
if [ -n "${ZSH_VERSION:-}" ]
then
    emulate sh
fi

# This is required to preserve the Windows drive letter in the
# path to HOME.
case "$(uname)" in
    CYGWIN*)
        HOME="$(cygpath --mixed --windows "${HOME}")"
        ;;
    *)
        ;;
esac

# func <program>
program_is_available() {
    local program="${1}"

    assert test -n "${program}"

    command -v "${program}"
}

# func <port>
port_is_active() {
    local port="$1"

    assert program_is_available nc

    if nc -z localhost "${port}"
    then
        printf "Port %s is active\n" "${port}"
        return 0
    else
        printf "Port %s is free\n" "${port}"
        return 1
    fi
}

# func <port>
await_port_is_active() {
    local port="$1"
    local i=0

    log "Waiting for port ${port} to open"

    while ! port_is_active 61616
    do
        i=$((i + 1))

        if [ "${i}" = 30 ]
        then
            log "Timed out waiting for port ${port} to open"
            return 1
        fi

        sleep 2
    done
}

# func <port>
await_port_is_free() {
    local port="$1"
    local i=0

    log "Waiting for port ${port} to close"

    while port_is_active 61616
    do
        i=$((i + 1))

        if [ "${i}" = 30 ]
        then
            log "Timed out waiting for port ${port} to close"
            return 1
        fi

        sleep 2
    done
}

# func <string> <glob>
string_is_match() {
    local string="$1"
    local glob="$2"

    assert test -n "${glob}"

    # shellcheck disable=SC2254 # We want the glob
    case "${string}" in
        ${glob})
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

random_number() {
    printf "%s%s" "$(date +%s)" "$$"
}

# func <archive-file> <output-dir>
extract_archive() {
    local archive_file="$1"
    local output_dir="$2"

    assert test -f "${archive_file}"
    assert test -d "${output_dir}"
    assert program_is_available gzip
    assert program_is_available tar

    gzip -dc "${archive_file}" | (cd "${output_dir}" && tar xf -)
}

assert() {
    local location="$0:"

    # shellcheck disable=SC2128 # We want only the first element of the array
    if [ -n "${BASH_LINENO:-}" ]
    then
        location="$0:${BASH_LINENO}:"
    fi

    if ! "$@" > /dev/null 2>&1
    then
        printf "%s %s assert %s\n" "$(red "ASSERTION FAILED:")" "$(yellow "${location}")" "$*" >&2
        exit 1
    fi
}

log() {
    printf -- "-- %s\n" "$1"
}

run() {
    printf -- "-- Running '%s'\n" "$*" >&2
    "$@"
}

bold() {
    printf "\033[1m%s\033[0m" "$1"
}

red() {
    printf "\033[1;31m%s\033[0m" "$1"
}

green() {
    printf "\033[0;32m%s\033[0m" "$1"
}

yellow() {
    printf "\033[0;33m%s\033[0m" "$1"
}

print() {
    if [ "$#" = 0 ]
    then
        printf "\n" >&3
        printf -- "--\n"
        return
    fi

    if [ "$1" = "-n" ]
    then
        shift

        printf "   %s" "$1" >&3
        printf -- "-- %s" "$1"
    else
        printf "   %s\n" "$1" >&3
        printf -- "-- %s\n" "$1"
    fi
}

print_section() {
    printf "== %s ==\n\n" "$(bold "$1")" >&3
    printf "== %s\n" "$1"
}

print_result() {
    printf "   %s\n\n" "$(green "$1")" >&3
    log "Result: $(green "$1")"
}

fail() {
    printf "   %s %s\n\n" "$(red "ERROR:")" "$1" >&3
    log "$(red "ERROR:") $1"

    if [ -n "${2:-}" ]
    then
        printf "   See %s\n\n" "$2" >&3
        log "See $2"
    fi

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

        assert test -n "${POSIXLY_CORRECT}"
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
    # This must go first
    local exit_code=$?

    local log_file="$1"
    local verbose="$2"

    # Restore stdout and stderr
    exec 1>&7
    exec 2>&8

    # shellcheck disable=SC2181 # This is intentionally indirect
    if [ "${exit_code}" != 0 ] && [ -z "${suppress_trouble_report:-}" ]
    then
        if [ -n "${verbose}" ]
        then
            printf "%s Something went wrong.\n\n" "$(red "TROUBLE!")"
        else
            printf "   %s Something went wrong.\n\n" "$(red "TROUBLE!")"
            printf "== Log ==\n\n"

            sed -e "s/^/  /" < "${log_file}" || :

            printf "\n"
        fi
    fi
}

# func <log-file> <verbose>
init_logging() {
    local log_file="$1"
    local verbose="$2"

    # shellcheck disable=SC2064 # We want to expand these now, not later
    trap "handle_exit '${log_file}' '${verbose}'" EXIT

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
    if [ -n "${verbose}" ]
    then
        exec 3> /dev/null
    else
        exec 4> "${log_file}"
    fi
}

# func [<dir>...]
check_writable_directories() {
    log "Checking for permission to write to the install directories"

    local dirs="$*"
    local dir=
    local base_dir=
    local unwritable_dirs=

    for dir in ${dirs}
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
            unwritable_dirs="${unwritable_dirs}${base_dir}, "
        fi
    done

    if [ -n "${unwritable_dirs}" ]
    then
        fail "Some install directories are not writable: ${unwritable_dirs%??}" \
             "https://github.com/ssorj/persephone/blob/main/docs/troubleshooting.md#some-install-directories-are-not-writable"
    fi
}

# func [<program>...]
check_required_programs() {
    log "Checking for required programs"

    local programs="$*"
    local program=
    local unavailable_programs=

    for program in ${programs}
    do
        log "Checking program '${program}'"

        if ! command -v "${program}"
        then
            unavailable_programs="${unavailable_programs}${program}, "
        fi
    done

    if [ -n "${unavailable_programs}" ]
    then
        fail "Some required programs are not available: ${unavailable_programs%??}" \
             "https://github.com/ssorj/persephone/blob/main/docs/troubleshooting.md#some-required-programs-are-not-available"
    fi
}

check_required_program_sha512sum() {
    log "Checking for either 'sha512sum' or 'shasum'"

    if ! command -v sha512sum && ! command -v shasum
    then
        fail "Some required programs are not available: sha512sum or shasum" \
             "https://github.com/ssorj/persephone/blob/main/docs/troubleshooting.md#some-required-programs-are-not-available"
    fi
}

# func [<port>...]
check_required_ports() {
    log "Checking for required ports"

    local ports="$*"
    local port=
    local unavailable_ports=

    for port in ${ports}
    do
        log "Checking port ${port}"

        if port_is_active "${port}"
        then
            unavailable_ports="${unavailable_ports}${port}, "
        fi
    done

    if [ -n "${unavailable_ports}" ]
    then
        fail "Some required ports are in use by something else: ${unavailable_ports%??}" \
             "https://github.com/ssorj/persephone/blob/main/docs/troubleshooting.md#some-required-ports-are-in-use-by-something-else"
    fi
}

# func [<url>...]
check_required_network_resources() {
    log "Checking for required network resources"

    local urls="$*"
    local url=
    local unavailable_urls=

    assert program_is_available curl

    for url in ${urls}
    do
        log "Checking URL '${url}'"

        if ! curl -sf --show-error --head "${url}"
        then
            unavailable_urls="${unavailable_urls}${url}, "
        fi
    done

    if [ -n "${unavailable_urls}" ]
    then
        fail "Some required network resources are not available: ${unavailable_urls%??}" \
             "https://github.com/ssorj/persephone/blob/main/docs/troubleshooting.md#some-required-network-resources-are-not-available"
    fi
}

check_java() {
    log "Checking the Java installation"

    if ! java --version
    then
        fail "Java is available, but it is not working" \
             "https://github.com/ssorj/persephone/blob/main/docs/troubleshooting.md#java-is-available-but-it-is-not-working"
    fi
}

# func <url-path> <output-dir> -> release_version=<version>, release_file=<file>
fetch_latest_apache_release() {
    local url_path="$1"
    local output_dir="$2"

    assert string_is_match "${url_path}" "/*/"
    assert test -d "${output_dir}"
    assert program_is_available curl
    assert program_is_available awk
    assert program_is_available sort
    assert program_is_available tail
    program_is_available sha512sum || program_is_available shasum || assert false

    local release_version_file="${output_dir}/release-version.txt"

    log "Looking up the latest release version"

    run curl -sf --show-error "https://dlcdn.apache.org${url_path}" \
        | awk 'match($0, /[0-9]+\.[0-9]+\.[0-9]+/) { print substr($0, RSTART, RLENGTH) }' \
        | sort -t . -k1n -k2n -k3n \
        | tail -n 1 >| "${release_version_file}"

    release_version="$(cat "${release_version_file}")"

    printf "Release version: %s\n" "${release_version}"
    printf "Release version file: %s\n" "${release_version_file}"

    local release_file_name="apache-artemis-${release_version}-bin.tar.gz"
    release_file="${output_dir}/${release_file_name}"
    local release_file_checksum="${release_file}.sha512"

    if [ ! -e "${release_file}" ]
    then
        log "Downloading the latest release"

        run curl -sf --show-error -o "${release_file}" \
            "https://dlcdn.apache.org/activemq/activemq-artemis/${release_version}/${release_file_name}"
    else
        log "Using the cached release archive"
    fi

    printf "Archive file: %s\n" "${release_file}"

    log "Downloading the checksum file"

    run curl -sf --show-error -o "${release_file_checksum}" \
        "https://downloads.apache.org/activemq/activemq-artemis/${release_version}/${release_file_name}.sha512"

    printf "Checksum file: %s\n" "${release_file_checksum}"

    log "Verifying the release archive"

    if command -v sha512sum
    then
        if ! run sha512sum -c "${release_file_checksum}"
        then
            fail "The checksum does not match the downloaded release archive" \
                 "https://github.com/ssorj/persephone/blob/main/docs/troubleshooting.md#the-checksum-does-not-match-the-downloaded-release-archive"
        fi
    elif command -v shasum
    then
        if ! run shasum -a 512 -c "${release_file_checksum}"
        then
            fail "The checksum does not match the downloaded release archive" \
                 "https://github.com/ssorj/persephone/blob/main/docs/troubleshooting.md#the-checksum-does-not-match-the-downloaded-release-archive"
        fi
    else
        assert false
    fi

    assert test -n "${release_version}"
    assert test -f "${release_file}"
}

# func <backup-dir> <config-dir> <share-dir> <state-dir> [<bin-file>...]
save_backup() {
    local backup_dir="$1"
    local config_dir="$2"
    local share_dir="$3"
    local state_dir="$4"

    shift 4

    local bin_files="$*"
    local bin_file=

    log "Saving the previous config dir"

    if [ -e "${config_dir}" ]
    then
        mkdir -p "${backup_dir}/config"
        mv "${config_dir}" "${backup_dir}/config"
    fi

    log "Saving the previous share dir"

    if [ -e "${share_dir}" ]
    then
        mkdir -p "${backup_dir}/share"
        mv "${share_dir}" "${backup_dir}/share"
    fi

    log "Saving the previous state dir"

    if [ -e "${state_dir}" ]
    then
        mkdir -p "${backup_dir}/state"
        mv "${state_dir}" "${backup_dir}/state"
    fi

    for bin_file in ${bin_files}
    do
        if [ -e "${bin_file}" ]
        then
            mkdir -p "${backup_dir}/bin"
            mv "${bin_file}" "${backup_dir}/bin"
        fi
    done

    assert test -d "${backup_dir}"
}

generate_password() {
    assert test -e /dev/urandom
    assert program_is_available head
    assert program_is_available tr

    head -c 1024 /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 16
}
