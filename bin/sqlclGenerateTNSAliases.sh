#shellcheck shell=bash

# TODO2: Add call generation information to header like OID Aliases

# TODO3: Add name generation function like in OID Aliases (-f)

# TODO4: Add an alias generation funciton like in OID Aliases (-a)

function sqlclGenerateTNSAliases() {
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
        printf -- 'This script is used to generate SQLcL aliases based on TNS aliases\n\n'
        printf -- 'The following arguments are recognized\n\n'
        printf -- '  -b {binary}  --Specify the SQLcl binary to use\n'
        printf -- '  -c {zip}     --Generate shell aliases for the provided cloud configuration wallet (zip file)\n'
        printf -- '  -h           --Show this help\n'
        printf -- '  -p {prefix}  --Prefix used for generated aliases\n'
        printf -- '               --Defaults to "sql."\n'
        printf -- '  -t {file}    --Generate shell aliases for the provided TNS names file\n'
        printf -- '               --Should be a valid tnsnames.ora file\n'
        printf -- '  -T           --Generate shell aliases for the tnsnames.ora file in the standard location\n'
        printf -- '\n'
        printf -- 'Example:\n'
        printf -- '  %s -T -t "~/tnsnames.ora" -c "~/cloud_wallet_1.zip" -c "~/cloud_wallet_2.zip"\n\n' "${scriptName}"

        return 0
    } # usage

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
    local pFlag='false'
    local tFlag='false'
    local TFlag='false'

    local sqlclBinary               # -b
    local cloudConfigZip            # -c
    local aliasPrefix               # -p
    local tnsFile                   # -t

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
    local tnsFileCount
    local file

    ############################################################################
    #
    # Option parsing
    #
    ############################################################################
    while getopts ':b:c:hp:t:T' opt
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
        'h')
            usage
            return 0
            ;;
        'p')
            pFlag='true'
            aliasPrefix="${OPTARG}"
            ;;
        't')
            tFlag='true'
            tnsFile="${OPTARG}"
            ;;
        'T')
            TFlag='true'
            if ! tnsFile="$(standardTnsFileLookup)"; then
                return 2
            fi
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
    if [[ "${pFlag}" == 'false' ]]; then
        aliasPrefix='sql.'
    fi

    #
    # Parameter validations
    #

    # Check SQLcl binary is executable
    if [[ "${bFlag}" == 'true' ]] && [[ ! "$(command -v "${sqlclBinary}")" ]]; then
        printf 'Cannot execute SQLcl binary "%s"\n' "${sqlclBinary}" >&2
        return 11
    fi

    tnsFileCount=0
    if [[ "${cFlag}" == 'true' ]]; then
        ((tnsFileCount=tnsFileCount+1))
    fi;

    if [[ "${tFlag}" == 'true' ]]; then
        ((tnsFileCount=tnsFileCount+1))
    fi;


    if [[ "${TFlag}" == 'true' ]]; then
        ((tnsFileCount=tnsFileCount+1))
    fi;

    # Check at least some version of TNS aliases is supplied
    if [[ "${tnsFileCount}" -eq 0 ]]; then
        printf -- "At least one TNS alias file must be specified\n" >&2
        return 12
    fi;

    # Check at only one version of TNS aliases is supplied
    if [[ "${tnsFileCount}" -gt 1 ]]; then
        printf -- "Only one TNS alias file can be specified\n" >&2
        return 13
    fi;

    # Check TNS file or cloud config zip file is readable
    if [[ ! -r "${tnsFile}${cloudConfigZip}" ]]; then
        printf 'Not a readable file: "%s"\n' "${tnsFile}${cloudConfigZip}" >&2
        return 14
    fi

    ##############################################################################
    #
    # Function Logic
    #
    ##############################################################################
    printf -- '# shellcheck shell=bash\n'
    printf -- '\n'
    printf -- '%s\n' "${h1}"
    printf -- '%s This file generated by %s\n' "${hs}" "${scriptName}"
    printf -- '%s\n' "${h1}"
    printf -- '\n'

    if [[ "${bFlag}" == 'true' ]]; then
        # shellcheck disable=1003
        sqlclBinary=' -b '\''\'\'''\'"${sqlclBinary}"\''\'\'''\'''
    fi

    # Process TNS file
    if [[ "${tFlag}" == 'true' ]] || [[ "${TFlag}" == 'true' ]]; then
        while read -r netServiceName; do
            # shellcheck disable=1003
            printf -- 'alias %s%s='\''sqlclConnectHelper%s -i '\''\'\'''\''%s'\''\'\'''\'''\''\n' \
                "${aliasPrefix}" \
                "${netServiceName}" \
                "${sqlclBinary}" \
                "${netServiceName}"
        done <<< "$(getNetServiceNamesFromFile "${tnsFile}")"
    fi

    # Process cloud configs
    if [[ "${cFlag}" == 'true' ]]; then
        while read -r netServiceName; do
            # shellcheck disable=1003
            printf -- 'alias %s%s='\''sqlclConnectHelper%s -c '\''\'\'''\''%s'\''\'\'''\'' -i '\''\'\'''\''%s'\''\'\'''\'''\''\n' \
                "${aliasPrefix}" \
                "${netServiceName}" \
                "${sqlclBinary}" \
                "${cloudConfigZip}" \
                "${netServiceName}"
        done <<< "$(getCloudCounfigNetServiceNamesFromZip "${cloudConfigZip}")"
    fi

    return 0
} # sqlclGenerateTNSAliases
