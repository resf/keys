#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WKD_BASE="$SCRIPT_DIR/.well-known/openpgpkey"

if ! command -v gpg >/dev/null 2>&1; then
    echo "error: gpg not found" >&2
    exit 1
fi

echo "==> Importing all keys from repo into local keyring..."
count=0
for domain_dir in "$WKD_BASE"/*/; do
    [ -d "$domain_dir/hu" ] || continue
    domain="$(basename "$domain_dir")"
    for keyfile in "$domain_dir"/hu/*; do
        [ -f "$keyfile" ] || continue
        echo "    $domain/hu/$(basename "$keyfile")"
        gpg --import "$keyfile" 2>&1 | sed 's/^/      /'
        count=$((count + 1))
    done
done

echo
echo "Done. Processed $count key file(s)."
