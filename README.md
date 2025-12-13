# Nim OTR

Lightweight Windows overlay that mirrors a selected application's client area using DWM thumbnails.

## Architecture Overview
- **Picker (`picker/main.nim`)**: enumerates visible, user-facing windows and captures their metadata for selection.
- **Overlay state (`config/storage.nim` + `app/overlay.nim`)**: persists the chosen target HWND, overlay geometry, and crop rectangle; rehydrates those settings on launch.
- **DWM manager (`app/overlay.nim`)**: registers the thumbnail for the selected window, maps overlay clicks to source coordinates, and applies crop/opacity updates.

## Win32 Integrations
- **Picker**: wraps `EnumWindows`, `GetWindowTextW`, and `GetWindowThreadProcessId` to list eligible windows.
- **Overlay**: handles window creation and input via `RegisterClassExW`, `CreateWindowExW`, and `WndProc` handlers, while mirroring content with `DwmRegisterThumbnail`, `DwmUpdateThumbnailProperties`, and related DWM APIs.

## Building and Debugging
- Build the overlay executable: `nimble build app/overlay`
- Run with debug symbols and stack traces: `nim c -d:debug --stackTrace:on app/overlay.nim`
- Execute picker standalone for manual testing: `nim c -r picker/main.nim`
- Run geometry/unit tests: `nim c -r tests/geometry_test.nim`

## Formatting
Format Nim sources before committing:

```bash
nimpretty --indent:2 --maxLineLen:100 <path-to-file>
```
