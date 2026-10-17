FROM debian:trixie

# ZFS packages live in contrib on Debian.
RUN sed -i 's/^Components: main$/Components: main contrib/' \
        /etc/apt/sources.list.d/debian.sources

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

# Runtime library names on Debian trixie (13).
# OpenZFS 2.3.x = libzfs6linux (the resolute build needs libzfs7linux and does
# not install here); tss2/ssl packages carry the t64 suffix as on Ubuntu.
# trixie-backports ships OpenZFS 2.4 (libzfs7linux): rebuild if the host uses it.
ENV LIBZFS_PKG="libzfs6linux" \
    LIBSSL_PKG="libssl3t64" \
    LIBTSS2_ESYS_PKG="libtss2-esys-3.0.2-0t64" \
    LIBTSS2_RC_PKG="libtss2-rc0t64"

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY build-pkg.sh  /usr/local/bin/build-pkg.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/build-pkg.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/build-pkg.sh"]
