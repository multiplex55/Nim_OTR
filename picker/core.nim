## Core picker utilities for enumerating and selecting windows without console I/O.

import std/[options, sets, strutils]
import winim/lean
import ../util/winutils
import ../util/virtualdesktop
import ../win/dwmapi

when not declared(SetROP2):
  proc SetROP2(hdc: HDC; fnDrawMode: int32): int32 {.stdcall, dynlib: "gdi32",
      importc.}

const
  R2_NOT = 6

## Captured window metadata for display and selection.
type
  WindowInfo* = object
    hwnd*: HWND
    title*: string
    processName*: string
    processPath*: string
    desktopId*: Option[string]

  WindowEligibilityOptions* = object
    includeCloaked*: bool

  EnumWindowsContext = object
    opts: ptr WindowEligibilityOptions
    strict: bool
    listPtr: ptr seq[WindowInfo]
    desktopManager: ptr VirtualDesktopManager

proc defaultEligibilityOptions*(): WindowEligibilityOptions =
  WindowEligibilityOptions(includeCloaked: false)

proc rootWindow(hwnd: HWND): HWND =
  GetAncestor(hwnd, GA_ROOT)

proc rootOwnerWindow(hwnd: HWND): HWND =
  GetAncestor(hwnd, GA_ROOTOWNER)

proc processIdentity*(hwnd: HWND): tuple[name: string, path: string] {.inline.} =
  winutils.processIdentity(hwnd)

proc collectWindowInfo(hwnd: HWND; desktopManager: ptr VirtualDesktopManager = nil): WindowInfo =
  let procInfo = processIdentity(hwnd)
  let desktopId = windowDesktopId(desktopManager, hwnd)
  var desktopLabel: Option[string]
  if desktopId.isSome:
    desktopLabel = some(formatDesktopId(desktopId.get()))
  WindowInfo(
    hwnd: hwnd,
    title: windowTitle(hwnd),
    processName: procInfo.name,
    processPath: procInfo.path,
    desktopId: desktopLabel
  )

proc hasShellOwner(hwnd: HWND): bool =
  let owner = GetWindow(hwnd, GW_OWNER)
  if owner == 0:
    return false
  let shell = GetShellWindow()
  let desktop = GetDesktopWindow()
  owner == shell or owner == desktop

proc hasVisibleRootOwner(hwnd: HWND): bool =
  let rootOwner = rootOwnerWindow(hwnd)
  if rootOwner == 0:
    return false
  if IsWindowVisible(rootOwner) != 0:
    return true

  var popup = GetLastActivePopup(rootOwner)
  while popup != 0 and popup != rootOwner:
    if IsWindowVisible(popup) != 0:
      return true
    let nextPopup = GetLastActivePopup(popup)
    if nextPopup == popup:
      break
    popup = nextPopup
  false

proc hasTitle(hwnd: HWND): bool =
  let title = windowTitle(hwnd)
  title.strip.len > 0

proc shouldIncludeWindow*(hwnd: HWND; opts: WindowEligibilityOptions;
    desktopManager: ptr VirtualDesktopManager = nil; strict: bool = true): bool =
  if hwnd == 0:
    return false
  if isToolWindow(hwnd):
    return false
  if not hasTitle(hwnd):
    return false

  let root = rootWindow(hwnd)
  if root != hwnd:
    return false

  let onCurrent =
    block:
      let desktopCheck = isOnCurrentDesktop(desktopManager, hwnd)
      if desktopCheck.isSome:
        desktopCheck.get()
      else:
        true
  let visible = IsWindowVisible(hwnd) != 0
  let cloaked = isCloaked(hwnd)

  if onCurrent:
    if not visible:
      return false
    if not opts.includeCloaked and cloaked:
      return false
  else:
    if not opts.includeCloaked and cloaked:
      discard
    elif not visible:
      return false

  if strict:
    if not hasVisibleRootOwner(hwnd):
      return false
    if hasShellOwner(hwnd):
      return false

  true

proc collectEligibleWindows(opts: WindowEligibilityOptions; strict: bool;
    desktopManager: ptr VirtualDesktopManager): seq[WindowInfo] =
  var resultList: seq[WindowInfo] = @[]
  var context = EnumWindowsContext(opts: addr opts, strict: strict, listPtr: addr resultList,
      desktopManager: desktopManager)

  proc callback(hwnd: HWND; lParam: LPARAM): WINBOOL {.stdcall.} =
    let ctx = cast[ptr EnumWindowsContext](lParam)
    if shouldIncludeWindow(hwnd, ctx.opts[], ctx.desktopManager, ctx.strict):
      ctx.listPtr[].add(collectWindowInfo(hwnd, ctx.desktopManager))
    1

  discard EnumWindows(callback, cast[LPARAM](addr context))
  resultList

## Enumerates visible, eligible windows with a fallback to a relaxed filter.
proc enumTopLevelWindows*(opts: WindowEligibilityOptions = defaultEligibilityOptions()): seq[WindowInfo] =
  var desktopManager = initVirtualDesktopManager()
  var desktopManagerPtr: ptr VirtualDesktopManager = nil
  if desktopManager.valid:
    desktopManagerPtr = addr desktopManager

  let strictList = collectEligibleWindows(opts, true, desktopManagerPtr)
  let relaxedList = collectEligibleWindows(opts, false, desktopManagerPtr)

  var seen = initHashSet[int]()
  for win in strictList:
    seen.incl(cast[int](win.hwnd))
    result.add(win)

  for win in relaxedList:
    let hwndKey = cast[int](win.hwnd)
    if seen.contains(hwndKey):
      continue
    seen.incl(hwndKey)
    result.add(win)

  shutdown(desktopManager)

proc windowBounds*(hwnd: HWND): RECT =
  if hwnd == 0:
    return
  if DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, addr result,
      DWORD(sizeof(result))) == 0:
    return
  if GetWindowRect(hwnd, addr result) != 0:
    return

proc toggleHighlight(rect: RECT) =
  let hdc = GetDC(0)
  if hdc == 0:
    return
  discard SetROP2(hdc, R2_NOT)
  var r = rect
  discard DrawFocusRect(hdc, addr r)
  discard ReleaseDC(0, hdc)

proc currentHoveredWindow(opts: WindowEligibilityOptions): HWND =
  var pt: POINT
  if GetCursorPos(addr pt) == 0:
    return 0
  let hwndAtPoint = WindowFromPoint(pt)

  proc resolveCandidate(source: HWND; strict: bool): HWND =
    let root = rootWindow(source)
    if shouldIncludeWindow(root, opts, strict = strict):
      return root
    let owner = rootOwnerWindow(root)
    if owner != root and shouldIncludeWindow(owner, opts, strict = strict):
      return owner
    0

  let strictCandidate = resolveCandidate(hwndAtPoint, true)
  if strictCandidate != 0:
    return strictCandidate
  resolveCandidate(hwndAtPoint, false)

proc keyJustPressed(vk: int32): bool =
  (GetAsyncKeyState(vk) and 0x8001) != 0

proc clickToPick(opts: WindowEligibilityOptions): HWND =
  var lastRect: RECT
  var lastHwnd: HWND

  while true:
    let hovered = currentHoveredWindow(opts)
    if hovered != lastHwnd:
      if lastHwnd != 0:
        toggleHighlight(lastRect)
      if hovered != 0:
        lastRect = windowBounds(hovered)
        toggleHighlight(lastRect)
        lastHwnd = hovered
      else:
        lastHwnd = 0

    if keyJustPressed(VK_LBUTTON) or keyJustPressed(VK_RETURN):
      if lastHwnd != 0:
        toggleHighlight(lastRect)
        return lastHwnd
    if keyJustPressed(VK_ESCAPE):
      if lastHwnd != 0:
        toggleHighlight(lastRect)
      return 0

    Sleep(50)

## Click-to-pick helper that returns a chosen window without prompting via stdin.
proc clickToPickWindow*(opts: WindowEligibilityOptions = defaultEligibilityOptions()): Option[WindowInfo] =
  var desktopManager = initVirtualDesktopManager()
  var desktopManagerPtr: ptr VirtualDesktopManager = nil
  if desktopManager.valid:
    desktopManagerPtr = addr desktopManager

  let hwnd = clickToPick(opts)
  if hwnd == 0:
    shutdown(desktopManager)
    return
  result = some(collectWindowInfo(hwnd, desktopManagerPtr))
  shutdown(desktopManager)
