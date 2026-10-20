FROM debian:bookworm

# dh-dkms only for its maintainer script templates; nothing is compiled here.
RUN apt-get update && apt-get install -y --no-install-recommends \
        make \
        dh-dkms \
        gosu \
        fakeroot \
        dpkg-dev \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY build-pkg.sh  /usr/local/bin/build-pkg.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/build-pkg.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/build-pkg.sh"]
