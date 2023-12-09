# Standardized $0 handling
# https://wiki.zshell.dev/community/zsh_plugin_standard#zero-handling
0="${ZERO:-${${0:#$ZSH_ARGZERO}:-${(%):-%N}}}"
0="${${(M)0:#/*}:-$PWD/$0}"

declare sqlclConnectionAliasGeneratorsPluginDirectory="${0:h}"

function () {
    # Standardize options
    # https://wiki.zshell.dev/community/zsh_plugin_standard#standard-recommended-options
    builtin emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
    builtin setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd

    local binDirectory
    local file

    binDirectory="${sqlclConnectionAliasGeneratorsPluginDirectory}/bin"

    for file in "${binDirectory}"/*.sh; do
        source "${file}"
    done
}

unset sqlclConnectionAliasGeneratorsPluginDirectory
