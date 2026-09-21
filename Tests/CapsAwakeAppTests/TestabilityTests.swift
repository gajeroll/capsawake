import Testing

@testable import CapsAwake

/// Proves the seam the rest of this target is built on.
///
/// `CapsAwake` is an executable target. SwiftPM lets a test target depend on one and
/// `@testable import` reaches its internals, so the app's own wiring can be tested
/// where it lives instead of being moved into a library to become reachable. If this
/// ever stops compiling, that assumption has changed and every other test here goes
/// with it.
@Test func theAppTargetIsReachableFromTests() {
    #expect(AppController.self == AppController.self)
    Log.debug("CapsAwakeAppTests reached the app target")
}
