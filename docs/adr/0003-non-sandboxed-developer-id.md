# Non-Sandboxed Developer ID Distribution

macOS App Sandbox strictly restricts an application's ability to launch arbitrary third-party application bundles and pass custom command-line arguments via `NSWorkspace.OpenConfiguration.arguments`. Because HiddenStart's core window suppression strategy depends on passing startup arguments (such as `--start-minimized` to Discord and `-silent` to Steam) and inspecting external running application states, sandboxing would disable primary functionality.

We decided to configure HiddenStart as a non-sandboxed Developer ID application with Hardened Runtime enabled. This preserves full LaunchServices argument injection and process management capabilities while maintaining code signing integrity.
