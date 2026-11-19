#!/usr/bin/env bash
# Prepare an archlinux:base-devel container: full upgrade, extra tools,
# an unprivileged "builder" user with passwordless sudo (makepkg -s needs it),
# and the published guykawaii repo as a dependency source when it exists.
# Usage (as root, from the repo root): ci/container-setup.sh [extra packages...]
set -euo pipefail
# shellcheck source=ci/lib.sh
source "$(dirname "$0")/lib.sh"

# The published repo, so a package can depend on one of ours that was not
# rebuilt in this run. Verified with the key in keys/ when it is committed.
if curl -fsIL --retry 3 -o /dev/null "$REPO_URL/$REPO_NAME.db"; then
	siglevel='Never'
	if [[ -f keys/$REPO_NAME.asc ]]; then
		pacman-key --init
		pacman-key --add "keys/$REPO_NAME.asc"
		while read -r fpr; do
			pacman-key --lsign-key "$fpr"
		done < <(gpg --show-keys --with-colons "keys/$REPO_NAME.asc" | awk -F: '$1 == "fpr" { print $10 }')
		siglevel='Required DatabaseRequired'
	else
		echo "::warning::keys/$REPO_NAME.asc is missing; CI installs published dependencies without signature checks"
	fi
	printf '\n[%s]\nSigLevel = %s\nServer = %s\n' "$REPO_NAME" "$siglevel" "$REPO_URL" >>/etc/pacman.conf
fi

pacman -Syu --noconfirm --needed git "$@"

# makepkg refuses to run as root.
if ! id builder &>/dev/null; then
	useradd --create-home builder
	echo 'builder ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/builder
	chmod 0440 /etc/sudoers.d/builder
fi

# No -debug split packages in the published repo; build with every core.
mkdir -p /etc/makepkg.conf.d
cat >/etc/makepkg.conf.d/ci.conf <<EOF
OPTIONS+=(!debug)
MAKEFLAGS="-j$(nproc)"
EOF

# The checkout is owned by root; git runs as root on files builder touched.
git config --global --add safe.directory '*'
