# Nim OTR

> Lightweight Windows overlay that mirrors a selected application's client area using DWM thumbnails for streamers, presenters, and multitaskers who need a resizable, always-on-top view.

![Platform](https://img.shields.io/badge/Platform-Windows%2010%2B-0078D6?style=flat-square) ![Nim](https://img.shields.io/badge/Nim-1.6%2B-FFC200?style=flat-square) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)

## Overview
Nim OTR (Overlay Telemetry Recorder) mirrors any chosen window into a frameless overlay using Windows Desktop Window Manager (DWM) thumbnails. It keeps the mirrored view interactive through crop controls, opacity adjustments, and click-through defaults so you can keep the overlay on top without stealing focus from the underlying apps.

## Key Features
- Always-on-top overlay that mirrors live content via DWM thumbnails.
- List- and click-to-pick window selector that labels windows (including by virtual desktop) before mirroring.
- Crop controls via dialog fields, reset button, and mouse-drag “rubber band” selection with keyboard navigation.
- Opacity slider with real-time updates so the overlay can stay visible without hiding the source apps.
- Click-through by default with Shift+Click to interact with overlay controls, plus right-click context menu shortcuts.
- Optional persistence for target window, geometry, opacity, crop, and sorting preferences across sessions.

## Screenshots / Demo
- Screenshots are in progress while the UI stabilizes. If you capture a helpful workflow, please open a PR and link the image here.

## Quick Start
1. Install Nim 1.6+ and Nimble on Windows 10/11 with DWM enabled.
2. Clone the repository and install any Nim dependencies via `nimble install` (e.g., `winim`).
3. Build a GUI release binary without a console window:
   ```bash
   nimble releaseOverlay
   ```
4. Run the overlay (from the project root the binary will live under `app/`):
   ```bash
   app\main.exe
   ```
5. Press **Ctrl+Shift+P** or use the context menu to pick a window, then drag/resize the overlay to fit your layout.

## Installation
- **Requirements:** Windows 10/11 with DWM enabled, Nim 1.6+, Nimble, and a C/C++ toolchain (e.g., Visual Studio Build Tools) for native compilation.
- **Dependencies:** Install Nim packages with `nimble install`; `winim` is required for Win32 bindings.
- **Source build:** Use `nim c -d:debug --stackTrace:on app/overlay.nim` for a debug build with logs and assertions enabled.
- **Release build:** `nimble releaseOverlay` compiles a GUI-only executable suitable for distributing to end users.

## Usage
- **Window selection:** Press **Ctrl+Shift+P** or open the overlay context menu to select a target window. Picker entries include virtual desktop labels to make cross-desktop mirroring clear.
- **Crop:** Right-click → **Crop…** to open the crop dialog. Toggle **Mouse Crop** to drag a selection directly on the overlay; the thumbnail hides while dragging so the outline stays visible. Use **Reset Crop** to restore the full source view.
- **Opacity:** Adjust opacity from the context menu and see the overlay update immediately.
- **Click-through:** The overlay ignores mouse clicks by default. Hold **Shift** while clicking to focus the overlay; Shift+right-click toggles click-through unless Mouse Crop is active.
- **Minimize/restore handling:** If the source window is minimized, the overlay hides the thumbnail and shows status text until the source is restored.
- **Manual validation:** Run `nim c -r picker/cli.nim` to list available windows (with virtual desktop GUIDs) and `nim c -r tests/geometry_test.nim` to verify geometry helpers.

## Configuration
- Settings such as target window identity, overlay position/size, opacity, crop rectangle, borderless mode, and sort order live in `OverlayConfig` (`config/storage.nim`).
- Persistence is gated by `persistOverlayConfig`; when enabled, settings serialize to `config/overlay_config.json` so your layout is restored on restart.
- Sort behavior for picker menus can be toggled between title and virtual desktop ordering; include cloaked windows by flipping `includeCloaked` in the config.

## Architecture / How It Works
- **app/** initializes logging/utilities, applies configuration, sets DPI awareness, and runs the overlay loop.
- **picker/** enumerates eligible windows via Win32 APIs (e.g., `EnumWindows`, `GetWindowTextW`) and feeds selection data to the UI.
- **ui/** hosts the overlay window, message pump, and `WndProc`, mapping overlay input to the mirrored source via DWM (`DwmRegisterThumbnail`, `DwmUpdateThumbnailProperties`).
- **config/** loads/saves user settings, while **util/** shares geometry math and logging. **win/** wraps low-level Win32/DWM helpers consumed by the other layers.

## Roadmap / Project Status
- **Status:** Early-stage (v0.1 plan). Focused on single-window mirroring and core UX polish.
- **Near-term:** Always-on-top toggle, persistent settings, robust crop rectangle handling, opacity slider, and richer picker feedback (titles + virtual desktop labels).
- **Out of scope for v0.1:** Multiple simultaneous overlays, presets/profiles, customizable hotkeys beyond Shift+Click behavior, and system tray/background agent features.

## Contributing
- Report issues or feature ideas via GitHub issues; include steps to reproduce and environment details.
- Format Nim sources with `nimpretty --indent:2 --maxLineLen:100 <path>` before committing; exported procs/types need `##` doc comments.
- Recommended checks:
  - Debug build with logging: `nim c -d:debug --stackTrace:on app/overlay.nim`
  - Picker inspection: `nim c -r picker/cli.nim`
  - Geometry/unit tests: `nim c -r tests/geometry_test.nim`
- Manual test passes for overlay selection, crop, opacity, minimize/restore, and persistence are outlined in `docs/manual-tests.md`.

## Security / Responsible Disclosure
- Please do not post sensitive vulnerability details publicly. Instead, open a private issue or contact the maintainer to coordinate a fix and disclosure window.

## FAQ / Troubleshooting
- **Overlay shows blank when the source is minimized:** Restore the source window; the overlay intentionally hides thumbnails while minimized.
- **Can't interact with the overlay:** Hold **Shift** while clicking to focus it, or temporarily disable click-through via the context menu.
- **Crop seems to ignore tiny drags:** Very small drag regions are discarded to prevent accidental crops; use the crop dialog for precise values.
- **Need window ordering by desktop:** Switch the picker sort mode to virtual desktop ordering in the configuration.

## License
This project is licensed under the [MIT License](LICENSE).

## Credits / Acknowledgements
- Built with Nim and the `winim` Windows API bindings.
- Uses Windows DWM thumbnails to mirror live content efficiently.
