# v0.1 Feature Plan

## In-scope Features

### Overlay mirroring via DWM thumbnail
- Description: Mirror a selected window using a DWM thumbnail overlay to reflect live content.
- Acceptance criteria:
  - User can select a window and see its live content mirrored in the overlay without noticeable lag.
  - Mirrored content updates when the source window changes.
  - Mirroring stops if the source window closes and the user receives a clear indication.

### Always-on-top toggle
- Description: Allow the overlay window to be toggled to stay above other windows.
- Acceptance criteria:
  - Toggle control exists and changes the overlay between normal and topmost states.
  - The current state is visually indicated.
  - State persists across app restarts.

### Crop rectangle
- Description: Provide a crop rectangle to limit the mirrored area of the source window.
- Acceptance criteria:
  - User can define and adjust a crop region with visible handles/edges.
  - Mirrored output reflects the crop immediately.
  - Crop settings persist across sessions.

### Opacity slider
- Description: Adjustable transparency for the overlay.
- Acceptance criteria:
  - Slider (or equivalent control) changes overlay opacity smoothly from fully opaque to partially transparent.
  - Overlay responds in real time as the slider moves.
  - Opacity value persists across restarts.

### Click-through default with Shift+Click focusing
- Description: Overlay defaults to ignoring mouse clicks; holding Shift enables focusing and interaction.
- Acceptance criteria:
  - By default, mouse clicks pass through the overlay to underlying windows.
  - Holding Shift while clicking focuses the overlay and allows interaction with its controls.
  - Clear affordance or hint communicates the Shift+Click behavior.

### Window picker (list + click-to-pick)
- Description: Provide a list of available windows and support click-to-pick selection.
- Acceptance criteria:
  - Picker shows window titles/identifiers for all eligible windows.
  - Clicking a window in the list sets it as the mirrored target.
  - Selection feedback is visible and the choice persists across restarts.

### Persistence of last settings
- Description: Remember the last target window, opacity, crop rectangle, and overlay size/position.
- Acceptance criteria:
  - On restart, the overlay restores the previous target (if available) and layout (opacity, crop, size/position).
  - If the previous target is unavailable, app falls back gracefully (e.g., prompt to reselect).
  - Settings save automatically without manual export/import.

## Out of Scope for v0.1
- Presets or profiles beyond the single saved state.
- Multiple simultaneous mirrors or overlays.
- Hotkey editor or customizable shortcuts beyond Shift+Click focus behavior.
- System tray menu or background agent behaviors.
- Advanced UI/UX features (themes, animations, complex layouts beyond essential controls).
