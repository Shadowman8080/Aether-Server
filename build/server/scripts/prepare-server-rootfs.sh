#!/bin/bash
# Prepare an Aether Server rootfs from an Aether base rootfs.
#
# Copies the base, installs the server edition (assets, role catalog, backend,
# launchers), compiles the Qt graphical installer against the base's Qt, and
# configures the image for the console-first server edition.
#
# Usage:
#   prepare-server-rootfs.sh --base /path/to/aether-base-rootfs --out /path/to/server-rootfs
#
# The base rootfs is the offline root produced by the main Aether build. This
# script never rebuilds it; it derives the server edition from it.
set -euo pipefail

base_rootfs=''
out=''
version='0.1'
while [ $# -gt 0 ]; do
    case "$1" in
        --base) base_rootfs=${2:?--base needs a path}; shift 2 ;;
        --out)  out=${2:?--out needs a path}; shift 2 ;;
        --version) version=${2:?--version needs a value}; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -n "$base_rootfs" ] && [ -n "$out" ] || { echo 'Both --base and --out are required.' >&2; exit 2; }
base_rootfs=$(realpath -e "$base_rootfs")
case "$out" in /*) ;; *) out=$(realpath -m "$out") ;; esac
[ -f "$base_rootfs/etc/os-release" ] || { echo 'Base is not an Aether rootfs.' >&2; exit 2; }
grep -q 'Aether' "$base_rootfs/etc/os-release" || { echo 'Base is not an Aether rootfs.' >&2; exit 2; }
[ "$out" != "$base_rootfs" ] || { echo '--out must differ from --base.' >&2; exit 2; }

repo=$(realpath "$(dirname "$0")/../../..")

echo "==> copying $base_rootfs -> $out"
rm -rf "$out"
cp -a "$base_rootfs" "$out"

mounts=()
cleanup() { for m in "${mounts[@]:-}"; do umount "$m" 2>/dev/null || true; done; }
trap cleanup EXIT

echo "==> bind-mounting pseudo filesystems"
for d in proc sys dev run; do mount --bind "/$d" "$out/$d"; mounts+=("$out/$d"); done
mount -t tmpfs tmpfs "$out/tmp"; mounts+=("$out/tmp")

echo "==> installing server edition assets"
bash "$repo/build/server/scripts/install-server-assets.sh" "$out"

echo "==> compiling the graphical installer"
rm -rf "$out/root/build-server-installer"
cp -a "$repo/src/server/installer" "$out/root/build-server-installer"
chroot "$out" /usr/bin/env -i PATH=/usr/bin:/usr/sbin:/bin:/sbin HOME=/root \
    bash -c '
        set -e
        cd /root/build-server-installer
        cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
        cmake --build build
        cmake --install build --prefix /usr
    '
test -x "$out/usr/bin/aether-server-installer" || { echo 'Installer did not build.' >&2; exit 1; }
rm -rf "$out/root/build-server-installer"

echo "==> configuring the server image"
python3 "$repo/build/server/scripts/configure-server.py" --root "$out" --version "$version"

echo "==> writing the server edition identity"
cat >"$out/etc/os-release" <<EOF
NAME="Aether Server"
PRETTY_NAME="Aether Server $version Development"
ID=aether
VERSION="$version"
VERSION_ID="$version"
LOGO=aether-logo
EOF
printf 'Aether Server %s Development \\n \\l\n' "$version" >"$out/etc/issue"

for d in proc sys dev run tmp; do umount "$out/$d" 2>/dev/null || true; done
mounts=()

echo "==> verifying the prepared rootfs"
chroot "$out" /usr/bin/python3 /usr/libexec/aether-server-install-backend --validate
echo "Server rootfs ready at $out"
