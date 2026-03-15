#!/bin/sh
set -ex

PKG_NAME="tzpfms"
PKG_VERSION="${PKG_VERSION:?PKG_VERSION is required}"
WORKDIR="/workspace/${PKG_NAME}"

cd "$WORKDIR"

# Strip leading 'v': Debian versions don't start with 'v'.
# TZPFMS_VERSION is passed with embedded double-quotes so the Makefile produces
# a valid C string literal: -DTZPFMS_VERSION='"0.4.1"'.
PKG_VERSION_BARE="$(echo "$PKG_VERSION" | sed 's/^v//')"
MAKE_VERSION="\"${PKG_VERSION_BARE}\""

# ── Versioning ────────────────────────────────────────────────────────────────
# Suffix format: <upstream_debian_rev>+<DEB_VERSION_SUFFIX><N>
#   0.4.1-1+artyrepo1  >  0.4.1-1   (upstream current)   — won't be downgraded
#   0.4.1-1+artyrepo1  <  0.4.2-1   (upstream next)      — auto-upgradeable
DEB_VERSION_SUFFIX="${DEB_VERSION_SUFFIX:-local}"
PKG_REVISION="${PKG_REVISION:-1+${DEB_VERSION_SUFFIX}1}"
DEB_VERSION="${PKG_VERSION_BARE}-${PKG_REVISION}"

ARCH="$(dpkg --print-architecture)"

# Library names differ between OS releases; set in the Dockerfile as ENV.
# Defaults target noble (Ubuntu 24.04) / Debian bookworm.
LIBZFS_PKG="${LIBZFS_PKG:-libzfs4linux}"
LIBSSL_PKG="${LIBSSL_PKG:-libssl3}"
LIBTSS2_ESYS_PKG="${LIBTSS2_ESYS_PKG:-libtss2-esys-3.0.2-0}"
LIBTSS2_RC_PKG="${LIBTSS2_RC_PKG:-libtss2-rc0}"

# ── Build ─────────────────────────────────────────────────────────────────────
# Clean first: the source dir is a host bind-mount shared across OS builds,
# so stale artifacts from a previous run must be removed.
make clean
# Targets: build + locales + manpages + integration glue.
# Skip: htmlpages (not packaged), shellcheck (linter).
# SOURCE_DATE_EPOCH may be set by the caller for reproducible builds.
make build locales manpages i-t init.d-systemd dracut \
    TZPFMS_VERSION="${MAKE_VERSION}"

# ── Helpers ───────────────────────────────────────────────────────────────────
make_staging() {
    local s
    s="$(mktemp -d)"
    mkdir -p "$s/DEBIAN"
    echo "$s"
}

build_deb() {
    local stage="$1" outfile="$2"
    fakeroot dpkg-deb --build "$stage" "/out/$outfile"
    echo "Built: /out/$outfile"
    rm -rf "$stage"
}

# ── tzpfms-common ─────────────────────────────────────────────────────────────
# zfs-tpm-list + systemd integration + locales
S="$(make_staging)"
install -Dm0755 -t "$S/usr/sbin/"             out/zfs-tpm-list
install -Dm0644 -t "$S/usr/share/man/man8/"   out/man/zfs-tpm-list.8
[ -d out/locale ]  && cp -aT out/locale/  "$S/usr/share/locale/"
[ -d out/systemd ] && cp -aT out/systemd/ "$S/"

cat > "$S/DEBIAN/control" << EOF
Package: tzpfms-common
Version: ${DEB_VERSION}
Section: admin
Priority: optional
Architecture: ${ARCH}
Depends: libc6 (>= 2.17), libnvpair3linux (>= 0.8.2), ${LIBZFS_PKG} (>= 0.8.2)
Maintainer: automated build <build@localhost>
Description: TPM-based encryption keys for ZFS datasets -- common binaries
 tzpfms generates and seals random raw encryption keys to the TPM, tying ZFS
 dataset encryption to the platform.
 This package provides the common zfs-tpm-list binary and systemd integration.
EOF
build_deb "$S" "tzpfms-common_${DEB_VERSION}_${ARCH}.deb"

# ── tzpfms-tpm2 ───────────────────────────────────────────────────────────────
S="$(make_staging)"
install -Dm0755 -t "$S/usr/sbin/"             out/zfs-tpm2-change-key out/zfs-tpm2-clear-key out/zfs-tpm2-load-key
install -Dm0644 -t "$S/usr/share/man/man8/"   out/man/zfs-tpm2-change-key.8 out/man/zfs-tpm2-clear-key.8 out/man/zfs-tpm2-load-key.8

cat > "$S/DEBIAN/control" << EOF
Package: tzpfms-tpm2
Version: ${DEB_VERSION}
Section: admin
Priority: optional
Architecture: ${ARCH}
Depends: libc6 (>= 2.17), libnvpair3linux (>= 0.8.2), ${LIBSSL_PKG} (>= 3.0.0), ${LIBTSS2_ESYS_PKG} (>= 2.3.1), ${LIBTSS2_RC_PKG} (>= 3.0.1), ${LIBZFS_PKG} (>= 0.8.2)
Recommends: tzpfms-common (= ${DEB_VERSION})
Maintainer: automated build <build@localhost>
Description: TPM-based encryption keys for ZFS datasets -- TPM2 binaries
 Provides zfs-tpm2-change-key, zfs-tpm2-clear-key, and zfs-tpm2-load-key
 for TPM 2.0 back-end.
EOF
build_deb "$S" "tzpfms-tpm2_${DEB_VERSION}_${ARCH}.deb"

# ── tzpfms-tpm1x ──────────────────────────────────────────────────────────────
S="$(make_staging)"
install -Dm0755 -t "$S/usr/sbin/"             out/zfs-tpm1x-change-key out/zfs-tpm1x-clear-key out/zfs-tpm1x-load-key
install -Dm0644 -t "$S/usr/share/man/man8/"   out/man/zfs-tpm1x-change-key.8 out/man/zfs-tpm1x-clear-key.8 out/man/zfs-tpm1x-load-key.8

cat > "$S/DEBIAN/control" << EOF
Package: tzpfms-tpm1x
Version: ${DEB_VERSION}
Section: admin
Priority: optional
Architecture: ${ARCH}
Depends: libc6 (>= 2.17), libnvpair3linux (>= 0.8.2), libtspi1 (>= 0.3.1), ${LIBZFS_PKG} (>= 0.8.2)
Recommends: tzpfms-common (= ${DEB_VERSION}), trousers
Maintainer: automated build <build@localhost>
Description: TPM-based encryption keys for ZFS datasets -- TPM 1.x binaries
 Provides zfs-tpm1x-change-key, zfs-tpm1x-clear-key, and zfs-tpm1x-load-key
 for TPM 1.x back-end.
EOF
build_deb "$S" "tzpfms-tpm1x_${DEB_VERSION}_${ARCH}.deb"

# ── tzpfms-initramfs ──────────────────────────────────────────────────────────
# Architecture-independent: shell scripts only.
S="$(make_staging)"
cp -aT out/initramfs-tools/ "$S/"

cat > "$S/DEBIAN/control" << EOF
Package: tzpfms-initramfs
Version: ${DEB_VERSION}
Section: admin
Priority: optional
Architecture: all
Depends: tzpfms-common (= ${DEB_VERSION}), zfs-initramfs
Suggests: tzpfms-tpm2 (= ${DEB_VERSION}), tzpfms-tpm1x (= ${DEB_VERSION})
Maintainer: automated build <build@localhost>
Description: TPM-based encryption keys for ZFS datasets -- initramfs-tools integration
 initramfs-tools hooks for tzpfms, enabling ZFS-on-root early-boot key loading.
EOF
build_deb "$S" "tzpfms-initramfs_${DEB_VERSION}_all.deb"

# ── tzpfms-dracut ─────────────────────────────────────────────────────────────
# Architecture-independent: shell scripts only.
S="$(make_staging)"
cp -aT out/dracut/ "$S/"

cat > "$S/DEBIAN/control" << EOF
Package: tzpfms-dracut
Version: ${DEB_VERSION}
Section: admin
Priority: optional
Architecture: all
Depends: tzpfms-common (= ${DEB_VERSION}), zfs-dracut
Suggests: tzpfms-tpm2 (= ${DEB_VERSION}), tzpfms-tpm1x (= ${DEB_VERSION})
Maintainer: automated build <build@localhost>
Description: TPM-based encryption keys for ZFS datasets -- dracut integration
 dracut module for tzpfms, enabling ZFS-on-root early-boot key loading.
EOF
build_deb "$S" "tzpfms-dracut_${DEB_VERSION}_all.deb"

echo "==> All packages built in /out/"
