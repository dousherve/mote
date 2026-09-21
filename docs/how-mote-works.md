# How Mote works

This document explains the current Mote implementation from the command line
down to Apple’s Virtualization framework. It is intended to be read alongside
the source and describes what the code does today, including its limitations.

## 1. The short version

Mote is one Swift executable with two roles:

1. A short-lived CLI process parses commands, edits VM bundles, and starts or
   contacts running VMs.
2. A private background invocation of the same executable owns each running
   `VZVirtualMachine` until that guest stops.

There is no global daemon. Every running VM has one unprivileged supervisor
process. Durable VM state and the supervisor’s local communication files live
inside that VM’s `.motevm` bundle.

```text
                         one process per running VM

  mote start fedora ───► mote _run fedora ───► VZVirtualMachine
       CLI parent          supervisor              guest
          │                    ▲  ▲
          │                    │  │
          ├─ mote display ─────┤  │  bundle-local control FIFO
          ├─ mote stop ────────┘  │
          └─ mote attach ─────────┘  input FIFO + serial log
```

The public `start`, `display`, `stop`, and `attach` commands never share a
`VZVirtualMachine` object across processes. The supervisor owns the object;
other CLI processes communicate through files and FIFOs in the bundle.

## 2. Project structure

Mote is a Swift Package Manager project with no third-party dependencies.

```text
Package.swift
Makefile
Resources/
  Mote.entitlements
Sources/Mote/
  Mote.swift
  CLI.swift
  CLIOutput.swift
  ExitStatus.swift
  ISOImage.swift
  VMStore.swift
  VMRecord.swift
  VMConfigurationBuilder.swift
  VMRunner.swift
  VMDisplay.swift
  VMProcessLauncher.swift
  VMBackgroundSupervisor.swift
  VMRuntime.swift
  VMLock.swift
  VMControlChannel.swift
  VMISOControl.swift
  BackgroundConsole.swift
  SerialAttachment.swift
  TerminalSession.swift
  InstallationMedia.swift
  ByteSize.swift
Tests/MoteTests/
docs/
```

`Package.swift` defines:

- an executable product named `mote`;
- an executable target named `Mote`;
- a test target named `MoteTests`;
- a minimum deployment target of macOS 14;
- links to AppKit and Virtualization.framework.

AppKit is needed for `VZVirtualMachineView`. Virtualization.framework supplies
the VM, devices, boot loader, EFI variable store, and NAT attachment.

### Source inventory

| File | Responsibility |
|---|---|
| [`Mote.swift`](../Sources/Mote/Mote.swift) | Process entry point, output, and top-level error handling |
| [`CLI.swift`](../Sources/Mote/CLI.swift) | Command routing, argument parsing, and command orchestration |
| [`CLIOutput.swift`](../Sources/Mote/CLIOutput.swift) | Codable reports and deterministic JSON encoding |
| [`ExitStatus.swift`](../Sources/Mote/ExitStatus.swift) | Stable mapping from typed errors to `sysexits` codes |
| [`VMStore.swift`](../Sources/Mote/VMStore.swift) | Bundle paths, creation, loading, manifests, and runtime metadata |
| [`VMRecord.swift`](../Sources/Mote/VMRecord.swift) | Durable manifest and installation-state models |
| [`ByteSize.swift`](../Sources/Mote/ByteSize.swift) | Human-readable binary size parsing and formatting |
| [`InstallationMedia.swift`](../Sources/Mote/InstallationMedia.swift) | ISO path and ARM64 filename policy |
| [`ISOImage.swift`](../Sources/Mote/ISOImage.swift) | Regular-file ISO validation for runtime mounting |
| [`VMConfigurationBuilder.swift`](../Sources/Mote/VMConfigurationBuilder.swift) | Translation from a bundle into Virtualization.framework devices |
| [`VMRunner.swift`](../Sources/Mote/VMRunner.swift) | VM ownership, callbacks, signals, event pumping, and shutdown |
| [`VMDisplay.swift`](../Sources/Mote/VMDisplay.swift) | AppKit window and `VZVirtualMachineView` integration |
| [`VMProcessLauncher.swift`](../Sources/Mote/VMProcessLauncher.swift) | Parent-side supervisor spawning and readiness wait |
| [`VMBackgroundSupervisor.swift`](../Sources/Mote/VMBackgroundSupervisor.swift) | Child-side background VM lifetime and cleanup |
| [`VMRuntime.swift`](../Sources/Mote/VMRuntime.swift) | Ephemeral PID and start-time record |
| [`VMLock.swift`](../Sources/Mote/VMLock.swift) | Nonblocking per-VM advisory lock |
| [`VMControlChannel.swift`](../Sources/Mote/VMControlChannel.swift) | Bundle-local command FIFO and liveness probe |
| [`VMISOControl.swift`](../Sources/Mote/VMISOControl.swift) | Mount/unmount request encoding and completion responses |
| [`BackgroundConsole.swift`](../Sources/Mote/BackgroundConsole.swift) | Supervisor-side serial input FIFO and output log |
| [`SerialAttachment.swift`](../Sources/Mote/SerialAttachment.swift) | Client-side terminal attachment to a background VM |
| [`TerminalSession.swift`](../Sources/Mote/TerminalSession.swift) | Direct terminal transport used during installation |

## 3. Build and signing

The useful Make targets are:

```sh
make build    # debug SwiftPM build
make test     # test with the full Xcode toolchain
make release  # optimized build followed by ad-hoc signing
make clean
make re       # clean, then build and sign a release
```

`make release` builds `.build/release/mote` and signs it with
`Resources/Mote.entitlements`. The only entitlement currently requested is:

```text
com.apple.security.virtualization = true
```

The signed release binary is the intended way to run actual VMs. A successful
Swift compilation alone does not grant permission to use the virtualization
APIs.

## 4. Program entry and error handling

`Mote.swift` is the `@main` entry point. It:

1. removes the executable name from `CommandLine.arguments`;
2. calls `CLI.run(arguments:)` on the main actor;
3. prints a nonempty returned string to standard output;
4. prints thrown errors to standard error as `mote: <message>`;
5. maps typed errors to stable BSD `sysexits` values through `MoteExitStatus`.

Usage errors return `EX_USAGE` (64), malformed data returns `EX_DATAERR` (65),
missing input returns `EX_NOINPUT` (66), unavailable runtime services return
`EX_UNAVAILABLE` (69), local I/O errors return `EX_IOERR` (74), temporary lock
or shutdown failures return `EX_TEMPFAIL` (75), and invalid persisted
configuration returns `EX_CONFIG` (78). Unexpected failures use `EX_SOFTWARE`
(70). Messages remain on standard error, so scripts can consume standard
output independently.

`CLI.run` also handles the private `_run` command. It is deliberately omitted
from help because it is an implementation detail used to launch supervisors.

## 5. The VM store and bundle format

### Store location

`VMStore` selects its root in this order:

1. an explicit URL passed to `VMStore.init`, mainly for tests;
2. the nonempty `MOTE_HOME` environment variable;
3. `~/Library/Application Support/Mote/Virtual Machines`.

Each VM is a directory named `<name>.motevm`.

### Bundle contents

A running or previously run bundle can contain:

```text
fedora.motevm/
  config.json             durable manifest
  disk.img                durable raw, writable system disk
  efi-variable-store      durable EFI NVRAM

  .lock                   persistent lock file; lock ownership is ephemeral
  .runtime.json           present while a supervisor is active
  .control                control FIFO, present while active
  .console-input          serial-input FIFO, present while active
  .console.log            serial output for the current/last run
  .runner.log             supervisor diagnostics for the current/last run
  .iso-response-<UUID>     temporary ISO operation result, while requested
```

The first three files are the portable VM state. Hidden files are runtime and
diagnostic implementation details.

| File | Created by | Lifetime and purpose |
|---|---|---|
| `config.json` | `VMStore.create` | Durable, versioned VM configuration |
| `disk.img` | `VMStore.create` | Durable raw disk, logically sized with `truncate` |
| `efi-variable-store` | `VZEFIVariableStore` | Durable EFI variables and boot entries |
| `.lock` | `VMLock` | File remains; BSD advisory lock exists only while held |
| `.runtime.json` | supervisor | PID and start time; removed on normal cleanup |
| `.control` | `VMControlChannel` | FIFO used by commands such as `display` |
| `.console-input` | `BackgroundConsole` | FIFO carrying attached-terminal input to the guest |
| `.console.log` | `BackgroundConsole` | Guest serial output; truncated at each background start |
| `.runner.log` | `VMProcessLauncher` | Supervisor stdout/stderr; truncated at each launch |
| `.iso-response-<UUID>` | `VMISOControl` | Owner-only, short-lived mount/unmount completion result |

Runtime metadata, FIFOs, and logs are assigned owner-only permissions where the
code creates them. The lock is also opened with mode `0600`.

### VM names

Names must:

- contain 1 through 64 Unicode scalars;
- not equal `.` or `..`;
- use only alphanumerics, `.`, `_`, or `-`.

This prevents a name from escaping the store through path separators.

### Manifest

`VMRecord` is the Codable model for `config.json`. New records use schema
version 2:

```json
{
  "createdAt": "2026-09-20T18:00:00Z",
  "cpuCount": 4,
  "diskSize": 34359738368,
  "id": "12345678-9ABC-DEF0-1234-56789ABCDEF0",
  "installation": null,
  "memorySize": 4294967296,
  "name": "fedora",
  "schemaVersion": 2
}
```

Dates use ISO 8601. JSON output is pretty-printed and key-sorted. The optional
`installation` property allows schema-version-1 manifests without that property
to continue decoding.

Installation metadata has four fields:

- `state`: `started` or `guestStopped`;
- `mediaName`: only the ISO’s final filename;
- `startedAt`;
- optional `guestStoppedAt`.

This state records what Mote observed. It does not prove that the guest OS
installed successfully.

### Creating a bundle

`VMStore.create` performs these steps:

1. validates the name;
2. creates the store and bundle directories;
3. creates `disk.img` and truncates it to the requested logical size;
4. asks `VZEFIVariableStore` to create `efi-variable-store`;
5. writes `config.json` atomically;
6. removes the partial bundle if any step fails.

On a filesystem that supports sparse files, truncating a new disk gives it a
large logical size without immediately allocating all of that space.

`VMStore.load` requires a decodable manifest, `disk.img`, and the EFI variable
store. `VMStore.list` only reads manifests from `.motevm` directories; it does
not perform the full component validation that `load` does.

## 6. CLI command behavior

### `host`

Reports the host’s logical CPU count, physical memory, Virtualization.framework
CPU and memory bounds, and selected store path. The displayed architecture is
currently fixed to `arm64` because Mote targets Apple silicon. `--json` returns
the same data as a Codable object with byte counts represented as integers.

### `create`

```sh
mote create <name> [--cpus N] [--memory 8G] [--disk 64G]
```

Defaults are up to 4 CPUs, 8 GiB of memory, and a 64 GiB disk. CPU and memory
values are checked against Virtualization.framework’s host limits. Disk sizes
must be positive multiples of 512 bytes.

`ByteSize` accepts whole numbers with optional binary `K`, `M`, `G`, or `T`
suffixes. For example, `8G` is `8 × 2^30`, not eight decimal gigabytes.

### `list`

Reads every manifest in the store, sorts records by localized VM name, and
prints runtime state, CPU count, memory, and configured disk size. `--json`
returns an array with integer byte counts.

### `show`

```sh
mote show <name> [--json]
```

Loads and validates one bundle, then reports its ID, schema, creation time,
CPU and memory configuration, bundle path, installation record, and runtime
state. Disk output separates the manifest's configured size, the file's logical
size, and the filesystem-allocated size. Runtime state is one of `stopped`,
`running`, `stale`, or `invalid`; live or stale decodable metadata also includes
the recorded PID and start time.

### `install`

```sh
mote install <name> --iso <path> [--force]
```

Installation is intentionally different from normal background execution. It
runs in the invoking process, opens a display immediately, and connects the
virtio serial port directly to that terminal.

The flow is:

1. load the bundle;
2. reject a prior installation attempt unless `--force` is present;
3. acquire the per-VM lock;
4. validate the ISO path;
5. build an installation VM configuration;
6. atomically record installation state as `started`;
7. run the VM with a display and foreground terminal session;
8. if the guest stops normally, record `guestStopped` and its timestamp.

`--force` permits another installer boot. It does not erase the VM disk.

`InstallationMedia` currently validates the filename and filesystem entry, not
the contents of the ISO. The path must exist, end in `.iso`, and contain
`aarch64` or `arm64`. Names containing `x86_64` or `amd64` are rejected.

During installation, pressing `Ctrl-]` once asks the guest to stop gracefully.
A second press forces the virtual machine to stop.

### `start`

```sh
mote start <name> [--display] [--console]
```

Normal starts are background starts. The public process:

1. loads the VM bundle;
2. checks for an active runtime;
3. uses `VMProcessLauncher` to execute the same binary as `mote _run <name>`;
4. waits up to 10 seconds for the child to publish matching runtime metadata;
5. optionally sends a `display` command;
6. optionally enters `SerialAttachment`;
7. otherwise returns the supervisor PID and exits.

The launcher passes the exact store root to the child through `MOTE_HOME`, sends
the child’s stdin to `/dev/null`, and sends its stdout and stderr to
`.runner.log`. It polls every 50 ms during startup. If the child exits early or
does not become ready within 10 seconds, `start` reports the runner log path.

`--display` and `--console` can be combined. The former asks the supervisor to
open a window; the latter keeps the original CLI process in a serial attachment
after startup.

### `stop` and `restart`

```sh
mote stop <name> [--force]
mote restart <name> [--force]
```

Without `--force`, `stop` writes `stop\n` to the control FIFO. The supervisor
calls Virtualization.framework's graceful `requestStop()` API, which asks the
guest to shut itself down. With `--force`, the command is `force-stop\n` and the
supervisor uses the asynchronous `stop()` API instead.

The CLI waits for both the active control channel to disappear and the per-VM
lock to become acquirable. This two-part check prevents a restart from racing
the old supervisor after it removed runtime metadata but before it released the
disk and EFI state. Graceful shutdown waits up to 30 seconds; forced shutdown
waits up to 10 seconds. `restart` requires a running VM, completes this same
stop sequence, and then launches a fresh supervisor.

### `delete`

```sh
mote delete <name> --force
```

Deletion requires an explicit `--force` confirmation and refuses to operate on
a running or locked VM. It acquires the VM lock, rechecks liveness, and removes
the entire `.motevm` bundle while still holding the lock. This permanently
removes the disk, EFI variables, manifest, and diagnostic files; `--force` does
not implicitly stop a guest.

### `mount` and `unmount`

```sh
mote mount <name> --iso <path>
mote unmount <name>
```

On macOS 15 or newer, a background VM has an XHCI USB controller. `mount`
validates a regular `.iso` file, then asks the supervisor to attach it as a
read-only `VZUSBMassStorageDevice`. The ISO may contain any guest-compatible
content; unlike installation media, its filename need not identify ARM64.
The command waits for Virtualization.framework's attach callback before it
reports success. One hot-mounted ISO is supported per VM at a time.

`unmount` asks the supervisor to detach that device and waits for the detach
callback. Eject or unmount it in the guest first so guest software is no longer
reading it. Neither operation changes the manifest, and a hot-mounted ISO is
not restored after shutdown or restart. The host ISO file must remain present
while mounted. Foreground `mote install` sessions do not have a supervisor
control channel and do not support these commands.

The request travels over `.control` with a UUID and an encoded path. The
supervisor writes an operation result to a short-lived response file in the
bundle; the CLI waits up to 30 seconds and then removes it. A timeout means
the result is unknown, not necessarily that the framework canceled the action.
On macOS 14, Mote still runs VMs normally but returns an unsupported-version
error for runtime ISO mounting.

### `display`

```sh
mote display <name>
```

This command verifies that the runtime and control FIFO are active, then writes
the line `display\n` to `.control`. The supervisor consumes that command and
shows or re-shows its `VZVirtualMachineView` window.

Closing the window does not stop the VM. VM ownership stays with the supervisor.

### `attach`

```sh
mote attach <name>
```

This command attaches to the background serial transport. It:

1. opens `.console-input` for nonblocking writes;
2. opens `.console.log` for reads;
3. prints up to the most recent 64 KiB of serial output;
4. puts the host terminal into raw mode when stdin is a TTY;
5. forwards new stdin bytes to the input FIFO;
6. polls the log for appended output;
7. restores the terminal when detached.

`Ctrl-]` is consumed locally and detaches without stopping the guest. This is
different from its behavior during the foreground installer. Attachment also
ends if the control FIFO disappears, which indicates that the supervisor has
stopped.

The current design does not enforce a single attached reader. Multiple attach
processes can independently tail the log, and their input writes can interleave.

## 7. Background supervisor lifecycle

`VMBackgroundSupervisor` implements the private `_run` role.

```text
public start process                   private supervisor process

load bundle
clear stale runtime
truncate runner log
spawn `mote _run name` ─────────────► detach from terminal session if possible
                                      load bundle
                                      acquire .lock
                                      clear stale runtime
                                      create serial transport
                                      create control FIFO
                                      build VZ configuration
                                      start VZVirtualMachine
poll for .runtime.json ◄───────────── write PID/start time after VZ start succeeds
return to shell                        poll control + framework/AppKit events
                                      guest stops or runner fails
                                      remove runtime/FIFOs and release lock
                                      process exits
```

The child calls `setsid`. `EPERM` is accepted because Foundation may already
have made the child a process-group leader. Either state separates normal CLI
completion from the long-lived VM owner.

### Readiness and runtime detection

After Virtualization.framework reports a successful start, the supervisor
writes:

```json
{
  "pid": 12345,
  "startedAt": "2026-09-20T18:10:00Z"
}
```

The launcher accepts readiness only when this PID matches the child it spawned.

For later commands, `VMStore.runtimeStatus` distinguishes four states: no
runtime file is `stopped`, a decodable file plus an openable control FIFO is
`running`, a decodable file without a listener is `stale`, and an undecodable
file is `invalid`. `activeRuntime` returns metadata only for `running`. The FIFO
check is the liveness check; Mote does not currently call `kill(pid, 0)`.

### Locking

`VMLock` opens `.lock` and acquires `flock(LOCK_EX | LOCK_NB)`. A second process
trying to install or supervise the same VM fails immediately rather than sharing
the disk or EFI state.

The `.lock` file itself remains in the bundle. The lock is released when its
file descriptor closes, normally when `VMLock` is deinitialized after the runner
returns.

### Cleanup

The supervisor uses `defer` to:

- remove `.runtime.json`;
- close and unlink `.control`;
- close the console handles and unlink `.console-input`.

The diagnostic logs and `.lock` file remain. Their presence alone does not mean
the VM is running.

## 8. Serial console architecture

Mote has two console implementations because foreground installation and
background operation have different ownership.

### Foreground: `TerminalSession`

Used by `mote install`:

```text
host stdin ──DispatchSource──► Pipe ──► VZ serial input
host stdout ◄───────────────────────── VZ serial output
```

It saves the terminal attributes, enables raw mode, watches stdin with a
main-queue dispatch source, filters `Ctrl-]`, and restores the original terminal
attributes on stop.

### Background: `BackgroundConsole` and `SerialAttachment`

Used by the supervisor:

```text
attached stdin ──► .console-input FIFO ──► VZ serial input

VZ serial output ──► .console.log ◄────── serial attachment tailing the file
```

The supervisor opens the input FIFO read-write so the read side remains valid
even when no client is attached. Serial output always goes to a regular file,
so a chatty guest cannot fill an unattended pseudo-terminal buffer. A later
attachment can display recent output and then follow new bytes.

Both `.console.log` and `.runner.log` are truncated for each new background
start. There is no size rotation while a VM remains up.

The Linux guest must be configured to use its virtio console, normally with
`console=hvc0` and `serial-getty@hvc0.service`. Without that guest configuration,
the transport can be healthy while `mote attach` shows little or no output.

## 9. Control channel

`VMControlChannel` is a newline-delimited command channel implemented as the
`.control` FIFO.

The supervisor:

- removes a stale FIFO path;
- creates a mode-`0600` FIFO;
- opens it read-write and nonblocking;
- polls it from the VM run loop;
- buffers partial reads and emits complete newline-delimited commands.

Clients open the FIFO write-only and nonblocking. That open fails when there is
no supervisor reader, which is why the FIFO also serves as a liveness signal.

The only implemented command is currently `display`. The channel is deliberately
small but provides the natural place for future stop and status operations.

## 10. Building the virtual hardware

`VMConfigurationBuilder` is the single place that translates a bundle record
into `VZVirtualMachineConfiguration`.

### CPU and memory

The configuration uses `cpuCount` and `memorySize` directly from `VMRecord`.
Creation validates them against host limits, and the finished VZ configuration
is validated again before use.

### Platform and boot

Mote uses:

- `VZGenericPlatformConfiguration`;
- `VZEFIBootLoader`;
- the bundle’s persistent `VZEFIVariableStore`.

The persistent EFI store lets firmware boot entries survive across launches.
The guest disk should still contain the ARM64 fallback loader
`EFI/BOOT/BOOTAA64.EFI` so boot does not depend on one NVRAM entry.

### Storage

The system disk is a writable `VZDiskImageStorageDeviceAttachment` with:

- automatic caching;
- full synchronization;
- a `VZVirtioBlockDeviceConfiguration` wrapper;
- a stable identifier derived from the first 20 characters of the VM UUID.

Normal boot presents only that block device.

Installation also creates a read-only disk-image attachment for the ISO and
wraps it in `VZUSBMassStorageDeviceConfiguration`. Device ordering is explicit:
the installer medium comes first, followed by the writable system disk.

### Network

Every VM receives one virtio network device backed by
`VZNATNetworkDeviceAttachment`. The MAC address is stable:

```text
02:<first five bytes of the VM UUID>
```

The leading `02` marks it as a locally administered unicast address. Networking
uses Apple’s NAT implementation; Mote has no bridged-network or port-forwarding
layer yet.

### Entropy and ballooning

Every VM receives:

- `VZVirtioEntropyDeviceConfiguration`;
- `VZVirtioTraditionalMemoryBalloonDeviceConfiguration`.

### Serial

Every VM receives one `VZVirtioConsoleDeviceSerialPortConfiguration` backed by
the file handles supplied by either `TerminalSession` or `BackgroundConsole`.

### Graphics and input

When graphics are enabled, the builder adds:

- one virtio graphics device;
- one 1280×800 scanout;
- one USB keyboard;
- one USB screen-coordinate pointing device.

Installation enables graphics. Background supervisors also always configure
graphics, even for a headless start, because Virtualization.framework device
configuration is fixed after startup and `mote display` must work later.
On macOS 15 or newer, background configurations also include an XHCI USB
controller so the runner can hot-plug ISO media later.

Finally, `configuration.validate()` asks Virtualization.framework to reject an
invalid combination before `VZVirtualMachine` starts.

## 11. Running the VM and processing events

`VMRunner` owns the `VZVirtualMachine`, implements its delegate, and keeps the
owning process alive.

Its `run` method must execute on the main thread. It:

1. optionally creates a display;
2. optionally starts a foreground `TerminalSession`;
3. installs dispatch-based SIGINT and SIGTERM handlers;
4. calls `VZVirtualMachine.start`;
5. drives the main run loop until the start callback completes;
6. invokes `didStart`, which the supervisor uses to publish runtime metadata;
7. repeatedly polls supervisor work and processes framework/AppKit events;
8. returns when the guest stops or throws when the framework reports an error.

`guestDidStop` records a normal guest stop. `didStopWithError` preserves the
framework error. Network disconnect errors are logged without immediately
ending the runner.

For direct signals or the foreground installer’s escape key, the first stop
request calls `requestStop()` when the VM supports it. A later request uses the
asynchronous forced `stop` API. Background control commands call the same two
runner methods, so foreground and supervisor-owned VMs share shutdown logic.
The runner also retains the active USB mass-storage object and serializes
mount/unmount requests until their framework callbacks complete.

## 12. Display and AppKit integration

`VMDisplay` is a thin presentation object around `VZVirtualMachineView`.

It creates a resizable 1280×800 `NSWindow`, associates the running VM with the
view, enables system-key capture and automatic guest-display reconfiguration,
and makes the view the first responder.

Because Mote is a command-line executable rather than a conventional app with
`NSApplication.run()`, `VMDisplay.processEvents` explicitly fetches and sends
AppKit events. `VMRunner` alternates between this AppKit event pump and its
supervisor polling. Without this step the window can render but not reliably
receive keyboard or pointer input.

AppKit and Virtualization callbacks are kept on the main actor. Classes wrapping
system handles or framework objects use `@unchecked Sendable` only where the
implementation externally confines their use.

## 13. Command sequences

### Create, install, then use the background VM

```text
mote create fedora
  └─ writes manifest, sparse disk, and EFI store

mote install fedora --iso Fedora-Server-aarch64.iso
  └─ foreground VM + ISO + display + terminal
     └─ guest shutdown detaches ISO on process exit

mote start fedora
  └─ parent spawns supervisor and returns

mote display fedora
  └─ writes `display` to control FIFO
     └─ supervisor opens VZVirtualMachineView

mote attach fedora
  └─ tails serial log and writes terminal input to console FIFO
     └─ Ctrl-] detaches; supervisor and guest remain alive

mote stop fedora
  └─ writes `stop` to control FIFO and waits
     └─ supervisor requests guest shutdown and releases the bundle lock
```

### Guest-initiated shutdown

```text
guest poweroff
  └─ Virtualization.framework calls guestDidStop
     └─ VMRunner exits
        └─ supervisor removes runtime and FIFO files
           └─ lock is released and supervisor exits
```

## 14. Tests

The test suite uses Swift Testing rather than XCTest.

Current coverage includes:

- binary size parsing and invalid values;
- VM-name validation;
- empty stores and bundle loading;
- missing required bundle components;
- decoding a schema-version-1 manifest;
- atomic installation-state updates;
- ARM64 ISO filename policy;
- disk alignment policy;
- stable MAC-address derivation;
- CLI argument rejection;
- runtime metadata round trips;
- per-VM lock contention;
- control FIFO availability and command delivery;
- stopped, stale, running, and invalid runtime-state detection;
- logical and allocated disk reporting;
- deterministic JSON output for list and show;
- stable exit-code mapping;
- explicit, lock-protected deletion;
- recovery in the presence of an orphaned interrupted-write temporary file;
- ISO path validation and control-command encoding.

The tests use temporary directories and do not download guest images. They do
not boot a real Linux guest, exercise Anaconda, or prove graphical attachment to
a long-running guest. Those remain integration tests performed with signed
binaries and real ARM64 media.

## 15. How to debug Mote

### Inspect the selected store

```sh
mote host
```

For isolated experiments:

```sh
export MOTE_HOME="$PWD/vms"
```

### Inspect a bundle

```sh
ls -la "$MOTE_HOME/fedora.motevm"
cat "$MOTE_HOME/fedora.motevm/config.json"
cat "$MOTE_HOME/fedora.motevm/.runtime.json"
tail -f "$MOTE_HOME/fedora.motevm/.runner.log"
tail -f "$MOTE_HOME/fedora.motevm/.console.log"
```

`.runtime.json` plus an active `.control` FIFO means Mote considers the VM
running. A leftover `.lock` file does not.

### Verify signing

```sh
codesign -d --entitlements - .build/release/mote
```

The output should include `com.apple.security.virtualization`.

### Common failure boundaries

- Failure before runtime publication: inspect `.runner.log`.
- Display works but serial is blank: verify `console=hvc0` and the hvc0 getty in
  the guest.
- VM immediately stops: inspect the serial and runner logs and verify the ARM64
  EFI fallback loader.
- “already in use”: another installer or supervisor owns the advisory lock.
- “not running” with a runtime file present: the control FIFO has no active
  supervisor reader, so the metadata is stale.

## 16. Current boundaries and deliberate omissions

The current implementation does not yet provide:

- a global daemon or privileged helper;
- detached installation;
- console-log rotation;
- exclusive serial attachments;
- bridged networking or host port forwarding;
- filesystem sharing;
- snapshots, cloning, resize, or image import;
- macOS guests;
- inspection of an ISO’s actual CPU architecture.

The roadmap intentionally builds these features on top of inspectable bundles,
one supervisor per running VM, and a small bundle-local control protocol.

## 17. Where to make changes

Use this map when extending the project:

| Change | Primary location |
|---|---|
| Add or parse a public command | [`CLI.swift`](../Sources/Mote/CLI.swift) |
| Change durable manifest data | [`VMRecord.swift`](../Sources/Mote/VMRecord.swift), then add compatibility tests |
| Change bundle paths or persistence | [`VMStore.swift`](../Sources/Mote/VMStore.swift) |
| Add virtual hardware | [`VMConfigurationBuilder.swift`](../Sources/Mote/VMConfigurationBuilder.swift) |
| Change VM callbacks or shutdown behavior | [`VMRunner.swift`](../Sources/Mote/VMRunner.swift) |
| Change background ownership | [`VMProcessLauncher.swift`](../Sources/Mote/VMProcessLauncher.swift), [`VMBackgroundSupervisor.swift`](../Sources/Mote/VMBackgroundSupervisor.swift) |
| Add a supervisor command | [`VMControlChannel.swift`](../Sources/Mote/VMControlChannel.swift) and the supervisor poll closure |
| Change background serial transport | [`BackgroundConsole.swift`](../Sources/Mote/BackgroundConsole.swift), [`SerialAttachment.swift`](../Sources/Mote/SerialAttachment.swift) |
| Change installer terminal behavior | [`TerminalSession.swift`](../Sources/Mote/TerminalSession.swift) |
| Change graphical presentation | [`VMDisplay.swift`](../Sources/Mote/VMDisplay.swift) |
| Change ISO admission policy | [`InstallationMedia.swift`](../Sources/Mote/InstallationMedia.swift) |
| Change hot ISO mount policy or protocol | [`ISOImage.swift`](../Sources/Mote/ISOImage.swift), [`VMISOControl.swift`](../Sources/Mote/VMISOControl.swift), [`VMRunner.swift`](../Sources/Mote/VMRunner.swift) |
| Add tests | [`Tests/MoteTests`](../Tests/MoteTests) |

When adding a manifest field, keep decoding older manifests in mind. When adding
a destructive lifecycle command, acquire the per-VM lock or communicate with
the active supervisor instead of directly mutating a running bundle.
