#!/usr/bin/env bash
#
# secret.sh — minimal GPG-backed secret store
#
# Usage:
#   secret.sh set <name>       Store a secret (prompts for value, or reads stdin)
#   secret.sh get <name>       Print a secret to stdout
#   secret.sh list             List stored secret names
#   secret.sh delete <name>    Remove a secret
#
# Config (optional):
#   SECRET_DIR        Storage directory   (default: ~/.secrets)
#   SECRET_GPG_KEY    GPG key/recipient   (default: symmetric passphrase mode)
#
# Examples:
#   ./secret.sh set myapp-api-key                 # interactive prompt
#   printf '%s' "sk-abc123" | ./secret.sh set myapp-api-key
#   TOKEN=$(./secret.sh get myapp-api-key)

set -euo pipefail

SECRET_DIR="${SECRET_DIR:-$HOME/.secrets}"
SECRET_GPG_KEY="${SECRET_GPG_KEY:-}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

require_name() {
    [[ -n "${1:-}" ]] || die "missing secret name (see: $0 --help)"
    # keep names filesystem-safe: alphanumerics, dash, underscore, dot
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid name '$1' (use letters, digits, . _ -)"
}

ensure_dir() {
    if [[ ! -d "$SECRET_DIR" ]]; then
        mkdir -p "$SECRET_DIR"
    fi
    chmod 700 "$SECRET_DIR"
}

secret_path() { printf '%s/%s.gpg' "$SECRET_DIR" "$1"; }

cmd_set() {
    require_name "${1:-}"
    ensure_dir
    local file value
    file="$(secret_path "$1")"

    if [[ -t 0 ]]; then
        # interactive: silent prompt, never echoes or lands in history
        printf 'Enter secret for "%s": ' "$1" >&2
        IFS= read -rs value
        printf '\n' >&2
        [[ -n "$value" ]] || die "empty secret, nothing stored"
    else
        # piped input: read everything from stdin, strip one trailing newline
        value="$(cat)"
        value="${value%$'\n'}"
        [[ -n "$value" ]] || die "empty stdin, nothing stored"
    fi

    umask 177  # resulting file: 600
    if [[ -n "$SECRET_GPG_KEY" ]]; then
        printf '%s' "$value" | gpg --quiet --yes --encrypt \
            --recipient "$SECRET_GPG_KEY" -o "$file"
    else
        printf '%s' "$value" | gpg --quiet --yes --symmetric \
            --cipher-algo AES256 -o "$file"
    fi
    unset value
    printf 'stored: %s\n' "$1" >&2
}

cmd_get() {
    require_name "${1:-}"
    local file
    file="$(secret_path "$1")"
    [[ -f "$file" ]] || die "no such secret: $1"
    gpg --quiet --decrypt "$file"
}

cmd_list() {
    [[ -d "$SECRET_DIR" ]] || exit 0
    local f
    for f in "$SECRET_DIR"/*.gpg; do
        [[ -e "$f" ]] || break   # no matches
        f="${f##*/}"
        printf '%s\n' "${f%.gpg}"
    done
}

cmd_delete() {
    require_name "${1:-}"
    local file
    file="$(secret_path "$1")"
    [[ -f "$file" ]] || die "no such secret: $1"
    rm -f -- "$file"
    printf 'deleted: %s\n' "$1" >&2
}

main() {
    command -v gpg >/dev/null 2>&1 || die "gpg not found in PATH"

    case "${1:-}" in
        set)          shift; cmd_set "$@" ;;
        get)          shift; cmd_get "$@" ;;
        list|ls)      cmd_list ;;
        delete|rm)    shift; cmd_delete "$@" ;;
        -h|--help|"") usage ;;
        *)            die "unknown command: $1 (see: $0 --help)" ;;
    esac
}

main "$@"
