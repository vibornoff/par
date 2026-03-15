#!/usr/bin/env bash
# Generate APT repository metadata (dists/) and optionally sign Release files.
#
# Usage: scripts/index.sh [--key-id=KEY] [<os> ...]
#
# Arguments:
#   --key-id=KEY   GPG key fingerprint or e-mail for signing.
#                  Can also be set via GPG_KEY_ID env var.
#   <os> ...       One or more pool subdirectory names to process.
#                  If omitted, all subdirectories of repo/pool/ are processed.
#
# Environment:
#   GPG_KEY_ID     Fallback key ID if --key-id is not passed.
#   APT_ORIGIN     Value for the Origin field in Release  (default: Personal APT Repository)
#   APT_LABEL      Value for the Label  field in Release  (default: personal)
#
# Tools required: apt-ftparchive (package apt-utils), gpg (for signing)
#
# APT sources.list entry (example for noble):
#   deb [signed-by=/etc/apt/keyrings/repo.asc] https://<user>.github.io/<repo>/ noble main
#
# Note on cross-distro packages (e.g. sbctl built on bookworm):
#   sbctl lives in pool/bookworm/ and is served under the bookworm codename.
#   To install it on noble/resolute, either:
#     a) add "deb [...] <url> bookworm main" alongside the noble sources line, or
#     b) copy the .deb into pool/noble/ and pool/resolute/ before running this script.

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
KEY_ID="${GPG_KEY_ID:-}"
POSITIONAL=()
for arg in "$@"; do
    case "$arg" in
        --key-id=*) KEY_ID="${arg#*=}" ;;
        *)          POSITIONAL+=("$arg") ;;
    esac
done
set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$REPO_ROOT/repo"
ORIGIN="${APT_ORIGIN:-Personal APT Repository}"
LABEL="${APT_LABEL:-personal}"

# ── OS list ───────────────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    OS_LIST=("$@")
else
    mapfile -t OS_LIST < <(
        find "$REPO_DIR/pool" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
    )
fi

if [[ ${#OS_LIST[@]} -eq 0 ]]; then
    echo "Error: no pool directories found under $REPO_DIR/pool/" >&2
    exit 1
fi

# ── Per-distro indexing ───────────────────────────────────────────────────────
for OS in "${OS_LIST[@]}"; do
    POOL_DIR="$REPO_DIR/pool/$OS"
    DIST_DIR="$REPO_DIR/dists/$OS"

    if [[ ! -d "$POOL_DIR" ]]; then
        echo "Warning: pool/$OS does not exist, skipping." >&2
        continue
    fi

    echo "==> Indexing $OS ..."

    mkdir -p "$DIST_DIR/main/binary-amd64"

    # Packages — Filename: paths are relative to REPO_DIR (the apt repo root).
    # apt-ftparchive includes both amd64 and arch:all packages in this file;
    # apt resolves arch:all packages from the architecture-specific Packages file.
    (cd "$REPO_DIR" && apt-ftparchive packages "pool/$OS") \
        > "$DIST_DIR/main/binary-amd64/Packages"

    gzip  --keep --force "$DIST_DIR/main/binary-amd64/Packages"
    bzip2 --keep --force "$DIST_DIR/main/binary-amd64/Packages"

    # Release — checksums over everything inside dists/<os>/
    apt-ftparchive \
        -o "APT::FTPArchive::Release::Origin=$ORIGIN" \
        -o "APT::FTPArchive::Release::Label=$LABEL" \
        -o "APT::FTPArchive::Release::Suite=$OS" \
        -o "APT::FTPArchive::Release::Codename=$OS" \
        -o "APT::FTPArchive::Release::Architectures=amd64" \
        -o "APT::FTPArchive::Release::Components=main" \
        -o "APT::FTPArchive::Release::Description=$ORIGIN – $OS" \
        release "$DIST_DIR" > "$DIST_DIR/Release"

    # Signing
    if [[ -n "$KEY_ID" ]]; then
        echo "    Signing $OS ..."
        # InRelease — cleartext-signed (preferred by modern apt)
        gpg --batch --yes --default-key "$KEY_ID" \
            --clearsign -o "$DIST_DIR/InRelease" "$DIST_DIR/Release"
        # Release.gpg — detached signature (legacy compatibility)
        gpg --batch --yes --default-key "$KEY_ID" \
            --detach-sign --armor -o "$DIST_DIR/Release.gpg" "$DIST_DIR/Release"
    else
        echo "    (GPG_KEY_ID not set — skipping signing)"
        rm -f "$DIST_DIR/InRelease" "$DIST_DIR/Release.gpg"
    fi
done

# ── Public key export ─────────────────────────────────────────────────────────
if [[ -n "$KEY_ID" ]]; then
    echo "==> Exporting public key → repo/pubkey.asc"
    gpg --armor --export "$KEY_ID" > "$REPO_DIR/pubkey.asc"
fi

echo "==> Done."
echo
echo "APT sources.list entry:"
for OS in "${OS_LIST[@]}"; do
    echo "  deb [signed-by=/etc/apt/keyrings/repo.asc] https://<user>.github.io/<repo>/ $OS main"
done
