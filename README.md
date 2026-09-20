# Mote

Mote is a tiny command-line VM manager for Apple silicon Macs, built directly on
Apple's Virtualization framework.

See [ROADMAP.md](ROADMAP.md) for planned milestones and project boundaries.

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
```

By default, VM bundles live in
`~/Library/Application Support/Mote/Virtual Machines`. Set `MOTE_HOME` to use a
different directory.

The current milestone creates VM bundles with a sparse disk, EFI variable store,
and versioned manifest. Booting and installing an ARM64 Linux ISO are next.
