import Foundation
import Testing
@testable import MoteCLI

@Test func acceptsARM64ISOFile() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let iso = directory.appending(path: "Fedora-Server-aarch64.iso")
    try Data().write(to: iso)

    let media = try InstallationMedia(path: iso.path)

    #expect(media.url == iso.standardizedFileURL)
}

@Test func rejectsNonARM64Media() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let x86ISO = directory.appending(path: "Fedora-Server-x86_64.iso")
    let unknownISO = directory.appending(path: "installer.iso")
    let rawImage = directory.appending(path: "Fedora-Server-aarch64.raw")
    try Data().write(to: x86ISO)
    try Data().write(to: unknownISO)
    try Data().write(to: rawImage)

    #expect(throws: InstallationMedia.MediaError.self) { try InstallationMedia(path: x86ISO.path) }
    #expect(throws: InstallationMedia.MediaError.self) { try InstallationMedia(path: unknownISO.path) }
    #expect(throws: InstallationMedia.MediaError.self) { try InstallationMedia(path: rawImage.path) }
}

@Test @MainActor func installRequiresNameAndISO() {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cli = CLI(store: VMStore(root: root))

    #expect(throws: CLI.CLIError.self) { try cli.run(arguments: ["install"]) }
    #expect(throws: CLI.CLIError.self) { try cli.run(arguments: ["install", "fedora"]) }
    #expect(throws: CLI.CLIError.self) {
        try cli.run(arguments: ["install", "fedora", "--unknown"])
    }
}
