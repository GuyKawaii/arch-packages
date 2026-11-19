# Shared helpers for the CI scripts. Source it; do not run it.
# Every package lives in a top-level directory with a PKGBUILD and a .SRCINFO.

REPO_NAME=guykawaii
RELEASE_TAG=repo
REPO_URL=${REPO_URL:-https://github.com/${GITHUB_REPOSITORY:-GuyKawaii/arch-packages}/releases/download/${RELEASE_TAG}}

log() { printf '==> %s\n' "$*" >&2; }
die() { printf '::error::%s\n' "$*" >&2; exit 1; }

# All package directories, sorted.
pkg_dirs() {
	local f
	for f in */PKGBUILD; do
		if [[ -f $f ]]; then printf '%s\n' "${f%/PKGBUILD}"; fi
	done
}

# srcinfo_get DIR KEY: values of KEY in the pkgbase section of DIR/.SRCINFO.
srcinfo_get() {
	awk -v k="$2" '
		/^pkgname = / { exit }
		$1 == k && $2 == "=" { sub(/^[^=]*= /, ""); print }
	' "$1/.SRCINFO"
}

# All pkgnames built from DIR.
pkg_names() {
	awk '$1 == "pkgname" && $2 == "=" { print $3 }' "$1/.SRCINFO"
}

# Full version of DIR as pacman shows it: [epoch:]pkgver-pkgrel.
pkg_version() {
	local epoch ver rel
	epoch=$(srcinfo_get "$1" epoch)
	ver=$(srcinfo_get "$1" pkgver)
	rel=$(srcinfo_get "$1" pkgrel)
	printf '%s%s-%s\n' "${epoch:+$epoch:}" "$ver" "$rel"
}

# Names of every dependency of DIR (all sections, all architectures),
# without version constraints.
pkg_all_deps() {
	awk '$1 ~ /^(depends|makedepends|checkdepends)(_.*)?$/ && $2 == "=" { print $3 }' "$1/.SRCINFO" |
		sed -E 's/[<>=].*$//' | sort -u
}

# dir_for_pkgname NAME: the directory that builds NAME, if it is ours.
dir_for_pkgname() {
	local d
	for d in $(pkg_dirs); do
		if pkg_names "$d" | grep -qxF "$1"; then
			printf '%s\n' "$d"
			return 0
		fi
	done
	return 1
}

# fetch_db DEST: download and unpack the published files database into
# DEST/db (desc + files per package). Returns 1 if nothing is published yet.
fetch_db() {
	local dest=$1
	mkdir -p "$dest/db"
	if ! curl -fsSL --retry 3 -o "$dest/$REPO_NAME.files" "$REPO_URL/$REPO_NAME.files"; then
		log "no published repository at $REPO_URL yet"
		return 1
	fi
	tar -xzf "$dest/$REPO_NAME.files" -C "$dest/db"
}

# published_entry DBDIR NAME: the db entry directory for NAME, if published.
published_entry() {
	local desc
	for desc in "$1"/db/*/desc; do
		[[ -f $desc ]] || continue
		if awk '/^%NAME%$/ { getline; print; exit }' "$desc" | grep -qxF "$2"; then
			printf '%s\n' "${desc%/desc}"
			return 0
		fi
	done
	return 1
}

# published_version DBDIR NAME: version of NAME in the published repo.
published_version() {
	local entry
	entry=$(published_entry "$1" "$2") || return 1
	awk '/^%VERSION%$/ { getline; print; exit }' "$entry/desc"
}

# The python major.minor that Arch currently ships (needs a synced pacman db).
arch_python_minor() {
	pacman -Si python | awk '$1 == "Version" { print $3; exit }' | grep -oE '^[0-9]+\.[0-9]+'
}

# bump_pkgrel DIR: increment pkgrel in DIR/PKGBUILD by one whole number.
bump_pkgrel() {
	local rel
	rel=$(sed -n 's/^pkgrel=//p' "$1/PKGBUILD")
	[[ $rel =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "$1: cannot parse pkgrel=$rel"
	sed -i "s/^pkgrel=.*/pkgrel=$((${rel%%.*} + 1))/" "$1/PKGBUILD"
}

# as_builder CMD...: run a command as the unprivileged build user.
as_builder() {
	sudo -u builder --preserve-env=SRCDEST,PKGDEST,MAKEFLAGS -- "$@"
}

# srcinfo_regen DIR: rewrite DIR/.SRCINFO from the PKGBUILD.
srcinfo_regen() {
	(cd "$1" && as_builder makepkg --printsrcinfo) >"$1/.SRCINFO.new"
	mv "$1/.SRCINFO.new" "$1/.SRCINFO"
}
