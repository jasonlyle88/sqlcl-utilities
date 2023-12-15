#shellcheck shell=bash

function sqlclUpdater() {
    ############################################################################
    #
    # Functions
    #
    ############################################################################
    function usage() {
        printf -- 'This script is used to install/update Oracle SQLcl\n'
        printf -- '\n'
        printf -- 'This script installs or updates Oracle SQLcl in a given directory.\n'
        printf -- 'It also creates/updates a symlink called "latest" to point to the\n'
        printf -- 'most recently downloaded version of Oracle SQLcl.\n'
        printf -- 'This script does not alter your PATH, you must do that manually.\n'
        printf -- '\n'
        printf -- 'The following arguments are recognized (* = required)\n'
        printf -- '\n'
        printf -- '  -d {dir}   --  Sets the directory into which SQLcl should be installed.\n'
        printf -- '                 Defaults to "/opt/sqlcl"\n'
        printf -- '  -k {num}   --  Sets the number of SQLcl versions to keep. Must be >=1.\n'
        printf -- '                 All versions are kept if this is not specified.\n'
        printf -- '  -l         --  Creates/updates a symbolic link called "live" that points\n'
        printf -- '                 to the most recent version of Oracle SQLcl.\n'
        printf -- '  -q         --  Quiet, only output errors.\n'
        printf -- '  -h         --  Show this help.\n'
        printf -- '\n'
        printf -- 'Example:\n'
        # shellcheck disable=2016
        printf -- '  %s -sld "$HOME/sqlcl" -k 3\n' "${scriptName}"
        printf -- '\n'

        return 0
    } # usage

    function toUpperCase() {
        ########################################################################
        #   toUpperCase
        #
        #   Return a string with all upper case letters
        #
        #   All parameters are taken as a single string to get in all upper case
        #
        #   upperCaseVar="$(toUpperCase "${var}")"
        ########################################################################
        local string="$*"

        printf -- '%s' "${string}" | tr '[:lower:]' '[:upper:]'

        return 0
    } # toUpperCase

    function toLowerCase() {
        ########################################################################
        #   toLowerCase
        #
        #   Return a string with all lower case letters
        #
        #   All parameters are taken as a single string to get in all lower case
        #
        #   toLowerCase="$(toLowerCase "${var}")"
        ########################################################################
        local string="${*}"

        printf -- '%s' "${string}" | tr '[:upper:]' '[:lower:]'

        return 0
    } # toLowerCase

    function getCanonicalPath() {
        ########################################################################
        #   getCanonicalPath
        #
        #   Return a path that is both absolute and does not contain any
        #   symbolic links. Always returns without a trailing slash.
        #
        #   The first parameter is the path to canonicalize
        #
        #   canonicalPath="$(getCanonicalPath "${somePath}")"
        ########################################################################
        local target="${1}"

        if [ -d "${target}" ]; then
            # dir
            (cd "${target}" || exit; pwd -P)
        elif [ -f "${target}" ]; then
            # file
            if [[ "${target}" = /* ]]; then
                # Absolute file path
                (cd "$(dirname "${target}")" || exit; printf -- '%s/%s\n' "$(pwd -P)" "$(basename "${target}")")
            elif [[ "${target}" == */* ]]; then
                # Relative file with path
                printf -- '%s\n' "$(cd "${target%/*}" || exit; pwd -P)/${target##*/}"
            else
                # Relative file without path
                printf -- '%s\n' "$(pwd -P)/${target}"
            fi
        fi
    } # getCanonicalPath

    function printVerbose() {
        local silentFlag="${1}"

        shift

        if [[ "${silentFlag}" == "false" ]]; then
            # shellcheck disable=2059
            printf -- "$@"
        fi
    } # printVerbose

    ############################################################################
    #
    # Variables
    #
    ############################################################################

    ############################################################################
    ##  Configurable variables
    ############################################################################

    ############################################################################
    ##  Script info
    ############################################################################
    local scriptBase
    local scriptName
    local scriptPath

    # BASH and ZSH safe method for obtaining the current script
    # shellcheck disable=SC2296
    scriptBase="${BASH_SOURCE[0]:-${(%):-%x}}"
    # shellcheck disable=SC2034
    scriptName="$(basename -- "${scriptBase}" '.sh')"
    # shellcheck disable=SC2034
    scriptPath="$(getCanonicalPath "$(dirname -- "${scriptBase}")")"

    ############################################################################
    ##  Parameter variables
    ############################################################################
    local OPTIND
    local OPTARG
    local opt

    local dFlag='false'
    local kFlag='false'
    local lFlag='false'
    local qFlag='false'

    local localDirectory
    local keepNumVersions

    ############################################################################
    ##  Constants
    ############################################################################
    # shellcheck disable=SC2034,SC2155
    local h1="$(printf "%0.s-" {1..80})"
    # shellcheck disable=SC2034,SC2155
    local h2="$(printf "%0.s-" {1..60})"
    # shellcheck disable=SC2034,SC2155
    local h3="$(printf "%0.s-" {1..40})"
    # shellcheck disable=SC2034,SC2155
    local h4="$(printf "%0.s-" {1..20})"
    # shellcheck disable=SC2034,SC2155
    local hs="$(printf "%0.s-" {1..2})"
    # shellcheck disable=SC2034
    local originalPWD="${PWD}"
    # shellcheck disable=SC2034
    local originalIFS="${IFS}"

    local integerRegularExpression='^[0-9]+$'
    local defaultLocalDirectory="/opt/sqlcl"
    local remoteUrl="https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip"
    local zipFilename="sqlcl-latest.zip"
    local unzippedFolder="sqlcl"
    local etagFilename="sqlcl.etag"

    ############################################################################
    ##  Procedural variables
    ############################################################################
    local rawEtag
    local sqlclEtag
    local localEtag
    local newVersionNumber
    local idx

    ############################################################################
    #
    # Option parsing
    #
    ############################################################################
    while getopts ':d:k:lqh' opt
    do

        case "${opt}" in
        'd')
            dFlag='true'
            localDirectory="${OPTARG}"
            ;;
        'k')
            kFlag='true'
            keepNumVersions="${OPTARG}"
            ;;
        'l')
            lFlag='true'
            ;;
        'q')
            qFlag='true'
            ;;
        'h')
            usage
            return $?
            ;;
        '?')
            printf -- 'ERROR: Invalid option -%s\n\n' "${OPTARG}" >&2
            usage >&2
            return 3
            ;;
        ':')
            printf -- 'ERROR: Option -%s requires an argument.\n' "${OPTARG}" >&2
            return 4
            ;;
        esac

    done

    ############################################################################
    #
    # Parameter handling
    #
    ############################################################################
    if [[ "${dFlag}" == 'false' ]]; then
        localDirectory="${defaultLocalDirectory}"
    fi

    if [[ "${kFlag}" == 'true' ]]; then
        if ! [[ "${keepNumVersions}" =~ ${integerRegularExpression} ]]; then
            printf -- 'ERROR: Argument to -k must be an positive integer.\n' >&2
            return 4
        fi

        if [[ "${keepNumVersions}" -lt 1 ]]; then
            printf -- 'ERROR: Argument to -k must be >=1\n' >&2
            return 5
        fi
    else
        keepNumVersions=-1
    fi

    ############################################################################
    #
    # Function Logic
    #
    ############################################################################
    # Ensure localDirectory exists
    if [[ ! -d "${localDirectory}" ]]; then
        if ! mkdir -p "${localDirectory}"; then
            printf -- 'ERROR: Cannot create specified directory "%s"\n' "${localDirectory}" >&2
            return 6
        fi
    fi

    # Get the raw ETag for the remote sqlcl
    printVerbose "${qFlag}" 'Getting server ETag....\n'
    if ! rawEtag=$(curl -Isf "${remoteUrl}"); then
        printf -- 'ERROR: Unable to download ETag information\n' >&2
        return 7
    fi

    # Remove any carriage returns in headers
    rawEtag="$(printf '%s' "${rawEtag}" | tr -d '\r')"

    # Get the actual ETag value for SQLcl
    if ! sqlclEtag="$(printf '%s' "${rawEtag}" | sed -En 's/^ETag: (.*)/\1/p')"; then
        printf -- 'ERROR: Unable to parse ETag information\n' >&2
        return 8
    fi

    # Get the ETag for the local sqlcl
    if [[ -e "${localDirectory}/${etagFilename}" ]]; then
        localEtag=$(cat "${localDirectory}/${etagFilename}")
    else
        localEtag="none"
    fi

    # Check if ETags match
    if [[ "${sqlclEtag}" == "${localEtag}" ]]; then
        printVerbose "${qFlag}" 'SQLcl is current\n'
    else
        # Download sqlcl zip file and save the newest Etag
        printVerbose "${qFlag}" 'Downloading....\n'
        if ! curl -sS -f \
            -o "${localDirectory}/${zipFilename}" \
            "${remoteUrl}" 2>/dev/null
        then
            printf -- 'ERROR: Unable to download new version\n' >&2
            return 9
        fi

        # Save the ETag for future reference
        # NOTE: not using etag options of curl as they version is not widely available
        printf -- '%s\n' "${sqlclEtag}" > "${localDirectory}/${etagFilename}"

        # Unzip sqlcl zip file
        printVerbose "${qFlag}" 'Unzipping %s/%s....\n' "${localDirectory}" "${zipFilename}"
        unzip -qq -d "${localDirectory}" "${localDirectory}/${zipFilename}"

        # Remove the zip file since it has been unzipped
        printVerbose "${qFlag}" 'Remove ZIP file....\n'
        rm -rf "${localDirectory:?}/${zipFilename:?}"

        # Get the sqlcl version number from the unzipped directory
        printVerbose "${qFlag}" 'Getting version number...\n'
        newVersionNumber=$(find "${localDirectory}/${unzippedFolder}" -maxdepth 1 -type f | awk -F/ '{print $NF}' | grep -E '^([0-9]+\.)+[0-9]+$')

        # Move the unzipped directory to a folder named as the sqlcl version number
        printVerbose "${qFlag}" 'Moving unzipped directory to version number directory....\n'
        mv "${localDirectory}/${unzippedFolder}" "${localDirectory}/${newVersionNumber}"

        # Update the latest symlink
        printVerbose "${qFlag}" 'Update latest symlink....\n'
        ln -sfn "${newVersionNumber}" "${localDirectory}/latest"

        # Conditionally update the live symlink
        if [[ "${lFlag}" = 'true' ]]; then
            printVerbose "${qFlag}" 'Update live symlink....\n'
            ln -sfn "${newVersionNumber}" "${localDirectory}/live"
        fi

        # Conditionally only keep the the previous N versions of sqlcl
        if [[ "${keepNumVersions}" -ge "1" ]]; then
            idx=0
            find "${localDirectory}" -mindepth 1 -maxdepth 1 -type d | awk -F/ '{print $NF}' | grep -E '^([0-9]+\.)+[0-9]+$' | sort --reverse --version-sort | while read -r versionDirectory; do
                ((idx++))
                if [ "${idx}" -le "${keepNumVersions}" ]; then
                    continue
                fi

                printVerbose "${qFlag}" 'Remove version %s\n' "${versionDirectory}"
                rm -rf "${localDirectory:?}/${versionDirectory:?}"
            done
        fi

        printVerbose "${qFlag}" 'Done\n'
    fi

    return 0
} # main
