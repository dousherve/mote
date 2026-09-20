import Testing
@testable import Mote

@Test func parsesBinaryUnits() throws {
    #expect(try ByteSize.parse("8G") == 8 << 30)
    #expect(try ByteSize.parse("512m") == 512 << 20)
    #expect(try ByteSize.parse("4096") == 4096)
}

@Test func rejectsInvalidSizes() {
    #expect(throws: ByteSize.ParseError.self) { try ByteSize.parse("8.5G") }
    #expect(throws: ByteSize.ParseError.self) { try ByteSize.parse("0G") }
}
