# Findings & Decisions

## Requirements
- Keep Notch hook logic and Settings hook logic consistent.
- Make the user-facing hook toggle drive one shared behavior path.

## Research Findings
- `AppSettingsView` uses `AppSettings.hookMonitorEnabled` and `AppSettings.setHookMonitorEnabled(...)` as the Settings source of truth.
- `NotchMenuView` currently uses `HookInstaller.isInstalled()` for its toggle state and calls `HookInstaller.installIfNeeded()` / `HookInstaller.uninstall()` directly.
- `AppDelegate` installs hooks on launch only when `AppSettings.hookMonitorEnabled` is true, and its `.hookMonitorToggled` observer starts monitoring when enabled but does not uninstall hooks when disabled.
- `ClaudeSessionMonitor` starts/stops the local HTTP server based on `AppSettings.hookMonitorEnabled`, so installation state and monitor state can drift apart today.
- The mismatch is observable from the UI because Settings and sidebar reflect `AppSettings.hookMonitorEnabled`, while the Notch menu reflected raw hook installation state.

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| Use `AppSettings.hookMonitorEnabled` as the single user-facing state | Most of the app already keys off this value, so it is the least risky truth source to preserve. |
| Move enable/disable side effects behind one shared coordinator | This prevents Notch, Settings, and app launch observers from drifting again. |
| Update the Notch label from `Hooks` to `Hook Monitor` | Matching the Settings terminology makes the shared behavior clearer to users. |

## Issues Encountered
| Issue | Resolution |
|-------|------------|
| Passing isolated static methods directly as function values introduced new warnings | Replaced them with explicit closures at the view call sites. |

## Resources
- /Users/mac/Code/GITHUB/---/claude-island/ClaudeIsland/Core/Settings.swift
- /Users/mac/Code/GITHUB/---/claude-island/ClaudeIsland/MainWindow/Views/AppSettingsView.swift
- /Users/mac/Code/GITHUB/---/claude-island/ClaudeIsland/UI/Views/NotchMenuView.swift
- /Users/mac/Code/GITHUB/---/claude-island/ClaudeIsland/App/AppDelegate.swift
- /Users/mac/Code/GITHUB/---/claude-island/ClaudeIsland/Services/Hooks/HookInstaller.swift
- /Users/mac/Code/GITHUB/---/claude-island/ClaudeIsland/Services/Session/ClaudeSessionMonitor.swift

## Visual/Browser Findings
- The Settings panel presents hook enablement as a monitor-level feature.
- The Notch menu presents hooks as an installation-level toggle.
- Those two labels currently map to different code paths and can disagree after toggling off from Settings because hooks remain installed.
- After the fix, both surfaces can point at the same logical feature and the same enabled/disabled state.

---
*Update this file after every 2 view/browser/search operations*
*This prevents visual information from being lost*
