import winim/lean

## Shared user32 wrappers for window management utilities.

when not declared(EnumWindowsProc):
  type
    EnumWindowsProc* = proc(hwnd: HWND; lParam: LPARAM): WINBOOL {.stdcall.}

when not declared(EnumWindows):
  proc EnumWindows*(lpEnumFunc: EnumWindowsProc; lParam: LPARAM): WINBOOL {.stdcall,
      dynlib: "user32", importc.}

when not declared(CreatePopupMenu):
  proc CreatePopupMenu*(): HMENU {.stdcall, dynlib: "user32", importc.}

when not declared(AppendMenuW):
  proc AppendMenuW*(hMenu: HMENU; uFlags: UINT; uIDNewItem: UINT_PTR;
      lpNewItem: LPCWSTR): WINBOOL {.stdcall, dynlib: "user32", importc.}

when not declared(TrackPopupMenu):
  proc TrackPopupMenu*(hMenu: HMENU; uFlags: UINT; x: int32; y: int32;
      nReserved: int32; hWnd: HWND; prcRect: ptr RECT): int32 {.stdcall,
      dynlib: "user32", importc.}

when not declared(DestroyMenu):
  proc DestroyMenu*(hMenu: HMENU): WINBOOL {.stdcall, dynlib: "user32", importc.}

when not declared(CheckMenuItem):
  proc CheckMenuItem*(hMenu: HMENU; uIDCheckItem: UINT; uCheck: UINT): DWORD {.
      stdcall, dynlib: "user32", importc.}

when not declared(RegisterHotKey):
  proc RegisterHotKey*(hWnd: HWND; id: int32; fsModifiers: UINT; vk: UINT): WINBOOL
      {.stdcall, dynlib: "user32", importc.}

when not declared(UnregisterHotKey):
  proc UnregisterHotKey*(hWnd: HWND; id: int32): WINBOOL {.stdcall,
      dynlib: "user32", importc.}

when not declared(SetWindowLongPtrW):
  proc SetWindowLongPtrW*(hWnd: HWND; nIndex: int32; dwNewLong: LONG_PTR): LONG_PTR
      {.stdcall, dynlib: "user32", importc.}

when not declared(GetWindowLongPtrW):
  proc GetWindowLongPtrW*(hWnd: HWND; nIndex: int32): LONG_PTR {.stdcall,
      dynlib: "user32", importc.}

when not declared(GetClientRect):
  proc GetClientRect*(hWnd: HWND; lpRect: ptr RECT): WINBOOL {.stdcall,
      dynlib: "user32", importc.}

when not declared(GetAsyncKeyState):
  proc GetAsyncKeyState*(vKey: int32): int16 {.stdcall, dynlib: "user32", importc.}

when not declared(IsIconic):
  proc IsIconic*(hWnd: HWND): WINBOOL {.stdcall, dynlib: "user32", importc.}

when not declared(SetForegroundWindow):
  proc SetForegroundWindow*(hWnd: HWND): WINBOOL {.stdcall, dynlib: "user32",
      importc.}

when not declared(SetTimer):
  proc SetTimer*(hwnd: HWND; nIDEvent: UINT_PTR; uElapse: UINT; lpTimerFunc: pointer): UINT_PTR
      {.stdcall, dynlib: "user32", importc.}

when not declared(KillTimer):
  proc KillTimer*(hwnd: HWND; uIDEvent: UINT_PTR): WINBOOL {.stdcall,
      dynlib: "user32", importc.}

when not declared(IsWindow):
  proc IsWindow*(hWnd: HWND): WINBOOL {.stdcall, dynlib: "user32", importc.}

when not declared(IsWindowVisible):
  proc IsWindowVisible*(hWnd: HWND): WINBOOL {.stdcall, dynlib: "user32",
      importc.}

when not declared(MessageBoxW):
  proc MessageBoxW*(hWnd: HWND; lpText: LPCWSTR; lpCaption: LPCWSTR; uType: UINT): int32
      {.stdcall, dynlib: "user32", importc.}

when not declared(GetWindowTextLengthW):
  proc GetWindowTextLengthW*(hWnd: HWND): int32 {.stdcall, dynlib: "user32",
      importc.}

when not declared(GetWindowTextW):
  proc GetWindowTextW*(hWnd: HWND; lpString: LPWSTR; nMaxCount: int32): int32 {.
      stdcall, dynlib: "user32", importc.}

when not declared(GetWindowThreadProcessId):
  proc GetWindowThreadProcessId*(hwnd: HWND; lpdwProcessId: ptr DWORD): DWORD {.
      stdcall, dynlib: "user32", importc.}

when not declared(GetShellWindow):
  proc GetShellWindow*(): HWND {.stdcall, dynlib: "user32", importc.}

when not declared(GetDesktopWindow):
  proc GetDesktopWindow*(): HWND {.stdcall, dynlib: "user32", importc.}

when not declared(GetWindow):
  proc GetWindow*(hWnd: HWND; uCmd: UINT): HWND {.stdcall, dynlib: "user32",
      importc.}

when not declared(GetLastActivePopup):
  proc GetLastActivePopup*(hWnd: HWND): HWND {.stdcall, dynlib: "user32",
      importc.}

when not declared(GetAncestor):
  proc GetAncestor*(hwnd: HWND; gaFlags: UINT): HWND {.stdcall, dynlib: "user32",
      importc.}

when not declared(GetCursorPos):
  proc GetCursorPos*(lpPoint: ptr POINT): WINBOOL {.stdcall, dynlib: "user32",
      importc.}

when not declared(WindowFromPoint):
  proc WindowFromPoint*(point: POINT): HWND {.stdcall, dynlib: "user32", importc.}

when not declared(GetWindowRect):
  proc GetWindowRect*(hWnd: HWND; lpRect: ptr RECT): WINBOOL {.stdcall,
      dynlib: "user32", importc.}

when not declared(DrawFocusRect):
  proc DrawFocusRect*(hDC: HDC; lprc: ptr RECT): WINBOOL {.stdcall,
      dynlib: "user32", importc.}

when not declared(GetDC):
  proc GetDC*(hWnd: HWND): HDC {.stdcall, dynlib: "user32", importc.}

when not declared(ReleaseDC):
  proc ReleaseDC*(hWnd: HWND; hDC: HDC): int32 {.stdcall, dynlib: "user32",
      importc.}

