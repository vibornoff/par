FROM debian:trixie

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gosu \
        fakeroot \
        dpkg-dev \
    && rm -rf /var/lib/apt/lists/*

# Debian trixie (13) ships systemd units in /usr/lib.
ENV SYSTEMDUNITDIR="/usr/lib/systemd/system"

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY build-pkg.sh  /usr/local/bin/build-pkg.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/build-pkg.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/build-pkg.sh"]
