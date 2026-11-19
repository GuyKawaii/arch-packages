#!/usr/bin/env bash
# Finish a Renovate pkgver bump: for every package changed compared to BASE,
# reset pkgrel to 1 when pkgver changed, refresh the checksums with
# updpkgsums and regenerate .SRCINFO. Stages the result; prints the changed
# directories. Runs updpkgsums and makepkg as the builder user.
# Usage (as root, after ci/container-setup.sh): ci/fixup.sh BASE
set -euo pipefail
# shellcheck source=ci/lib.sh
source "$(dirname "$0")/lib.sh"

base=$1
export SRCDEST=/home/builder/sources
install -d -o builder -g builder "$SRCDEST"

while read -r d; do
	[[ -f $d/PKGBUILD ]] || continue
	old=$(git show "$base:$d/PKGBUILD" 2>/dev/null | sed -n 's/^pkgver=//p' || true)
	new=$(sed -n 's/^pkgver=//p' "$d/PKGBUILD")
	if [[ -n $old && $old != "$new" ]]; then
		log "$d: pkgver $old -> $new, pkgrel reset to 1"
		sed -i 's/^pkgrel=.*/pkgrel=1/' "$d/PKGBUILD"
	fi
	chown -R builder:builder "$d"
	(cd "$d" && as_builder updpkgsums)
	srcinfo_regen "$d"
	git add -- "$d/PKGBUILD" "$d/.SRCINFO"
	printf '%s\n' "$d"
done < <(git diff --name-only "$base...HEAD" | cut -d/ -f1 | sort -u)
