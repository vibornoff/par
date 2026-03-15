#!/bin/sh
set -ex

PKG_NAME="sbctl"
PKG_VERSION="${PKG_VERSION:?PKG_VERSION is required}"
WORKDIR="/workspace/${PKG_NAME}"

cd "$WORKDIR"

# Build binary, man pages, and completions; install to staging tree.
# VERSION is overridden on the make command line so git-describe is not needed
# (the .git inside the worktree points to an absolute host path that is not
# reachable from inside the container).
STAGING="$(mktemp -d)"
make install \
    DESTDIR="$STAGING" \
    PREFIX=/usr \
    VERSION="${PKG_VERSION}"

ARCH="$(dpkg --print-architecture)"

mkdir -p "$STAGING/DEBIAN"
cat > "$STAGING/DEBIAN/control" << EOF
Package: sbctl
Version: ${PKG_VERSION}
Section: admin
Priority: optional
Architecture: ${ARCH}
Depends: binutils, util-linux
Maintainer: automated build <build@localhost>
Description: Secure Boot key manager
 sbctl is a user-friendly secure boot key manager capable of setting up secure
 boot, offering key management capabilities, and keeping track of files that
 need to be signed in the boot chain.
EOF

OUTPUT="/out/${PKG_NAME}_${PKG_VERSION}_${ARCH}.deb"
fakeroot dpkg-deb --build "$STAGING" "$OUTPUT"
echo "Built: $OUTPUT"
