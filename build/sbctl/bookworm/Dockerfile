# golang:1.23-bookworm bundles a recent Go toolchain on top of debian:bookworm.
# Debian bookworm's own golang-go (1.19) is too old for sbctl (requires >= 1.20).
FROM golang:1.24-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
        binutils \
        util-linux \
        asciidoc \
        libpcsclite-dev \
        gosu \
        fakeroot \
        dpkg-dev \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY build-pkg.sh  /usr/local/bin/build-pkg.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/build-pkg.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/build-pkg.sh"]
