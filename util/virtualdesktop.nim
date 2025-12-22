import std/options
import winim/lean
import winim/com
import ../win/virtualdesktop

type
  VirtualDesktopManager* = object
    raw: ptr IVirtualDesktopManager
    needsUninit: bool

proc initVirtualDesktopManager*(): VirtualDesktopManager =
  let initResult = CoInitializeEx(nil, COINIT_APARTMENTTHREADED)
  let needsUninit = initResult == S_OK

  var manager: ptr IVirtualDesktopManager
  let hr = CreateVirtualDesktopManager(addr manager)
  if FAILED(hr):
    if needsUninit:
      CoUninitialize()
    return

  VirtualDesktopManager(raw: manager, needsUninit: needsUninit)

proc valid*(manager: VirtualDesktopManager): bool =
  manager.raw != nil

proc shutdown*(manager: var VirtualDesktopManager) =
  if manager.raw != nil:
    discard manager.raw.lpVtbl.Release(manager.raw)
    manager.raw = nil
  if manager.needsUninit:
    CoUninitialize()
    manager.needsUninit = false

proc windowDesktopId*(manager: ptr VirtualDesktopManager; hwnd: HWND): Option[GUID] =
  if manager == nil or not manager[].valid:
    return

  var desktopId: GUID
  if SUCCEEDED(manager[].raw.lpVtbl.GetWindowDesktopId(manager[].raw, hwnd,
      addr desktopId)):
    return some(desktopId)

proc isOnCurrentDesktop*(manager: ptr VirtualDesktopManager;
    hwnd: HWND): Option[bool] =
  if manager == nil or not manager[].valid:
    return

  var onCurrent: WINBOOL
  if SUCCEEDED(manager[].raw.lpVtbl.IsWindowOnCurrentVirtualDesktop(manager[
      ].raw, hwnd, addr onCurrent)):
    return some(onCurrent != 0)

proc formatDesktopId*(desktopId: GUID): string =
  $desktopId
