import Foundation
import Testing
@testable import MoteCLI

@Test func validatesNames() {
    #expect(VMStore.isValidName("ubuntu-dev_1"))
    #expect(!VMStore.isValidName("../escape"))
    #expect(!VMStore.isValidName("two words"))
    #expect(!VMStore.isValidName(""))
}

@Test func emptyStoreListsNoVMs() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = VMStore(root: root)
    #expect(try store.list().isEmpty)
}
