# HiddenStart

A lightweight background-resident macOS menu bar utility that manages application startup on login with intelligent network gating, custom delays, and window suppression.

## Language

**Managed App**:
An application configured within HiddenStart to be launched on login.
_Avoid_: Target app, program, login item

**Startup Run**:
The automated launch cycle initiated when the user logs in that evaluates and launches managed apps.
_Avoid_: Boot sequence, launch session

**Network Gate**:
The reachability condition that delays an app's launch until active internet connectivity is verified.
_Avoid_: Internet check, wifi wait

**Launch Delay**:
The duration in seconds to wait before launching an app during a Startup Run.
_Avoid_: Countdown, sleep timer

**Window Suppression**:
The multi-stage technique used to prevent an app's UI from stealing focus or appearing on screen during launch.
_Avoid_: App hiding, backgrounding

**App Preset**:
A set of pre-configured default settings (arguments, launch delay, network gate) automatically mapped to recognized managed apps.
_Avoid_: App template, default profile

**Deferred Retry**:
The bounded observation window following an offline startup run during which skipped network-gated apps are triggered if connectivity is established.
_Avoid_: Reconnect watcher, delayed launch
