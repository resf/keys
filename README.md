# RESF / Rocky Linux WKD Keys

OpenPGP keys published over [Web Key Directory](https://datatracker.ietf.org/doc/draft-koch-openpgp-webkey-service/)
for `resf.org` and `rockylinux.org`, so that `gpg --locate-keys someone@rockylinux.org`
just works.

## Layout

This repo uses the WKD **advanced method**, which serves keys from a dedicated
`openpgpkey.` subdomain and namespaces them per domain:

```
.well-known/openpgpkey/<domain>/hu/<wkd-hash>    binary (not ASCII-armored) key export
.well-known/openpgpkey/<domain>/policy           required, may be empty
```

The WKD hash is a z-base-32 encoding of the SHA-1 of the lowercased local part,
so `security@resf.org` and `security@rockylinux.org` hash identically and are
published once per domain.

`keys.yaml` is the source of truth. Each entry maps one or more fingerprints to
the addresses they should be published under:

```yaml
  - fingerprints:
      - F4C0847D7089F5B9B827E66F327541AF5CE5F44B
    uids:
      - security@resf.org
      - security@rockylinux.org
```

Listing several fingerprints under one entry bundles them into a single file,
which is how multiple signing keys are served for one address.

## Adding or updating a key

1. Get the key into your local keyring, and make sure it is current — including
   any new signatures, subkeys, or revocations:

   ```
   gpg --keyserver hkps://keys.openpgp.org --recv-keys <fingerprint>
   ```

2. Add or edit the entry in `keys.yaml`. To remove a key, delete its entry.

3. Run the sync script:

   ```
   ./manage-keys.sh
   ```

   It imports the existing repo keys into your keyring, re-exports everything
   listed in `keys.yaml` to the right paths, creates any missing `policy` files,
   and deletes files no longer backed by an entry.

4. Review `git diff` before committing. The script re-exports *every* key, so a
   newer copy in your keyring can cause unrelated files to change. Revert
   anything you did not mean to touch.

5. Commit and push to `master`.

The key published at a given hash **must** carry a user ID matching that exact
address, or clients will reject it.

`./import-keys.sh` imports every key in the repo into your local keyring without
writing anything back, which is useful for inspection.

## Deployment

Pushing to `master` deploys automatically via the Vercel `keys` project, which
serves `keys.resf.org`, `openpgpkey.resf.org`, and `openpgpkey.rockylinux.org`.
The project is managed in OpenTofu, not configured by hand.

## Verifying

Check that a key resolves end to end. Use a throwaway `GNUPGHOME` so a copy
already in your own keyring cannot mask a failed lookup:

```
GNUPGHOME=$(mktemp -d) gpg --auto-key-locate clear,wkd --locate-keys security@resf.org
```

Or fetch the file directly:

```
curl -sI https://openpgpkey.resf.org/.well-known/openpgpkey/resf.org/hu/<hash>
```

A working response is `200` with `content-type: application/octet-stream`.
