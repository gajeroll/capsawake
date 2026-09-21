import Testing

@testable import CapsAwakeSystem

@Test func clamshellReaderDoesNotCrash() {
    _ = ClamshellReader.isClosed()
}
