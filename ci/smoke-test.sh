#!/usr/bin/env bash
# Install every package of this repo together and run the smoke tests in
# ci/smoke/<pkgname>.sh. Packages built in this run come from OUT; the rest
# come from the published repo, so a rebuilt python-dlib is also tested with
# the published howdy. Tests must not need hardware (no camera in CI).
# Usage (as root, after ci/build.sh): ci/smoke-test.sh
set -euo pipefail
# shellcheck source=ci/lib.sh
source "$(dirname "$0")/lib.sh"

out=$(realpath -m "${OUT:-out}")
shopt -s nullglob
built=("$out"/*.pkg.tar.zst)
((${#built[@]})) || { log "nothing was built; no smoke tests"; exit 0; }

pacman -U --noconfirm --needed "${built[@]}"

# Our other packages, from the published repo when pacman knows it.
others=()
for d in $(pkg_dirs); do
	for name in $(pkg_names "$d"); do
		pacman -Q "$name" &>/dev/null || others+=("$name")
	done
done
if ((${#others[@]})) && grep -q "^\[$REPO_NAME\]" /etc/pacman.conf; then
	pacman -S --noconfirm --needed "${others[@]}" ||
		echo "::warning::could not install published ${others[*]}; their smoke tests are skipped"
fi

for t in "$(dirname "$0")"/smoke/*.sh; do
	name=$(basename "$t" .sh)
	if pacman -Q "$name" &>/dev/null; then
		log "smoke test: $name"
		bash -euo pipefail "$t"
	fi
done
