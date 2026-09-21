import Foundation
import Testing
@testable import Mote

@Test func acceptsRegularISORegardlessOfGuestArchitecture() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "data disk x86_64.iso")
    try Data("iso".utf8).write(to: url)

    let image = try ISOImage(path: url.path)

    #expect(image.url == url)
}

@Test func rejectsMissingNonISOAndDirectoryMedia() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let missing = directory.appending(path: "missing.iso")
    let wrongExtension = directory.appending(path: "disk.img")
    let isoDirectory = directory.appending(path: "folder.iso")
    try Data().write(to: wrongExtension)
    try FileManager.default.createDirectory(at: isoDirectory, withIntermediateDirectories: false)

    #expect(throws: ISOImage.ISOError.self) { try ISOImage(path: missing.path) }
    #expect(throws: ISOImage.ISOError.self) { try ISOImage(path: wrongExtension.path) }
    #expect(throws: ISOImage.ISOError.self) { try ISOImage(path: isoDirectory.path) }
}

@Test func ISOControlCommandsRoundTripWithoutLosingPaths() {
    let id = UUID(uuidString: "12345678-9ABC-DEF0-1234-56789ABCDEF0")!
    let mount = VMISOControl.Request.mount(id: id, path: "/tmp/Fedora media/été.iso")
    let unmount = VMISOControl.Request.unmount(id: id)

    #expect(VMISOControl.Request(command: mount.command) == mount)
    #expect(VMISOControl.Request(command: unmount.command) == unmount)
    #expect(VMISOControl.Request(command: "mount-iso invalid abc") == nil)
    #expect(VMISOControl.Request(command: "unmount-iso \(id.uuidString) extra") == nil)
}

@Test @MainActor func ISOControlWaitsForSupervisorResponse() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let record = VMRecord(name: "media-control", cpuCount: 2, memorySize: 1 << 30, diskSize: 1 << 30)
    let bundle = VMBundle(record: record, url: directory)
    let channel = try VMControlChannel(url: bundle.controlURL)
    defer { channel.stop() }
    let request = VMISOControl.Request.mount(id: UUID(), path: "/tmp/data.iso")

    let client = Task.detached {
        try VMISOControl.request(request, to: bundle)
    }
    var received: String?
    let deadline = Date(timeIntervalSinceNow: 2)
    repeat {
        channel.poll { received = $0 }
        if received != nil { break }
        try await Task.sleep(for: .milliseconds(10))
    } while Date() < deadline

    #expect(received == request.command)
    try VMISOControl.respond(to: request, bundle: bundle, error: nil)
    try await client.value

    let failedRequest = VMISOControl.Request.unmount(id: UUID())
    let failedClient = Task.detached {
        try VMISOControl.request(failedRequest, to: bundle)
    }
    received = nil
    let failureDeadline = Date(timeIntervalSinceNow: 2)
    repeat {
        channel.poll { received = $0 }
        if received != nil { break }
        try await Task.sleep(for: .milliseconds(10))
    } while Date() < failureDeadline

    #expect(received == failedRequest.command)
    try VMISOControl.respond(to: failedRequest, bundle: bundle, error: VMRunner.ISOError.notMounted)
    do {
        try await failedClient.value
        Issue.record("A failed supervisor response should throw in the CLI")
    } catch let error as VMISOControl.RequestError {
        #expect(error.localizedDescription.contains("No ISO is mounted"))
    }
}
