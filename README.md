# Nim OTR

Lightweight Windows overlay that mirrors a selected application's client area using DWM thumbnails.

## Architecture Overview
- **Picker (`picker/core.nim` + `picker/cli.nim`)**: enumerates visible, user-facing windows, captures their metadata for selection, and exposes both console and programmatic entry points.
- **Overlay state (`config/storage.nim` + `app/overlay.nim`)**: persists the chosen target HWND, overlay geometry, and crop rectangle; rehydrates those settings on launch.
- **DWM manager (`app/overlay.nim`)**: registers the thumbnail for the selected window, maps overlay clicks to source coordinates, and applies crop/opacity updates.

## Win32 Integrations
- **Picker**: wraps `EnumWindows`, `GetWindowTextW`, and `GetWindowThreadProcessId` to list eligible windows.
- **Overlay**: handles window creation and input via `RegisterClassExW`, `CreateWindowExW`, and `WndProc` handlers, while mirroring content with `DwmRegisterThumbnail`, `DwmUpdateThumbnailProperties`, and related DWM APIs.

## Building and Debugging
- Build the overlay executable: `nimble build app/overlay`
- Run with debug symbols and stack traces: `nim c -d:debug --stackTrace:on app/overlay.nim`
- Execute picker standalone for manual testing: `nim c -r picker/cli.nim`
- Run geometry/unit tests: `nim c -r tests/geometry_test.nim`

## Using the Overlay and Cropping
- Select the window to mirror via the context menu or `Ctrl+Shift+P`, then position/size the overlay as needed.
- Right-click the overlay and choose **Crop…** to open the crop window. Toggle **Mouse Crop** on/off from the context menu to arm drag-based selection; enabling it automatically disables click-through so the overlay can receive the drag. Use Tab/Shift+Tab to move between fields and press Enter to apply.
- With **Mouse Crop** enabled, click-drag on the overlay to draw a rubber-band rectangle (the crop dialog does not need to stay open). The overlay hides the thumbnail while dragging so the selection outline is always visible; release to apply the crop and sync the dialog values. Drags stay inside the overlay bounds, require a minimal size, and can be cancelled with `Esc`; very small drags are ignored. The overlay status text reflects when mouse crop is armed/dragging.
- Press `Reset Crop` in the context menu (or the crop dialog) to clear the selection back to the full source window.
- Press Shift + right-click on the overlay to toggle click-through mode when you need to interact with the underlying window; while **Mouse Crop** is enabled, this toggle is ignored so dragging remains interactive.

## Formatting
Format Nim sources before committing:

```bash
nimpretty --indent:2 --maxLineLen:100 <path-to-file>
```
