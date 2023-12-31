# SQLcl Utilities

## Purpose
This plugin provides different utility functions to help you interact with [Oracle SQLcl](https://www.oracle.com/database/sqldeveloper/technologies/sqlcl/).

One function, `sqlclUpdater` helps you install and update SQLcl.

Another function, `sqlclConnectHelper` wraps a script around SQLcl to allow for unix style parameters to be passed to SQLcl.

`sqlclGenerateTNSAliases` and `sqlclGenerateOIDAliases` generate BASH/ZSH shell aliases for connecting via SQLcl to Oracle databases defined in TNS files or OID LDAP servers.

By default, the generated aliases take the format of `sql.database_name`. However, the alias name is completely customizable via a prefix parameter or an alias name format function (or both!).

### Utility Functions

#### sqlclUpdater
<details>
This function will download the latest version of Oracle SQLcl and unzip it into a given directory. The specific version of SQLcl downloaded is unzipped into a child directory or the given directory with the name of the SQLcl version. It additionally creates a symlink called 'latest' that points to the most recently downloaded version of SQLcl. You can also specify to create a symlink called 'live' that points to the most recently downloaded version of SQLcl as well as specify the number of versions of SQLcl to keep.

If you do not specify the directory to use for SQLcl downloads, `/opt/sqlcl` will be used. The `/opt` directory usually requires root permissions. Best practice would be to create the `/opt/sqlcl` directory and set the group permissions to allow for write and make sure you are a member of the group. Then you can work on SQLcl versions (update symlinks, download new versions, etc) without needing to use `sudo`.
</details>

#### sqlclConnectHelper
<details>
This function is a wrapper around the SQLcl CLI program. SQLcl uses the same connection syntax as SQLPlus, which is not super friendly to scripting. So, the `sqlclConnectHelper` function provides a unix-style parameter driven command line experience and then calls SQLcl with the provided information converted to a format that SQLcl understands.

For instance, a SQLcl connection may look like this:
```shell
sql -L -noupdates my_user/my_password@my_database
```

However, with the `sqlclConnectHelper` function, instead the connection could be made in any of the following ways:
```shell
sqlclConnectHelper -Lzu my_user -p my_password -i my_database
sqlclConnectHelper -L -z -u my_user -p my_password -i my_database
sqlclConnectHelper -zLi my_database -u my_user -p my_password
```

Which allows information to be given in any order.

This wrapper script is used by the aliases generated by the `sqlclGenerateOIDAliases` and `sqlclGenerateTNSAliases` functions. This is necessary because the aliases are for known database connect identifiers, but the username is not specified until the user invokes the alias. Because this is backwards from the format expected by SQLcl (`user@database`), the helper script is used.

The wrapper script provides all the same functionality as the base SQLcl CLI program, though it uses all single letter options, so it is not an exact mapping. To see all the options for the `sqlclConnectHelper` function, simply run:
```shell
sqlclConnectHelper -h
```
</details>

#### sqlclGenerateOIDAliases
<details>
This function outputs aliases for database connections collected from a provided OID LDAP server along with an additional header about the parameters used to generate the aliases.

The function accepts various information about the OID LDAP server to query as well as optional parameters of the SQLcl binary to use, the name of a custom function that prints to standard output additional aliases based on each database, as well as the name of a custom function that prints to standard output the alias to use for a given database connection alias.

Given that some LDAP servers limit the number of entities returned by the anonymous user, this function does not attempt to query all the available information in a single query call. Instead, it will first query all of the contexts (how databases are organized in an OID LDAP server). Then, the function will query each context individually for all the databases in that context. The function does the database queries in the background so they all may be done in parallel in order to improve performance. However, depending on the number of contexts and databases, this function may still take a little bit of time to run. With approximately 1100 databases spread across 80 contexts, the function takes approximately 50 seconds to run.

Additionally, the generated aliases set the `LDAPCON` variable that SQLcl uses for LDAP lookups for the specific connection. This way, if you have multiple LDAP servers, you do not have to manually update the `LDAPCON` variable when trying to connect to a database in a different LDAP.
</details>

#### sqlclGenerateTNSAliases
<details>
This function outputs aliases for database connections collected from a provided TNS names file or cloud wallet along wtih an additional header about the parameters used to generate the aliases.

The function accepts either a tnsnames.ora file in the standard oracle location, a file path pointing to a TNS names file, or a file path pointing to a cloud wallet zip file. It also optionally accepts parameters for the SQLcl binary to use, the name of a custom function that prints to standard output additional aliases based on each database, as well as the name of a custom function that prints to standard output the alias to use for a given database connection alias.
</details>

## Requirements
- A ZSH or BASH shell
- SQLcl

## Installation

### Manual installation (ZSH)
```shell
git clone 'https://github.com/jasonlyle88/sqlcl-utilities' "${XDG_CONFIG_HOME:-${HOME}}/sqlcl-utilities"
echo 'source "${XDG_CONFIG_HOME:-${HOME}}/sqlcl-utilities/sqlcl-utilities.plugin.zsh"' >> "${HOME}/.zshrc"
source "${XDG_CONFIG_HOME:-${HOME}}/sqlcl-utilities/sqlcl-utilities.plugin.zsh"
```

### Manual installation (BASH)
```shell
git clone 'https://github.com/jasonlyle88/sqlcl-utilities' "${XDG_CONFIG_HOME:-${HOME}}/sqlcl-utilities"
echo 'source "${XDG_CONFIG_HOME:-${HOME}}/sqlcl-utilities/sqlcl-utilities.plugin.bash"' >> "${HOME}/.bashrc"
source "${XDG_CONFIG_HOME:-${HOME}}/sqlcl-utilities/sqlcl-utilities.plugin.bash"
```

### Installation with ZSH package managers

#### [Antidote](https://getantidote.github.io/)
Add `jasonlyle88/sqlcl-utilities` to your plugins file (default is `~/.zsh_plugins.txt`)

#### [Oh-My-Zsh](https://ohmyz.sh/)
```shell
git clone 'https://github.com/jasonlyle88/sqlcl-utilities' "${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}/plugins/sqlcl-utilities"
omz plugin enable sqlcl-utilities
```

#### Others
This should be compatible with other ZSH frameworks/package managers, but I have not tested them. If you have tested this plugin with another package manager, feel free to create a merge request and add the instructions here!

## Usage

### Additional alias generation functions
If you want to generate additional aliases, both the `sqlclGenerateOIDAliases` and `sqlclGenerateTNSAliases` functions accept function names that will be called for every database that is processed. The `sqlclGenerateOIDAliases` and `sqlclGenerateTNSAliases` both accept the function name through the `-a` parameter, but both provide slightly different information to your function. Below is the information provided by the functions:

- `sqlclGenerateOIDAliases`
    - Alias prefix (from the `-p` parameter)
    - Alias name (Default alias name or the result of the `-f` alias format function)
    - LDAP Context (lowercase)
    - Database name (lowercase)
    - Database connect string
- `sqlclGenerateTNSAliases`
    - Alias prefix (from the `-p` parameter)
    - Alias name (Default alias name or the result of the `-f` alias format function)
    - Net service name
    - Cloud config zip file (absolute path) (if cloud config wallet)

An example where this is useful would be if you have APEX set up in each of the databases and want to be able to open the APEX builder in your browser of choice. This could be accomplished like the following example:
<details>

```shell
function generateAPEXAliases() {
    local prividedAliasPrefix="${1}"
    local providedAliasName="${2}"
    local netServiceName="${3}"
    local cloudConfigZip="${4}"

    local cloudConfigFilename="$(basename "${cloudConfigZip}" '.zip')"
    local apexUrl
    local additionalAliasName
    local browserBinary='/Applications/Firefox.app/Contents/MacOS/firefox'

    # Figure out the base of the URL based on the wallet
    if [[ "${cloudConfigFilename}" == 'Wallet_myatp1' ]]; then
        apexUrl='https://g86c945163ece5c-myatp1.adb.us-ashburn-1.oraclecloudapps.com/ords/r/apex'
    elif [[ "${cloudConfigFilename}" == 'Wallet_myatp2' ]]; then
        apexUrl='https://g86c945163ece5c-myatp2.adb.us-ashburn-1.oraclecloudapps.com/ords/r/apex'
    fi

    # Replace "sql." with "apex." in the provided alias name
    additionalAliasName="apex.${providedAliasName#"sql."}"

    # Anything sent to standard out will be included with your generated alias file
    printf 'alias %s="%s %s"\n' \
        "${additionalAliasName}" \
        "${browserBinary}" \
        "${apexUrl}"
}

sqlclGenerateTNSAliases \
    -p 'sql.myatp1.' \
    -a 'generateAPEXAliases' \
    -c "${TNS_ADMIN}/wallets/Wallet_myatp1.zip"

sqlclGenerateTNSAliases \
    -p 'sql.myatp2.' \
    -a 'generateAPEXAliases' \
    -c "${TNS_ADMIN}/wallets/Wallet_myatp2.zip"
```

</details>

### Alias name formatting functions
By default, aliases are generated as `sql.database_name`, but this may not be your desired format. If you want just a static string before the `database_name` in the alias, then the `-p` parameter provides this functionality. Otherwise, the the `sqlclGenerateOIDAliases` and `sqlclGenerateTNSAliases` both accept the `-f` parameter that takes in a function that gives you complete control over how the alias is formatted. However, each plugin function provides slightly different information to your format function. Below is the information provided by the functions:

- `sqlclGenerateOIDAliases`
    - Alias prefix (from the `-p` parameter)
    - LDAP Context (lowercase)
    - Database name (lowercase)
    - Database connect string
- `sqlclGenerateTNSAliases`
    - Alias prefix (from the `-p` parameter)
    - Net service name
    - Cloud config zip file (absolute path) (if cloud config wallet)

Examples of where this is useful is if you are using a TNS names file you don't control or and LDAP server and you want to programattically change the names that are used for the databases. Here is an example:
<details>

```shell
function formatLdapAliasNames() {
    local aliasPrefix="${1}"
    local contextName="${2}"
    local databaseName="${3}"
    local databaseConnectIdentifier="${4}"

    local prefix='work_db_prefix'
    local aliasName="${aliasPrefix}"

    # Add the database group (context) after the standard prefix
    aliasName="${aliasName}${contextName}."

    # Add the environment designator (DEV or QA) after the database group
    # (context) and before the database name
    if [[ "${databaseName}" == *'-dev' ]]; then
        aliasName="${aliasName}dev."
    elif [[ "${databaseName}" == *'-qa' ]]; then
        aliasName="${aliasName}qa."
    fi

    # Add the database name without the environment designator (DEV or QA) to
    # to the end of the alias name
    if [[ "${databaseName}" == *'-dev' ]]; then
        aliasName="${aliasName}${databaseName%????}"
    elif [[ "${databaseName}" == *'-qa' ]]; then
        aliasName="${aliasName}${databaseName%???}"
    fi

    # Output the alias name for the generation script to use
    printf '%s\n' "${aliasName}"
}

sqlclGenerateOIDAliases \
    -p 'sql.work.dev.' \
    -f 'formatLdapAliasNames' \
    -H 'ldap-dev.work.com' \
    -B 'dc=work,dc=com'

sqlclGenerateOIDAliases \
    -p 'sql.work.qa.' \
    -f 'formatLdapAliasNames' \
    -H 'ldap-qa.work.com' \
    -B 'dc=work,dc=com'
```

</details>

### EVAL or SOURCE
Because the `sqlclGenerateOIDAliases` and `sqlclGenerateTNSAliases` functions output their information to standard output, the data must be captured and used. There are two general ways to do this:

- Immediately run the output information with the `eval` command
- Store the output information in a file and use the `source` command to load the contents of that file into your current session.

#### EVAL
Using `eval` will immediately evaluate all the generated aliases, but those aliases are not saved for future terminals to use. This means that your aliases are the most up to date since they were parsed directly and added to your session; however it also means that the `sqlclGenerateOIDAliases` or `sqlclGenerateTNSAliases` functions must be run every time you start a new terminal session since the aliases are not saved anywhere.

This can generically be accomplished by doing the following:
```shell
eval "$([GENERATION_FUNCTION_INVOCATION])"
```
Where `[GENERATION_FUNCTION_INVOCATION]` is an invocation of `sqlclGenerateOIDAliases` or `sqlclGenerateTNSAliases` with parameters appropriate for what you want to generate.

A specific example is:
```shell
eval "$(sqlclGenerateTNSAliases -T -p 'sql.tns.')"
```
Which will load aliases for a `tnsnames.ora` file in the standard location oracle expects with a prefix of `sql.tns.`.

#### SOURCE
Using `source` requires you first save the aliases in a file that can then be loaded into your terminal session over and over again without having to run the `sqlclGenerateOIDAliases` or `sqlclGenerateTNSAliases` functions again. This allows for faster loading of your aliases since they don't need to be generated, but it also means that your aliases could be out of date if it has been a while since you ran the generation functions.

This can generically be accomplished by doing the following:
```shell
[GENERATION_FUNCTION_INVOCATION] > ~/tnsnames_aliases.sh
source ~/tnsnames_aliases.sh
```

A specific example is:
```shell
sqlclGenerateTNSAliases -T -p 'sql.tns.' > ~/tnsnames_aliases.sh
source ~/tnsnames_aliases.sh
```

Then, whenever you start a new terminal, you just need to run:
```shell
source ~/tnsnames_aliases.sh
```
and all the generated aliases will be available to you again in your new terminal session.

### Automatically adding aliases to your terminal session
If you want your aliases to be available as soon as your terminal loads, you can add code to your `.bashrc`, `.bash_profile`, `.zshrc`, or any file you run when your shell starts. This will be specific to your machine and which file to use is outside the scope of this document. There are tons of resources avialable if your google it though!

Using the `eval` method in such a file will provide the most up to date aliases but may slow down your terminal starting up. If you create and `eval` with a call to `sqlclGenerateOIDAliases` that takes 30 seconds, then you are adding 30 seconds to your shell startup before you are able to use your terminal.

Using the `source` method, you only need to put the `source` command in your startup file. This will be very fast, but your aliases may be out of date if the database inormation has changed. To update the information, the generation functions will need to be run again (in our example, `sqlclGenerateTNSAliases -T -p 'sql.tns.' > ~/tnsnames_aliases.sh`).

### My approach
I personally use the source approach because my OID LDAP generation can take a while. In order to make updating the file containing the generated aliases easier, I create a function that generates the aliases for me. In order to accomplish this, I add the following to my `.zshrc` file:
```shell
export SQLCL_ALIAS_FILE="${HOME}/.config/sqlclAliases.sh"

function generateSqlclAliases() {
    sqlclGenerateTNSAliases -T > "${SQLCL_ALIAS_FILE}"

    sqlclGenerateTNSAliases -c "${TNS_ADMIN}/wallets/Wallet_db1.zip" -p 'sql.db1.' >> "${SQLCL_ALIAS_FILE}"

    sqlclGenerateTNSAliases -c "${TNS_ADMIN}/wallets/Wallet_db2.zip" -p 'sql.db2.' >> "${SQLCL_ALIAS_FILE}"

    sqlclGenerateOIDAliases -h "${WORK_DATABASE_LDAP_HOST}" -p 'sql.work.' >> "${SQLCL_ALIAS_FILE}"

    source "${SQLCL_ALIAS_FILE}"
}

if [[ -f "${SQLCL_ALIAS_FILE}" ]]; then
    source "${SQLCL_ALIAS_FILE}"
fi
```

This allows all my new terminal sessions to automatically have all my SQLcl aliases loaded from the last time they were generated. And any time I need to refresh the alias generation, I just run the `generateSqlclAliases` function.
