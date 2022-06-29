# if lsof -PiTCP -sTCP:LISTEN | grep ":${1}"
# if netstat -an | grep LISTEN | grep ":${1}"

# func <file> <line-number> <lines>...
file_append_lines_at() {
    file="${1}"

    shift

    script="${1}a\\
"

    shift

    for arg in "$@"
    do
        script="${script}${arg}\\
"
    done

    run sed -i.backup -e "${script%??}" "${file}"

    rm "${file}.backup"
}
