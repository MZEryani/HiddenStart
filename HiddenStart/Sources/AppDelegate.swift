import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController()
        statusItemController?.viewModel.startStartupRun()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        statusItemController?.viewModel.quit()
    }
}
