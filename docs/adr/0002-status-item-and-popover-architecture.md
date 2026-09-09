# NSStatusItem with NSPopover over SwiftUI MenuBarExtra

While SwiftUI introduced `MenuBarExtra` in macOS 13+, it suffers from significant reliability limitations in desktop menu bar utilities: unreliable outside-click dismissal, inability to distinguish left-click (toggle popover) from right-click (instant context menu for Quit / Settings), and difficulty controlling dynamic popover resizing.

We decided to anchor the application using AppKit's `NSStatusItem` paired with an `NSPopover` wrapping an `NSHostingController` containing our SwiftUI views. This guarantees deterministic popover dismissal, clean right-click context menu handling, and rock-solid window positioning while keeping all UI component development in modern declarative SwiftUI.
