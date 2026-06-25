#!/usr/bin/env bash

# =============================================================================
# Script: bash_function.sh
# Description: Helper functions for interacting with AI model services (DESY,
#              Blablador) via the 'aider' tool. Includes API key retrieval,
#              model description caching, autocomplete, and wrapper commands.
# =============================================================================

# folder that stores descriptions of the models avaliable from each service
service_descriptions_folder="/home/henry/DESY_sync/Documents/Assistant/service_descriptions"

# ---------------------------------------------------------------------------
# get_password
# Description: Retrieves a password for a given entry from a KeePassXC database.
# Usage:       get_password <entry_name>
# Arguments:   $1 - Name of the entry in the KeePassXC database.
# Returns:     Prints the password to stdout.
# Notes:       Prompts for the KeePassXC master password via KeePassXC
# ---------------------------------------------------------------------------
get_password() {
    local db=~/Accounts/passwordManager/API_keys.kdbx
    keepassxc-cli show -a Password "$db" $1
}

# ---------------------------------------------------------------------------
# _get_api_keys
# Description: Fills a caller-provided associative array with API keys for
#              given service names, retrieving them from a KeePassXC database.
# Usage:       _get_api_keys <array_name>
#              The array must be declared in the caller with keys = service names
#              and empty values. After the call, each value is set to the key.
# Arguments:   $1 - Name of the associative array (passed by nameref).
# Returns:     0 on success, 1 if any key retrieval fails.
# Notes:       Prompts for the KeePassXC master password via systemd-ask-password.
# ---------------------------------------------------------------------------
_get_api_keys() {
    declare -n _callers_dict="$1"
    local db=~/Accounts/passwordManager/API_keys.kdbx
    local password
    password=$(systemd-ask-password "KeePassXC password: ")

    for service in "${!_callers_dict[@]}"; do
        local api_key
        api_key=$(echo "$password" | keepassxc-cli show -q -a Password "$db" "$service" 2>/dev/null)
        # Throw a sensible error if we don't get a key
        if [[ -z "$api_key" ]]; then
            echo "Error: failed to retrieve API key for '$service'." >&2
            return 1
        fi
        # add to the api_keys dict
        _callers_dict[$service]=$api_key
    done
}

# ---------------------------------------------------------------------------
# _get_api_key_flags
# Description: Converts an associative array of service→API key pairs into a
#              string of command-line flags suitable for the 'aider' tool.
# Usage:       _get_api_key_flags <array_name>
# Arguments:   $1 - Name of the associative array (passed by nameref).
# Returns:     Prints the flags string to stdout, or an error message to stderr
#              and returns 1 if 'desy' and 'blablador' are both present.
# Notes:       Enforces mutual exclusivity between 'desy' and 'blablador'.
#              Prompts for the KeePassXC master password via systemd-ask-password.
# ---------------------------------------------------------------------------
_get_api_key_flags() {
    declare -n _keys_dict="$1"

    # Enforce mutual exclusivity between desy and blablador
    local has_desy=0
    local has_blablador=0
    for name in "${!_keys_dict[@]}"; do
        case "$name" in
            desy) has_desy=1 ;;
            blablador) has_blablador=1 ;;
        esac
    done
    if (( has_desy && has_blablador )); then
        echo "Error: 'desy' and 'blablador' are mutually exclusive options." >&2
        return 1
    fi

    local flags=""
    for name in "${!_keys_dict[@]}"; do
        local key="${_keys_dict[$name]}"
        case "$name" in
            anthropic)   flags="$flags --anthropic-api-key=$key" ;;
            blablador)   flags="$flags --openai-api-key=$key" ;;
            desy)        flags="$flags --openai-api-key=$key" ;;
            *)           flags="$flags --${name}-api-key=$key" ;;
        esac
    done

    echo "${flags# }"  # trim leading space
}

# ---------------------------------------------------------------------------
# get_current_description
# Description: Fetches the current list of models from a given service's API
#              and prints the raw JSON response.
# Usage:       get_current_description <service> [api_key]
# Arguments:   $1 - Service name (e.g., 'desy', 'blablador').
#              $2 - Optional API key. If empty, the key is retrieved via
#                   _get_api_keys. (and prompts for password)
# Returns:     Prints the JSON description to stdout, or returns 1 on failure.
# ---------------------------------------------------------------------------
get_current_description() {
    local service="$1"
    local key="$2"
    # if key is empty, use _get_api_keys to get the key
    if [[ -z "$key" ]]; then
        local -A api_key_dict=( ["$service"]="" )
        _get_api_keys api_key_dict || return 1
        key="${api_key_dict[$service]}"
    fi

    local url=$( get_service_url "$service" )
    # Append /models to get the list of available models
    local models_url="${url}models"
    local description=$( curl -s "$models_url" -H "Authorization: Bearer $key" )
    echo "$description"
}

# ---------------------------------------------------------------------------
# get_last_description
# Description: Retrieves the most recently saved model description file for a
#              given service from the service_descriptions_folder.
# Usage:       get_last_description <service>
# Arguments:   $1 - Service name (used to match file prefix).
# Returns:     Prints the file contents to stdout, or an error message to
#              stderr and returns 1 if no file is found.
# Notes:       Files are named <service>_YYYY-MM-DD-HH.json. The most recent
#              is determined by sorting the filename suffix (not file mtime).
# ---------------------------------------------------------------------------
get_last_description() {
    local service="$1"
    # in the service_descriptions_folder there are a bunch of files with the format ${service}_YYYY-MM-DD-HH.json, I want the most recent
    # find this by the date and time on the file name, not by the date the file was last edited
    local recent_file
    recent_file=$( ls -1 "$service_descriptions_folder"/"${service}"_*.json 2>/dev/null | sort -t_ -k2 -r | head -n1 )
    if [[ -z "$recent_file" ]]; then
        echo "Error: no description files found for service '$service' in $service_descriptions_folder" >&2
        return 1
    fi
    cat "$recent_file"
}

# ---------------------------------------------------------------------------
# _check_update_descriptions
# Description: Compares the current model description (fetched from the API)
#              with the last saved description for each service. If they differ,
#              saves the new description and prints a notification.
# Usage:       _check_update_descriptions <array_name>
# Arguments:   $1 - Name of the associative array (service→key) passed by nameref.
# Returns:     Prints messages to stdout for any updated services.
# Notes:       Timestamps in the JSON are stripped before comparison to avoid
#              false positives.
# ---------------------------------------------------------------------------
_check_update_descriptions() {
    declare -n _keys_dict="$1"
    for service in "${!_keys_dict[@]}"; do
        local key="${_keys_dict[$service]}"
        local current_description
        current_description=$( get_current_description "$service" "$key" )
        # prettyify
        current_description=$( echo $current_description | python3 -m json.tool )
        local last_description
        last_description=$( get_last_description "$service" 2>/dev/null ) || true
        # check if they match
        # some timestamps get updated with every call, so this is a safe comparison function
        local stripped_current=$(echo $current_description | grep -v '[0-9]\{10\}')
        local stripped_last=$(echo $last_description | grep -v '[0-9]\{10\}')
        if [[ "$stripped_current" != "$stripped_last" ]]; then
            # if they don't match, write a new last description and echo the service name
            local timestamp
            timestamp=$( date +%Y-%m-%d-%H )
            local filename="${service_descriptions_folder}/${service}_${timestamp}.json"
            echo "$current_description" > $filename
            echo "Description has changed for ${service}"
        fi
    done
}

# ---------------------------------------------------------------------------
# check_update_descriptions
# Description: Public wrapper around _check_update_descriptions. Accepts a list
#              of service names, retrieves their API keys, and updates the
#              cached descriptions if needed.
# Usage:       check_update_descriptions [service1 service2 ...]
#              If no arguments are given, defaults to 'desy' and 'blablador'.
# Arguments:   $@ - Zero or more service names.
# Returns:     Prints messages to stdout for any updated services.
# ---------------------------------------------------------------------------
check_update_descriptions() {
    # if there are arguments, make them into a dict with blank keys
    local -A key_dict=()
    for service in "$@"; do
        key_dict["$service"]=""
    done

    if [[ ${#key_dict[@]} -eq 0 ]]; then
        key_dict["desy"]=""
        key_dict["blablador"]=""
    fi

    _get_api_keys key_dict

    _check_update_descriptions key_dict
}

# ---------------------------------------------------------------------------
# get_service_url
# Description: Returns the base URL for a given service's API.
# Usage:       get_service_url <service>
# Arguments:   $1 - Service name ('blablador' or 'desy').
# Returns:     Prints the URL to stdout, or an error message to stderr and
#              returns 1 if the service is unknown.
# ---------------------------------------------------------------------------
get_service_url() {
   if [[ -z "$1" ]]; then
       echo "Must give a service name"
       return 1
   fi
   local url=""
   case "$1" in
       blablador)   url="https://api.helmholtz-blablador.fz-juelich.de/v1/" ;;
       desy)        url="https://assistant.desy.de/api/" ;;
   esac
   if [[ -z "$url" ]]; then
       echo "Don't have a url for service named "
       return 1
   fi
   echo $url
}

# ---------------------------------------------------------------------------
# extract_model_names
# Description: Extracts the list of model IDs from the last saved description
#              JSON for a given service.
# Usage:       extract_model_names <service>
# Arguments:   $1 - Service name.
# Returns:     Prints each model ID on its own line to stdout.
# Notes:       Uses Python to parse the JSON and extract the 'id' field from
#              each object in the 'data' array.
# ---------------------------------------------------------------------------
extract_model_names() {
    local last_description=$( get_last_description "$1" )
    # Use python3 to parse the JSON and extract all "id" values from the data array
    local model_names=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
for item in data.get('data', []):
    print(item.get('id', ''))
    " <<< "$last_description")
    echo $model_names
}

# ---------------------------------------------------------------------------
# _aider_models_complete
# Description: Bash completion function for the 'aider_desy' and
#              'aider_blablador' commands. Provides model name suggestions.
# Usage:       This function is used internally by the 'complete' builtin.
#              It is registered via: complete -F _aider_models_complete ...
# Arguments:   Standard completion arguments (COMP_WORDS, COMP_CWORD, etc.).
# Returns:     Sets COMPREPLY with matching model names.
# Notes:       For 'aider_desy' it lists all models from the DESY service.
#              For 'aider_blablador' it lists only models whose ID starts with
#              'alias-', stripping the prefix.
# ---------------------------------------------------------------------------
_aider_models_complete() {
    local cur cmd models
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    cmd="${COMP_WORDS[0]}"

    if [[ "$cmd" == "aider_desy" ]]; then
        local desy_models=$(extract_model_names "desy")
        models=("${desy_models[@]}")
    elif [[ "$cmd" == "aider_blablador" ]]; then
        local blablador_models=$(extract_model_names "blablador")
        # only keep the ones that start with "alias-" and trim the "alias-"
        local filtered=()
        for model in $blablador_models; do
            if [[ "$model" == alias-* ]]; then
                filtered+=("${model#alias-}")
            fi
        done
        models=("${filtered[@]}")
    else
        models=()
    fi

    # Only autocomplete the first argument (the model name)
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "${models[*]}" -- "$cur") )
        return 0
    fi
}

# Register autocomplete for both commands
complete -F _aider_models_complete aider_desy aider_blablador

# ---------------------------------------------------------------------------
# aider_blablador
# Description: Wrapper around the 'aider' tool configured for the Blablador
#              service. Automatically retrieves the API key, checks for model
#              description updates, and passes appropriate flags.
# Usage:       aider_blablador [model] [aider options...]
# Arguments:   $1 - Model name (default: 'fast'). The 'alias-' prefix is
#                   automatically prepended.
#              $@ - Additional arguments forwarded to 'aider'.
# Returns:     Exits with the return code of the 'aider' command.
# ---------------------------------------------------------------------------
aider_blablador() {
    local service="blablador"

    # First argument can specify the model to use; defaults to "fast"
    local model="${1:-fast}"
    shift

    # Build the API keys dict and retrieve keys
    local -A api_key_dict=( ["$service"]="" )
    _get_api_keys api_key_dict || return 1
    _check_update_descriptions api_key_dict

    local flags
    flags=$( _get_api_key_flags api_key_dict ) || return 1
    aider $flags \
        --openai-api-base=$( get_service_url $service ) \
        --model="openai/alias-${model}"\
        --no-auto-commits \
        --watch-files \
        --read CONVENTIONS.md \
        --vim \
        "$@"
}

#--cache-prompts \  # only works on some apis
#--no-stream \  # needed to see cache statistics and costs

# ---------------------------------------------------------------------------
# aider_desy
# Description: Wrapper around the 'aider' tool configured for the DESY service.
#              Automatically retrieves the API key, checks for model description
#              updates, and passes appropriate flags.
# Usage:       aider_desy [model] [aider options...]
# Arguments:   $1 - Model name (default: 'coding').
#              $@ - Additional arguments forwarded to 'aider'.
# Returns:     Exits with the return code of the 'aider' command.
# ---------------------------------------------------------------------------
aider_desy() {
    local service="desy"
    # First argument can specify the model to use; defaults to "coding"
    local model="${1:-coding}"
    shift

    # Build the API keys dict and retrieve keys
    local -A api_key_dict=( ["$service"]="" )
    _get_api_keys api_key_dict || return 1
    _check_update_descriptions api_key_dict

    local flags
    flags=$( _get_api_key_flags api_key_dict ) || return 1
    aider $flags \
        --openai-api-base=$( get_service_url $service )\
        --model="openai/${model}"\
        --no-auto-commits \
        --watch-files \
        --read CONVENTIONS.md \
        --vim \
        "$@"
}
