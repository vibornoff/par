#!/bin/sh
set -ex

PKG_NAME="amneziawg-dkms"
DKMS_NAME="amneziawg"
PKG_VERSION="${PKG_VERSION:?PKG_VERSION is required}"
WORKDIR="/workspace/${PKG_NAME}"

cd "$WORKDIR"

# Strip leading 'v': Debian versions don't start with 'v'.
# The upstream version is also the DKMS module version: upstream dkms.conf pins
# PACKAGE_VERSION="1.0.0" for every release, so DKMS could not tell them apart.
PKG_VERSION_BARE="$(echo "$PKG_VERSION" | sed 's/^v//')"

# ── Versioning ────────────────────────────────────────────────────────────────
# Same scheme as tzpfms: <upstream>-1+<DEB_VERSION_SUFFIX><N>.
DEB_VERSION_SUFFIX="${DEB_VERSION_SUFFIX:-local}"
PKG_REVISION="${PKG_REVISION:-1+${DEB_VERSION_SUFFIX}1}"
DEB_VERSION="${PKG_VERSION_BARE}-${PKG_REVISION}"

# ── Staging ───────────────────────────────────────────────────────────────────
# Module sources as upstream installs them for DKMS (src/ without tests).
STAGING="$(mktemp -d)"
DKMS_SRC="/usr/src/${DKMS_NAME}-${PKG_VERSION_BARE}"
make -C src dkms-install DESTDIR="$STAGING" DKMSDIR="$DKMS_SRC"
# REMAKE_INITRD is deprecated in DKMS 3, and the module is not needed in the initramfs.
sed -i \
    -e "s/^PACKAGE_VERSION=.*/PACKAGE_VERSION=\"${PKG_VERSION_BARE}\"/" \
    -e '/^REMAKE_INITRD=/d' \
    "$STAGING$DKMS_SRC/dkms.conf"
install -Dm0644 COPYING "$STAGING/usr/share/doc/${PKG_NAME}/copyright"

# ── Maintainer scripts ────────────────────────────────────────────────────────
# What dh_dkms generates: the target release's own templates with the module
# name and version filled in. postinst adds the module to DKMS and builds it for
# the installed kernels with headers; prerm removes it from DKMS.
mkdir -p "$STAGING/DEBIAN"
DH_DKMS_VERSION="$(dpkg-query -W -f '${Version}' dh-dkms)"
for script in postinst prerm; do
    {
        printf '#!/bin/sh\nset -e\n\n'
        echo "# Automatically added by dh_dkms/${DH_DKMS_VERSION}"
        sed -e "s/#MODULE_NAME#/${DKMS_NAME}/g" \
            -e "s/#MODULE_VERSION#/${PKG_VERSION_BARE}/g" \
            "/usr/share/debhelper/autoscripts/${script}-dkms"
        echo "# End automatically added section"
    } > "$STAGING/DEBIAN/$script"
    chmod 0755 "$STAGING/DEBIAN/$script"
done

cat > "$STAGING/DEBIAN/control" << EOF
Package: ${PKG_NAME}
Version: ${DEB_VERSION}
Section: kernel
Priority: optional
Architecture: all
Installed-Size: $(du -sk --exclude=DEBIAN "$STAGING" | cut -f1)
Depends: dkms (>= 2.1.0.0)
Recommends: amneziawg-tools
Maintainer: automated build <build@localhost>
Homepage: https://github.com/amnezia-vpn/amneziawg-linux-kernel-module
Description: AmneziaWG VPN tunnel (DKMS kernel module)
 AmneziaWG is a fork of WireGuard with traffic obfuscation against DPI.
 This package provides the source of the amneziawg kernel module; DKMS builds
 it for every installed kernel that has headers.
EOF

OUTPUT="/out/${PKG_NAME}_${DEB_VERSION}_all.deb"
fakeroot dpkg-deb --build "$STAGING" "$OUTPUT"
rm -rf "$STAGING"
echo "Built: $OUTPUT"
