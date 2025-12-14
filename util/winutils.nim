import std/[os, widestrs]
import winim/lean
import ../win/[user32, kernel32, dwmapi]

## Shared helpers for reading window metadata and visibility characteristics.

proc windowTitle*(hwnd: HWND): string =
  let length = GetWindowTextLengthW(hwnd)
  if length <= 0:
    return
  var buf = newWideCString(length + 1)
  discard GetWindowTextW(hwnd, buf, length + 1)
  $buf

proc processIdentity*(hwnd: HWND; unknownName: string = "<unknown>"): tuple[name: string, path: string] =
  var pid: DWORD
  discard GetWindowThreadProcessId(hwnd, addr pid)
  if pid == 0:
    return (unknownName, "")

  let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
  if handle == 0:
    return (unknownName, "")

  var size = 260.DWORD
  var buffer = newWideCString(int(size))
  if QueryFullProcessImageNameW(handle, 0, buffer, addr size) != 0:
    let path = $buffer
    result = (splitFile(path).name, path)
  else:
    result = (unknownName, "")
  discard CloseHandle(handle)

proc processName*(hwnd: HWND; unknownName: string = "<unknown>"): string =
  processIdentity(hwnd, unknownName).name

proc processPath*(hwnd: HWND): string =
  processIdentity(hwnd).path

proc isCloaked*(hwnd: HWND): bool =
  var cloaked: DWORD
  if DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, addr cloaked, DWORD(sizeof(cloaked))) != 0:
    return false
  cloaked != 0

proc isToolWindow*(hwnd: HWND): bool =
  (GetWindowLongPtrW(hwnd, GWL_EXSTYLE) and WS_EX_TOOLWINDOW) != 0
