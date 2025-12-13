# Usage

## Build
1. Install Nim (>= 1.6) and Nimble.
2. Install dependencies if added via `nimble install`.
3. Build the project:
   ```bash
   nimble build
   ```

## Run
- Launch the compiled binary from `app/` entry point once implemented.
- The picker component will enumerate windows; choose a target to attach the overlay.
- Configuration updates persist between runs via the `config` module.

## Notes
- Use `nimpretty --indent:2 --maxLineLen:100 <path>` before submitting changes.
- Exported procs/types should have `##` doc comments to keep API documentation accurate.
