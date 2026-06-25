#!/usr/bin/env bash

# folder that stores descriptions of the models avaliable from each service
service_descriptions_folder="/home/henry/DESY_sync/Documents/Assistant/service_descriptions"

get_password() {
    local db=~/Accounts/passwordManager/API_keys.kdbx
    keepassxc-cli show -a Password "$db" $1
}

# usage;
# make a dict with your desired services
# local -A api_key_dict=( ["service1"]="" ["service2"]="" ...)
# pass it to the fuction
# _get_api_keys api_key_dict
# function will put the api in each dict entry if found in the password manager
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

# Takes a dict of API keys (built by _get_api_keys) and returns the flags string.
# Usage: _get_api_key_flags api_key_dict
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

# Takes a service name and an api key and returns the description of the models from the provider
# Usage: get_current_description service api_key
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

# get the last model description from the service_descriptions_folder
# usage get_last_description service
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


# Takes a dict of API keys (built by _get_api_keys) and checks the last descriptions match the current ones
# updates if needed, and echos all the services that are updated
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


# function that extracts a list of model names from a json string
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


# Autocomplete function for both aider_desy and aider_blablador
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
