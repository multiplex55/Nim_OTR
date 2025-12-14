## Core picker utilities for enumerating and selecting windows without console I/O.

import std/[options, os, strutils, widestrs]
import winim/lean

when not declared(EnumWindows):
  type
    EnumWindowsProc = proc(hwnd: HWND; lParam: LPARAM): WINBOOL {.stdcall.}
  proc EnumWindows(lpEnumFunc: EnumWindowsProc; lParam: LPARAM): WINBOOL {.stdcall,
      dynlib: "user32", importc.}

when not declared(GetWindowTextLengthW):
  proc GetWindowTextLengthW(hWnd: HWND): int32 {.stdcall, dynlib: "user32",
      importc.}

when not declared(GetWindowTextW):
  proc GetWindowTextW(hWnd: HWND; lpString: LPWSTR; nMaxCount: int32): int32 {.
      stdcall, dynlib: "user32", importc.}

when not declared(IsWindowVisible):
  proc IsWindowVisible(hWnd: HWND): WINBOOL {.stdcall, dynlib: "user32", importc.}

when not declared(GetWindowLongPtrW):
  proc GetWindowLongPtrW(hWnd: HWND; nIndex: int32): LONG_PTR {.stdcall,
      dynlib: "user32", importc.}

when not declared(GetAncestor):
  proc GetAncestor(hwnd: HWND; gaFlags: UINT): HWND {.stdcall, dynlib: "user32",
      importc.}

when not declared(DwmGetWindowAttribute):
  proc DwmGetWindowAttribute(hwnd: HWND; dwAttribute: DWORD; pvAttribute: pointer;
      cbAttribute: DWORD): HRESULT {.stdcall, dynlib: "dwmapi", importc.}

when not declared(GetWindowThreadProcessId):
  proc GetWindowThreadProcessId(hwnd: HWND; lpdwProcessId: ptr DWORD): DWORD {.
      stdcall, dynlib: "user32", importc.}

when not declared(OpenProcess):
  proc OpenProcess(dwDesiredAccess: DWORD; bInheritHandle: WINBOOL;
      dwProcessId: DWORD): HANDLE {.stdcall, dynlib: "kernel32", importc.}

when not declared(CloseHandle):
  proc CloseHandle(hObject: HANDLE): WINBOOL {.stdcall, dynlib: "kernel32",
      importc.}

when not declared(QueryFullProcessImageNameW):
  proc QueryFullProcessImageNameW(hProcess: HANDLE; dwFlags: DWORD;
      lpExeName: LPWSTR; lpdwSize: ptr DWORD): WINBOOL {.stdcall,
      dynlib: "kernel32", importc.}

when not declared(GetShellWindow):
  proc GetShellWindow(): HWND {.stdcall, dynlib: "user32", importc.}

when not declared(GetDesktopWindow):
  proc GetDesktopWindow(): HWND {.stdcall, dynlib: "user32", importc.}

when not declared(GetWindow):
  proc GetWindow(hWnd: HWND; uCmd: UINT): HWND {.stdcall, dynlib: "user32",
      importc.}

when not declared(GetLastActivePopup):
  proc GetLastActivePopup(hWnd: HWND): HWND {.stdcall, dynlib: "user32",
      importc.}

when not declared(GetCursorPos):
  proc GetCursorPos(lpPoint: ptr POINT): WINBOOL {.stdcall, dynlib: "user32",
      importc.}

when not declared(WindowFromPoint):
  proc WindowFromPoint(point: POINT): HWND {.stdcall, dynlib: "user32", importc.}

when not declared(GetWindowRect):
  proc GetWindowRect(hWnd: HWND; lpRect: ptr RECT): WINBOOL {.stdcall,
      dynlib: "user32", importc.}

when not declared(DrawFocusRect):
  proc DrawFocusRect(hDC: HDC; lprc: ptr RECT): WINBOOL {.stdcall,
      dynlib: "user32", importc.}

when not declared(SetROP2):
  proc SetROP2(hdc: HDC; fnDrawMode: int32): int32 {.stdcall, dynlib: "gdi32",
      importc.}

when not declared(GetDC):
  proc GetDC(hWnd: HWND): HDC {.stdcall, dynlib: "user32", importc.}

when not declared(ReleaseDC):
  proc ReleaseDC(hWnd: HWND; hDC: HDC): int32 {.stdcall, dynlib: "user32",
      importc.}

when not declared(GetAsyncKeyState):
  proc GetAsyncKeyState(vKey: int32): int16 {.stdcall, dynlib: "user32",
      importc.}

when not declared(Sleep):
  proc Sleep(dwMilliseconds: DWORD) {.stdcall, dynlib: "kernel32", importc.}

const
  GA_ROOT = 2
  GA_ROOTOWNER = 3
  GW_OWNER = 4
  DWMWA_EXTENDED_FRAME_BOUNDS = 9
  DWMWA_CLOAKED = 14
  WS_EX_TOOLWINDOW = 0x00000080
  GWL_EXSTYLE = -20
  PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
  R2_NOT = 6

## Captured window metadata for display and selection.
type
  WindowInfo* = object
    hwnd*: HWND
    title*: string
    processName*: string

  WindowEligibilityOptions* = object
    includeCloaked*: bool

  EnumWindowsContext = object
    opts: ptr WindowEligibilityOptions
    strict: bool
    listPtr: ptr seq[WindowInfo]

proc defaultEligibilityOptions*(): WindowEligibilityOptions =
  WindowEligibilityOptions(includeCloaked: false)

proc getWindowTitle(hwnd: HWND): string =
  let length = GetWindowTextLengthW(hwnd)
  if length <= 0:
    return
  var buf = newWideCString(length + 1)
  discard GetWindowTextW(hwnd, buf, length + 1)
  result = $buf

proc isCloaked(hwnd: HWND): bool =
  var cloaked: DWORD
  if DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, addr cloaked,
      DWORD(sizeof(cloaked))) != 0:
    return false
  cloaked != 0

proc isToolWindow(hwnd: HWND): bool =
  (GetWindowLongPtrW(hwnd, GWL_EXSTYLE) and WS_EX_TOOLWINDOW) != 0

proc rootWindow(hwnd: HWND): HWND =
  GetAncestor(hwnd, GA_ROOT)

proc rootOwnerWindow(hwnd: HWND): HWND =
  GetAncestor(hwnd, GA_ROOTOWNER)

proc processName(hwnd: HWND): string =
  var pid: DWORD
  discard GetWindowThreadProcessId(hwnd, addr pid)
  if pid == 0:
    return "<unknown>"

  let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
  if handle == 0:
    return "<unknown>"

  var size = 260.DWORD
  var buffer = newWideCString(int(size))
  if QueryFullProcessImageNameW(handle, 0, buffer, addr size) != 0:
    let path = $buffer
    result = splitFile(path).name
  else:
    result = "<unknown>"
  discard CloseHandle(handle)

proc collectWindowInfo(hwnd: HWND): WindowInfo =
  WindowInfo(
    hwnd: hwnd,
    title: getWindowTitle(hwnd),
    processName: processName(hwnd)
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
  let title = getWindowTitle(hwnd)
  title.strip.len > 0

proc shouldIncludeWindow*(hwnd: HWND; opts: WindowEligibilityOptions;
    strict: bool = true): bool =
  if hwnd == 0:
    return false
  if IsWindowVisible(hwnd) == 0:
    return false
  if isToolWindow(hwnd):
    return false
  if not opts.includeCloaked and isCloaked(hwnd):
    return false
  if not hasTitle(hwnd):
    return false

  let root = rootWindow(hwnd)
  if root != hwnd:
    return false

  if strict:
    if not hasVisibleRootOwner(hwnd):
      return false
    if hasShellOwner(hwnd):
      return false

  true

proc collectEligibleWindows(opts: WindowEligibilityOptions; strict: bool): seq[WindowInfo] =
  var resultList: seq[WindowInfo] = @[]
  var context = EnumWindowsContext(opts: addr opts, strict: strict, listPtr: addr resultList)

  proc callback(hwnd: HWND; lParam: LPARAM): WINBOOL {.stdcall.} =
    let ctx = cast[ptr EnumWindowsContext](lParam)
    if shouldIncludeWindow(hwnd, ctx.opts[], ctx.strict):
      ctx.listPtr[].add(collectWindowInfo(hwnd))
    1

  discard EnumWindows(callback, cast[LPARAM](addr context))
  resultList

## Enumerates visible, eligible windows with a fallback to a relaxed filter.
proc enumTopLevelWindows*(opts: WindowEligibilityOptions = defaultEligibilityOptions()): seq[WindowInfo] =
  result = collectEligibleWindows(opts, true)
  if result.len == 0:
    result = collectEligibleWindows(opts, false)

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
    if shouldIncludeWindow(root, opts, strict):
      return root
    let owner = rootOwnerWindow(root)
    if owner != root and shouldIncludeWindow(owner, opts, strict):
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
  let hwnd = clickToPick(opts)
  if hwnd == 0:
    return
  some(collectWindowInfo(hwnd))
