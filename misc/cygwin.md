        log "Patching problem 1"

        # This bit of the Artemis instance script uses a cygpath --unix,
        # cygpath --windows sequence that ends up stripping out the drive
        # letter and replacing it with whatever the current drive is. If your
        # current drive is different from the Artemis install drive, trouble.
        #
        # For the bug: Annotate the current code.  Suggest --absolute.

        # XXX Try patching for --absolute instead

        sed -i.backup2 -e "77,82d" "${artemis_instance_dir}/bin/artemis"
