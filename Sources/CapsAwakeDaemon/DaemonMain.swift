import CapsAwakeIPC
import Foundation

@main
enum CapsAwakeDaemonMain {
    static func main() {
        let delegate = CapsAwakeDaemonDelegate()
        delegate.startBootReconcile()
        let listener = NSXPCListener(machServiceName: CapsAwakeIPC.machServiceName)
        // Before the delegate, so an unauthorised peer is refused by macOS rather than
        // by us.
        ClientValidator.requireSignedClients(on: listener)
        listener.delegate = delegate
        listener.resume()
        RunLoop.main.run()
    }
}
