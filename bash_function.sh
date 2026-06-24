#!/usr/bin/env bash

get_password() {
    local db=~/Accounts/passwordManager/API_keys.kdbx
    keepassxc-cli show -a Password "$db" $1
}


get_api_key_flags() {
    local db=~/Accounts/passwordManager/API_keys.kdbx
    local password
    password=$(systemd-ask-password "KeePassXC password: ")

    # Enforce mutual exclusivity between desy and blablador
    local has_desy=0
    local has_blablador=0
    for name in "$@"; do
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
    for name in "$@"; do
        local key
        key=$(echo "$password" | keepassxc-cli show -q -a Password "$db" "$name" 2>/dev/null)
        # Throw a sensible error if we don't get a key
        if [[ -z "$key" ]]; then
            echo "Error: failed to retrieve API key for '$name'." >&2
            return 1
        fi
        case "$name" in
            anthropic)   flags="$flags --anthropic-api-key=$key" ;;
            blablador)   flags="$flags --openai-api-key=$key" ;;
            desy)        flags="$flags --openai-api-key=$key" ;;
            *)           flags="$flags --${name}-api-key=$key" ;;
        esac
    done

    echo "${flags# }"  # trim leading space
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
       echo "Don't have a url for service named <$1>"
       return 1
   fi
   echo $url
}

# list of available BLABLADOR models from (blablador_description.json)
BLABLADOR_MODELS=(
    "apertus"
    "eve"
    "fast"
    "huge"
    "large"
    "code"
    "embeddings"
    "qwen3-8b-embeddings"
    "qwen36-35b"
    "kimi-k2.7-code"
    "minimax-m3"
    "mis"
    "qwen-huge"
)

# List of available DESY models (from desy_description.json)
DESY_MODELS=(
    "desy-assistant"
    "reasoning"
    "coding"
    "it-uco"
    "maxwell"
    "maxwell-cssb-cryoem"
    "naf"
    "dcache-docs"
)

# Autocomplete function for both aider_desy and aider_blablador
_aider_models_complete() {
    local cur cmd models
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    cmd="${COMP_WORDS[0]}"

    if [[ "$cmd" == "aider_desy" ]]; then
        models=("${DESY_MODELS[@]}")
    elif [[ "$cmd" == "aider_blablador" ]]; then
        models=("${BLABLADOR_MODELS[@]}")
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


    local flags
    flags=$( get_api_key_flags $service )
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

    local flags
    flags=$( get_api_key_flags $service )
    aider $flags \
        --openai-api-base=$( get_service_url $service )\
        --model="openai/${model}"\
        --no-auto-commits \
        --watch-files \
        --read CONVENTIONS.md \
        --vim \
        "$@"
}
