## Application entry point that loads configuration and starts the overlay window.

import std/options
import winim/lean

import ../config/storage
import ../picker/cli
import overlay

proc selectInitialTarget(cfg: var OverlayConfig): HWND =
  if cfg.targetHwnd == 0 and cfg.targetTitle.len == 0:
    return 0

  let opts = eligibilityOptions(cfg)
  let matchedIdentity = findWindowByIdentity(cfg, opts)
  if matchedIdentity.isSome:
    return matchedIdentity.get()

  let storedHandle = validateStoredHandle(cfg, opts)
  if storedHandle.isSome:
    return storedHandle.get()

  let selection = pickWindow(opts)
  if selection.isSome:
    let win = selection.get()
    cfg.targetHwnd = cast[int](win.hwnd)
    cfg.targetTitle = win.title
    cfg.targetProcess = win.processName
    cfg.targetProcessPath = win.processPath
    return win.hwnd

  cfg.targetHwnd = 0
  cfg.targetTitle.setLen(0)
  cfg.targetProcess.setLen(0)
  cfg.targetProcessPath.setLen(0)
  0

when isMainModule:
  var cfg = loadOverlayConfig()
  let target = selectInitialTarget(cfg)
  if not initOverlay(cfg):
    quit(1)

  if target != 0:
    setTargetWindow(target)

  runOverlayLoop()
