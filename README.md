# Mote

Mote is a tiny command-line VM manager for Apple silicon Macs, built directly on
Apple's Virtualization framework.

See [ROADMAP.md](ROADMAP.md) for planned milestones and project boundaries.
See [How Mote works](docs/how-mote-works.md) for a detailed guide to the
architecture, bundle format, supervisor lifecycle, and source code.

To install Fedora ARM64 natively, follow
[Install Fedora Server with Mote](docs/install-fedora-with-mote.md).

## Requirements

- Apple silicon Mac
- macOS 14 or newer
- Xcode command-line tools
- ARM64 guest operating systems

## Build

The release target compiles Mote and ad-hoc signs it with the Virtualization
entitlement:

```sh
make release
```

Run the tests with the full Xcode toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

## Usage

```sh
.build/release/mote host
.build/release/mote create ubuntu --cpus 4 --memory 8G --disk 64G
.build/release/mote install ubuntu --iso /path/to/installer-aarch64.iso
.build/release/mote list
.build/release/mote show ubuntu
.build/release/mote start ubuntu
.build/release/mote attach ubuntu
.build/release/mote display ubuntu
.build/release/mote stop ubuntu
.build/release/mote restart ubuntu
.build/release/mote delete ubuntu --force
```

By default, VM bundles live in
`~/Library/Application Support/Mote/Virtual Machines`. Set `MOTE_HOME` to use a
different directory.

`mote install` attaches an ARM64 ISO read-only and opens a native graphical
installer window.

`mote start` launches a VM supervisor in the background with EFI boot, a writable
virtio disk, NAT networking, entropy, a memory balloon, graphics, and a serial
console. Use `mote display <name>` to open its native window and `mote attach
<name>` to connect the current terminal to its serial console. Press `Ctrl-]` to
detach without stopping the VM.

`mote start <name> --display` opens the display immediately after starting.
`mote start <name> --console` starts and immediately attaches the serial console;
both options may be used together.

`mote stop <name>` requests a graceful guest shutdown and waits for the
supervisor to release the VM. Use `--force` to stop immediately. `restart`
supports the same option. Deletion is intentionally limited to stopped VMs and
requires `mote delete <name> --force`.

`mote show` reports configuration, logical and allocated disk sizes,
installation metadata, bundle location, and runtime state. `host`, `list`, and
`show` accept `--json` for structured output.

New VM disks are blank until `mote install` runs. The installed guest must be
configured to use its virtio serial console (commonly `console=hvc0`) for
headless terminal output and input.
