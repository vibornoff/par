#!/bin/sh
set -e

BUILD_UID="${BUILD_UID:-1000}"
BUILD_GID="${BUILD_GID:-1000}"

if ! getent group "$BUILD_GID" > /dev/null 2>&1; then
    groupadd -g "$BUILD_GID" builder
fi
if ! getent passwd "$BUILD_UID" > /dev/null 2>&1; then
    useradd -m -u "$BUILD_UID" -g "$BUILD_GID" -s /bin/sh builder
fi

exec gosu "$BUILD_UID" "$@"
