# Package
description     = "Overlay telemetry recorder for Windows with picker and UI helpers"
version         = "0.1.0"
author          = "multiplex55"
license         = "MIT"

requires "nim >= 1.6"

bin = @["app/main"]

task releaseOverlay, "Build GUI-only release binary without a console window":
  exec "nim c -d:release --app:gui app/main.nim"
