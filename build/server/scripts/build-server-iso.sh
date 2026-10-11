#!/bin/bash
# Assemble the Aether Server live ISO from a prepared server rootfs.
#
# The ISO boots a small busybox initrd that mounts the rootfs squashfs as a
# read-only lower layer under a writable overlay, so the same medium can both
# "try" the server and run the installer. The graphical installer is launched
# on demand by aether-server-setup; the default target is the console.
#
# Usage:
#   build-server-iso.sh --root /path/to/server-rootfs --out /path/to/aether-server.iso
#
# Needs mksquashfs, xorriso, cpio, gzip and grub-mkrescue on the build host.
set -euo pipefail

root=''
out=''
release=''
volid='AETHER_SERVER_01'
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root=${2:?--root needs a path}; shift 2 ;;
        --out)  out=${2:?--out needs a path}; shift 2 ;;
        --release) release=${2:?--release needs a value}; shift 2 ;;
        --volid) volid=${2:?--volid needs a value}; shift 2 ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ -n "$root" ] && [ -n "$out" ] || { echo 'Both --root and --out are required.' >&2; exit 2; }
root=$(realpath -e "$root")
case "$out" in /*) ;; *) out=$(realpath -m "$out") ;; esac
repo=$(realpath "$(dirname "$0")/../../..")

for program in mksquashfs xorriso cpio gzip grub-mkrescue; do
    command -v "$program" >/dev/null || { echo "Missing build tool: $program" >&2; exit 1; }
done
test -x "$root/usr/bin/aether-server-setup"
test -x "$root/usr/bin/aether-server-installer"
test -f "$root/usr/share/aether/server/roles.json"
test -f "$root/usr/libexec/aether-server-install-backend"

if [ -z "$release" ]; then
    release=$(ls "$root"/boot/vmlinuz-* 2>/dev/null | sed 's/.*vmlinuz-//' | sort -V | tail -1)
fi
test -n "$release" || { echo 'Could not determine the kernel release; pass --release.' >&2; exit 1; }
test -f "$root/boot/vmlinuz-$release" || { echo "No kernel for release $release." >&2; exit 1; }

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/live" "$stage/boot/grub"

echo "==> building the live initrd"
initrd=$stage/initrd
mkdir -p "$initrd"/{bin,lib,usr,dev,proc,sys,run,newroot}
install -m755 "$root/usr/lib/aether-initramfs/busybox" "$initrd/bin/busybox"
ln -sfn busybox "$initrd/bin/sh"
ln -sfn lib "$initrd/lib64"
ln -sfn ../lib "$initrd/usr/lib"
for library in libc.so.6 libresolv.so.2 ld-linux-x86-64.so.2; do
    install -m755 "$root/usr/lib/$library" "$initrd/lib/$library"
done
install -m755 "$repo/build/server/live/live-init" "$initrd/init"
install -m755 "$repo/build/server/live/live-shutdown" "$initrd/shutdown"
chroot "$initrd" /bin/busybox true
chroot "$initrd" /bin/sh -n /init
chroot "$initrd" /bin/sh -n /shutdown
( cd "$initrd" && find . -print0 | cpio --null --quiet -o --format=newc --owner=0:0 | gzip -9 ) >"$stage/boot/initrd.img"
rm -rf "$initrd"

echo "==> copying the kernel"
install -m644 "$root/boot/vmlinuz-$release" "$stage/boot/vmlinuz"

echo "==> writing release markers"
# aether-server-release is the marker the server live-init looks for;
# aether-release records the Aether base the image was derived from.
printf '%s\n' "$(cat "$root/usr/share/aether/server/version" 2>/dev/null || echo 0.1)" >"$stage/live/aether-server-release"
printf '0.3\n' >"$stage/live/aether-release"

echo "==> squashing the server rootfs"
mksquashfs "$root" "$stage/live/rootfs.squashfs" -noappend -comp xz \
    -processors "$(nproc)" -one-file-system \
    -e 'dev/*' 'proc/*' 'sys/*' 'run/*' 'tmp/*'

echo "==> writing the GRUB menu"
cat >"$stage/boot/grub/grub.cfg" <<'EOF'
set default=0
set timeout=8
serial --unit=0 --speed=115200
terminal_input console serial
terminal_output console serial
menuentry 'Install or try Aether Server 0.1' {
    linux /boot/vmlinuz console=tty0 console=ttyS0,115200n8 systemd.unit=multi-user.target quiet loglevel=3
    initrd /boot/initrd.img
}
menuentry 'Aether Server live diagnostics' {
    linux /boot/vmlinuz console=tty0 console=ttyS0,115200n8 systemd.show_status=yes loglevel=7
    initrd /boot/initrd.img
}
if [ "$grub_platform" = efi ]; then
    menuentry 'UEFI firmware settings' { fwsetup }
fi
EOF

echo "==> grub-mkrescue"
rm -f "$out"
grub-mkrescue --fonts= --themes= --locales= -o "$out" "$stage" -volid "$volid" >/dev/null
echo "ISO written: $out"
sha256sum "$out"
