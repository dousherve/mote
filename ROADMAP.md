# Mote roadmap

Mote is a small, native command-line VM manager for Apple silicon Macs. It uses
Virtualization.framework directly and favors understandable VM bundles, few
dependencies, and predictable commands over a large feature set.

The roadmap is ordered by dependency and risk rather than by calendar date.

## Guiding constraints

- Support ARM64 Linux guests first.
- Keep the core dependency-free beyond Apple system frameworks.
- Store each VM as a portable, inspectable `.motevm` bundle.
- Keep each running VM in a small unprivileged supervisor; avoid a global daemon.
- Prefer safe, explicit lifecycle operations; never silently discard guest data.
- Keep configuration backward-compatible through a versioned manifest.
- Target macOS 14 or newer until a newer API provides a compelling simplification.

## Milestone 0 — Bundle foundation

Status: complete

- Provide `help`, `version`, `host`, `create`, and `list` commands.
- Parse human-readable binary sizes.
- Validate host CPU and memory limits.
- Create a versioned JSON manifest, sparse disk, and EFI variable store.
- Support an isolated VM store through `MOTE_HOME`.
- Build and sign with the Virtualization entitlement.
- Cover parsing and storage primitives with tests.

Exit criteria:

- A signed release binary creates and rediscovers a valid `.motevm` bundle.
- A large logical disk consumes negligible physical space when empty.

## Milestone 1 — First Linux boot

Goal: boot an ARM64 Linux guest and expose its serial console in the terminal.

Status: implemented; end-to-end guest login verification requires a bootable
ARM64 raw disk image.

- [x] Add a configuration builder separate from CLI parsing and persistence.
- [x] Configure `VZEFIBootLoader` using the bundle's persistent EFI variable store.
- [x] Attach the primary disk through a virtio block device.
- [x] Add virtio entropy and memory-balloon devices.
- [x] Add a virtio serial port connected to stdin and stdout.
- [x] Add NAT networking with a virtio network device.
- [x] Implement the initial foreground `mote start <name>` runner, later
  superseded by the Milestone 3 supervisor.
- [x] Validate the complete `VZVirtualMachineConfiguration` before starting.
- [x] Forward termination signals into graceful and forced shutdown paths.
- [x] Report VM lifecycle transitions and actionable framework errors.

Exit criteria:

- `mote start <name> --console` reaches a Linux login prompt in the current
  terminal.
- The guest sees its configured CPUs, memory, disk, and network interface.
- Exiting or interrupting Mote does not leave corrupt bundle state.

## Milestone 2 — Installation media

Goal: install Linux into an empty Mote VM without manually editing its bundle.

Status: implemented; end-to-end Fedora installation verification is pending a
real ARM64 installer run.

- [x] Implement `mote install <name> --iso <path>`.
- [x] Require ARM64 installation media and reject obviously incompatible inputs.
- [x] Attach the ISO as a read-only USB mass-storage device.
- [x] Make device ordering explicit during installation.
- [x] Detach installation media when the installer VM exits.
- [x] Record installation state in the manifest without treating it as authoritative
  guest state.
- [x] Document a Fedora installation and serial-console flow.

Exit criteria:

- A fresh VM can install and subsequently boot from its own disk.
- Re-running installation requires explicit confirmation or a force option.

If mainstream installers cannot provide a usable serial interface, add a minimal
AppKit display runner backed by `VZVirtualMachineView`. Keep it as a presentation
layer over the same VM core rather than moving VM logic into the UI.

## Milestone 3 — Reliable lifecycle management

Goal: make everyday VM operations safe and unsurprising.

Status: in progress

- [x] Start VMs in background supervisor processes by default.
- [x] Add `mote attach <name>` and `mote display <name>` for delayed serial and
  graphical access.
- [ ] Add `mote show <name>` for configuration, bundle path, disk allocation, and
  runtime state.
- [ ] Add graceful `stop`, forced `stop --force`, `restart`, and `delete` commands.
- [x] Add a per-VM lock so two processes cannot run or mutate one VM concurrently.
- [x] Persist the runner PID and detect stale runtime metadata.
- [ ] Use stable exit codes for usage, missing VM, invalid configuration, and runtime
  failure.
- [ ] Make command output script-friendly; add `--json` where structured output is
  useful.
- [ ] Add temporary-directory and interrupted-write tests for storage operations.

Design checkpoint:

The need for delayed display and serial attachment established the case for a
detached process. Each VM now has its own supervisor and bundle-local control
channel; Mote still has no global daemon or privileged helper.

Exit criteria:

- Concurrent and destructive operations fail safely.
- A guest can be started, inspected, stopped, restarted, and deleted entirely
  through documented commands.

## Milestone 4 — Useful host integration

Goal: make Linux guests pleasant for development without turning Mote into an
orchestration platform.

- Give each VM a stable locally administered MAC address.
- Add read-only and read-write virtio filesystem shares.
- Support host-to-guest port forwarding if it can be implemented cleanly; do not
  depend on undocumented networking behavior.
- Add clipboard support only if it has a small, supportable guest component.
- Offer Rosetta directory sharing for Linux guests as an explicit opt-in on
  supported macOS versions.
- Document SSH discovery and access patterns.

Exit criteria:

- A guest can access the internet, exchange files with an approved host folder,
  and expose a development service predictably.

## Milestone 5 — Image and bundle operations

Goal: reduce setup time while keeping storage behavior transparent.

- Add `clone`, `rename`, and disk-resize operations.
- Report logical and physically allocated disk size separately.
- Import supported raw disk images.
- Evaluate a small image catalog only after checksum verification and cache
  behavior are designed.
- Add manifest migrations and fixtures for every supported schema version.
- Investigate crash-consistent cloning and snapshots; expose them only if their
  guarantees can be stated clearly.

Exit criteria:

- VM bundles can be copied, moved, imported, and upgraded without identity or
  data surprises.

## Milestone 6 — Optional native interface

Goal: add a thin macOS interface where the CLI is inherently insufficient.

- Present graphical guest output with `VZVirtualMachineView`.
- Support keyboard and pointer input.
- Reuse the same configuration, store, and lifecycle components as the CLI.
- Keep every non-graphical operation available from the command line.

This milestone is optional. A display runner may be pulled forward into Milestone
2 if graphical Linux installation proves necessary.

## Milestone 7 — macOS guests

Goal: support macOS only after the Linux lifecycle is stable.

- Download or load a supported IPSW restore image.
- Persist the hardware model, machine identifier, and auxiliary storage.
- Install through `VZMacOSInstaller` with progress reporting.
- Configure macOS graphics, input, audio, and platform devices.
- Document host/guest compatibility and Apple-specific limitations.

macOS guests use a materially different platform and installation path. Their
metadata should extend the manifest through a typed guest-platform model rather
than optional Linux fields scattered throughout the codebase.

## Continuous work

These requirements apply to every milestone:

- Unit-test parsers, manifest migrations, and configuration policy.
- Add integration tests that do not require downloading guest media.
- Keep partial writes recoverable and destructive commands explicit.
- Treat malformed bundles as errors rather than guessing how to repair them.
- Keep `README.md` examples synchronized with the actual CLI.
- Verify release binaries carry the Virtualization entitlement.
- Record tested macOS, host architecture, and guest combinations.

## Deliberate non-goals

Until the core is mature, Mote will not attempt to provide:

- Intel guest emulation on Apple silicon.
- Kubernetes or multi-VM orchestration.
- A public cloud-style API.
- Undocumented bridged-network setup.
- Automatic background services or privileged helpers.
- Compatibility with every virtual disk format.

## Next implementation slice

Continue Milestone 3 with `mote show <name>`, supervisor-backed stop and restart
commands, and stable exit codes. Add `delete` only after those observability and
lifecycle controls are complete.
