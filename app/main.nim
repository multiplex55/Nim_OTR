## Application entry point that loads configuration and starts the overlay window.

import std/options
import winim/lean

import ../config/storage
import ../picker/cli
import overlay

proc selectInitialTarget(cfg: var OverlayConfig): HWND =
  let storedHandle = HWND(cfg.targetHwnd)
  if storedHandle != 0 and IsWindow(storedHandle) != 0:
    return storedHandle

  let matched = findWindowByIdentity(cfg)
  if matched != 0:
    return matched

  let selection = pickWindow()
  if selection.isSome:
    let win = selection.get()
    cfg.targetHwnd = cast[int](win.hwnd)
    cfg.targetTitle = win.title
    cfg.targetProcess = win.processName
    return win.hwnd

  cfg.targetHwnd = 0
  cfg.targetTitle.setLen(0)
  cfg.targetProcess.setLen(0)
  0

when isMainModule:
  var cfg = loadOverlayConfig()
  let target = selectInitialTarget(cfg)
  if not initOverlay(cfg):
    quit(1)

  if target != 0:
    setTargetWindow(target)

  runOverlayLoop()
