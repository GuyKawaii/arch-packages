#!/usr/bin/env bash
# Print the package directories whose published build installs into a
# different python than the one Arch ships now (e.g. site-packages under
# python3.13 while Arch moved to 3.14). Such packages need a pkgrel bump and
# a rebuild, or "import" fails for users after the python upgrade.
# Usage: ci/python-outdated.sh DBDIR   (needs a synced pacman db)
set -euo pipefail
# shellcheck source=ci/lib.sh
source "$(dirname "$0")/lib.sh"

dbdir=$1
current=$(arch_python_minor)
log "Arch ships python $current"

for d in $(pkg_dirs); do
	for name in $(pkg_names "$d"); do
		entry=$(published_entry "$dbdir" "$name") || continue
		built=$(grep -oE '^usr/lib/python[0-9]+\.[0-9]+/' "$entry/files" | head -n1 | grep -oE '[0-9]+\.[0-9]+' || true)
		[[ -n $built ]] || continue
		if [[ $built != "$current" ]]; then
			log "$d: $name was built for python $built"
			printf '%s\n' "$d"
			break
		fi
	done
done
