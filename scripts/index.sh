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
#   deb [arch=amd64 signed-by=/etc/apt/keyrings/repo.asc] https://<user>.github.io/<repo>/ noble main
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

# ── Signing key check ─────────────────────────────────────────────────────────
# apt >= 3.0 (Debian trixie) verifies with sqv, whose policy rejects SHA-1 self-signatures (user ID and
# subkey bindings) since 2026-02-01: "Signing key ... is not bound", and the whole repo counts as unsigned.
# sqv checks the binding at the time of each repo signature, so after re-issuing the self-signatures every
# dist must be signed again.
if [[ -n "$KEY_ID" ]]; then
    FPR="$(gpg --with-colons --list-keys "$KEY_ID" | awk -F: '/^fpr/ {print $10; exit}')"
    WEAK="$(gpg --export "$FPR" | LC_ALL=C gpg --list-packets 2>/dev/null | awk -v kid="${FPR: -16}" '
        /^:user ID packet:/                       { obj = "uid " substr($0, 18); seen[obj] = 1; next }
        /^:public sub key packet:/                { obj = "subkey #" ++n; seen[obj] = 1; next }
        /^:signature packet:/                     { self = index($0, "keyid " kid) > 0; cls = ""; next }
        self && /sigclass 0x/                     { cls = $NF; next }
        self && cls ~ /^0x1[0-38]$/ && /digest algo/ {
            split($0, a, /digest algo |,/); if (a[2] + 0 != 2) ok[obj] = 1 }
        END { for (o in seen) if (!(o in ok)) print "  " o }')"
    if [[ -n "$WEAK" ]]; then
        echo "Error: key $FPR is bound only by SHA-1 self-signatures, apt >= 3.0 (sqv) rejects the repo:" >&2
        echo "$WEAK" >&2
        echo "Re-issue them (keep the current expiry, 0 = never), then re-run this script for all dists:" >&2
        echo "  gpg --cert-digest-algo SHA512 --quick-set-expire $FPR 0" >&2
        echo "  gpg --cert-digest-algo SHA512 --quick-set-expire $FPR 0 '*'" >&2
        exit 1
    fi
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
        gpg --batch --yes --default-key "$KEY_ID" --digest-algo SHA512 \
            --clearsign -o "$DIST_DIR/InRelease" "$DIST_DIR/Release"
        # Release.gpg — detached signature (legacy compatibility)
        gpg --batch --yes --default-key "$KEY_ID" --digest-algo SHA512 \
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
    echo "  deb [arch=amd64 signed-by=/etc/apt/keyrings/repo.asc] https://<user>.github.io/<repo>/ $OS main"
done
