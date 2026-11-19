# One-time setup

Everything after these steps runs on its own.

## 1. Repository settings

On github.com/GuyKawaii/arch-packages, **Settings**:

- **General → Pull Requests**: turn on **Allow auto-merge** (Renovate uses it) and **Automatically delete head branches**.
- **Actions → General → Workflow permissions**: keep **Read repository contents** as the default and turn on **Allow GitHub Actions to create and approve pull requests**. The weekly python check needs it to open its rebuild PR.

## 2. Protect `main`

**Settings → Rules → Rulesets → New branch ruleset**, target the default branch:

- **Require status checks to pass**: add `build` (source: GitHub Actions). This is the check that gates automerge. Leave "require branches to be up to date" off, because Renovate rebases on its own.
- **Block force pushes** and **Restrict deletions**.
- Optional: **Require a pull request before merging** with **0** required approvals. Any approval requirement stops automerge and the python-rebuild merge.

With this rule in place, direct pushes to `main` also need a passing `build` on the pushed commit. Make your changes through PRs.

## 3. Renovate

Install the Renovate GitHub App (<https://github.com/apps/renovate>) and give it access to this repository only. `renovate.json` is already in place, so Renovate skips its onboarding PR. Its Dependency Dashboard issue lists updates that are still inside the 30-day wait.

## 4. Signing key and secrets

Make a signing-only key on your own machine. Keep the private key offline after export.

```sh
gpg --quick-gen-key "guykawaii pacman repo" ed25519 sign 3y
FPR=$(gpg --list-keys --with-colons "guykawaii pacman repo" | awk -F: '$1=="fpr"{print $10; exit}')
echo "$FPR"
```

Create an environment called `publish` (**Settings → Environments**) and limit **Deployment branches** to `main`. Then store the key in it:

```sh
gpg --armor --export-secret-keys "$FPR" | gh secret set GPG_PRIVATE_KEY --env publish -R GuyKawaii/arch-packages
gh variable set GPG_KEY_ID --body "$FPR" -R GuyKawaii/arch-packages   # optional; the first key is used otherwise
# only if the key has a passphrase:
gh secret set GPG_PASSPHRASE --env publish -R GuyKawaii/arch-packages
```

Commit the public key so CI and users can verify the repository. Then put the new fingerprint in `README.md` and in the `pacman-key` commands below (current key: `1DC977D7A2C06F2B1670111509E996AA6DD48778`, expires 2028-11-18):

```sh
mkdir -p keys
gpg --armor --export "$FPR" > keys/guykawaii.asc
```

## 5. First publish

Merge the commit that adds the key, or go to **Actions → build → Run workflow** on `main`. That run builds both packages, signs them and creates the `repo` release.

## 6. Use the repository on a machine

```sh
curl -fsSLO https://raw.githubusercontent.com/GuyKawaii/arch-packages/main/keys/guykawaii.asc
gpg --show-keys guykawaii.asc            # compare the fingerprint with the README
sudo pacman-key --add guykawaii.asc
sudo pacman-key --lsign-key 1DC977D7A2C06F2B1670111509E996AA6DD48778
```

Add this to the end of `/etc/pacman.conf`:

```ini
[guykawaii]
SigLevel = Required DatabaseRequired
Server = https://github.com/GuyKawaii/arch-packages/releases/download/repo
```

Then run `sudo pacman -Syu howdy`.

## Signing key backup and renewal

The private key and its revocation certificate are backed up in the owner's password manager, not in this repository.

- **Renew** (the `maintenance` workflow opens an issue 60 days before expiry): import the backup, run `gpg --quick-set-expire 1DC977D7A2C06F2B1670111509E996AA6DD48778 2y`, commit the new public key to `keys/guykawaii.asc`, replace the `GPG_PRIVATE_KEY` secret in the `publish` environment, and re-import the public key on each machine with `sudo pacman-key --add keys/guykawaii.asc`.
- **Revoke** (if the key may have leaked): `sudo pacman-key --import` the revocation certificate on each machine, then create a new key as described above.
