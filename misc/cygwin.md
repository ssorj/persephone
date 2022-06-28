        log "Patching problem 1"

        # This bit of the Artemis instance script uses a cygpath --unix,
        # cygpath --windows sequence that ends up stripping out the drive
        # letter and replacing it with whatever the current drive is. If your
        # current drive is different from the Artemis install drive, trouble.
        #
        # For the bug: Annotate the current code.  Suggest --absolute.

        # XXX Try patching for --absolute instead

        sed -i.backup2 -e "77,82d" "${artemis_instance_dir}/bin/artemis"

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
