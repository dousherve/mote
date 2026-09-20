# Install Fedora Server for Mote with QEMU

Mote can run an installed ARM64 Linux system, but it cannot attach installation
media yet. This guide uses QEMU once to install Fedora Server into the raw disk
that Mote creates. After installation, the same disk boots with Apple's
Virtualization framework through `mote start`.

The process does not convert or copy the disk between hypervisors:

```text
Mote creates disk.img
        │
        ▼
QEMU installs Fedora into disk.img
        │
        ▼
Fedora is configured for EFI fallback boot and hvc0
        │
        ▼
Mote boots disk.img
```

## Requirements

- An Apple silicon Mac
- A Fedora Server ISO whose filename contains `aarch64`
- Homebrew
- A built and signed Mote executable

An `x86_64` ISO cannot run through Virtualization.framework on Apple silicon.
Download the ARM aarch64 Server DVD or network-install ISO from the
[official Fedora Server download page](https://www.fedoraproject.org/server/download/)
and verify it using Fedora's published checksum.

> [!WARNING]
> The installer will repartition the selected VM disk. Use a new Mote VM or back
> up any bundle that contains data you care about. Never run QEMU and Mote against
> the same `disk.img` at the same time.

## 1. Build Mote

From the repository root:

```sh
./scripts/build.sh
```

The result is `.build/release/mote`, signed with the Virtualization entitlement.

### Automated setup through the first reboot

Steps 1 through 4 can be performed by the included host-side script:

```sh
scripts/install-fedora-with-qemu.sh \
  --iso /absolute/path/to/Fedora-Server-dvd-aarch64.iso
```

The script checks the ISO architecture from its filename, offers to install QEMU
when necessary, builds Mote, creates a fresh VM bundle, and opens the interactive
Fedora installer. It passes `-no-reboot` to QEMU, so QEMU exits when Fedora asks
for its first reboot. Continue at step 5 afterward.

Use `--help` to customize the VM name, store, CPU count, memory, or disk size. The
remaining sections show every command the script performs and can also be
followed manually.

## 2. Choose paths and create the VM

Choose an isolated VM store and point `FEDORA_ISO` at the downloaded ISO. Use an
absolute ISO path so QEMU can find it regardless of the working directory.

```sh
export MOTE_HOME="$PWD/vms"
export MOTE_VM_NAME="fedora"
export FEDORA_ISO="/absolute/path/to/Fedora-Server-dvd-aarch64.iso"

test -f "$FEDORA_ISO"
```

Create a VM with a 32 GiB sparse raw disk:

```sh
.build/release/mote create "$MOTE_VM_NAME" \
  --cpus 4 \
  --memory 4G \
  --disk 32G
```

Record the disk path and confirm that it exists:

```sh
export MOTE_DISK="$MOTE_HOME/$MOTE_VM_NAME.motevm/disk.img"

ls -lh "$MOTE_DISK"
du -h "$MOTE_DISK"
```

`ls` reports the logical 32 GiB size. `du` should report very little allocated
space because the new disk is sparse.

## 3. Install QEMU

Install QEMU from Homebrew:

```sh
brew install qemu
```

Locate QEMU's ARM64 UEFI firmware:

```sh
export QEMU_SHARE="$(brew --prefix qemu)/share/qemu"
export QEMU_EFI="$QEMU_SHARE/edk2-aarch64-code.fd"

qemu-system-aarch64 --version
test -f "$QEMU_EFI"
```

QEMU uses Apple's Hypervisor framework (`hvf`) here, so the ARM64 guest runs with
hardware virtualization rather than CPU emulation.

## 4. Run the Fedora installer

Start QEMU with the Fedora ISO as the first bootable virtio disk and Mote's raw
disk as the installation target:

```sh
qemu-system-aarch64 \
  -machine virt,accel=hvf,highmem=on \
  -cpu host \
  -smp 4 \
  -m 4G \
  -bios "$QEMU_EFI" \
  -drive if=none,id=system,format=raw,file="$MOTE_DISK",cache=none \
  -device virtio-blk-pci,drive=system,bootindex=1 \
  -drive if=none,id=installer,format=raw,readonly=on,file="$FEDORA_ISO" \
  -device virtio-blk-pci,drive=installer,bootindex=0 \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0 \
  -device virtio-gpu-pci \
  -device qemu-xhci,id=xhci \
  -device usb-kbd,bus=xhci.0 \
  -device usb-tablet,bus=xhci.0 \
  -display cocoa
```

In the Fedora installer:

1. Select the 32 GiB virtio disk as the installation destination. Do not select
   the Fedora installation medium.
2. Automatic partitioning is sufficient. It should create an EFI system
   partition along with the Fedora system partitions.
3. Enable the network if the installer has not enabled it automatically.
4. Create an administrator user and password.
5. Install Fedora Server. A graphical desktop is not required.
6. Shut the VM down when installation finishes. If the installer only offers a
   reboot, quit QEMU when it begins rebooting so it does not start the ISO again.

## 5. Boot the installed system once with QEMU

Run QEMU again without the installation medium:

```sh
qemu-system-aarch64 \
  -machine virt,accel=hvf,highmem=on \
  -cpu host \
  -smp 4 \
  -m 4G \
  -bios "$QEMU_EFI" \
  -drive if=none,id=system,format=raw,file="$MOTE_DISK",cache=none \
  -device virtio-blk-pci,drive=system,bootindex=0 \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0 \
  -device virtio-gpu-pci \
  -device qemu-xhci,id=xhci \
  -device usb-kbd,bus=xhci.0 \
  -device usb-tablet,bus=xhci.0 \
  -display cocoa
```

Log in using the account created during installation.

## 6. Enable Mote's virtio serial console

Mote connects its terminal to a virtio console. Linux exposes that console as
`/dev/hvc0`. Add both the graphical console and `hvc0` to every installed kernel:

```sh
sudo grubby --update-kernel=ALL \
  --args="console=tty0 console=hvc0"
```

Enable a login prompt on `hvc0`:

```sh
sudo systemctl enable serial-getty@hvc0.service
```

Ensure the virtio console driver is present in the early boot environment:

```sh
echo 'add_drivers+=" virtio_console "' | \
  sudo tee /etc/dracut.conf.d/mote.conf

sudo dracut --force --regenerate-all
```

Confirm that the kernel arguments were updated:

```sh
sudo grubby --info=ALL | grep '^args='
```

Each entry should contain `console=hvc0`.

## 7. Verify the fallback EFI loader

QEMU and Mote maintain different EFI variable stores. A boot entry created in
QEMU's firmware is therefore not available to Mote. The disk needs the standard
ARM64 removable-media fallback loader:

```sh
sudo test -f /boot/efi/EFI/BOOT/BOOTAA64.EFI
```

If that succeeds, continue to the next section. If the file is missing, first
ensure Fedora's ARM64 EFI packages are installed:

```sh
sudo dnf install -y \
  grub2-efi-aa64 \
  grub2-efi-aa64-modules \
  shim-aa64
```

Then install a removable-media GRUB loader and regenerate its configuration:

```sh
sudo grub2-install \
  --target=arm64-efi \
  --efi-directory=/boot/efi \
  --removable \
  --recheck

sudo grub2-mkconfig -o /boot/grub2/grub.cfg
```

Some Fedora installations intentionally prevent `grub2-install` for signed EFI
packages. If it reports that restriction, use the installed Fedora GRUB binary as
the fallback loader:

```sh
sudo install -d /boot/efi/EFI/BOOT
sudo install -m 0644 \
  /boot/efi/EFI/fedora/grubaa64.efi \
  /boot/efi/EFI/BOOT/BOOTAA64.EFI
```

Verify the final path:

```sh
ls -l /boot/efi/EFI/BOOT/BOOTAA64.EFI
```

Shut Fedora down cleanly:

```sh
sudo poweroff
```

Wait for the QEMU process to exit before starting Mote.

## 8. Boot Fedora with Mote

From the Mote repository on the host:

```sh
MOTE_HOME="$MOTE_HOME" \
  .build/release/mote start "$MOTE_VM_NAME"
```

Expected lifecycle messages look like this:

```text
mote: Starting virtual machine…
mote: Virtual machine is running. Press Ctrl-] to request shutdown.
```

Fedora kernel messages should follow, ending at an `hvc0` login prompt. Log in
with the account created during installation.

Inside Fedora, confirm the architecture and devices:

```sh
uname -m
cat /proc/cmdline
lsblk
ip address
```

Expected results:

- `uname -m` prints `aarch64`.
- `/proc/cmdline` contains `console=hvc0`.
- The virtio system disk is visible.
- The network interface has an address obtained through Mote's NAT network.

To stop the VM, prefer shutting it down inside Fedora:

```sh
sudo poweroff
```

From the host console, press `Ctrl-]` once to request graceful shutdown. Press it
a second time only when the guest is unresponsive; the second request force-stops
the VM and may lose unwritten guest data.

## Troubleshooting

### The VM immediately stops under Mote

The EFI firmware probably did not find a bootloader. Boot the disk with QEMU and
check:

```sh
ls -l /boot/efi/EFI/BOOT/BOOTAA64.EFI
```

Repeat the fallback EFI loader step if the file is absent.

### Mote stays running but displays no Fedora output

Boot with QEMU and verify:

```sh
sudo grubby --info=ALL | grep '^args='
systemctl is-enabled serial-getty@hvc0.service
grep virtio_console /etc/dracut.conf.d/mote.conf
```

Regenerate the initramfs after correcting anything:

```sh
sudo dracut --force --regenerate-all
```

### QEMU opens the EFI shell instead of the installer

Confirm that the ISO is ARM64, both paths exist, and the ISO was attached with
`bootindex=0`:

```sh
test -f "$FEDORA_ISO"
test -f "$MOTE_DISK"
```

At the EFI shell, `exit` returns to the firmware boot manager, where the installer
device can be selected manually.

### Fedora has no network under Mote

Mote presents a virtio network adapter backed by NAT. In Fedora, inspect it with:

```sh
nmcli device status
ip address
```

If necessary, ask NetworkManager to connect the interface shown by `nmcli`:

```sh
sudo nmcli device connect <interface>
```

### Recovering the guest

The QEMU command in step 5 remains a useful recovery console. Ensure Mote is not
running, boot the disk with QEMU, make the repair, shut down, and try Mote again.

## Native Mote alternative

Mote can now attach an ARM64 ISO and present a graphical installer directly. See
[Install Fedora Server with Mote](install-fedora-with-mote.md). This QEMU path is
retained as a compatibility and recovery option.
