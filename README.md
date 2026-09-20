# Mote

Mote is a tiny command-line VM manager for Apple silicon Macs, built directly on
Apple's Virtualization framework.

See [ROADMAP.md](ROADMAP.md) for planned milestones and project boundaries.

To prepare a bootable Fedora ARM64 disk today, follow
[Install Fedora Server for Mote with QEMU](docs/install-fedora-with-qemu.md).

## Requirements

- Apple silicon Mac
- macOS 14 or newer
- Xcode command-line tools
- ARM64 guest operating systems

## Build

The build script compiles Mote and ad-hoc signs it with the Virtualization
entitlement:

```sh
chmod +x scripts/build.sh
./scripts/build.sh
```

Run the tests with the full Xcode toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

## Usage

```sh
.build/release/mote host
.build/release/mote create ubuntu --cpus 4 --memory 8G --disk 64G
.build/release/mote list
.build/release/mote start ubuntu
```

By default, VM bundles live in
`~/Library/Application Support/Mote/Virtual Machines`. Set `MOTE_HOME` to use a
different directory.

`mote start` runs a VM in the foreground with EFI boot, a writable virtio disk,
NAT networking, entropy and memory-balloon devices, and an interactive serial
console. Press `Ctrl-]` once to request graceful guest shutdown and again to
force stop. `SIGINT` and `SIGTERM` follow the same behavior.

New VM disks are blank. Until Mote gains an installer, replace `disk.img` with a
bootable raw ARM64 Linux disk image of the same size. The guest must be configured
to use its virtio serial console (commonly `console=hvc0`) for terminal output and
input. Mote does not yet install an ISO or display a graphical console.
