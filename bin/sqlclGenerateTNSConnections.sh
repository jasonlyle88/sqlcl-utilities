#shellcheck shell=bash

function sqlclGenerateTNSConnections() {
    ############################################################################
    #
    # Setup
    #
    ############################################################################
    # For this function, make arrays behave like KSH/BASH
    if command -v setopt 1>/dev/null 2>&1; then
        setopt local_options KSH_ARRAYS
    fi

    ############################################################################
    #
    # Functions
    #
    ############################################################################
    function usage() {
        printf -- 'This script is used to generate SQLcL connections based on TNS aliases\n\n'
        printf -- 'The following arguments are recognized\n\n'
        printf -- '  -b {binary}    --Specify the SQLcl binary to use\n'
        printf -- '  -c {zip}       --Generate SQLcl connections for the provided cloud configuration wallet (zip file)\n'
        printf -- '  -f {folder}    --The folder into which to import connections\n'
        printf -- '                 --Defaults to the TNS source filename\n'
        printf -- '  -h             --Show this help\n'
        printf -- '  -T             --Generate SQLcl connections for the tnsnames.ora file in the standard location\n'
        printf -- '  -r {root}      --The folder root in which to place the generated folder and connections\n'
        printf -- '                 --Defaults to the SQLcl connection root\n'
        printf -- '* -u {user}      --Database user used to setup connections\n'
        printf -- '                 --Can be specified more than once\n'
        printf -- '  -v             --Verbose output\n'
        printf -- '                 --Can be specified once or twice\n'
        printf -- '\n'
        printf -- 'Example:\n'
        printf -- '  %s -c "~/cloud_wallet.zip"\n\n' "${scriptName}"

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
            if [[ "${target}" == /* ]]; then
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

    function standardTnsFileLookup() {
        local tnsnamesName='tnsnames.ora'
        local file

        # Check if the TNS_ADMIN variable is set
        if [[ -n "${TNS_ADMIN}"  ]]; then
            file="${TNS_ADMIN}/${tnsnamesName}"

            if [[ -r "${file}" ]]; then
                printf -- '%s' "${file}"
            else
                printf -- 'No %s readable file at location (%s)\n' "$(basename "${file}")" "$(dirname "${file}")" >&2
                return 1
            fi
        elif [[ -n "${ORACLE_HOME}" ]]; then
            file="${ORACLE_HOME}/network/admin/${tnsnamesName}"

            if [[ -r "${file}" ]]; then
                printf -- '%s' "${file}"
            else
                printf -- 'No %s readable file at location (%s)\n' "$(basename "${file}")" "$(dirname "${file}")" >&2
                return 2
            fi
        else
            printf -- 'No existing TNS_ADMIN or ORACLE_HOME variable, unable to locate standard %s\n' "${tnsnamesName}" >&2
            return 3
        fi
    } #standardTnsFileLookup

    function getNetServiceNamesFromFile() {
        local file="$1"

        # First GREP removes all lines that are comments
        # Second GREP pulls out all parameters
        # Third GREP removes the equals sign from the end of all parameters
        # Fourth GREP removes items that are not net service names
            # First list of items are TNS name file parameters
            # Second list of items are identifiers that can show up in the SSL_SERVER_CERT_DN parameter
        grep -v '^[[:space:]]*#' "${file}" \
        | grep -oe '[^\(\=[:space:]"][^\(\=[:space:]"]*[[:space:]]*=' \
        | grep -oe '[^\=[:space:]]*' \
        | grep -iv \
            \
            -e '^DESCRIPTION$' \
            -e '^ADDRESS$' \
            -e '^ADDRESS_LIST$' \
            -e '^BACKUP$' \
            -e '^COMPRESSION$' \
            -e '^COMPRESSION_LEVELS$' \
            -e '^CONNECT_DATA$' \
            -e '^CONNECT_TIMEOUT$' \
            -e '^DELAY$' \
            -e '^DESCRIPTION$' \
            -e '^DESCRIPTION_LIST$' \
            -e '^ENABLE$' \
            -e '^FAILOVER$' \
            -e '^FAILOVER_MODE$' \
            -e '^GLOBAL_NAME$' \
            -e '^HOST$' \
            -e '^HS$' \
            -e '^IFILE$' \
            -e '^INSTANCE_NAME$' \
            -e '^LEVEL$' \
            -e '^LOAD_BALANCE$' \
            -e '^METHOD$' \
            -e '^PORT$' \
            -e '^PROTOCOL$' \
            -e '^RDB_DATABASE$' \
            -e '^RECV_BUF_SIZE$' \
            -e '^RETRIES$' \
            -e '^RETRY_COUNT$' \
            -e '^RETRY_DELAY$' \
            -e '^SDU$' \
            -e '^SECURITY$' \
            -e '^SEND_BUF_SIZE$' \
            -e '^SERVER$' \
            -e '^SERVICE_NAME$' \
            -e '^SID$' \
            -e '^SOURCE_ROUTE$' \
            -e '^SSL_SERVER_CERT_DN$' \
            -e '^SSL_SERVER_DN_MATCH$' \
            -e '^TRANSACTION$' \
            -e '^TRANSPORT_CONNECT_TIMEOUT$' \
            -e '^TYPE$' \
            -e '^TYPE_OF_SERVICE$'\
            \
            -e '^CN$' \
            -e '^OU$' \
            -e '^O$' \
            -e '^L$' \
            -e '^ST$' \
            -e '^C$'
    } # getNetServiceNamesFromFile

    function getCloudCounfigNetServiceNamesFromZip() {
        local cloudConfigZip="$1"
        local filename
        local extractDir

        filename="$(basename "${cloudConfigZip}").XXXXXXXXXX"
        extractDir="$(mktemp -dt "${filename}")"

        if command -v unzip 1>/dev/null 2>&1; then
            unzip -qq "${cloudConfigZip}" -d "${extractDir}"
        else
            tar -xf "${cloudConfigZip}" -C "${extractDir}"
        fi

        getNetServiceNamesFromFile "${extractDir}/tnsnames.ora"

        rm -rf "${extractDir}"
    } # getCloudCounfigNetServiceNamesFromZip

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

    local bFlag='false'
    local cFlag='false'
    local fFlag='false'
    local TFlag='false'
    local rFlag='false'
    local uFlag='false'

    local sqlclBinary               # -b
    local cloudConfigZip            # -c
    local folderBaseName            # -f
    local tnsFile                   # -T
    local folderBaseRoot            # -r
    local -a userList=()            # -u
    local verboseLevel=0            # -v

    ############################################################################
    ##  Constants
    ############################################################################
    # shellcheck disable=SC2034,SC2155
    local h1="$(printf "%0.s#" {1..80})"
    # shellcheck disable=SC2034,SC2155
    local h2="$(printf "%0.s#" {1..60})"
    # shellcheck disable=SC2034,SC2155
    local h3="$(printf "%0.s#" {1..40})"
    # shellcheck disable=SC2034,SC2155
    local h4="$(printf "%0.s#" {1..20})"
    # shellcheck disable=SC2034,SC2155
    local hs="$(printf "%0.s#" {1..2})"
    # shellcheck disable=SC2034
    local originalPWD="${PWD}"
    # shellcheck disable=SC2034
    local originalIFS="${IFS}"

    ############################################################################
    ##  Procedural variables
    ############################################################################
    local folderRoot
    local tnsFileCount
    local netServiceName
    local connectionsFile
    local sqlFile
    local user
    local folderName
    local connectionName
    local stdOutTarget
    local stdErrTarget

    ############################################################################
    #
    # Option parsing
    #
    ############################################################################
    while getopts ':b:c:f:hTr:u:v' opt
    do
        case "${opt}" in
        'b')
            bFlag='true'
            sqlclBinary="${OPTARG}"
            ;;
        'c')
            cFlag='true'
            cloudConfigZip="${OPTARG}"
            ;;
        'f')
            fFlag='true'
            folderBaseName="${OPTARG}"
            ;;
        'h')
            usage
            return 0
            ;;
        'T')
            TFlag='true'
            if ! tnsFile="$(standardTnsFileLookup)"; then
                return 2
            fi
            ;;
        'r')
            rFlag='true'
            folderBaseRoot="${OPTARG}"
            ;;
        'u')
            uFlag='true'
            userList+=("${OPTARG}")
            ;;
        'v')
            ((verboseLevel=verboseLevel+1))
            ;;
        '?')
            printf 'ERROR: Invalid option -%s\n\n' "${OPTARG}" >&2
            usage >&2
            return 1
            ;;
        ':')
            printf 'ERROR: Option -%s requires an argument.\n' "${OPTARG}" >&2
            return 1
            ;;
        esac
    done

    ############################################################################
    #
    # Parameter handling
    #
    ############################################################################

    #
    # Parameter defaults
    #

    if [[ "${bFlag}" != 'true' ]]; then
        sqlclBinary='sql'
    fi

    if [[ "${fFlag}" != 'true' ]]; then
        folderBaseName="$(basename "${tnsFile%.*}${cloudConfigZip%.*}")"
    fi

    #
    # Parameter validations
    #

    # Check SQLcl binary is executable
    if [[ ! "$(command -v "${sqlclBinary}")" ]]; then
        printf 'Cannot execute SQLcl binary "%s"\n' "${sqlclBinary}" >&2
        return 12
    fi

    # Count the number of TNS file types provided
    tnsFileCount=0
    if [[ "${cFlag}" == 'true' ]]; then
        ((tnsFileCount=tnsFileCount+1))
    fi;

    if [[ "${TFlag}" == 'true' ]]; then
        ((tnsFileCount=tnsFileCount+1))
    fi;

    # Check at least one version of TNS alias files are supplied
    if [[ "${tnsFileCount}" -eq 0 ]]; then
        printf -- "At least one TNS alias file must be specified\n" >&2
        return 13
    fi;

    # Check only one version of TNS aliases is supplied
    if [[ "${tnsFileCount}" -gt 1 ]]; then
        printf -- "Only one TNS alias file can be specified\n" >&2
        return 14
    fi;

    # Check TNS file or cloud config zip file is readable
    if [[ ! -r "${tnsFile}${cloudConfigZip}" ]]; then
        printf 'Not a readable file: "%s"\n' "${tnsFile}${cloudConfigZip}" >&2
        return 15
    fi

    # Check for requried -u parameter
    if [[ "${uFlag}" != 'true' ]]; then
        printf -- 'ERROR: At least one database user (-u) must be specified.\n' >&2
        return 16
    fi

    ##############################################################################
    #
    # Function Logic
    #
    ##############################################################################
    if [[ "${rFlag}" == 'true' ]]; then
        folderRoot="${folderBaseRoot}/${folderBaseName}"
    else
        folderRoot="${folderBaseName}"
    fi

    printf -- '%s\n' "${h1}"
    printf -- '%s %-32s: "%s"\n' "${hs}" "SQLcl Binary" "${sqlclBinary}"
    printf -- '%s %-32s: "%s"\n' "${hs}" "TNS Source" "${tnsFile}${cloudConfigZip}"
    printf -- '%s %-32s: "%s"\n' "${hs}" "Root Folder" "${folderRoot}"
    printf -- '%s\n' "${h1}"
    printf -- '\n'

    if [[ "${verboseLevel}" -eq 0 ]]; then
        stdOutTarget='/dev/null'
        stdErrTarget='/dev/null'
    else
        stdOutTarget='/dev/fd/1'
        stdErrTarget='/dev/fd/2'
    fi

    printf -- '\n'
    printf -- '%s\n' "${h2}"
    printf -- '%s %s\n' "${hs}" "Generate SQLcl files"
    printf -- '%s\n' "${h2}"

    connectionsFile="$(mktemp)"
    mv "${connectionsFile}" "${connectionsFile}.json"
    connectionsFile="${connectionsFile}.json"
    connectionsFiles+=("${connectionsFile}")

    sqlFile="$(mktemp)"
    mv "${sqlFile}" "${sqlFile}.sql"
    sqlFile="${sqlFile}.sql"
    sqlFiles+=("${sqlFile}")

    {
        printf -- '{\n'
        printf -- '    "connections": [\n'
        printf -- '        {}\n' # Dummy object so all real object can have a comma before them for easier formatting
    } > "${connectionsFile}"

    {
        printf -- 'cm delete -force -folder "%s"\n' "${folderRoot}"
        printf -- 'cm import %s\n' "${connectionsFile}"
        printf -- 'cm add -folder "%s"\n' "${folderRoot}"
    } > "${sqlFile}"

    # Process TNS file
    if [[ "${TFlag}" == 'true' ]]; then
        while read -r netServiceName; do
            folderName="${folderRoot}/${netServiceName}"

            printf -- 'cm add -folder "%s"\n' "${folderName}" >> "${sqlFile}"

            for user in "${userList[@]}"; do

                connectionName="${user}@${netServiceName}"

                {
                    printf -- '        ,{\n'
                    printf -- '            "info": {\n'
                    printf -- '                "OracleConnectionType": "TNS",\n'
                    printf -- '                "oraDriverType": "thin",\n'
                    printf -- '                "subtype": "oraJDBC",\n'
                    printf -- '                "customUrl": "%s",\n' "${netServiceName}"
                    printf -- '                "user": "%s"\n' "${user}"
                    printf -- '            },\n'
                    printf -- '            "name": "%s",\n' "${connectionName}"
                    printf -- '            "type": "jdbc"\n'
                    printf -- '        }\n'
                } >> "${connectionsFile}"

                printf -- 'cm move -conn "%s" "%s"\n' "${connectionName}" "${folderName}" >> "${sqlFile}"
            done
        done <<< "$(getNetServiceNamesFromFile "${tnsFile}")"
    fi

    # Process cloud configs
    if [[ "${cFlag}" == 'true' ]]; then
        while read -r netServiceName; do
            folderName="${folderRoot}/${netServiceName}"

            printf -- 'cm add -folder "%s"\n' "${folderName}" >> "${sqlFile}"

            for user in "${userList[@]}"; do

                connectionName="${user}@${netServiceName}"

                {
                    printf -- '        ,{\n'
                    printf -- '            "info": {\n'
                    printf -- '                "OracleConnectionType": "CLOUD",\n'
                    printf -- '                "oraDriverType": "thin",\n'
                    printf -- '                "subtype": "oraJDBC",\n'
                    printf -- '                "sqldev.cloud.configfile": "%s",\n' "${cloudConfigZip}"
                    printf -- '                "customUrl": "%s",\n' "$(toUpperCase "${netServiceName}")"
                    printf -- '                "user": "%s"\n' "${user}"
                    printf -- '            },\n'
                    printf -- '            "name": "%s",\n' "${connectionName}"
                    printf -- '            "type": "jdbc"\n'
                    printf -- '        }\n'
                } >> "${connectionsFile}"

                printf -- 'cm move -conn "%s" "%s"\n' "${connectionName}" "${folderName}" >> "${sqlFile}"
            done
        done <<< "$(getCloudCounfigNetServiceNamesFromZip "${cloudConfigZip}")"
    fi

    {
        printf -- '    ]\n'
        printf -- '}\n'
    } >> "${connectionsFile}"

    printf -- 'exit' >> "${sqlFile}"

    if [[ "${verboseLevel}" -ge 2 ]]; then
        printf -- '\n'
        printf -- '%s\n' "${h3}"
        printf -- '%s %s\n' "${hs}" "Connections file"
        printf -- '%s\n' "${h3}"
        cat "${connectionsFile}"

        printf -- '\n'
        printf -- '%s\n' "${h3}"
        printf -- '%s %s\n' "${hs}" "SQL file"
        printf -- '%s\n' "${h3}"
        cat "${sqlFile}"
    fi

    printf -- '\n'
    printf -- 'Complete\n'

    printf -- '\n'
    printf -- '%s\n' "${h2}"
    printf -- '%s %s\n' "${hs}" "Load connections and organize them"
    printf -- '%s\n' "${h2}"

    if [[ "${verboseLevel}" -gt 0 ]]; then
        printf -- '\n'
    fi
    SQLPATH="" "${sqlclBinary}" -S -nolog -noupdates -nohistory @"${sqlFile}" 1>"${stdOutTarget}" 2>"${stdErrTarget}"

    printf -- '\n'
    printf -- 'Complete\n'

    return 0
} # sqlclGenerateTNSConnections
