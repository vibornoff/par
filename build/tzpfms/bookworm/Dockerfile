FROM debian:bookworm

# ZFS packages live in contrib on Debian.
# The sources file format differs between docker image versions; handle both.
RUN sed -i 's/^Components: main$/Components: main contrib/' \
        /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's/^\(deb [^ ]* bookworm main\)$/\1 contrib/' \
        /etc/apt/sources.list

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        pkgconf \
        libzfslinux-dev \
        libtss2-dev \
        libtspi-dev \
        libssl-dev \
        mandoc \
        gettext \
        gosu \
        fakeroot \
        dpkg-dev \
    && rm -rf /var/lib/apt/lists/*

# Runtime library names on Debian bookworm (OpenZFS 2.1.x = libzfs4linux,
# tss2 packages without the Ubuntu t64 suffix, libssl3 without t64).
ENV LIBZFS_PKG="libzfs4linux" \
    LIBSSL_PKG="libssl3" \
    LIBTSS2_ESYS_PKG="libtss2-esys-3.0.2-0" \
    LIBTSS2_RC_PKG="libtss2-rc0"

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY build-pkg.sh  /usr/local/bin/build-pkg.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/build-pkg.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/build-pkg.sh"]
