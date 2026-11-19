#!/usr/bin/env bash
# Sign the packages in PKGDIR and publish them, with a signed database, to
# the rolling GitHub release "repo". Packages already published and not
# rebuilt stay: the current assets are downloaded first and repo-add only
# replaces the entries of the new packages (--remove deletes the files they
# replace). Assets that are no longer part of the repo are deleted.
#
# Env: GH_TOKEN, GH_REPO (owner/name), GPG_PRIVATE_KEY (armored secret key),
#      GPG_PASSPHRASE (optional), GPG_KEY_ID (optional; default: first key).
# Usage (as root, needs github-cli): ci/publish.sh PKGDIR
set -euo pipefail
# shellcheck source=ci/lib.sh
source "$(dirname "$0")/lib.sh"

pkgdir=$(realpath "$1")
: "${GH_TOKEN:?}" "${GH_REPO:?}" "${GPG_PRIVATE_KEY:?GPG_PRIVATE_KEY secret is not set}"

work=$(mktemp -d)
repo=$work/repo
mkdir -p "$repo"

# --- signing key ------------------------------------------------------------
export GNUPGHOME=$work/gnupg
install -d -m 700 "$GNUPGHOME"
echo allow-preset-passphrase >"$GNUPGHOME/gpg-agent.conf"
printf '%s\n' "$GPG_PRIVATE_KEY" | gpg --batch --quiet --import
key=${GPG_KEY_ID:-$(gpg --list-secret-keys --with-colons | awk -F: '$1 == "fpr" { print $10; exit }')}
[[ -n $key ]] || die "no secret key in GPG_PRIVATE_KEY"
log "signing with $key"
if [[ -n ${GPG_PASSPHRASE:-} ]]; then
	gpgconf --launch gpg-agent
	while read -r grip; do
		printf '%s' "$GPG_PASSPHRASE" | /usr/lib/gnupg/gpg-preset-passphrase --preset "$grip"
	done < <(gpg --list-secret-keys --with-colons --with-keygrip "$key" | awk -F: '$1 == "grp" { print $10 }')
fi

# --- current release --------------------------------------------------------
if ! gh release view "$RELEASE_TAG" &>/dev/null; then
	log "creating release $RELEASE_TAG"
	gh release create "$RELEASE_TAG" --target "${GITHUB_SHA:-main}" --latest=false \
		--title "pacman repository" \
		--notes "Rolling pacman repository [$REPO_NAME]. Server = $REPO_URL — see the README. Assets change on every publish."
fi
mapfile -t existing < <(gh release view "$RELEASE_TAG" --json assets --jq '.assets[].name')
if ((${#existing[@]})); then
	gh release download "$RELEASE_TAG" --dir "$repo" --pattern '*'
fi
# Real copies of repo-add's symlinks; repo-add recreates the links.
rm -f "$repo/$REPO_NAME".{db,files}{,.sig}

# --- add the new packages ---------------------------------------------------
shopt -s nullglob
new=()
for p in "$pkgdir"/*.pkg.tar.zst; do
	f=$(basename "$p")
	[[ $f != *:* ]] || die "$f: GitHub renames ':' in asset names, so epochs are not supported"
	if [[ -e $repo/$f ]]; then
		# Same file name, different bytes would break pacman caches and mirrors.
		echo "::warning::$f is already published; bump pkgrel to publish a rebuild. Skipped."
		continue
	fi
	cp "$p" "$repo/$f"
	gpg --batch --yes --detach-sign --no-armor --local-user "$key" "$repo/$f"
	new+=("$f")
done
if ! ((${#new[@]})); then
	log "nothing new to publish"
	exit 0
fi

cd "$repo"
verify=()
if [[ -f $REPO_NAME.db.tar.gz ]]; then verify=(--verify); fi
repo-add "${verify[@]}" --sign --key "$key" --remove "$REPO_NAME.db.tar.gz" "${new[@]}"

for l in "$REPO_NAME".{db,files}{,.sig}; do
	if [[ -L $l ]]; then cp --remove-destination "$(readlink -f "$l")" "$l"; fi
done
dbfiles=("$REPO_NAME".{db,files}{,.tar.gz}{,.sig})
for f in "${dbfiles[@]}"; do
	if [[ ! -f $f ]]; then die "repo-add did not produce $f"; fi
done

# --- upload: packages first, database last, then drop stale assets ----------
uploads=()
for f in "${new[@]}"; do uploads+=("$f" "$f.sig"); done
gh release upload "$RELEASE_TAG" --clobber "${uploads[@]}"
gh release upload "$RELEASE_TAG" --clobber "${dbfiles[@]}"

while read -r asset; do
	if [[ ! -e $asset ]]; then
		log "deleting stale asset $asset"
		gh release delete-asset "$RELEASE_TAG" "$asset" --yes
	fi
done < <(gh release view "$RELEASE_TAG" --json assets --jq '.assets[].name')

log "published: ${new[*]}"
