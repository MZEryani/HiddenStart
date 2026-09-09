# Window Suppression via Two-Stage Launch and Focus Guard

Chromium and Electron-based applications (such as Discord and Steam) frequently ignore the operating system's native `NSWorkspace.OpenConfiguration.hides` flag by asynchronously displaying their primary window and ordering it front seconds after process launch. While macOS Accessibility APIs (`AXUIElement`) could forcibly minimize windows, doing so requires users to grant invasive Accessibility permissions in System Settings.

We decided to implement a non-intrusive two-stage suppression pipeline: requesting initial launch in hidden mode (`config.hides = true`), actively polling `NSRunningApplication.hide()`, and attaching a temporary 10-second `NSWorkspace.didActivateApplicationNotification` Focus Guard to immediately suppress any late window focus-stealing without requiring Accessibility permissions.
