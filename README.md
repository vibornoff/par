# PAR — Personal APT Repository

A self-hosted APT repository that builds selected upstream packages from source
inside Docker containers and publishes the resulting `.deb` files via GitHub
Pages.

## Contents

| Package                                            | Version | Distros                           | Upstream                           |
| -------------------------------------------------- | ------- | --------------------------------- | ---------------------------------- |
| [sbctl](https://github.com/Foxboron/sbctl)         | 0.18    | bookworm, trixie                  | Secure Boot key manager            |
| [tzpfms](https://git.sr.ht/~nabijaczleweli/tzpfms) | v0.4.1  | bookworm, trixie, noble, resolute | TPM-backed encryption keys for ZFS |

## Using the repository

### 1. Import the signing key

```sh
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://vibornoff.github.io/par/pubkey.asc \
     -o /etc/apt/keyrings/vibornoff.asc
```

### 2. Add the sources

Replace `<codename>` with your distro codename (`bookworm`, `trixie`, `noble`, or `resolute`).

tzpfms links against libzfs, so pick the codename that matches the host's OpenZFS: e.g. the `resolute`
build needs `libzfs7linux` (OpenZFS 2.4) and does not install on trixie (2.3, `libzfs6linux`). The binaries
link the exact soname (`libzfs.so.6` or `.so.7`), so an alternative `libzfs7linux | libzfs6linux` dependency
would install a binary that cannot start. The two libraries cannot be co-installed either: both ship
`libzfs_core.so.3`, and `libzfs7linux` Breaks/Replaces `libzfs6linux`. A trixie host moving to OpenZFS 2.4
from trixie-backports needs tzpfms rebuilt against it, switched in the same apt transaction: otherwise apt
removes either tzpfms or zfsutils-linux.

```sh
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/vibornoff.asc] \
https://vibornoff.github.io/par/ <codename> main" \
| sudo tee /etc/apt/sources.list.d/vibornoff.list
```

> **Note — sbctl on Ubuntu:** `sbctl` is built on `bookworm` (the only shared
> library it links is `libpcsclite.so.1`, from `libpcsclite1`). To install it on
> `noble` or `resolute`, add a `bookworm` line alongside your Ubuntu line:
>
> ```sh
> echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/vibornoff.asc] \
> https://vibornoff.github.io/par/ bookworm main" \
> | sudo tee -a /etc/apt/sources.list.d/vibornoff.list
> ```

### 3. Install

```sh
sudo apt update
sudo apt install sbctl
# or
sudo apt install tzpfms-tpm2 tzpfms-common tzpfms-initramfs
```

## Repository structure

```
packages/               upstream sources (git submodules / worktrees)
  sbctl/0.18/
  tzpfms/v0.4.1/

build/                  Docker build contexts
  sbctl/
    bookworm/Dockerfile
    trixie/Dockerfile
    entrypoint.sh       creates matching uid/gid inside the container
    build-pkg.sh        make install → staging tree → dpkg-deb
  tzpfms/
    bookworm/Dockerfile
    trixie/Dockerfile
    noble/Dockerfile
    resolute/Dockerfile
    entrypoint.sh
    build-pkg.sh        produces 5 split .deb packages

scripts/
  build.sh              build a package for a target OS
  index.sh              generate APT metadata and sign Release files

repo/                   apt repository root (published on GitHub Pages)
  pool/<os>/            .deb files
  dists/<os>/           Release, InRelease, Packages{,.gz,.bz2}
  pubkey.asc            GPG public key
```

## Building packages locally

Requires Docker and Bash.

```sh
# sbctl for Debian bookworm / trixie
scripts/build.sh sbctl/0.18 bookworm
scripts/build.sh sbctl/0.18 trixie

# tzpfms for Debian trixie
scripts/build.sh --deb-version-suffix=vibornoff tzpfms/v0.4.1 trixie

# tzpfms for Ubuntu noble
scripts/build.sh tzpfms/v0.4.1 noble

# tzpfms for Ubuntu resolute
scripts/build.sh tzpfms/v0.4.1 resolute
```

Output `.deb` files land in `repo/pool/<os>/`.

Pass `--deb-version-suffix=<suffix>` to override the local build suffix (default
`local`). Published tzpfms builds use `vibornoff`:

```sh
scripts/build.sh --deb-version-suffix=vibornoff tzpfms/v0.4.1 noble
```

Version scheme: `<upstream_version>+<suffix>1`
(e.g. `0.4.1-1+vibornoff1`) — always greater than the upstream Debian package
(`0.4.1-1`) but less than the next upstream release (`0.4.2-1`), so `apt upgrade`
will replace this build automatically when a newer upstream version appears.

## Generating and signing repository metadata

```sh
# Generate metadata only (unsigned)
scripts/index.sh

# Generate and sign with a GPG key
scripts/index.sh --key-id=<fingerprint-or-email>
# or
GPG_KEY_ID=<fingerprint-or-email> scripts/index.sh

# Process a specific distro only
scripts/index.sh --key-id=<key> noble
```

After signing, `repo/dists/<os>/InRelease` and `repo/dists/<os>/Release.gpg` are
created alongside an updated `repo/pubkey.asc`.

## Adding a new package version

1. Add the new version as a submodule pinned to the desired tag:
   ```sh
   git submodule add --name "pkg/1.2.3" \
       https://example.com/pkg.git packages/pkg/1.2.3
   git -C packages/pkg/1.2.3 checkout v1.2.3
   git submodule absorbgitdirs
   git add .gitmodules packages/pkg/1.2.3
   git commit -m "add pkg 1.2.3"
   ```
2. Add a `build/pkg/` directory with `entrypoint.sh`, `build-pkg.sh`, and one
   `Dockerfile` per target OS (copy and adapt an existing package's layout).
3. Build and verify locally:
   ```sh
   scripts/build.sh pkg/1.2.3 <os>
   ```
4. Run `scripts/index.sh --key-id=<key>` and commit `repo/`.

## Adding a new target OS

1. Add `build/<package>/<new-os>/Dockerfile` with the correct library names in
   `ENV` variables (`LIBZFS_PKG`, `LIBSSL_PKG`, etc.).
2. Build: `scripts/build.sh <package>/<version> <new-os>`.
3. Re-run `scripts/index.sh`.
