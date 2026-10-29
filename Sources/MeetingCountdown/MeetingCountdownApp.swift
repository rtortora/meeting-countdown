import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}

@main
enum MeetingCountdownApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu bar only; LSUIElement in Info.plist does the same when launched as a bundle.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
