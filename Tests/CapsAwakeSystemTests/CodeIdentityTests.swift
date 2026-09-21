import Foundation
import Testing

@testable import CapsAwakeSystem

@Suite("Code identity")
struct CodeIdentityTests {
    @Test func aSignedBinaryHashesToTheSameThingEveryTime() {
        let binary = URL(fileURLWithPath: "/bin/ls")
        let hash = CodeIdentity.hash(at: binary)
        #expect(hash != nil)
        #expect(hash == CodeIdentity.hash(at: binary))
    }

    @Test func differentBinariesHashDifferently() {
        let ls = CodeIdentity.hash(at: URL(fileURLWithPath: "/bin/ls"))
        let cat = CodeIdentity.hash(at: URL(fileURLWithPath: "/bin/cat"))
        #expect(ls != cat)
    }

    /// The daemon may be missing from a half-built bundle, and a stamp is wanted
    /// either way rather than a crash.
    @Test func nothingToReadIsNoHash() {
        #expect(CodeIdentity.hash(at: URL(fileURLWithPath: "/nowhere/at/all")) == nil)
    }
}
