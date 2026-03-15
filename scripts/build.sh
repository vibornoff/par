#!/usr/bin/env bash
# Usage: scripts/build.sh <package>/<version> <os>
#
# Examples:
#   scripts/build.sh sbctl/0.18     bookworm
#   scripts/build.sh tzpfms/v0.4.1  bookworm
#   scripts/build.sh tzpfms/v0.4.1  noble
#
# The script:
#   1. Builds (or refreshes) a Docker image from build/<package>/<os>/Dockerfile.
#   2. Runs a container with the package source bind-mounted at
#      /workspace/<package> and the output directory at /out.
#   3. Passes the caller's UID/GID into the container so that output files
#      are owned by the invoking user.
#
# Output .deb files are written to repo/<os>/ relative to the repository root.

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
DEB_VERSION_SUFFIX="local"

args=()
for arg in "$@"; do
    case "$arg" in
        --deb-version-suffix=*)
            DEB_VERSION_SUFFIX="${arg#*=}"
            ;;
        *)
            args+=("$arg")
            ;;
    esac
done
set -- "${args[@]}"

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 [--deb-version-suffix=SUFFIX] <package>/<version> <os>" >&2
    echo "  e.g. $0 sbctl/0.18 bookworm" >&2
    echo "  e.g. $0 --deb-version-suffix=artyrepo tzpfms/v0.4.1 noble" >&2
    exit 1
fi

PACKAGE="$1"
TARGET_OS="$2"

PKG_NAME="${PACKAGE%%/*}"
PKG_VERSION="${PACKAGE##*/}"

# ── Paths ─────────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTEXT_DIR="${REPO_ROOT}/build/${PKG_NAME}"
DOCKERFILE="${CONTEXT_DIR}/${TARGET_OS}/Dockerfile"
SOURCE_DIR="${REPO_ROOT}/packages/${PKG_NAME}/${PKG_VERSION}"
OUTPUT_DIR="${REPO_ROOT}/repo/pool/${TARGET_OS}"

# ── Validation ────────────────────────────────────────────────────────────────
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: source directory not found: $SOURCE_DIR" >&2
    exit 1
fi
if [[ ! -f "$DOCKERFILE" ]]; then
    echo "Error: Dockerfile not found: $DOCKERFILE" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ── Source commit timestamp ───────────────────────────────────────────────────
# The container has no git and cannot follow the worktree gitfile back to the
# host. Compute SOURCE_DATE_EPOCH here and pass it in, so the tzpfms Makefile
# (and any other build using it) can use a deterministic date for man pages.
SOURCE_DATE_EPOCH=$(git -C "$SOURCE_DIR" log -1 --no-show-signature --format=%at HEAD 2>/dev/null || date +%s)

# ── Docker image ──────────────────────────────────────────────────────────────
IMAGE_TAG="apt-repo/${PKG_NAME}:${TARGET_OS}"

echo "==> Building image ${IMAGE_TAG} ..."
# Build context is build/<package>/ so that entrypoint.sh and build-pkg.sh
# (shared across OS variants) are available for COPY in the Dockerfile.
docker build \
    --file    "$DOCKERFILE" \
    --tag     "$IMAGE_TAG" \
    "$CONTEXT_DIR"

# ── Container run ─────────────────────────────────────────────────────────────
echo "==> Building package ${PACKAGE} for ${TARGET_OS} ..."
docker run --rm \
    --env BUILD_UID="$(id -u)" \
    --env BUILD_GID="$(id -g)" \
    --env PKG_VERSION="${PKG_VERSION}" \
    --env DEB_VERSION_SUFFIX="${DEB_VERSION_SUFFIX}" \
    --env SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}" \
    --volume "${SOURCE_DIR}:/workspace/${PKG_NAME}" \
    --volume "${OUTPUT_DIR}:/out" \
    "$IMAGE_TAG"

echo "==> Done. Output: ${OUTPUT_DIR}/"
