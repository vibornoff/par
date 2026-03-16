FROM ubuntu:noble

# ZFS packages live in the 'universe' component on Ubuntu.
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common \
    && add-apt-repository -y universe \
    && apt-get update && apt-get install -y --no-install-recommends \
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

# Runtime library names on Ubuntu noble (24.04).
# libzfs4linux = OpenZFS 2.2.x; tss2/ssl packages carry the Ubuntu t64 suffix.
ENV LIBZFS_PKG="libzfs4linux" \
    LIBSSL_PKG="libssl3t64" \
    LIBTSS2_ESYS_PKG="libtss2-esys-3.0.2-0t64" \
    LIBTSS2_RC_PKG="libtss2-rc0t64"

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY build-pkg.sh  /usr/local/bin/build-pkg.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/build-pkg.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/build-pkg.sh"]
