#!/bin/bash
# Assemble an installed-disk Aether Server VMDK from a prepared server rootfs.
#
# Creates a fresh GPT disk (BIOS boot + EFI System Partition + ext4 root that
# fills the disk), copies the server rootfs onto it, installs GRUB for BIOS and
# UEFI, writes the fstab, the server identity (hostname / os-release) and the
# GRUB menu, resets the machine identity, and exports the result as a VMware disk.
#
# Usage:
#   build-server-vmdk.sh --root /path/to/server-rootfs --out /path/to/aether-server.vmdk [--size 16G]
#
# Needs qemu-img, sfdisk, mkfs.fat, mkfs.ext4, rsync, grub-install and blkid.
set -euo pipefail

root=''
out=''
size='16G'
admin_user='aether'
admin_password='aether2026'
while [ $# -gt 0 ]; do
    case "$1" in
        --root) root=${2:?--root needs a path}; shift 2 ;;
        --out)  out=${2:?--out needs a path}; shift 2 ;;
        --size) size=${2:?--size needs a value}; shift 2 ;;
        --admin-user) admin_user=${2:?--admin-user needs a value}; shift 2 ;;
        --admin-password) admin_password=${2:?--admin-password needs a value}; shift 2 ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ -n "$root" ] && [ -n "$out" ] || { echo 'Both --root and --out are required.' >&2; exit 2; }
root=$(realpath -e "$root")
case "$out" in /*) ;; *) out=$(realpath -m "$out") ;; esac

for program in qemu-img sfdisk mkfs.fat mkfs.ext4 rsync grub-install blkid; do
    command -v "$program" >/dev/null || { echo "Missing build tool: $program" >&2; exit 1; }
done
test -x "$root/usr/bin/aether-server-installer"
test -d "$root/usr/lib/grub/$(uname -m)-efi" || true

work=$(mktemp -d)
ROOT=$work/rootfs
raw=$work/disk.raw
LOOP=''
cleanup() {
    set +e
    for d in dev proc sys; do umount "$ROOT/$d" 2>/dev/null; done
    umount "$ROOT/boot/efi" 2>/dev/null
    umount "$ROOT" 2>/dev/null
    [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT

echo "==> creating a $size disk image"
truncate -s "$size" "$raw"

echo "==> partitioning (GPT: BIOS boot, EFI, root)"
sfdisk "$raw" >/dev/null <<'EOF'
label: gpt
start=2048, size=4096, type=21686148-6449-6E6F-744E-656564454649, name="BIOS boot"
size=1048576, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI System"
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="Aether root"
EOF

echo "==> attaching loop device"
LOOP=$(losetup --find --show --partscan "$raw")
partx -a "$raw" 2>/dev/null || true
sleep 1
mkfs.fat -F32 -n AETHER_EFI "${LOOP}p2" >/dev/null
mkfs.ext4 -q -F -L aether-root "${LOOP}p3"

echo "==> copying the server rootfs"
mkdir -p "$ROOT"
mount "${LOOP}p3" "$ROOT"
mkdir -p "$ROOT/boot/efi"
mount "${LOOP}p2" "$ROOT/boot/efi"
rsync -aHAX --numeric-ids "$root/" "$ROOT/"

echo "==> writing fstab"
uuid=$(blkid -s UUID -o value "${LOOP}p3")
efiuuid=$(blkid -s UUID -o value "${LOOP}p2")
partuuid=$(blkid -s PARTUUID -o value "${LOOP}p3")
cat >"$ROOT/etc/fstab" <<EOF
# <file system>                            <mount point>  <type>  <options>        <dump> <pass>
UUID=$uuid   /              ext4    defaults         0      1
UUID=$efiuuid   /boot/efi      vfat    umask=0077       0      2
EOF

echo "==> installing GRUB (BIOS + UEFI)"
grub-install --target=i386-pc --boot-directory="$ROOT/boot" --recheck "$LOOP" >/dev/null
grub-install --target=x86_64-efi --boot-directory="$ROOT/boot" \
    --efi-directory="$ROOT/boot/efi" --bootloader-id=Aether --no-nvram >/dev/null
grub-install --target=x86_64-efi --boot-directory="$ROOT/boot" \
    --efi-directory="$ROOT/boot/efi" --removable --no-nvram >/dev/null

release=$(ls "$ROOT"/boot/vmlinuz-* 2>/dev/null | sed 's/.*vmlinuz-//' | sort -V | tail -1)
test -n "$release" || { echo 'No kernel found in the rootfs.' >&2; exit 1; }
echo "==> GRUB menu (kernel $release)"
cat >"$ROOT/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=3
serial --unit=0 --speed=115200
terminal_input console serial
terminal_output console serial
insmod part_gpt
insmod ext2
search --no-floppy --fs-uuid --set=root $uuid
menuentry 'Aether Server 0.1 (console)' {
    linux /boot/vmlinuz-$release root=PARTUUID=$partuuid rootwait rw console=tty0 console=ttyS0,115200n8 systemd.unit=multi-user.target quiet loglevel=3
}
menuentry 'Aether Server 0.1 (verbose)' {
    linux /boot/vmlinuz-$release root=PARTUUID=$partuuid rootwait rw console=tty0 console=ttyS0,115200n8 systemd.unit=multi-user.target systemd.show_status=yes loglevel=7
}
if [ "\$grub_platform" = efi ]; then
    menuentry 'UEFI firmware settings' { fwsetup }
fi
EOF

echo "==> server identity"
printf 'aether-server\n' >"$ROOT/etc/hostname"
if [ -f "$ROOT/etc/hosts" ]; then
    sed -i '/^127\.0\.1\.1/d' "$ROOT/etc/hosts"
fi
printf '127.0.1.1 aether-server\n' >>"$ROOT/etc/hosts"
cat >"$ROOT/etc/os-release" <<'EOF'
NAME="Aether Server"
PRETTY_NAME="Aether Server 0.1 Development"
ID=aether
VERSION="0.1"
VERSION_ID="0.1"
LOGO=aether-logo
EOF
printf 'Aether Server 0.1 Development \\n \\l\n' >"$ROOT/etc/issue"

echo "==> configuring the administrator account"
# Set the hash directly in /etc/shadow: chpasswd runs the target's PAM stack,
# whose password-quality policy rejects the short development password. Writing
# the hash offline is deterministic and matches what an offline installer does.
if [ -n "$admin_password" ]; then
    command -v openssl >/dev/null || { echo 'openssl is needed to set the password' >&2; exit 1; }
    hash=$(openssl passwd -6 -salt "$(openssl rand -hex 8)" "$admin_password")
    python3 - "$ROOT" "$admin_user" "$hash" <<'PY'
import sys
root, user, digest = sys.argv[1:4]
path = root + '/etc/shadow'
lines = open(path, encoding='utf-8').read().splitlines()
for i, line in enumerate(lines):
    fields = line.split(':')
    if fields and fields[0] == user:
        fields[1] = digest
        lines[i] = ':'.join(fields)
        break
else:
    raise SystemExit(f'user {user!r} not found in {path}')
open(path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
print(f'  password set for {user}')
PY
fi
for d in dev proc sys; do mount --bind "/$d" "$ROOT/$d"; done

echo "==> resetting machine identity for a distributable image"
truncate -s0 "$ROOT/etc/machine-id"
rm -f "$ROOT/var/lib/systemd/random-seed" "$ROOT/var/lib/dbus/machine-id"
rm -f "$ROOT"/etc/ssh/ssh_host_* 2>/dev/null || true
chroot "$ROOT" ldconfig

for d in dev proc sys; do umount "$ROOT/$d"; done
umount "$ROOT/boot/efi" "$ROOT"
sync
losetup -d "$LOOP"; LOOP=''

echo "==> exporting VMDK"
rm -f "$out"
qemu-img convert -p -O vmdk -o subformat=monolithicSparse "$raw" "$out"
echo "VMDK written: $out"
qemu-img info "$out" | head -5
sha256sum "$out"
