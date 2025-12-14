# Package
name            = "nim_otr"
description     = "Overlay telemetry recorder for Windows with picker and UI helpers"
version         = "0.1.0"
author          = "multiplex55"
license         = "MIT"

# Deps
requires "nim >= 1.6"

# Tasks
bin             = @["app/main"]

# Settings
# Use nimpretty for formatting; keep exported procs/types documented.
