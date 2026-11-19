# arch-packages

Our own pacman repository, `[guykawaii]`, for Arch packages that are not in the official repositories. Right now it has:

| Package | Upstream |
| --- | --- |
| `howdy` | [boltgolt/howdy](https://github.com/boltgolt/howdy): face login for Linux (PAM) |
| `python-dlib` | [davisking/dlib](https://github.com/davisking/dlib): Python bindings, CPU-only, needed by howdy. Built with AVX, so it needs a CPU from roughly 2013 or later |

Each top-level folder holds one `PKGBUILD`. GitHub Actions builds the packages, signs them and publishes them as assets of the rolling release [`repo`](https://github.com/GuyKawaii/arch-packages/releases/tag/repo).

## Trust model

- **Source**: every package builds from an upstream release (its git tag). The `sha256sums` in the PKGBUILD pin the exact bytes, and the build fails if upstream ever changes a tag.
- **Wait**: Renovate proposes a new upstream version only once it is at least 30 days old, and it skips prereleases. That gives bad or hijacked releases time to be noticed.
- **Build**: packages are built from this repository on GitHub-hosted runners, in a clean `archlinux:base-devel` container, as a non-root user. They are checked with namcap and smoke-tested before anything is published.
- **Signature**: packages and the database are signed with our own GPG key. The key is stored as a GitHub secret that only the publish job on `main` can read. Fingerprint: `1DC977D7A2C06F2B1670111509E996AA6DD48778`.
- **Repository rules**: `main` only changes through squash-merged PRs with a passing `build` check, with no bypass. Force pushes and deletion are blocked, and tags cannot be deleted or moved.

So you trust upstream's tagged code, GitHub's runners, and whoever controls this repository and its signing key.

## How updates flow

1. Renovate sees a new upstream GitHub release older than 30 days and opens a PR that changes `pkgver`.
2. `renovate-fixup` resets `pkgrel` to 1, updates the checksums and `.SRCINFO`, and pushes that to the PR.
3. `build` builds and tests the PR: `python-dlib` first, then `howdy` installed on top of it. A passing `build` check is required, and Renovate's PR then merges itself. New upstream major versions wait for a human.
4. On `main`, `build` rebuilds every package whose version is not published yet, signs it and updates the release. Packages that did not change stay in place.
5. Every week, CI checks whether Arch has moved to a new Python minor version. If it has, CI opens a PR that bumps `pkgrel` for `python-dlib`. The PR merges itself once its build passes, and the rebuilt package is then published.

GitHub Actions versions are pinned to commit SHAs and updated by Renovate with the same 30-day wait.

## Use it

Trust the key once (check the fingerprint against the one above):

```sh
curl -fsSLO https://raw.githubusercontent.com/GuyKawaii/arch-packages/main/keys/guykawaii.asc
sudo pacman-key --add guykawaii.asc
sudo pacman-key --lsign-key 1DC977D7A2C06F2B1670111509E996AA6DD48778
```

Add to `/etc/pacman.conf`:

```ini
[guykawaii]
SigLevel = Required DatabaseRequired
Server = https://github.com/GuyKawaii/arch-packages/releases/download/repo
```

Then install: `sudo pacman -Syu howdy`.

Maintainers: the one-time repository setup is in [docs/setup.md](docs/setup.md).
