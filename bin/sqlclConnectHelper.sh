#shellcheck shell=bash

function sqlclConnectHelper() {
    ############################################################################
    #
    # Functions
    #
    ############################################################################
    function usage() {
        printf -- 'This script is used to connect to SQLcl in a more unix based method (all parameters specified with flags)\n'
        printf -- '\n'
        printf -- 'The following arguments are recognized (* = required)\n\n'
        printf -- '  -a {param}     --Specify a parameter to pass to the SQL script to run.\n'
        printf -- '                 --Can be specified more than one time to specify multiple script parameters.\n'
        printf -- '                 --Cannot be specified without the "-s" argument.\n'
        printf -- '  -b             --Specify the SQLcl binary to use.\n'
        printf -- '                 --If this is not specified, then "sql" is used.\n'
        printf -- '  -c {wallet}    --Corresponds to SQLcl'\''s "-cloudconfig" parameter.\n'
        printf -- '                 --Specify a zip file to use as the cloud configuration wallet.\n'
        printf -- '  -h             --Show this help.\n'
        printf -- '* -i {id}        --Specify the database'\''s connect identifier.\n'
        printf -- '  -L             --Corresponds to SQLcl'\''s "-L"\\"-LOGON" parameter.\n'
        printf -- '                 --Tells SQLcl not to reprompt for a username and password if the first login attempt fails.\n'
        printf -- '  -o             --Corresponds to SQLcl'\''s "-oci" parameter.\n'
        printf -- '                 --Tells SQLcl to use an Oracle instant client installation.\n'
        printf -- '                 --When set, SQLcl will use the drivers from the first installation on the path.\n'
        printf -- '  -p {password}  --Specify the user'\''s password to use to connect to the database.\n'
        printf -- '  -r {role}      --Specify the user'\''s role to use to connect to the database.\n'
        printf -- '  -R {level}     --Corresponds to SQLcl'\''s "-R" parameter.\n'
        printf -- '                 --Sets the restricted mode to disable SQLcl commands that interact with the file system.\n'
        printf -- '                 --The level can be 1, 2, 3, or 4.\n'
        printf -- '                 --Level 4 is the most restrictive.\n'
        printf -- '  -s {script}    --Specify a SQL script to be run (file or URL).\n'
        printf -- '  -S             --Corresponds to SQLcl'\''s "-S" parameter.\n'
        printf -- '                 --Enables SQLcl'\''s silent mode.\n'
        printf -- '                 --This disables the login banner, prompts, and echoing of commands.\n'
        printf -- '* -u {user}      --Specify the user as which to connect to the database.\n'
        printf -- '  -v             --Corresponds to SQLcl'\''s "-verbose" parameter.\n'
        printf -- '                 --Set this to show SQLcl logging messages inline.\n'
        printf -- '  -x {proxy}     --Corresponds to SQLcl'\''s "-socksproxy" parameter.\n'
        printf -- '                 --Specify a SOCKS proxy to use to connect to a cloud database.\n'
        printf -- '  -y             --Corresponds to SQLcl'\''s "-nohistory" parameter.\n'
        printf -- '                 --Switches off SQLcl'\''s history logging.\n'
        printf -- '  -z             --Corresponds to SQLcl'\''s "-noupdates" parameter.\n'
        printf -- '                 --Switches off SQLcl'\''s update checking.\n'
        printf -- '\n'
        printf -- 'Example:\n'
        printf -- '  %s -SLz -i orcl -u sys -r sysdba\n' "${scriptName}"
        printf -- '  corresponds to: '\''sql -S -LOGON -noupdates "sys"@"orcl" as sysdba'\''\n'
        printf -- '\n'

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

    ############################################################################
    #
    # Variables
    #
    ############################################################################

    ############################################################################
    ##  Configurable variables
    ############################################################################
    local DEFAULT_SQLCL_BINARY="${DEFAULT_SQLCL_BINARY:-sql}"

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

    local aFlag='false'
    local bFlag='false'
    local cFlag='false'
    local iFlag='false'
    local LFlag='false'
    local oFlag='false'
    local pFlag='false'
    local rFlag='false'
    local RFlag='false'
    local sFlag='false'
    local SFlag='false'
    local uFlag='false'
    local vFlag='false'
    local xFlag='false'
    local yFlag='false'
    local zFlag='false'

    local -a sqlclScriptToRunParameters=()
    local sqlclBinary
    local sqlclCloudConfig
    local sqlclConnectIdentifier
    local sqlclPassword
    local sqlclRole
    local sqlclRestrictedMode
    local sqlclScriptToRun
    local sqlclUser
    local sqlclSocksProxy

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

    # Procedural variables
    local -a sqlclArguments=()
    local -a sqlclRunScriptParameters=()

    ##############################################################################
    #
    # Option parsing
    #
    ##############################################################################
    while getopts ':a:b:c:hi:Lop:r:R:s:Su:vx:yz' opt
    do
        case "${opt}" in
        'a')
            aFlag='true'
            sqlclScriptToRunParameters+=("${OPTARG}")
            ;;
        'b')
            bFlag='true'
            sqlclBinary="${OPTARG}"
            ;;
        'c')
            cFlag='true'
            sqlclCloudConfig="${OPTARG}"
            ;;
        'h')
            usage
            return 0
            ;;
        'i')
            iFlag='true'
            sqlclConnectIdentifier="${OPTARG}"
            ;;
        'L')
            LFlag='true'
            ;;
        'o')
            oFlag='true'
            ;;
        'p')
            pFlag='true'
            sqlclPassword="${OPTARG}"
            ;;
        'r')
            rFlag='true'
            sqlclRole="${OPTARG}"
            ;;
        'R')
            RFlag='true'
            sqlclRestrictedMode="${OPTARG}"
            ;;
        's')
            sFlag='true'
            sqlclScriptToRun="${OPTARG}"
            ;;
        'S')
            SFlag='true'
            ;;
        'u')
            uFlag='true'
            sqlclUser="${OPTARG}"
            ;;
        'v')
            vFlag='true'
            ;;
        'x')
            xFlag='true'
            sqlclSocksProxy="${OPTARG}"
            ;;
        'y')
            yFlag='true'
            ;;
        'z')
            zFlag='true'
            ;;
        "?")
            printf "ERROR: Invalid option -%s\n\n" "${OPTARG}" >&2
            usage >&2
            return 3
            ;;
        ":")
            printf "ERROR: Option -%s requires an argument.\n" "${OPTARG}" >&2
            return 3
            ;;
        esac
    done

    ##############################################################################
    #
    # Parameter handling
    #
    ##############################################################################
    # Check a user was provided
    if [[ "${uFlag}" != 'true' ]]; then
        printf "A database username/schema name must be provided.\n" >&2
        return 11
    fi

    # Check a connect identifier was provided
    if [[ "${iFlag}" != 'true' ]]; then
        printf "A database connect identifier must be provided.\n" >&2
        return 12
    fi

    # Check cloud config wallet is readable
    if [[ "${cFlag}" = 'true' ]] && [[ ! -r "${sqlclCloudConfig}" ]]; then
        printf "Cannot read cloud config file \"%s\".\n" "${sqlclCloudConfig}" >&2
        return 13
    fi

    # Check run script parameters were not provided without a run script
    if [[ "${sFlag}" != 'true' ]] && [[ "${aFlag}" = 'true' ]]; then
        printf "Cannot provide run script parameters without a run script.\n" >&2
        return 14
    fi

    # Setup sqlclBinary
    if [[ "${bFlag}" != 'true' ]]; then
        sqlclBinary="${DEFAULT_SQLCL_BINARY}"
    fi

    ##############################################################################
    #
    # Function Logic
    #
    ##############################################################################
    # Check SQLcl binary is executable
    if [[ ! -x "$(command -v "${sqlclBinary}")" ]]; then
        printf 'Cannot execute SQLcl binary "%s"\n' "${sqlclBinary}" >&2
        return 31
    fi

    # Setup SQLcl role
    if [[ "${rFlag}" = 'true' ]]; then
        sqlclRole=" as ${sqlclRole} "
    fi

    # Setup SQLcl arguments array
    if [[ "${RFlag}" = 'true' ]]; then
        sqlclArguments+=('-R')
        sqlclArguments+=("${sqlclRestrictedMode}")
    fi

    if [[ "${SFlag}" = 'true' ]]; then
        sqlclArguments+=('-S')
    fi

    if [[ "${vFlag}" = 'true' ]]; then
        sqlclArguments+=('-verbose')
    fi

    if [[ "${yFlag}" = 'true' ]]; then
        sqlclArguments+=('-nohistory')
    fi

    if [[ "${zFlag}" = 'true' ]]; then
        sqlclArguments+=('-noupdates')
    fi

    if [[ "${oFlag}" = 'true' ]]; then
        sqlclArguments+=('-oci')
    fi

    if [[ "${LFlag}" = 'true' ]]; then
        sqlclArguments+=('-L')
    fi

    if [[ "${cFlag}" = 'true' ]]; then
        sqlclArguments+=('-cloudconfig')
        sqlclArguments+=("${sqlclCloudConfig}")
    fi

    if [[ "${xFlag}" = 'true' ]]; then
        sqlclArguments+=('-socksproxy')
        sqlclArguments+=("${sqlclSocksProxy}")
    fi

    # Setup SQLcl start array
    if [[ "${sFlag}" = 'true' ]]; then
        sqlclRunScriptParameters+=(' ' "@${sqlclScriptToRun}" "${sqlclScriptToRunParameters[@]}")
    fi

    # Set terminal title
    if command -v title 1>/dev/null 2>&1 && [[ "${DISABLE_AUTO_TITLE:-false}" != 'true' ]]; then
        titleString="$(echo "\"${sqlclBinary}\" ${sqlclArguments[*]} \"${sqlclUser}\"@\"${sqlclConnectIdentifier}\"${sqlclRole}" | sed -e 's|^[[:space:]]*||' -e 's|[[:space:]]*$||' -e 's|[[:space:]][[:space:]]*| |g')"

        title "${sqlclBinary}" "${titleString}"
    fi

    if [[ "${pFlag}" != 'true' ]]; then
        # shellcheck disable=2145
        "${sqlclBinary}" "${sqlclArguments[@]}" "${sqlclUser}"@"${sqlclConnectIdentifier}""${sqlclRole}""${sqlclRunScriptParameters[@]}"
    else
        # shellcheck disable=2145
        "${sqlclBinary}" "${sqlclArguments[@]}" "${sqlclUser}"/"${sqlclPassword}"@"${sqlclConnectIdentifier}""${sqlclRole}""${sqlclRunScriptParameters[@]}"
    fi

    return 0
} # sqlclConnectHelper
