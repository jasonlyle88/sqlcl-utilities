#shellcheck shell=bash

function sqlclGenerateOIDAliases() {
    ############################################################################
    #
    # Notes
    #
    ############################################################################
    # In an attempt to avoid limits on the number of entities returned in a
    # single search request, this function makes multiple LDAP requests.
    # First it queries all of the requested orclContext entities
    # (contexts/groups/projects).
    # Then it loops over each orclContext entity and requests all the
    # associated orclNetService entities (databases).

    ############################################################################
    #
    # Setup
    #
    ############################################################################
    # For this function in ZSH, make arrays behave like KSH/BASH and do not
    # monitor background processes
    if command -v setopt 1>/dev/null 2>&1; then
        setopt local_options KSH_ARRAYS NO_MONITOR
    fi

    ############################################################################
    #
    # Functions
    #
    ############################################################################
    function usage() {
        printf -- 'This script is used to generate SQLcL aliases based on Oracle Internet Directory (OID) LDAP server entries\n'
        printf -- '\n'
        printf -- 'The following arguments are recognized\n'
        printf -- '\n'
        printf -- '  -a {function}  --The name of a function that prints additional aliases (one per line)}\n'
        printf -- '                 --The function will receive the following parameters (in the provided order):\n'
        printf -- '                 --      Alias prefix\n'
        printf -- '                 --      Alias name\n'
        printf -- '                 --      LDAP Context (lowercase)\n'
        printf -- '                 --      Database name (lowercase)\n'
        printf -- '                 --      Database connect string\n'
        printf -- '  -b {binary}    --Specify the SQLcl binary to use\n'
        printf -- '  -B {base}      --The LDAP base from where the script should start searching for database entires\n'
        printf -- '                 --Example: "dc=example,dc=com"\n'
        printf -- '  -e {context}   --Context from LDAP to exclude from alias generation\n'
        printf -- '                 --Can be specified more than once\n'
        printf -- '                 --Cannot be specified with "-i"\n'
        printf -- '  -f {function}  --The name of a function that prints the formatted name to use for an alias\n'
        printf -- '                 --The function will receive the following parameters (in the provided order):\n'
        printf -- '                 --      Alias prefix\n'
        printf -- '                 --      LDAP Context (lowercase)\n'
        printf -- '                 --      Database name (lowercase)\n'
        printf -- '                 --      Database connect string\n'
        printf -- '  -h             --Show this help\n'
        printf -- '* -H {host}      --LDAP host used to query for entries\n'
        printf -- '  -i {context}   --Context from LDAP to include for alias generation\n'
        printf -- '                 --Can be specified more than once\n'
        printf -- '                 --Cannot be specified with "-e"\n'
        printf -- '  -p {prefix}    --Prefix used for generated aliases\n'
        printf -- '                 --Defaults to "sql."\n'
        printf -- '  -P {port}      --LDAP port used to query for entries\n'
        printf -- '                 --Defaults to "389"\n'
        printf -- '\n'
        printf -- 'Example:\n'
        printf -- '  %s -H "example.ldap-host.com"\n' "${scriptName}"
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

    function parseLdapSearchResponse() {
        local ldapSearchUrl="${1}"
        local ldapUser="${2}"
        local ldapPassword="${3}"

        ########################################################################
        #
        # Notes
        #
        ########################################################################
        # LDAP uses the following URI scheme
        # protocol://host:port/dn?attributes?scope?filter?extensions
        #
        #   protocol: Almost always ldap (ldaps is an alternative)
        #   host: FQDN or IP address of the LDAP server
        #   port: port to access the LDAP server
        #       389 is standard port - unsecure
        #       636 is standard port - secure
        #   dn: distinguished name to use as the search base
        #   attributes: blank to return all attributes, or comma seperated list of attributes to return
        #   scope:
        #       'base'  (level indecated by base_dn) (default)
        #       'one'   (single level below base_dn)
        #       'sub'   (entire subtree of base_dn)
        #   filter: An LDAP filter
        #   extensions: Extensions to the LDAP URL format

        # Separators used in transformation
        #   GS    HEX: x1D    OCT: 035  Name: Group Separator
        #   RS    HEX: x1E    OCT: 036  Name: Record Separator

        # Explanation of process:
        #   Trim leading whitepsace
        #   Trim trailing whitepsace
        #   Delete blank lines
        #   Add record separator (RS) character before each DN
        #   Convert new lines to group separator (GS) character, creating just a single line of data
        #   Convert very first character from record seperator (RS) to group separator (GS)
        #   Convert very last character from group separator (GS) to a group separator (GS) followed by a record seperator (RS)
        #   ** At this point the data is in a single line where consits of:
        #       An LDAP entity followed by a record seperator (RS). An LDAP entity consists of:
        #           An initial group seperator (GS)
        #           A full attribute. A full attribute is:
        #               Optional white space
        #               An attribute name
        #               Optional white space
        #               A colon (:)
        #               Optional white space
        #               An attribute value
        #               A group seperator (GS)
        #   SPECIFIC TO OID LDAP: Parse the first common name part and print it out mimicing other LDAP attributes
        #   SPECIFIC TO OID LDAP: Sort by cn part
        #   Remove first line that is just a group seperator (GS) and a newline (artifact of data manipulation used here)
        #   Seperate each attribute (that is not first attribute or last attribute) onto its own line by replacing each group seperator (GS) by a newline
        #   Remove remaining group seperator (GS) characters: before the first attribute of an entity and after the last attribute of an entity
        #   ** Each line is now an entity attribute
        #   Seperate attribute name and attribute value onto their own lines
        #   Put each record seperator (RS) on its own line after all the atrributes for the entity
        #   ** Format is now in the format of the following line example setup:
        #       Entity 1 - Attribute 1 name
        #       Entity 1 - Attribute 1 value
        #       Entity 1 - Attribute 2 name
        #       Entity 1 - Attribute 2 value
        #       ...
        #       Record seperator character
        #       Entity 2 - Attribute 1 name
        #       Entity 2 - Attribute 1 value
        #       Entity 2 - Attribute 2 name
        #       Entity 2 - Attribute 2 value
        #       ...
        #       Record seperator character
        #       ...
        #
        # Notes:
        #   Attribute order is not guaranteed if the search request does not specify the attributes

        local ldapResponse

        if ! ldapResponse="$(curl --fail -su "${ldapUser}:${ldapPassword}" "${ldapSearchUrl}")"; then
            printf -- 'ERROR: LDAP request failed\n' >&2
            return 1
        fi

        printf '%s\n' "${ldapResponse}" | \
            sed -r \
                -e 's|^[[:space:]]+||' \
                -e 's|[[:space:]]+$||' \
                -e '/^\s*$/d' \
                -e 's|^(DN:)|\x1E\1|i' | \
            tr '\n' '\035' | \
            sed -r \
                -e 's|^\x1E|\x1D|' \
                -e 's|\x1D$|\x1D\x1E|' \
                -e 's|\x1D\x1E|\x1D\x1E\n\x1D|g' | \
            sed -r \
                -e 's|^\x1D(DN:[[:space:]]*cn=([^,]+))|\x1Dcn: \2\x1D\1|i' | \
            sort | \
            tail -n +2 | \
            sed -r \
                -e 's|([[:print:]])\x1D([[:print:]])|\1\n\2|g' \
                -e 's|\x1D||g' | \
            sed -r \
                -e 's|^[[:space:]]*([^:]+)[[:space:]]*:[[:space:]]*([[:print:]]*)|\1\n\2|' \
                -e "s|(\x1E)|\n\1|"
    } # parseLdapSearchResponse

    function parseContextDatabases() {
        local ldapDatabaseSearchUrl="${1}"
        local context="${2}"

        local ldapResponse
        local ldapResponseExitCode
        local count
        local iteration
        local line
        local attributeName
        local attributeValue
        local databaseName
        local databaseDn
        local databaseConnectString
        local aliasName
        local ldapconBase

        printf -- '\n'
        printf -- '%s\n' "${h2}"
        printf -- '%s %s\n' "${hs}" "${context}"
        printf -- '%s\n' "${h2}"

        # Get parsed LDAP response
        ldapResponse="$(parseLdapSearchResponse "${ldapDatabaseSearchUrl}")"
        ldapResponseExitCode=$?
        if [[ "${ldapResponseExitCode}" -gt 0 ]]; then
            return
        fi

        # Loop over all the databases for this context
        count=0
        while read -r line; do
            if [[ "${line}" == "${recordSeparator}" ]]; then
                # All attributes have been read by this loop, so process entity
                aliasName="$(
                    "${aliasNameFormatFunction}" \
                        "${aliasPrefix}" \
                        "${context}" \
                        "${databaseName}" \
                        "${databaseConnectString}"
                )"

                # LDAPCON must have #ENTRY# in it, so we cannot provide the
                # actual database name in the LDAPCON string. Because of that,
                # the database name must be deleted from the DN attribute.
                ldapconBase="${databaseDn#"cn=${databaseName}"}"

                # shellcheck disable=1003
                printf -- 'alias %s='\''LDAPCON='\''\'\'''\''jdbc:oracle:thin:@ldap://%s:%s/#ENTRY#%s'\''\'\'''\'' sqlclConnectHelper%s -i '\''\'\'''\''%s'\''\'\'''\'''\''\n' \
                        "${aliasName}" \
                        "${ldapHost}" \
                        "${ldapPort}" \
                        "${ldapconBase}" \
                        "${sqlclBinary}" \
                        "${databaseName}"

                # Call the additional aliases function if provided
                if [[ "${aFlag}" == 'true' ]]; then
                    "${additionalAliasesFunction}" \
                        "${aliasPrefix}" \
                        "${aliasName}" \
                        "${context}" \
                        "${databaseName}" \
                        "${databaseConnectString}"
                fi

                # Reset info and continue on to the next entity
                count=0
                continue
            fi

            ((count=count+1))
            iteration=$((count % 2))

            if [[ "${iteration}" -eq 1 ]]; then
                attributeName="$(toUpperCase "${line}")"
            else
                attributeValue="$(toLowerCase "${line}")"

                if [[ "${attributeName}" == 'CN' ]]; then
                    databaseName="${attributeValue}"
                elif [[ "${attributeName}" == 'DN' ]]; then
                    databaseDn="${attributeValue}"
                elif [[ "${attributeName}" == 'ORCLNETDESCSTRING' ]]; then
                    databaseConnectString="${attributeValue}"
                fi
            fi

        done < <(printf '%s\n' "${ldapResponse}")
    } # parseContextDatabases

    # shellcheck disable=2317
    function defaultAliasNameFormatFunction() {
        local aliasPrefix="${1}"
        local contextName="${2}"
        local databaseName="${3}"
        # shellcheck disable=2034
        local databaseConnectIdentifier="${4}"

        printf -- '%s%s.%s' \
            "${aliasPrefix}" \
            "${contextName}" \
            "${databaseName}"
    } # defaultAliasNameFormatFunction

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
    # shellcheck disable=2034
    scriptName="$(basename -- "${scriptBase}" '.sh')"
    # shellcheck disable=2034
    scriptPath="$(getCanonicalPath "$(dirname -- "${scriptBase}")")"

    ############################################################################
    ##  Parameter variables
    ############################################################################
    local OPTIND
    local OPTARG
    local opt

    local aFlag='false'
    local bFlag='false'
    local BFlag='false'
    local eFlag='false'
    local fFlag='false'
    local HFlag='false'
    local iFlag='false'
    local pFlag='false'
    local PFlag='false'

    local additionalAliasesFunction
    local sqlclBinary
    local ldapBasePath
    local -a providedContextList=()
    local aliasNameFormatFunction
    local ldapHost
    local aliasPrefix
    local ldapPort

    ############################################################################
    ##  Constants
    ############################################################################
    # shellcheck disable=2034,SC2155
    local h1="$(printf "%0.s#" {1..80})"
    # shellcheck disable=2034,SC2155
    local h2="$(printf "%0.s#" {1..60})"
    # shellcheck disable=2034,SC2155
    local h3="$(printf "%0.s#" {1..40})"
    # shellcheck disable=2034,SC2155
    local h4="$(printf "%0.s#" {1..20})"
    # shellcheck disable=2034,SC2155
    local hs="$(printf "%0.s#" {1..2})"
    # shellcheck disable=2034
    local originalPWD="${PWD}"
    # shellcheck disable=2034
    local originalIFS="${IFS}"

    local recordSeparator
    local basePathToken='#BASE_PATH_TOKEN#'

    recordSeparator="$(printf '\x1E')"

    ############################################################################
    ##  Procedural variables
    ############################################################################
    local contextSearchFilter
    local ldapBaseUrl
    local ldapContextSearchUrl
    local ldapDatabaseSearchTemplate
    local ldapDatabaseSearchUrl
    local ldapResponse
    local ldapResponseExitCode
    local line
    local count
    local iteration
    local index
    local attributeName
    local attributeValue
    local -a contextList=()
    local -a contextPathList=()
    local context
    local contextPath
    local tempFile
    local -a tempFiles=()
    local pid
    local -a pidList=()
    local databaseName

    ############################################################################
    #
    # Option parsing
    #
    ############################################################################
    while getopts ':a:b:B:e:f:hH:i:p:P:' opt
    do
        case "${opt}" in
        'a')
            aFlag='true'
            additionalAliasesFunction="${OPTARG}"
            ;;
        'b')
            bFlag='true'
            sqlclBinary="${OPTARG}"
            ;;
        'B')
            # shellcheck disable=2034
            BFlag='true'
            ldapBasePath="${OPTARG}"
            ;;
        'e')
            eFlag='true'
            providedContextList+=("$(toLowerCase "${OPTARG}")")
            ;;
        'f')
            fFlag='true'
            aliasNameFormatFunction="${OPTARG}"
            ;;
        'h')
            usage
            return 0
            ;;
        'H')
            HFlag='true'
            ldapHost="${OPTARG}"
            ;;
        'i')
            iFlag='true'
            providedContextList+=("$(toLowerCase "${OPTARG}")")
            ;;
        'p')
            pFlag='true'
            aliasPrefix="${OPTARG}"
            ;;
        'P')
            # shellcheck disable=2034
            PFlag='true'
            ldapPort="${OPTARG}"
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

    #
    # Parameter defaults
    #
    if [[ "${fFlag}" != 'true' ]]; then
        aliasNameFormatFunction='defaultAliasNameFormatFunction'
    fi

    if [[ "${pFlag}" != 'true' ]]; then
        aliasPrefix='sql.'
    fi

    if [[ "${PFlag}" != 'true' ]]; then
        ldapPort='389'
    fi

    #
    # Parameter verification
    #

    # Check alias format function is executable
    if [[ "${aFlag}" == 'true' ]] && [[ ! "$(command -v "${additionalAliasesFunction}")" ]]; then
        printf -- 'Cannot execute additional aliases function "%s"\n' "${additionalAliasesFunction}" >&2
        return 13
    fi

    # Check SQLcl binary is executable
    if [[ "${bFlag}" == 'true' ]] && [[ ! "$(command -v "${sqlclBinary}")" ]]; then
        printf -- 'Cannot execute SQLcl binary "%s"\n' "${sqlclBinary}" >&2
        return 11
    fi

    # Check -e and -i parameter mutual exclusivity
    if [[ "${eFlag}" == 'true' ]] && [[ "${iFlag}" == 'true' ]]; then
        printf -- 'Can only have -e or -i flags, not a combination of both\n' >&2
        return 12
    fi

    # Check alias format function is executable
    if [[ "${fFlag}" == 'true' ]] && [[ ! "$(command -v "${aliasNameFormatFunction}")" ]]; then
        printf -- 'Cannot execute alias format function "%s"\n' "${aliasNameFormatFunction}" >&2
        return 13
    fi

    # Check for requried -h parameter
    if [[ "${HFlag}" != 'true' ]]; then
        printf -- 'ERROR: LDAP Host (-H) must be specified.\n' >&2
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
    printf -- '%s %-32s: "%s"\n' "${hs}" "SQLcl Binary" "${sqlclBinary}"
    printf -- '%s %-32s: "%s"\n' "${hs}" "Prefix" "${aliasPrefix}"
    printf -- '%s %-32s: "%s"\n' "${hs}" "Name generation function" "${aliasNameFormatFunction}"
    printf -- '%s %-32s: "%s"\n' "${hs}" "Additional aliases function" "${additionalAliasesFunction}"
    printf -- '%s %-32s: "%s"\n' "${hs}" "LDAP Host" "${ldapHost}"
    printf -- '%s %-32s: "%s"\n' "${hs}" "LDAP Port" "${ldapPort}"
    printf -- '%s %-32s: "%s"\n' "${hs}" "LDAP Base" "${ldapBasePath}"
    [[ "${iFlag}" == 'true' ]] && printf -- '%s %-32s:\n' "${hs}" "LDAP included contexts"
    [[ "${iFlag}" == 'true' ]] && printf -- "${hs}    - %s\n" "${providedContextList[@]}"
    [[ "${eFlag}" == 'true' ]] && printf -- '%s %-32s:\n' "${hs}" "LDAP excluded contexts"
    [[ "${eFlag}" == 'true' ]] && printf -- "${hs}    - %s\n" "${providedContextList[@]}"
    printf -- '%s\n' "${h1}"

    if [[ "${bFlag}" == 'true' ]]; then
        # shellcheck disable=1003
        sqlclBinary=' -b '\''\'\'''\'"${sqlclBinary}"\''\'\'''\'''
    fi

    if [[ "${iFlag}" == 'true' ]]; then
        contextSearchFilter="$(
            printf -- '(|'
            printf '(cn=%s)' "${providedContextList[@]}"
            printf -- ')'
        )"
    elif [[ "${eFlag}" == 'true' ]]; then
        contextSearchFilter="$(
            printf -- '(!(|'
            printf '(cn=%s)' "${providedContextList[@]}"
            printf -- '))'
        )"
    fi

    ldapBaseUrl="ldap://${ldapHost}:${ldapPort}/${ldapBasePath}"
    ldapDatabaseSearchTemplate="ldap://${ldapHost}:${ldapPort}/${basePathToken}?orclNetDescString?one?(objectClass=orclNetService)"
    ldapContextSearchUrl="${ldapBaseUrl}?cn?sub?(&(objectClass=orclContext)${contextSearchFilter})"

    # Get parsed LDAP response
    ldapResponse="$(parseLdapSearchResponse "${ldapContextSearchUrl}")"
    ldapResponseExitCode=$?
    if [[ "${ldapResponseExitCode}" -gt 0 ]]; then
        return ${ldapResponseExitCode}
    fi

    # Populate list of contexts to search through
    count=0
    while read -r line; do
        if [[ "${line}" == "${recordSeparator}" ]]; then
            # All attributes have been read by this loop, so process entity
            contextList+=("${context}")
            contextPathList+=("${contextPath}")

            # Reset info and continue on to the next entity
            count=0
            continue
        fi

        ((count=count+1))
        iteration=$((count % 2))

        if [[ "${iteration}" -eq 1 ]]; then
            attributeName="$(toUpperCase "${line}")"
        else
            attributeValue="$(toLowerCase "${line}")"

            if [[ "${attributeName}" == 'CN' ]]; then
                context="${attributeValue}"
            elif [[ "${attributeName}" == 'DN' ]]; then
                contextPath="${attributeValue}"
            fi
        fi
    done < <(printf '%s\n' "${ldapResponse}")

    # Loop over each context in the contextList
    # for context in "${contextList[@]}"; do
    for (( index=0; index<${#contextList[@]}; index++ )); do
        context="${contextList[${index}]}"
        contextPath="${contextPathList[${index}]}"

        ldapDatabaseSearchUrl="$(
            printf -- '%s' "${ldapDatabaseSearchTemplate}" | \
                sed -re "s|${basePathToken}|${contextPath}|"
        )"

        tempFile="$(mktemp)"
        tempFiles+=("${tempFile}")

        # Contain parseContextDatabases call in execution block so that the
        # job monitor output in BASH can be directed to /dev/null
        {
            parseContextDatabases \
                "${ldapDatabaseSearchUrl}" \
                "${context}" \
                1>"${tempFile}" 2>&1 &
        } 1>/dev/null 2>&1

        pid=$!
        pidList+=("${pid}")
    done

    wait "${pidList[@]}" 1>/dev/null 2>&1

    for tempFile in "${tempFiles[@]}"; do
        command cat "${tempFile}"
        rm "${tempFile}"
    done

    printf -- '\n'

    return 0
} # sqlclGenerateOIDAliases
