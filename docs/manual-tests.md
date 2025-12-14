# Manual Test Matrix

Quick checks to verify overlay interactions and persistence across sessions.

## Selection
- **Pick from list**: Launch overlay with multiple visible windows, trigger the picker list, choose a window, and confirm the overlay mirrors it.
- **Click-to-select**: Use the click picker to choose a window, confirm mirroring switches to the new target.

## Minimize / Restore Handling
- With a window selected, minimize it and verify the overlay hides the thumbnail and shows the suppressed status text.
- Restore the window and confirm the thumbnail reappears and status clears.

## Crop
- Open the crop dialog, enter values, and confirm the overlay respects the new crop.
- Use Reset to revert to the full window and confirm the thumbnail updates.

## Opacity
- Adjust opacity and confirm the overlay updates immediately.

## Restart Persistence
- Set target, crop, window position, and opacity. Close and relaunch the app, then confirm the settings and selection are restored.
