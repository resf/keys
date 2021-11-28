# Update Instructions

Ensure the key is up to date and includes all current signatures / revocations.

Find the key's WKD hash with `gpg --list-keys --with-wkd example@resf.org`.

Export the key to the appropriate file `gpg --export example@resf.org > .well-known/openpgpkey/hu/$hash`
