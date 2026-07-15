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
# Config (all optional):
#   SECRET_DIR              Storage directory   (default: ~/.secrets)
#   SECRET_GPG_KEY          GPG recipient       (default: symmetric passphrase mode)
#   SECRET_PASSPHRASE_FILE  Read passphrase from file instead of prompting
#   SECRET_NO_AGENT=1       Force agent-free mode (auto-detected otherwise)
#
# Examples:
#   ./secret.sh set myapp-api-key
#   printf '%s' "sk-abc123" | ./secret.sh set myapp-api-key
#   TOKEN=$(./secret.sh get myapp-api-key)

set -euo pipefail

export GNUPGHOME=/tmp/gnupg-$USER && mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME"
SECRET_DIR="${SECRET_DIR:-$HOME/.secrets}"
SECRET_GPG_KEY="${SECRET_GPG_KEY:-}"
SECRET_PASSPHRASE_FILE="${SECRET_PASSPHRASE_FILE:-}"
SECRET_NO_AGENT="${SECRET_NO_AGENT:-}"

NO_AGENT=0                  # agent is dead: symmetric-only, no caching
LOOPBACK=0                  # this script supplies the passphrase itself
GPG_EXTRA=(--quiet --yes)   # never empty, so "${GPG_EXTRA[@]}" is safe under set -u

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
    cat >&2 <<'USAGE'
secret.sh — minimal GPG-backed secret store

  secret.sh set <name>      Store a secret (prompts for value, or reads stdin)
  secret.sh get <name>      Print a secret to stdout
  secret.sh list            List stored secret names
  secret.sh delete <name>   Remove a secret

Environment:
  SECRET_DIR              Storage directory  (default: ~/.secrets)
  SECRET_GPG_KEY          GPG recipient      (default: symmetric passphrase mode)
  SECRET_PASSPHRASE_FILE  Read passphrase from file instead of prompting
  SECRET_NO_AGENT=1       Force agent-free mode (auto-detected otherwise)
USAGE
    exit "${1:-0}"
}

require_name() {
    [[ -n "${1:-}" ]] || die "missing secret name (see: $0 --help)"
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid name '$1' (use letters, digits, . _ -)"
}

ensure_dir() {
    [[ -d "$SECRET_DIR" ]] || mkdir -p "$SECRET_DIR"
    chmod 700 "$SECRET_DIR"
}

secret_path() { printf '%s/%s.gpg' "$SECRET_DIR" "$1"; }

# --- agent handling --------------------------------------------------------
# Some environments can't start gpg-agent at all (network-mounted home, no
# logind session, exhausted quota). Symmetric crypto can bypass the agent via
# --pinentry-mode loopback; public-key *decryption* cannot, since gpg delegates
# all private-key operations to the agent.
agent_is_working() {
    [[ -z "$SECRET_NO_AGENT" ]] || return 1
    command -v gpg-connect-agent >/dev/null 2>&1 || return 1
    if command -v timeout >/dev/null 2>&1; then
        timeout 5 gpg-connect-agent /bye >/dev/null 2>&1
    else
        gpg-connect-agent /bye >/dev/null 2>&1
    fi
}

# gpg tells the agent which terminal pinentry should prompt on, taking it from
# $GPG_TTY and falling back to ttyname(stdin). This script always pipes the
# secret into gpg's stdin, so that fallback can never succeed -- without this,
# pinentry dies with "Inappropriate ioctl for device". Derive it from stderr,
# which is still the terminal.
init_tty() {
    if [[ -n "${GPG_TTY:-}" ]]; then
        return 0
    fi
    local t=""
    if [[ -t 2 ]]; then
        t="$(tty <&2 2>/dev/null || true)"
    elif [[ -t 1 ]]; then
        t="$(tty <&1 2>/dev/null || true)"
    elif [[ -t 0 ]]; then
        t="$(tty 2>/dev/null || true)"
    fi
    if [[ -n "$t" && -c "$t" ]]; then
        export GPG_TTY="$t"
    fi
    return 0
}

init_mode() {
    init_tty
    agent_is_working || NO_AGENT=1

    # Supply the passphrase ourselves when the agent is dead, or whenever the
    # caller pointed us at a passphrase file for non-interactive use.
    if (( NO_AGENT )) || [[ -n "$SECRET_PASSPHRASE_FILE" ]]; then
        LOOPBACK=1
        GPG_EXTRA+=(--batch --pinentry-mode loopback)
        # avoids a pointless round-trip to the agent; GnuPG >= 2.2.7
        if gpg --dump-options 2>/dev/null | grep -qx -- '--no-symkey-cache'; then
            GPG_EXTRA+=(--no-symkey-cache)
        fi
    fi

    if (( NO_AGENT )) && [[ -n "$SECRET_GPG_KEY" ]]; then
        die "gpg-agent is not working, and public-key mode needs it to decrypt.
       Either unset SECRET_GPG_KEY to use symmetric mode, or repair the agent:
       run 'gpg-agent --daemon --verbose' to see the underlying reason."
    fi
}

# Reads into the global PASSPHRASE. Uses /dev/tty so it works even when stdin
# is a pipe carrying the secret itself.
read_passphrase() {
    local prompt="$1" confirm="${2:-}" p1 p2
    if [[ -n "$SECRET_PASSPHRASE_FILE" ]]; then
        [[ -r "$SECRET_PASSPHRASE_FILE" ]] || die "cannot read $SECRET_PASSPHRASE_FILE"
        IFS= read -r p1 < "$SECRET_PASSPHRASE_FILE" || true
        [[ -n "$p1" ]] || die "empty passphrase file"
        PASSPHRASE="$p1"
        return 0
    fi
    [[ -r /dev/tty ]] || die "no terminal for passphrase prompt; set SECRET_PASSPHRASE_FILE"
    printf '%s' "$prompt" >/dev/tty
    IFS= read -rs p1 </dev/tty
    printf '\n' >/dev/tty
    [[ -n "$p1" ]] || die "empty passphrase"
    if [[ "$confirm" == confirm ]]; then
        printf 'Confirm passphrase: ' >/dev/tty
        IFS= read -rs p2 </dev/tty
        printf '\n' >/dev/tty
        [[ "$p1" == "$p2" ]] || die "passphrases do not match"
    fi
    PASSPHRASE="$p1"
}

cmd_set() {
    require_name "${1:-}"
    ensure_dir
    local file value
    file="$(secret_path "$1")"

    if [[ -t 0 ]]; then
        printf 'Enter secret for "%s": ' "$1" >&2
        IFS= read -rs value
        printf '\n' >&2
        [[ -n "$value" ]] || die "empty secret, nothing stored"
    else
        value="$(cat)"
        value="${value%$'\n'}"
        [[ -n "$value" ]] || die "empty stdin, nothing stored"
    fi

    umask 177  # resulting file: 600
    if [[ -n "$SECRET_GPG_KEY" ]]; then
        printf '%s' "$value" | gpg "${GPG_EXTRA[@]}" \
            --encrypt --recipient "$SECRET_GPG_KEY" -o "$file"
    elif (( LOOPBACK )); then
        read_passphrase "Passphrase for \"$1\": " confirm
        # passphrase travels through a pipe on fd 3: never on the command line,
        # never on disk, invisible to ps
        printf '%s' "$value" | gpg "${GPG_EXTRA[@]}" --passphrase-fd 3 \
            --symmetric --cipher-algo AES256 -o "$file" \
            3< <(printf '%s' "$PASSPHRASE")
        unset PASSPHRASE
    else
        printf '%s' "$value" | gpg "${GPG_EXTRA[@]}" \
            --symmetric --cipher-algo AES256 -o "$file"
    fi
    unset value
    printf 'stored: %s\n' "$1" >&2
}

cmd_get() {
    require_name "${1:-}"
    local file
    file="$(secret_path "$1")"
    [[ -f "$file" ]] || die "no such secret: $1"

    if (( LOOPBACK )); then
        read_passphrase "Passphrase for \"$1\": "
        gpg "${GPG_EXTRA[@]}" --passphrase-fd 3 --decrypt "$file" \
            3< <(printf '%s' "$PASSPHRASE")
        unset PASSPHRASE
    else
        gpg "${GPG_EXTRA[@]}" --decrypt "$file"
    fi
}

cmd_list() {
    [[ -d "$SECRET_DIR" ]] || exit 0
    local f
    for f in "$SECRET_DIR"/*.gpg; do
        [[ -e "$f" ]] || break
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
        set)          init_mode; shift; cmd_set "$@" ;;
        get)          init_mode; shift; cmd_get "$@" ;;
        list|ls)      cmd_list ;;
        delete|rm)    shift; cmd_delete "$@" ;;
        -h|--help|"") usage ;;
        *)            die "unknown command: $1 (see: $0 --help)" ;;
    esac
}

main "$@"
