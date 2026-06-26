#!/usr/bin/env bash

# =============================================================================
# Script: bash_function.sh
# Description: Helper functions for interacting with AI model services (DESY,
#              Blablador) via the 'aider' tool. Includes API key retrieval,
#              model description caching, autocomplete, and wrapper commands.
# =============================================================================

# folder that stores descriptions of the models avaliable from each service
service_descriptions_folder="/home/henry/DESY_sync/Documents/Assistant/service_descriptions"
aider_repository_dir="home/henry/DESY_sync/Documents/Assistant/aider_repo"

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
            claude)   flags="$flags --anthropic-api-key=$key" ;;
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

    # Build curl arguments
    local curl_args=(-s "$models_url" -H "Authorization: Bearer $key")
    if [[ "$service" == "claude" ]]; then
        curl_args+=(-H "x-api-key: $key")
        curl_args+=(-H "anthropic-version: 2023-06-01")
    else
        curl_args+=(-H "Authorization: Bearer $key")
    fi

    local description=$( curl "${curl_args[@]}" )
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

        echo "Not updating claude without explicit instructions due to token cost"
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
       claude)      url="https://api.anthropic.com/v1/" ;;
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
#              Autocomplete is provided for up to 3 positional arguments.
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

    # Add all models for claude (always available)
    local claude_models=$(extract_model_names "claude" 2>/dev/null) || true
    if [[ -n "$claude_models" ]]; then
        models+=($claude_models)
    fi

    # Autocomplete up to 3 positional arguments (model names)
    if [[ $COMP_CWORD -ge 1 && $COMP_CWORD -le 3 ]]; then
        COMPREPLY=( $(compgen -W "${models[*]}" -- "$cur") )
        return 0
    fi
}

# Register autocomplete for both commands
complete -F _aider_models_complete aider_desy aider_blablador


# consider leaving these to .aider.conf.yml
_aider_default_flags() {
    echo "  --no-auto-commits \
            --watch-files \
            --dark-mode \
            --editor vim \
            --shell-completions bash \
            --read CONVENTIONS.md \
            --vim "
}


# Check to see if confs are found
check_for_aider_confs() {
    _git_root=$(git rev-parse --show-toplevel 2>/dev/null)

    if [ ! -f ~/.aider.conf.yml ] \
      && { [ -z "$_git_root" ] || [ ! -f "$_git_root/.aider.conf.yml" ]; } \
      && [ ! -f ./.aider.conf.yml ]; then
      echo "No .aider.conf.yml found in any expected location"
      echo "Did you pass one as a flag?"
      echo "Otherwise, consider applying default_aider_flags"
    fi

    if [ ! -f ~/.aider.model.settings.yml ] \
      && { [ -z "$_git_root" ] || [ ! -f "$_git_root/.aider.model.settings.yml" ]; } \
      && [ ! -f ./.aider.model.settings.yml ]; then
      echo "No .aider.model.settings.yml found in any expected location"
      echo "Did you pass one as a flag?"
    fi
}

_aider_chat_flags() {
    local chat_scale="${1:-5}"
    if ! [[ "$chat_scale" =~ ^([0-9]|10)$ ]]; then
        echo "Error: chat_scale must be an integer 0-10" >&2
        return 1
    fi

    # continuous values: linear ramps
    local history_tokens=$(( chat_scale * 4000 ))   # 0 .. 40k
    local thinking_tokens=$(( chat_scale * 3200 ))  # 0 .. 32k

    # reasoning-effort is ENUMERATED, not continuous -> bucket it
    local effort
    if   (( chat_scale <= 3 )); then effort="low"
    elif (( chat_scale <= 7 )); then effort="medium"
    else                             effort="high"
    fi

    echo "--max-chat-history-tokens ${history_tokens} --thinking-tokens ${thinking_tokens} --reasoning-effort ${effort}"
}

_aider_map_flags() {
    local map_scale="${1:-5}"
    if ! [[ "$map_scale" =~ ^([0-9]|10)$ ]]; then
        echo "Error: map_scale must be an integer 0-10" >&2
        return 1
    fi

    # scale 0 disables the repo map entirely
    if (( map_scale == 0 )); then
        echo "--map-tokens 0"
        return 0
    fi

    local map_tokens=$(( map_scale * 1024 ))        # 1k .. 10k (default is 1024)
    # multiplier (default 2) ramps 1->4 across the range
    local multiplier=$(( 1 + (map_scale - 1) * 3 / 9 ))

    echo "--map-tokens ${map_tokens} --map-multiplier-no-files ${multiplier}"
}

_aider_cache_flags() {
    local cache_variant="${1:-cache}"   # note: "variant" not "varient"
    case "$cache_variant" in
        cache)    echo "--cache-prompts --cache-keepalive-pings 2" ;;  # ~30 min warm
        no-cache) echo "--no-cache-prompts" ;;
        *) echo "Error: cache variant must be 'cache' or 'no-cache'" >&2; return 1 ;;
    esac
}



# ---------------------------------------------------------------------------
# _get_model_flags_by_service
# Description: Takes a default service name (desy or blablador) and up to 3
#              model names. Models can be from the default service or from
#              claude. Formats them into --model, --weak-model, --editor-model
#              flags with appropriate defaults from the default service.
# Usage:       _get_model_flags_by_service <service> [model1] [model2] [model3]
# Arguments:   $1 - Service name ('desy' or 'blablador').
#              $2..$4 - Up to 3 model names (optional). Arguments starting
#                       with '-' are treated as flags and stop positional parsing.
# Returns:     Prints the flags string to stdout.
# ---------------------------------------------------------------------------
_get_model_flags_by_service() {
    local service="$1"
    shift

    # Collect up to 3 positional model arguments (non-flag)
    local models=()
    while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
        models+=("$1")
        shift
        if [[ ${#models[@]} -eq 3 ]]; then
            break
        fi
    done

    # Set defaults based on service
    local default_model default_weak default_editor
    case "$service" in
        desy)
            default_model="reasoning"
            default_weak="desy-assistant"
            default_editor="coding"
            ;;
        blablador)
            default_model="huge"
            default_weak="fast"
            default_editor="code"
            ;;
        *)
            echo "Error: unknown service '$service'" >&2
            return 1
            ;;
    esac

    # Retrieve claude model names for cross-service detection
    local -a claude_models=()
    while IFS= read -r line; do
        claude_models+=("$line")
    done < <(extract_model_names "claude" 2>/dev/null || true)

    # Helper: check if a model name belongs to claude
    _is_claude_model() {
        local name="$1"
        # Exact match against known claude model IDs
        for cm in "${claude_models[@]}"; do
            if [[ "$cm" == "$name" ]]; then
                return 0
            fi
        done
        # Fallback heuristic: name contains "claude" (case-insensitive)
        if [[ "${name,,}" == *claude* ]]; then
            return 0
        fi
        return 1
    }

    # Build the three model flags
    local model="${models[0]:-$default_model}"
    local weak="${models[1]:-$default_weak}"
    local editor="${models[2]:-$default_editor}"

    local model_flag weak_flag editor_flag

    # --model
    if _is_claude_model "$model"; then
        model_flag="--model=anthropic/${model}"
    else
        if [[ "$service" == "blablador" ]]; then
            model_flag="--model=openai/alias-${model}"
        else
            model_flag="--model=openai/${model}"
        fi
    fi

    # --weak-model
    if _is_claude_model "$weak"; then
        weak_flag="--weak-model=anthropic/${weak}"
    else
        if [[ "$service" == "blablador" ]]; then
            weak_flag="--weak-model=openai/alias-${weak}"
        else
            weak_flag="--weak-model=openai/${weak}"
        fi
    fi

    # --editor-model
    if _is_claude_model "$editor"; then
        editor_flag="--editor-model=anthropic/${editor}"
    else
        if [[ "$service" == "blablador" ]]; then
            editor_flag="--editor-model=openai/alias-${editor}"
        else
            editor_flag="--editor-model=openai/${editor}"
        fi
    fi

    echo "$model_flag $weak_flag $editor_flag"
}

# ---------------------------------------------------------------------------
# _aider_openai
# Description: Common logic for running aider with an OpenAI-compatible service
#              (DESY or Blablador). Takes a service name and up to 3 model
#              names, then any additional aider flags.
# Usage:       _aider_openai <service> [model1] [model2] [model3] [aider options...]
# Arguments:   $1 - Service name ('desy' or 'blablador').
#              $2..$4 - Up to 3 model names (optional). Arguments starting
#                       with '-' are treated as flags and stop positional parsing.
#              $@ - Additional arguments forwarded to 'aider'.
# Returns:     Exits with the return code of the 'aider' command.
# ---------------------------------------------------------------------------
_aider_openai() {
    local openai_service="$1"
    shift

    check_for_aider_confs

    # Build the API keys dict and retrieve keys
    local -A api_key_dict=( ["$openai_service"]="" ["claude"]="" )
    _get_api_keys api_key_dict || return 1
    _check_update_descriptions api_key_dict

    local flags
    flags=$( _get_api_key_flags api_key_dict ) || return 1
    flags+=" --openai-api-base="$( get_service_url $openai_service )" "

    # Collect up to 3 positional model arguments (non-flag)
    local models=()
    while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
        models+=("$1")
        shift
        # Stop after collecting 3
        if [[ ${#models[@]} -eq 3 ]]; then
            break
        fi
    done

    flags+=$( _get_model_flags_by_service "$openai_service" "${models[@]}" )
    flags+="$@"

    conda activate aider
    PYTHONPATH=${PYTHONPATH}:${aider_repository_dir} python -m aider $flags
}


# ---------------------------------------------------------------------------
# aider_blablador
# Description: Wrapper around the 'aider' tool configured for the Blablador
#              service. Automatically retrieves the API key, checks for model
#              description updates, and passes appropriate flags.
# Usage:       aider_blablador [model1] [model2] [model3] [aider options...]
#              Up to 3 positional model names can be given (non-flag arguments).
#              They are assigned to --model, --weak-model, --editor-model
#              respectively. Defaults: --model=huge, --weak-model=fast,
#              --editor-model=code. The 'alias-' prefix is automatically
#              prepended to each model name.
# Arguments:   $1..$3 - Model names (optional). Arguments starting with '-'
#                       are treated as flags and stop positional parsing.
#              $@ - Additional arguments forwarded to 'aider'.
# Returns:     Exits with the return code of the 'aider' command.
# ---------------------------------------------------------------------------
aider_blablador() {
    _aider_openai blablador "$@"
}


# ---------------------------------------------------------------------------
# aider_desy
# Description: Wrapper around the 'aider' tool configured for the DESY service.
#              Automatically retrieves the API key, checks for model description
#              updates, and passes appropriate flags.
# Usage:       aider_desy [model1] [model2] [model3] [aider options...]
#              Up to 3 positional model names can be given (non-flag arguments).
#              They are assigned to --model, --weak-model, --editor-model
#              respectively. Defaults: --model=reasoning,
#              --weak-model=desy-assistant, --editor-model=coding.
# Arguments:   $1..$3 - Model names (optional). Arguments starting with '-'
#                       are treated as flags and stop positional parsing.
#              $@ - Additional arguments forwarded to 'aider'.
# Returns:     Exits with the return code of the 'aider' command.
# ---------------------------------------------------------------------------
aider_desy() {
    _aider_openai desy "$@"
}
