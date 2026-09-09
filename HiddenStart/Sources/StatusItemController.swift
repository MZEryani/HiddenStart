import AppKit
import SwiftUI

@MainActor
public protocol PopoverPresenting: AnyObject {
    var isShown: Bool { get }
    func show(relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge)
    func close()
}

extension NSPopover: PopoverPresenting {}

@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    public let viewModel: StatusViewModel
    public let popover: PopoverPresenting
    public private(set) var statusItem: NSStatusItem?
    private var eventMonitor: Any?

    public init(
        viewModel: StatusViewModel = StatusViewModel(),
        popover: PopoverPresenting? = nil,
        statusBar: NSStatusBar? = NSStatusBar.system
    ) {
        self.viewModel = viewModel

        if let providedPopover = popover {
            self.popover = providedPopover
        } else {
            let standardPopover = NSPopover()
            standardPopover.behavior = .applicationDefined
            standardPopover.contentViewController = NSHostingController(
                rootView: PopoverContentView(viewModel: viewModel)
            )
            self.popover = standardPopover
        }

        super.init()

        if let statusBar = statusBar {
            let item = statusBar.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.image = NSImage(
                    systemSymbolName: "eye.slash",
                    accessibilityDescription: "HiddenStart"
                )
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.target = self
                button.action = #selector(statusItemClicked(_:))
            }
            self.statusItem = item
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            if let button = statusItem?.button {
                togglePopover(from: button)
            }
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            guard let button = statusItem?.button else { return }
            togglePopover(from: button)
        }
    }

    public func showContextMenu() {
        closePopover()

        let menu = NSMenu()
        menu.delegate = self

        let titleItem = NSMenuItem(title: "HiddenStart", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit HiddenStart",
            action: #selector(contextMenuQuitClicked),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
    }

    public func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }

    @objc private func contextMenuQuitClicked() {
        viewModel.quit()
    }

    public func togglePopover(from view: NSView) {
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            startEventMonitor()
        }
    }

    public func closePopover() {
        if popover.isShown {
            popover.close()
        }
        stopEventMonitor()
    }

    private func startEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover()
            }
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
