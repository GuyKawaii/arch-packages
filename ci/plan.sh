#!/usr/bin/env bash
# Print the package directories to build, one per line, dependencies first.
# A directory is built when
#   - its version is newer than the published one (or it is not published),
#   - it changed compared to BASE (pull requests and side branches), or
#   - it is named in FORCE ("all" builds everything).
# Usage: ci/plan.sh DBDIR [BASE] [FORCE]
#   DBDIR  output directory of fetch_db (may be empty: nothing published)
set -euo pipefail
# shellcheck source=ci/lib.sh
source "$(dirname "$0")/lib.sh"

dbdir=$1 base=${2:-} force=${3:-}
declare -A want=()

for d in $(pkg_dirs); do
	ver=$(pkg_version "$d")
	for name in $(pkg_names "$d"); do
		pub=$(published_version "$dbdir" "$name" || true)
		if [[ -z $pub ]] || (($(vercmp "$ver" "$pub") > 0)); then
			log "$d: $name $ver is not published (published: ${pub:-none})"
			want[$d]=1
		fi
	done
done

if [[ -n $base ]]; then
	while read -r d; do
		if [[ -f $d/PKGBUILD ]]; then
			log "$d: changed compared to $base"
			want[$d]=1
		fi
	done < <(git diff --name-only "$base...HEAD" | cut -d/ -f1 | sort -u)
fi

for d in $force; do
	if [[ $d == all ]]; then
		for a in $(pkg_dirs); do want[$a]=1; done
	elif [[ -f $d/PKGBUILD ]]; then
		want[$d]=1
	else
		die "force: no package directory '$d'"
	fi
done

((${#want[@]})) || exit 0

# Order by dependencies between our own packages (tsort: "before after").
{
	for d in "${!want[@]}"; do
		echo "$d $d"
		for dep in $(pkg_all_deps "$d"); do
			if depdir=$(dir_for_pkgname "$dep") && [[ -n ${want[$depdir]:-} && $depdir != "$d" ]]; then
				echo "$depdir $d"
			fi
		done
	done
} | tsort
