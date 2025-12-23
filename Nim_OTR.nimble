# Package
description     = "Overlay telemetry recorder for Windows with picker and UI helpers"
version         = "0.1.0"
author          = "multiplex55"
license         = "MIT"

# Deps
requires "nim >= 1.6"

# Tasks
bin             = @["app/main"]

task releaseOverlay, "Build GUI-only release binary without a console window" do:
  let args = @[
    "c",
    "-d:release",
    "--app:gui",
    "--subsystem:windows",
    "app/main.nim"
  ]

  if exec("nim", args) != 0:
    quit(1)

# Settings
# Use nimpretty for formatting; keep exported procs/types documented.
