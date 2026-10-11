# Built images

Reference images built from the Aether Linux **0.3** desktop base
(kernel `6.18.54-aether4`), as the from-source server build host is not
available. They are derived artifacts, not a from-source server build, and are
labelled as such.

| Image | Virtual size | SHA-256 |
| --- | --- | --- |
| `aether-server-0.1-x86_64.iso` | ~1.8 GiB (ISO) | `eb4b5e3d98b6833eec9703728c8c280fa6363b62e980e272bcc5bf8794318cbe` |
| `aether-server-0.1-x86_64.vmdk` | 16 GiB virtual / ~6 GiB on disk | `323cce9fb9d9a747eb1457264c20ba1446d1713f6e2c476defa49858fef30fc6` |

## How they were produced

Both are built from a server rootfs prepared by
`build/server/scripts/prepare-server-rootfs.sh` (assets, catalog, backend and a
graphical installer compiled against the base's Qt 6).

- **ISO** — `build-server-iso.sh`: a busybox initrd carrying `build/server/live/live-init`,
  the server rootfs squashed to `/live/rootfs.squashfs`, `/live/aether-server-release`
  = `0.1`, and a console-first GRUB menu, assembled with `grub-mkrescue`.
- **VMDK** — `build-server-vmdk.sh`: a fresh GPT disk (BIOS boot + EFI System
  Partition + ext4 root), the server rootfs copied on, GRUB installed for BIOS
  and UEFI, exported with `qemu-img`.

## Boot verification

- ISO: booted headlessly with QEMU (`-nographic`). The live initrd found the
  medium, mounted the squashfs, switch-rooted, and systemd reached a serial
  console login banner: `Aether Server 0.1 Development aether ttyS0` / `aether login:`.
- VMDK: booted headlessly with QEMU (BIOS, serial console).

## Distribution

The ISO (under GitHub's 2 GiB per-asset limit) is attached to the repository's
Releases. The VMDK exceeds that limit and is delivered outside GitHub
(OneDrive `Desktop\Aether-Server\`) together with this ISO and a VMware `.vmx`.

## Provenance caveat

The base kernel, initrd tooling and desktop userland come from Aether 0.3. The
server edition layer (installer, backend, catalog, assets, first-boot) is 0.1.
The role software for most roles is **not** present in the base; the installer
reports those roles unavailable rather than failing.
