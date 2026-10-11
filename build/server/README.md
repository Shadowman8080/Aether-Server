# Aether Server build — 0.1

The server edition is a second image target on the Aether base. This repository
does not rebuild that base (a multi-hour source build); it **derives** the server
edition from a prepared Aether base rootfs, the way a derivative distribution
does, and produces an installable ISO and VMDK.

```
build/server/
├── live/
│   ├── live-init              find the server medium and switch-root onto a
│   │                          writable overlay of its squashfs
│   └── live-shutdown          tear the live mounts down cleanly
└── scripts/
    ├── prepare-server-rootfs.sh   base rootfs → server rootfs (assets, config,
    │                              and a compiled graphical installer)
    ├── install-server-assets.sh   copy assets, catalog, configs, backend and
    │                              launchers into an offline Aether root
    ├── configure-server.py        image facts: version marker, multi-user
    │                              target, firstboot enablement, role dirs,
    │                              default firewall.json
    ├── build-server-iso.sh        server rootfs → aether-server-0.1-*.iso
    ├── build-server-vmdk.sh       server rootfs → aether-server-0.1-*.vmdk
    ├── build-server-packages.py   catalog → source-build recipe plan
    │                              (scaffolding; nothing is compiled yet)
    ├── test-server-roles.py       23-unit test suite for the catalog/backend
    └── test-server-roles.sh       thin wrapper for running the suite
```

## Pipeline

```
Aether base rootfs
   │  prepare-server-rootfs.sh        copy, install assets, compile the Qt
   ▼                                  installer against the base's Qt, configure
server rootfs ─┬─ build-server-iso.sh ─▶ aether-server-0.1-x86_64.iso   (live/install)
               └─ build-server-vmdk.sh ─▶ aether-server-0.1-x86_64.vmdk (installed disk)
```

1. `install-server-assets.sh /path/to/offline/root` installs the versioned
   assets, the role catalog as `/usr/share/aether/server/roles.json`, the
   per-role templates, the `aether-server-install-backend` and `server_roles.py`
   under `/usr/libexec/`, and the `aether-server-setup` / `aether-directory`
   launchers. It finishes by running the backend's `--validate` inside the
   chroot, so a catalog that fails to parse stops the image build.
2. `prepare-server-rootfs.sh --base … --out …` copies the base rootfs, calls
   `install-server-assets.sh`, builds `src/server/installer` with CMake/Ninja
   inside a chroot of the copy (the base ships GCC, CMake and Qt 6), runs
   `configure-server.py`, and writes the server `os-release`. The graphical
   installer ends up at `/usr/bin/aether-server-installer`.
3. `configure-server.py --root …` records `/etc/aether/server-version`, sets
   `multi-user.target` as default, enables `aether-server-firstboot.service`,
   creates the directories the shipped role templates assume (`/srv/www`,
   `/srv/aether`, `/srv/restic`, `/var/log/remote`, `/etc/aether`,
   `/etc/aether-security`), and writes a default empty `firewall.json`.
4. `build-server-iso.sh --root … --out …` builds a busybox initrd carrying
   `live/live-init`, squashes the root (`-one-file-system`, excluding
   dev/proc/sys/run/tmp), writes `/live/aether-server-release`, and emits the
   ISO with a console-first GRUB menu (install/try, live diagnostics, UEFI
   firmware settings) on serial + console via `grub-mkrescue`.
5. `build-server-vmdk.sh --root … --out …` builds a fresh GPT disk (BIOS boot +
   EFI System Partition + ext4 root), copies the server rootfs, installs GRUB
   for BIOS and UEFI, writes the fstab and GRUB menu, resets the machine
   identity, and exports a monolithic-sparse VMDK with `qemu-img`.
6. `build-server-packages.py --list` reads the catalog and prints exactly what
   each role would be built from. `--build` is the bring-up path that compiles
   each backlogged recipe into the base, which is what flips a role's status
   from *unavailable* to *available*.

## Tests

`test-server-roles.py` exercises the catalog, the backend helpers and the role
application path entirely off-line (`python3 test-server-roles.py`; 23 tests).
It validates the catalog, checks every role's templates exist, applies roles to
a throwaway root and asserts the configs/services/firewall/audit results, and
verifies the directory-join writers. Nothing here needs root, Linux, Qt, or a
real image.

## Status — say it plainly

- The **layout, the catalog→role mapping, and the image build** are exercised.
  A server ISO and VMDK have been built from the Aether 0.3 base and the
  installer runs from the medium.
- **No built role software and no `adcli`.** `build-server-packages.py` is
  scaffolding: none of its recipes has been compiled and no source pins exist
  for the role packages yet. Selecting one of those roles reports
  *unavailable*, naming the missing binary or package, rather than failing the
  install.
- The Active Directory join writes the domain configuration and reports the
  machine-account join as pending when `adcli` is absent.
- The images inherit the base account `aether` / `aether2026`; the VMDK builder
  resets it to that documented value so a fresh image has a known login. Change
  it on first boot.
