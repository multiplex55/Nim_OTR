# Architecture

## Modules and Responsibilities
- `app/`: Entry points and lifecycle wiring for the overlay executable. Bootstraps configuration, DPI awareness, and window creation.
- `config/`: Load and persist user settings (e.g., selected window, overlay toggles). Centralizes defaults and serialization.
- `picker/`: Enumerates candidate windows/sources and exposes selection APIs used by the UI and configuration layers.
- `ui/`: Hosts the overlay window, message pump, and `WndProc` implementation. Responsible for rendering and routing input.
- `win/`: Low-level Win32 and DWM wrappers used across picker, UI, and utility helpers.
- `util/`: Shared helpers for logging, geometry math, and DPI conversions.

## Data Flow
1. `app` initializes logging/utilities, applies configuration, and sets DPI/context awareness.
2. `picker` enumerates windows and returns selection data that `config` persists for reuse.
3. `ui` uses `win` wrappers to create the overlay window, connects `WndProc` callbacks, and renders based on `config`/`picker` data.
4. `util` is imported by all layers for structured logging and geometry conversions; `win` surfaces the platform APIs consumed by `ui` and `picker`.

## Contributing Conventions
- Format Nim code with `nimpretty --indent:2 --maxLineLen:100 <path>` before committing.
- Exported procs and types **must** include Nim doc comments (`##`) describing purpose and parameters.
