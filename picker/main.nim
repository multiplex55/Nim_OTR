## CLI helper that enumerates visible windows and lets users pick a target HWND.

import std/[options, os, strformat, strutils, widestrs]
import winlean

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
  DWMWA_CLOAKED = 14
  WS_EX_TOOLWINDOW = 0x00000080
  GWL_EXSTYLE = -20
  PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
  R2_NOT = 6

type
  ## Captured window metadata for display and selection.
  WindowInfo* = object
    hwnd*: HWND
    title*: string
    processName*: string

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

proc shouldInclude(hwnd: HWND): bool =
  if hwnd == 0:
    return false
  if IsWindowVisible(hwnd) == 0:
    return false
  if isToolWindow(hwnd):
    return false
  if isCloaked(hwnd):
    return false
  let title = getWindowTitle(hwnd)
  if title.strip.len == 0:
    return false
  true

## Enumerates visible, non-tool windows and returns their metadata.
proc enumTopLevelWindows*(): seq[WindowInfo] =
  var resultList: seq[WindowInfo] = @[]

  proc callback(hwnd: HWND; lParam: LPARAM): WINBOOL {.stdcall.} =
    if shouldInclude(hwnd) and rootWindow(hwnd) == hwnd:
      resultList.add(collectWindowInfo(hwnd))
    1

  discard EnumWindows(callback, 0)
  result = resultList

proc printWindowList(windows: seq[WindowInfo]) =
  echo "Available windows:"
  for i, win in windows:
    let hwndHex = cast[int](win.hwnd).toHex.upper()
    echo &"{i + 1}. {win.title} ({win.processName}) [HWND=0x{hwndHex}]"

proc toggleHighlight(rect: RECT) =
  let hdc = GetDC(0)
  if hdc == 0:
    return
  discard SetROP2(hdc, R2_NOT)
  var r = rect
  discard DrawFocusRect(hdc, addr r)
  discard ReleaseDC(0, hdc)

proc currentHoveredWindow(): HWND =
  var pt: POINT
  if GetCursorPos(addr pt) == 0:
    return 0
  let hwnd = rootWindow(WindowFromPoint(pt))
  if shouldInclude(hwnd):
    hwnd else: 0

proc keyJustPressed(vk: int32): bool =
  (GetAsyncKeyState(vk) and 0x8001) != 0

proc clickToPick(): HWND =
  echo "Click-to-pick: hover a window and click or press Enter to select. " &
    "Press Esc to cancel."
  var lastRect: RECT
  var lastHwnd: HWND

  while true:
    let hovered = currentHoveredWindow()
    if hovered != lastHwnd:
      if lastHwnd != 0:
        toggleHighlight(lastRect)
      if hovered != 0:
        if GetWindowRect(hovered, addr lastRect) != 0:
          toggleHighlight(lastRect)
          lastHwnd = hovered
        else:
          lastHwnd = 0
      else:
        lastHwnd = 0

    if keyJustPressed(VK_LBUTTON) or keyJustPressed(VK_RETURN):
      if lastHwnd != 0 and GetWindowRect(lastHwnd, addr lastRect) != 0:
        toggleHighlight(lastRect)
        return lastHwnd
    if keyJustPressed(VK_ESCAPE):
      if lastHwnd != 0 and GetWindowRect(lastHwnd, addr lastRect) != 0:
        toggleHighlight(lastRect)
      return 0

    Sleep(50)

## Interactive selection entry point that returns a chosen window, if any.
proc pickWindow*(): Option[WindowInfo] =
  var windows = enumTopLevelWindows()
  if windows.len == 0:
    echo "No eligible windows found."
    return

  printWindowList(windows)
  echo "\nEnter number to pick, or 'c' for click-to-pick (Esc to cancel):"

  while true:
    let input = stdin.readLine().strip()
    if input.len == 0:
      echo "Please enter a selection."
      continue
    if input.len == 1 and (input[0] == 'c' or input[0] == 'C'):
      let hwnd = clickToPick()
      if hwnd == 0:
        echo "Selection cancelled."
        return
      return some(collectWindowInfo(hwnd))
    if input.len == 1 and (input[0] == 'q' or input[0] == 'Q' or input[0] == 'x' or
        input[0] == 'X'):
      return
    if input.isDigit:
      let idx = parseInt(input) - 1
      if idx >= 0 and idx < windows.len:
        return some(windows[idx])
    echo "Invalid selection. Enter a number or 'c' for click-to-pick."

when isMainModule:
  let selection = pickWindow()
  if selection.isSome:
    let win = selection.get()
    echo &"Selected: {win.title} ({win.processName}) [HWND=0x{cast[int](win.hwnd).toHex.upper()}]"
