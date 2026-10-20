#!/bin/sh
set -ex

PKG_NAME="amneziawg-tools"
PKG_VERSION="${PKG_VERSION:?PKG_VERSION is required}"
WORKDIR="/workspace/${PKG_NAME}"

cd "$WORKDIR"

# Strip leading 'v': Debian versions don't start with 'v'.
# The binary reports the version from src/version.h: git describe in the
# Makefile fails here (no git, and the worktree gitfile points to the host).
PKG_VERSION_BARE="$(echo "$PKG_VERSION" | sed 's/^v//')"

# ── Versioning ────────────────────────────────────────────────────────────────
# Same scheme as tzpfms: <upstream>-1+<DEB_VERSION_SUFFIX><N>.
DEB_VERSION_SUFFIX="${DEB_VERSION_SUFFIX:-local}"
PKG_REVISION="${PKG_REVISION:-1+${DEB_VERSION_SUFFIX}1}"
DEB_VERSION="${PKG_VERSION_BARE}-${PKG_REVISION}"

ARCH="$(dpkg --print-architecture)"

# Unit directory differs between OS releases; set in the Dockerfile as ENV.
SYSTEMDUNITDIR="${SYSTEMDUNITDIR:-/usr/lib/systemd/system}"

# Same make arguments as upstream debian/rules.
MAKE_ARGS="WITH_BASHCOMPLETION=yes WITH_WGQUICK=yes WITH_SYSTEMDUNITS=yes SYSTEMDUNITDIR=${SYSTEMDUNITDIR} V=1"

# ── Build ─────────────────────────────────────────────────────────────────────
# Clean first: the source dir is a host bind-mount shared across OS builds.
make -C src clean
# Debian hardening flags, as upstream debian/rules (hardening=+all).
eval "$(DEB_BUILD_MAINT_OPTIONS=hardening=+all dpkg-buildflags --export=sh)"
make -C src $MAKE_ARGS

# Build-time test from upstream debian/rules: the public key of an all-zero
# private key is known.
test "$(head -c 32 /dev/zero | base64 | src/wg pubkey)" = "L+V9o0fNYkMVKNqsX7spBzD/9oSvxM/C7ZCZX1jLO3Q="

# ── Staging ───────────────────────────────────────────────────────────────────
# awg, awg-quick, man pages, bash completions, awg-quick@.service and
# awg-quick.target, /etc/amnezia/amneziawg (0700).
# Laid out as debian/<package> with DEBIAN/ next to a stub debian/control:
# dpkg-shlibdeps needs all three.
BUILDROOT="$(mktemp -d)"
STAGING="$BUILDROOT/debian/${PKG_NAME}"
make -C src install DESTDIR="$STAGING" PREFIX=/usr $MAKE_ARGS
strip --strip-unneeded --remove-section=.comment --remove-section=.note "$STAGING/usr/bin/awg"
install -Dm0644 COPYING "$STAGING/usr/share/doc/${PKG_NAME}/copyright"
mkdir "$STAGING/DEBIAN"

# Depends from the linked libraries (libc6 only), as dh_shlibdeps computes it.
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$PKG_NAME" "$PKG_NAME" > "$BUILDROOT/debian/control"
SHLIBS_DEPENDS="$(cd "$BUILDROOT" && dpkg-shlibdeps -O "debian/${PKG_NAME}/usr/bin/awg" | sed -n 's/^shlibs:Depends=//p')"

cat > "$STAGING/DEBIAN/control" << EOF
Package: ${PKG_NAME}
Version: ${DEB_VERSION}
Section: net
Priority: optional
Architecture: ${ARCH}
Installed-Size: $(du -sk --exclude=DEBIAN "$STAGING" | cut -f1)
Depends: ${SHLIBS_DEPENDS}
Recommends: nftables | iptables
Suggests: openresolv | resolvconf
Maintainer: automated build <build@localhost>
Homepage: https://github.com/amnezia-vpn/amneziawg-tools
Description: AmneziaWG VPN tunnel (userland utilities)
 AmneziaWG is a fork of WireGuard with traffic obfuscation against DPI.
 This package provides awg (configure AmneziaWG interfaces), awg-quick and
 the awg-quick@.service systemd unit. The kernel module (amneziawg-dkms) is
 not included.
EOF

OUTPUT="/out/${PKG_NAME}_${DEB_VERSION}_${ARCH}.deb"
fakeroot dpkg-deb --build "$STAGING" "$OUTPUT"
rm -rf "$BUILDROOT"
make -C src clean
echo "Built: $OUTPUT"
