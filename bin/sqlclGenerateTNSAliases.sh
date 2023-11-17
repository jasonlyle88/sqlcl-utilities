#shellcheck shell=bash

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
        printf -- '               --Can be specified more than once\n'
        printf -- '  -h           --Show this help\n'
        printf -- '  -p {prefix}  --The cloud configuration prefix for the shell aliases of the last specified cloud configuration wallet\n'
        printf -- '               --Can be specified once per cloud configuration paramater (-c)\n'
        printf -- '  -P {prefix}  --The global prefix for all the aliases generated\n'
        printf -- '               --Defaults to "sql."\n'
        printf -- '  -t {file}    --Generate shell aliases for the provided TNS file\n'
        printf -- '               --Can be specified more than once\n'
        printf -- '               --Should be a valid tnsnames.ora file\n'
        printf -- '  -T           --Generate shell aliases for the standard tnsnames.ora file\n'
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
    local PFlag='false'
    local tFlag='false'
    local TFlag='false'

    local sqlclBinary               # -b
    local -a cloudConfigFiles       # -c
    local -a cloudConfigPrefixes    # -p
    local globalPrefix              # -P
    local -a tnsFiles               # -t

    local handlingCloudConfigParams='false'

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

    local tnsnamesName='tnsnames.ora'

    ############################################################################
    ##  Procedural variables
    ############################################################################
    local file
    local -a netServiceNames
    local prefix

    ############################################################################
    #
    # Option parsing
    #
    ############################################################################
    while getopts ':b:c:hp:P:t:T' opt
    do
        case "${opt}" in
        'b')
            bFlag='true'
            sqlclBinary="${OPTARG}"
            ;;
        'c')
            cFlag='true'
            cloudConfigFiles+=("${OPTARG}")
            handlingCloudConfigParams='true'
            ;;
        'h')
            usage
            return 0
            ;;
        'p')
            # shellcheck disable=2034
            pFlag='true'
            if [[ "${handlingCloudConfigParams}" != 'true' ]]; then
                printf 'ERROR: Argument -p must only come after -c or -u arguments\n' >&2
                return 4
            fi

            cloudConfigPrefixes[${#cloudConfigFiles[@]}-1]="${OPTARG}"
            ;;
        'P')
            PFlag='true'
            globalPrefix="${OPTARG}"
            ;;
        't')
            tFlag='true'
            tnsFiles+=("${OPTARG}")
            handlingCloudConfigParams='false'
            ;;
        'T')
            TFlag='true'
            handlingCloudConfigParams='false'
            ;;
        '?')
            printf 'ERROR: Invalid option -%s\n\n' "${OPTARG}" >&2
            usage >&2
            return 3
            ;;
        ':')
            printf 'ERROR: Option -%s requires an argument.\n' "${OPTARG}" >&2
            return 3
            ;;
        esac
    done

    ##############################################################################
    #
    # Parameter handling
    #
    ##############################################################################
    # Check at least some version of TNS aliases is supplied
    if [[ "${TFlag}" != 'true' ]] && [[ "${tFlag}" != 'true' ]] && [[ "${cFlag}" != 'true' ]]; then
        printf "At least one TNS alias file must be specified\n" >&2
        return 5
    fi;

    # Check all provided non-standard TNS files are readable
    if [[ "${tFlag}" == 'true' ]]; then
        for tnsFile in "${tnsFiles[@]}"; do
            if [[ ! -r "${tnsFile}" ]]; then
                printf 'Not a readable file: \"%s\"\n' "${tnsFile}" >&2
                return 6
            fi
        done
    fi

    # Check for the tnsnames.ora file in standard locations
    if [[ "${TFlag}" == 'true' ]]; then

        # Check if the TNS_ADMIN variable is set
        if [[ -n "${TNS_ADMIN}"  ]]; then
            file="${TNS_ADMIN}/${tnsnamesName}"

            if [[ -r "${file}" ]]; then
                tnsFiles+=("${file}")
            else
                printf 'No %s readable file at location (%s)\n' "${tnsnamesName}" "$(dirname "${file}")" >&2
                return 7
            fi
        elif [[ -n "${ORACLE_HOME}" ]]; then
            file="${ORACLE_HOME}/network/admin/${tnsnamesName}"

            if [[ -r "${file}" ]]; then
                tnsFiles+=("${file}")
            else
                printf 'No %s readable file at location (%s)\n' "${tnsnamesName}" "$(dirname "${file}")" >&2
                return 8
            fi
        else
            printf 'No existing TNS_ADMIN or ORACLE_HOME variable, unable to locate standard %s\n' "${tnsnamesName}" >&2
            return 9
        fi

    fi

    # Check SQLcl binary is executable
    if [[ "${bFlag}" == 'true' ]] && [[ ! "$(command -v "${sqlclBinary}")" ]]; then
        printf 'Cannot execute SQLcl binary "%s"\n' "${sqlclBinary}" >&2
        return 10
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
        sqlclBinary=" -b '\\''${sqlclBinary}'\\''"
    fi

    if [[ "${PFlag}" != 'true' ]]; then
        globalPrefix='sql.'
    fi

    # Process TNS files
    for tnsFile in "${tnsFiles[@]}"; do
        printf -- '%s\n' "${h2}"
        printf -- '%s %s\n' "${hs}" "${tnsFile}"
        printf -- '%s\n' "${h2}"

        while read -r netServiceName; do
            # shellcheck disable=1003
            printf -- 'alias %s%s='\''sqlclConnectHelper%s -i '\''\'\'''\''%s'\''\'\'''\'''\''\n' \
                "${globalPrefix}" \
                "${netServiceName}" \
                "${sqlclBinary}" \
                "${netServiceName}"
        done <<< "$(getNetServiceNamesFromFile "${tnsFile}")"

        printf '\n'
    done

    # Process cloud configs
    for (( i=0; i<${#cloudConfigFiles[@]}; i++ )); do
        printf -- '%s\n' "${h2}"
        printf -- '%s %s\n' "${hs}" "${cloudConfigFiles[${i}]}"
        printf -- '%s\n' "${h2}"

        # Setup prefix
        prefix="${cloudConfigPrefixes[${i}]}"
        if [[ -n "${prefix}" ]]; then
            prefix+="."
        fi

        # Get service names for this cloud config
        netServiceNames=()
        while read -r serviceName; do
            netServiceNames+=("${serviceName}")
        done <<< "$(getCloudCounfigNetServiceNamesFromZip "${cloudConfigFiles[${i}]}")"

        for netServiceName in "${netServiceNames[@]}"; do
            # shellcheck disable=1003
            printf -- 'alias %s%s%s='\''sqlclConnectHelper%s -c '\''\'\'''\''%s'\''\'\'''\'' -i '\''\'\'''\''%s'\''\'\'''\'''\''\n' \
                "${globalPrefix}" \
                "${prefix}" \
                "${netServiceName}" \
                "${sqlclBinary}" \
                "${cloudConfigFiles[${i}]}" \
                "${netServiceName}"
        done

        if [[ "${i}" -lt "$((${#cloudConfigFiles[@]}-1))" ]]; then
            printf -- '\n'
        fi
    done

    return 0
} # sqlclGenerateTNSAliases
