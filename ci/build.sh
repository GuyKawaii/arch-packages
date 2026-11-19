#!/usr/bin/env bash
# Build the given package directories in order as the builder user.
# Each built package is installed right away, so a later package in the list
# builds against it (howdy against the fresh python-dlib). namcap runs on
# every PKGBUILD and package; its findings are printed, not fatal.
# Packages land in OUT (default: ./out).
# Usage (as root, after ci/container-setup.sh): ci/build.sh DIR...
set -euo pipefail
# shellcheck source=ci/lib.sh
source "$(dirname "$0")/lib.sh"

out=$(realpath -m "${OUT:-out}")
work=/home/builder/build
export PKGDEST=$work/out SRCDEST=$work/sources
install -d -o builder -g builder "$work" "$PKGDEST" "$SRCDEST"
mkdir -p "$out"

for d in "$@"; do
	log "building $d $(pkg_version "$d")"
	rm -rf "${work:?}/$d"
	cp -r "$d" "$work/$d"
	chown -R builder:builder "$work/$d"

	(
		cd "$work/$d"
		# .SRCINFO must match the PKGBUILD, or the AUR-style metadata lies.
		if ! diff -u .SRCINFO <(as_builder makepkg --printsrcinfo); then
			die "$d: .SRCINFO is out of date; run makepkg --printsrcinfo > .SRCINFO"
		fi
		as_builder makepkg --syncdeps --noconfirm --noprogressbar --cleanbuild --clean
		mapfile -t pkgs < <(as_builder makepkg --packagelist)
		for p in "${pkgs[@]}"; do
			[[ -f $p ]] || die "$d: expected package $p was not built"
		done

		echo "::group::namcap $d"
		namcap PKGBUILD || true
		for p in "${pkgs[@]}"; do namcap "$p" || true; done
		echo "::endgroup::"

		pacman -U --noconfirm "${pkgs[@]}"
		cp "${pkgs[@]}" "$out/"
	)
done

ls -l "$out"
