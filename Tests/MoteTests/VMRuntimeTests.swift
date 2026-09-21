import Foundation
import Testing
@testable import Mote

@Test func runtimeMetadataRoundTrips() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let record = VMRecord(name: "runtime", cpuCount: 2, memorySize: 1 << 30, diskSize: 1 << 30)
    let bundle = VMBundle(record: record, url: root)
    let store = VMStore(root: root.deletingLastPathComponent())
    let runtime = VMRuntime(pid: 42, startedAt: Date(timeIntervalSince1970: 1_800_000_000))

    try store.writeRuntime(runtime, for: bundle)
    #expect(store.runtime(for: bundle) == runtime)
    guard case .stale(let storedRuntime) = store.runtimeStatus(for: bundle) else {
        Issue.record("Runtime metadata without a control channel should be stale")
        return
    }
    #expect(storedRuntime == runtime)

    store.clearRuntime(for: bundle)
    #expect(store.runtime(for: bundle) == nil)
    guard case .stopped = store.runtimeStatus(for: bundle) else {
        Issue.record("A bundle without runtime metadata should be stopped")
        return
    }
}

@Test func malformedRuntimeMetadataIsReportedAsInvalid() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let bundle = VMBundle(
        record: VMRecord(name: "invalid-runtime", cpuCount: 2, memorySize: 1 << 30, diskSize: 1 << 30),
        url: root
    )
    try Data("not json".utf8).write(to: bundle.runtimeURL)

    guard case .invalid = VMStore(root: root.deletingLastPathComponent()).runtimeStatus(for: bundle) else {
        Issue.record("Malformed runtime metadata should be invalid")
        return
    }
}

@Test func perVMLockRejectsConcurrentOwner() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let record = VMRecord(name: "locked", cpuCount: 2, memorySize: 1 << 30, diskSize: 1 << 30)
    let bundle = VMBundle(record: record, url: root)

    let first = try VMLock(bundle: bundle)
    #expect(throws: VMLock.LockError.self) {
        _ = try VMLock(bundle: bundle)
    }
    withExtendedLifetime(first) {}
}

@Test @MainActor func controlChannelReportsAvailabilityAndDeliversCommands() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let record = VMRecord(name: "controlled", cpuCount: 2, memorySize: 1 << 30, diskSize: 1 << 30)
    let bundle = VMBundle(record: record, url: root)
    let store = VMStore(root: root.deletingLastPathComponent())
    let runtime = VMRuntime(pid: 42, startedAt: Date(timeIntervalSince1970: 1_800_000_000))
    try store.writeRuntime(runtime, for: bundle)

    var received: String?
    let channel = try VMControlChannel(url: bundle.controlURL)

    #expect(store.activeRuntime(for: bundle) == runtime)
    guard case .running(let activeRuntime) = store.runtimeStatus(for: bundle) else {
        Issue.record("A live control channel should make the runtime active")
        return
    }
    #expect(activeRuntime == runtime)
    try VMControlChannel.send("display", to: bundle)
    channel.poll { received = $0 }
    #expect(received == "display")

    channel.stop()
    #expect(store.activeRuntime(for: bundle) == nil)
}
