# Install Fedora Server with Mote

Mote can install an ARM64 Fedora Server ISO directly with Apple's Virtualization
framework. Installation runs in the foreground and opens a native macOS window
for the Fedora installer.

## Requirements

- Apple silicon Mac
- Fedora Server ISO whose filename contains `aarch64` or `arm64`
- A built and signed Mote executable

An `x86_64` or `amd64` ISO cannot run on Apple silicon through
Virtualization.framework.

## 1. Build Mote

```sh
./scripts/build.sh
```

## 2. Create an empty VM

The following example keeps its VMs in the repository's ignored `vms` directory:

```sh
export MOTE_HOME="$PWD/vms"

.build/release/mote create fedora \
  --cpus 4 \
  --memory 4G \
  --disk 32G
```

## 3. Start the installer

```sh
.build/release/mote install fedora \
  --iso /absolute/path/to/Fedora-Server-dvd-aarch64.iso
```

Mote attaches the ISO read-only ahead of the writable system disk and opens a
1280×800 VM window. The VM also has NAT networking, virtio entropy, a memory
balloon, and a serial console attached to the launching terminal.

In Anaconda:

1. Select the 32 GiB system disk as the installation destination, not the Fedora
   installation medium.
2. Automatic partitioning is sufficient and should create an EFI system
   partition.
3. Enable networking if necessary.
4. Create an administrator user and password.
5. Install Fedora Server.

The terminal that launched Mote remains the lifecycle console. Press `Ctrl-]`
once to request guest shutdown. A second press force-stops the VM and risks losing
unwritten guest data.

## 4. Complete the first boot

Allow Fedora to reboot when installation finishes. Its EFI boot entry may take
precedence over the still-attached installer, allowing the installed system to
start in the same window. Log in there and continue to the next section.

If the installer starts again, request shutdown with `Ctrl-]`, wait for Mote to
exit, and boot the installed disk without the ISO but with a display:

```sh
.build/release/mote start fedora --display
```

`--display` is useful until Fedora's virtio serial console is configured. Normal
headless starts do not create a window.

## 5. Configure the serial console

Inside Fedora, add `hvc0` to every installed kernel:

```sh
sudo grubby --update-kernel=ALL \
  --args="console=tty0 console=hvc0"
```

Enable a login prompt and include the virtio console driver in the initramfs:

```sh
sudo systemctl enable serial-getty@hvc0.service

echo 'add_drivers+=" virtio_console "' | \
  sudo tee /etc/dracut.conf.d/mote.conf

sudo dracut --force --regenerate-all
```

Confirm the kernel arguments:

```sh
sudo grubby --info=ALL | grep '^args='
```

Every entry should contain `console=hvc0`.

## 6. Verify fallback EFI boot

The installed disk should contain the standard ARM64 fallback bootloader so it
does not depend solely on one EFI variable-store entry:

```sh
sudo test -f /boot/efi/EFI/BOOT/BOOTAA64.EFI
```

If it is missing, install Fedora's ARM64 EFI packages:

```sh
sudo dnf install -y \
  grub2-efi-aa64 \
  grub2-efi-aa64-modules \
  shim-aa64
```

Then try installing a removable-media loader:

```sh
sudo grub2-install \
  --target=arm64-efi \
  --efi-directory=/boot/efi \
  --removable \
  --recheck

sudo grub2-mkconfig -o /boot/grub2/grub.cfg
```

If Fedora prevents `grub2-install` for its signed EFI packages, copy its installed
ARM64 GRUB binary into the fallback location:

```sh
sudo install -d /boot/efi/EFI/BOOT
sudo install -m 0644 \
  /boot/efi/EFI/fedora/grubaa64.efi \
  /boot/efi/EFI/BOOT/BOOTAA64.EFI
```

## 7. Test a normal Mote boot

Shut Fedora down cleanly:

```sh
sudo poweroff
```

Then start it without a display or installation media:

```sh
.build/release/mote start fedora
```

The terminal should show Fedora kernel output followed by an `hvc0` login prompt.
After logging in, verify the guest:

```sh
uname -m
cat /proc/cmdline
lsblk
ip address
```

Expected results:

- `uname -m` prints `aarch64`.
- `/proc/cmdline` contains `console=hvc0`.
- The virtio system disk is present.
- The network interface receives an address through Mote's NAT network.

## Re-running installation

Mote records that installation was attempted. It does not treat that record as
proof that an operating system was successfully installed. A second installation
requires an explicit override:

```sh
.build/release/mote install fedora \
  --iso /absolute/path/to/Fedora-Server-dvd-aarch64.iso \
  --force
```

This does not erase the disk before booting the installer. Any repartitioning or
data loss occurs only through actions taken inside the installer.

## QEMU fallback

If a particular Fedora installer does not work with Mote, follow
[Install Fedora Server for Mote with QEMU](install-fedora-with-qemu.md). Both
paths operate on the same raw `disk.img` format.
