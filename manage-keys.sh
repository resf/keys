#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_FILE="$SCRIPT_DIR/keys.yaml"
WKD_BASE="$SCRIPT_DIR/.well-known/openpgpkey"
MANAGED_TMP="$(mktemp)"
trap 'rm -f "$MANAGED_TMP"' EXIT

# --- Dependency checks ---

check_deps() {
    local missing=()
    command -v gpg >/dev/null 2>&1 || missing+=("gpg")
    command -v gpg-wks-client >/dev/null 2>&1 || missing+=("gpg-wks-client")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import yaml" 2>/dev/null || missing+=("python3-yaml (PyYAML)")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        echo "error: missing dependencies: ${missing[*]}" >&2
        exit 1
    fi
    if [ ! -f "$YAML_FILE" ]; then
        echo "error: $YAML_FILE not found" >&2
        exit 1
    fi
}

# --- Parse YAML ---
# Outputs one line per entry: fingerprints (comma-separated) TAB uid

parse_yaml() {
    python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
for entry in data['keys']:
    fprs = ','.join(entry['fingerprints'])
    for uid in entry['uids']:
        print(f'{fprs}\t{uid}')
" "$YAML_FILE"
}

# --- Phase 1: Import existing keys from repo ---

import_keys() {
    echo "==> Importing existing keys from repo into local keyring..."
    local count=0
    for domain_dir in "$WKD_BASE"/*/; do
        [ -d "$domain_dir/hu" ] || continue
        for keyfile in "$domain_dir"/hu/*; do
            [ -f "$keyfile" ] || continue
            gpg --import "$keyfile" 2>&1 \
                | grep -v "^gpg: Total\|^gpg: marginals\|^gpg: depth\|^gpg: next\|^gpg:$" \
                || true
            count=$((count + 1))
        done
    done
    echo "    Processed $count key file(s)."
    echo
}

# --- Phase 2: Export keys from local keyring to repo ---

export_keys() {
    echo "==> Exporting keys from local keyring to repo..."

    while IFS=$'\t' read -r fprs uid; do
        local domain="${uid##*@}"
        local wkd_hash
        wkd_hash="$(gpg-wks-client --print-wkd-hash "$uid" | awk '{print $1}')"

        local hu_dir="$WKD_BASE/$domain/hu"
        local target="$hu_dir/$wkd_hash"
        local policy="$WKD_BASE/$domain/policy"

        # Ensure directory structure exists
        mkdir -p "$hu_dir"
        if [ ! -f "$policy" ]; then
            echo "# Policy flags for domain $domain" > "$policy"
            echo "    Created policy file for $domain"
        fi

        # Export all fingerprints for this entry into the target file
        IFS=',' read -ra fpr_array <<< "$fprs"
        gpg --export "${fpr_array[@]}" > "$target"

        echo "    $uid -> $domain/hu/$wkd_hash (${#fpr_array[@]} key(s))"

        # Record this path for cleanup
        echo "$domain/hu/$wkd_hash" >> "$MANAGED_TMP"
    done < <(parse_yaml)

    echo
}

# --- Phase 3: Clean up stale key files ---

cleanup_stale() {
    echo "==> Cleaning up stale key files..."
    local removed=0

    for domain_dir in "$WKD_BASE"/*/; do
        [ -d "$domain_dir/hu" ] || continue
        local domain
        domain="$(basename "$domain_dir")"
        for keyfile in "$domain_dir"/hu/*; do
            [ -f "$keyfile" ] || continue
            local hash
            hash="$(basename "$keyfile")"
            local rel="$domain/hu/$hash"
            if ! grep -qxF "$rel" "$MANAGED_TMP" 2>/dev/null; then
                echo "    Removing stale: $rel"
                rm "$keyfile"
                removed=$((removed + 1))
            fi
        done
    done

    if [ "$removed" -eq 0 ]; then
        echo "    No stale files found."
    else
        echo "    Removed $removed stale file(s)."
    fi
    echo
}

# --- Phase 4: Report ---

report() {
    echo "==> Summary of changes:"
    if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local changes
        changes="$(git -C "$SCRIPT_DIR" status --short .well-known/)"
        if [ -n "$changes" ]; then
            echo "$changes"
        else
            echo "    No changes."
        fi
    else
        echo "    (not a git repo, skipping status)"
    fi
    echo
}

# --- Main ---

main() {
    check_deps
    import_keys
    export_keys
    cleanup_stale
    report
    echo "Done. Review changes and commit when ready."
}

main "$@"
