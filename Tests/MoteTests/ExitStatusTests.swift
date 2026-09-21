import Darwin
import Foundation
import Testing
@testable import Mote

@Test func mapsStableExitStatuses() {
    #expect(MoteExitStatus.code(for: CLI.CLIError.usage("bad input")) == EX_USAGE)
    #expect(MoteExitStatus.code(for: VMStore.StoreError.notFound("missing")) == EX_NOINPUT)
    #expect(MoteExitStatus.code(for: CLI.CLIError.notRunning("stopped")) == EX_UNAVAILABLE)
    #expect(MoteExitStatus.code(for: VMLock.LockError.unavailable("busy")) == EX_TEMPFAIL)
    #expect(MoteExitStatus.code(for: ByteSize.ParseError.invalid("nope")) == EX_USAGE)
    #expect(MoteExitStatus.code(for: VMConfigurationBuilder.ConfigurationError.invalidDiskSize(1)) == EX_CONFIG)
    #expect(MoteExitStatus.code(for: VMStore.StoreError.corruptBundle("broken")) == EX_DATAERR)
    #expect(MoteExitStatus.code(for: CocoaError(.fileReadUnknown)) == EX_IOERR)
}
