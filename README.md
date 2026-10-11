# Aether Server

The server edition of [Aether Linux](https://github.com/Shadowman8080/Aether):
a console-first image with a **graphical installer**, data-driven server-role
selection, and an option to join an Active Directory domain during install.

This repository is the server edition split out from the main Aether tree. It
carries the installer, the privileged backend, the role catalog and its
configuration templates, and the build tooling that turns an Aether base image
into an installable **Aether Server ISO** and **VMDK**.

> **Honesty note.** Aether does not ship what it has not built. This edition is
> at **0.1 (development)**. The installer, backend, role catalog and directory
> join are implemented and unit-tested; the server software for many roles is
> **not built into the image yet**, and the installer says so per role instead
> of pretending otherwise. See [Role availability](#role-availability).

## What is in the box

| Piece | Path | State |
| --- | --- | --- |
| Graphical installer (Qt 6 Widgets/Svg wizard) | `src/server/installer/main.cpp` | Implemented |
| Installer launcher (`aether-server-setup`) | `src/server/installer/aether-server-setup` | Implemented |
| Post-install directory tool (`aether-directory`) | `src/server/installer/aether-directory` | Implemented |
| Privileged backend (`aether-server-install`) | `src/server/backend/aether-server-install` | Implemented, tested |
| Role engine | `src/server/backend/server_roles.py` | Implemented, unit-tested |
| Role catalog (27 roles) | `src/server/roles/catalog.json` | Implemented |
| Per-role config templates | `src/server/roles/configs/` | Implemented |
| Edition assets (polkit, motd, firewall, first boot) | `src/server/assets/` | Implemented |

The role catalog is **data, not code**. The installer UI and the backend read
the same `roles.json`; adding a role is a catalog entry plus its configuration
templates, with no change to the installer or the backend.

## Layout

```
src/server/                 the edition itself
  installer/                Qt 6 wizard, launcher, aether-directory
  backend/                  privileged installer + role engine
  roles/                    catalog.json and configs/<role>/
  assets/                   files installed into the image root
build/server/
  live/                     live-init / live-shutdown for the live medium
  scripts/                  image assembly, packaging plan, tests
docs/server.md              full role reference
```

## Building the image

The image build turns a prepared **Aether base rootfs** into a server medium.
Because a base rootfs is produced by the main Aether build (a multi-hour
source build), this repository does not rebuild it: it *derives* the server
edition from a base, exactly as a derivative distribution would.

```sh
# 1. Prepare a server rootfs from an Aether base rootfs (copies it, installs the
#    edition assets, configures the image, and compiles the graphical installer).
build/server/scripts/prepare-server-rootfs.sh \
    --base /path/to/aether-0.3-rootfs \
    --out  /path/to/server-rootfs

# 2. Assemble the live ISO.
build/server/scripts/build-server-iso.sh \
    --root /path/to/server-rootfs \
    --out  /path/to/aether-server-0.1-x86_64.iso

# 3. Assemble an installed-disk VMDK.
build/server/scripts/build-server-vmdk.sh \
    --root /path/to/server-rootfs \
    --out  /path/to/aether-server-0.1-x86_64.vmdk
```

`prepare-server-rootfs.sh` needs a Linux host with `gcc`/`g++`, `cmake`,
`ninja`, and the base rootfs's Qt 6 development files (present in the Aether
base). `build-server-iso.sh` needs `mksquashfs`, `xorriso`, `cpio`, `gzip`, and
GRUB's `grub-mkrescue`. `build-server-vmdk.sh` needs `qemu-img`, `sgdisk` or
`sfdisk`, `mkfs.fat`, `mkfs.ext4`, and `grub-install`.

The prebuilt artifacts are attached to the repository's **Releases** rather than
committed (see `docs/server.md` for what each contains).

## Running the installer

On the live medium, `aether-server-setup` picks the lightest Qt platform that can
present a window (an existing Wayland/X11 session, then the framebuffer via
`linuxfb`, then `eglfs`) and launches the wizard. Set `AETHER_SERVER_TTY=1` to
run the text installer instead, or `AETHER_SERVER_QT_PLATFORM=...` to force a
platform.

The wizard walks through disk, hostname, network, the administrator account,
the server roles, and an optional Active Directory join, then hands off to
`/usr/libexec/aether-server-install-backend`, which performs the install and
reports progress as `AETHER_PROGRESS` JSON lines.

## Role availability

The installer reports each selected role as `applied`, `partial`, or
`unavailable`. Availability is computed from the image: a role is available when
one of its packages is installed or one of its binaries is present (a role with
neither requirement is configuration-only and always available). Because the
server software for most roles is not built into the Aether base yet, phases
that run on a fresh base will report most roles **unavailable** — on purpose,
with the missing binary or package named. `docs/server.md` lists all 27 roles.

## License

GPL-3.0-only, matching Aether. The installer sources are GPL-2.0-or-later.
