#!/bin/sh
set -eu

usage() {
    cat <<'EOF'
Install Fedora Server into a new Mote VM disk using QEMU.

Usage:
  scripts/install-fedora-with-qemu.sh --iso PATH [options]

Required:
  --iso PATH          Fedora Server aarch64 ISO

Options:
  --name NAME         VM name (default: fedora)
  --cpus COUNT        Virtual CPUs (default: 4)
  --memory SIZE       Guest memory (default: 4G)
  --disk SIZE         Guest disk size (default: 32G)
  --store PATH        Mote VM store (default: <project>/vms)
  -h, --help          Show this help

The Fedora installer remains interactive. QEMU exits when the installer performs
its first reboot, leaving the installed disk ready for the configuration boot
described in docs/install-fedora-with-qemu.md.
EOF
}

fail() {
    echo "install-fedora-with-qemu: $*" >&2
    exit 1
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(dirname -- "$script_dir")

fedora_iso=""
vm_name="fedora"
vm_cpus="4"
vm_memory="4G"
vm_disk_size="32G"
mote_store="$project_dir/vms"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --iso)
            [ "$#" -ge 2 ] || fail "--iso requires a path"
            fedora_iso=$2
            shift 2
            ;;
        --name)
            [ "$#" -ge 2 ] || fail "--name requires a value"
            vm_name=$2
            shift 2
            ;;
        --cpus)
            [ "$#" -ge 2 ] || fail "--cpus requires a value"
            vm_cpus=$2
            shift 2
            ;;
        --memory)
            [ "$#" -ge 2 ] || fail "--memory requires a value"
            vm_memory=$2
            shift 2
            ;;
        --disk)
            [ "$#" -ge 2 ] || fail "--disk requires a value"
            vm_disk_size=$2
            shift 2
            ;;
        --store)
            [ "$#" -ge 2 ] || fail "--store requires a path"
            mote_store=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

[ -n "$fedora_iso" ] || {
    usage >&2
    exit 2
}

case "$fedora_iso" in
    /*) ;;
    *) fedora_iso="$PWD/$fedora_iso" ;;
esac

case "$mote_store" in
    /*) ;;
    *) mote_store="$PWD/$mote_store" ;;
esac

[ -f "$fedora_iso" ] || fail "ISO not found: $fedora_iso"

iso_name=$(basename -- "$fedora_iso")
case "$iso_name" in
    *aarch64*|*AARCH64*) ;;
    *) fail "ISO filename must contain 'aarch64'; x86_64 guests cannot run in Mote" ;;
esac

case "$fedora_iso$mote_store" in
    *,*) fail "ISO and store paths cannot contain commas because QEMU drive options use commas" ;;
esac

command -v brew >/dev/null 2>&1 || fail "Homebrew is required: https://brew.sh"

if ! command -v qemu-system-aarch64 >/dev/null 2>&1; then
    [ -t 0 ] || fail "QEMU is not installed; run 'brew install qemu' first"
    printf '%s' "QEMU is not installed. Install it with Homebrew now? [y/N] "
    read -r answer
    case "$answer" in
        y|Y|yes|YES)
            brew install qemu
            ;;
        *)
            fail "QEMU is required; install it with 'brew install qemu'"
            ;;
    esac
fi

qemu_share="$(brew --prefix qemu)/share/qemu"
qemu_efi="$qemu_share/edk2-aarch64-code.fd"
[ -f "$qemu_efi" ] || fail "QEMU ARM64 EFI firmware not found: $qemu_efi"

vm_bundle="$mote_store/$vm_name.motevm"
[ ! -e "$vm_bundle" ] || fail "VM already exists: $vm_bundle"

echo "Building and signing Mote…"
(cd "$project_dir" && ./scripts/build.sh)

mote="$project_dir/.build/release/mote"
[ -x "$mote" ] || fail "Mote executable was not produced: $mote"

echo "Creating VM '$vm_name'…"
MOTE_HOME="$mote_store" "$mote" create "$vm_name" \
    --cpus "$vm_cpus" \
    --memory "$vm_memory" \
    --disk "$vm_disk_size"

mote_disk="$vm_bundle/disk.img"
[ -f "$mote_disk" ] || fail "Mote disk was not created: $mote_disk"

cat <<EOF

Starting the Fedora installer.

Installation target:
  $mote_disk

In Anaconda:
  1. Select the $vm_disk_size virtio disk as the installation destination.
  2. Use automatic partitioning and create an administrator account.
  3. Complete the installation and allow Fedora to request a reboot.

QEMU uses -no-reboot, so it will exit at that first reboot. Do not start Mote
until QEMU has exited.

EOF

qemu-system-aarch64 \
    -name "$vm_name" \
    -machine virt,accel=hvf,highmem=on \
    -cpu host \
    -smp "$vm_cpus" \
    -m "$vm_memory" \
    -bios "$qemu_efi" \
    -drive if=none,id=system,format=raw,file="$mote_disk",cache=none \
    -device virtio-blk-pci,drive=system,bootindex=1 \
    -drive if=none,id=installer,format=raw,readonly=on,file="$fedora_iso" \
    -device virtio-blk-pci,drive=installer,bootindex=0 \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -device virtio-gpu-pci \
    -device qemu-xhci,id=xhci \
    -device usb-kbd,bus=xhci.0 \
    -device usb-tablet,bus=xhci.0 \
    -display cocoa \
    -no-reboot

cat <<EOF

QEMU exited. If Fedora completed installation and requested a reboot, continue at
"Boot the installed system once with QEMU" in:

  $project_dir/docs/install-fedora-with-qemu.md

VM store for the remaining commands:

  export MOTE_HOME="$mote_store"
  export MOTE_VM_NAME="$vm_name"
  export MOTE_DISK="$mote_disk"

EOF
