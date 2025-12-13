## Overlay window entry point that manages DWM thumbnails and crop state.
when defined(windows):
  {.appType: gui.}

import std/[os, strutils, widestrs]
import winlean
import util/geometry

when not declared(CreatePopupMenu):
  proc CreatePopupMenu(): HMENU {.stdcall, dynlib: "user32", importc.}
when not declared(AppendMenuW):
  proc AppendMenuW(hMenu: HMENU; uFlags: UINT; uIDNewItem: UINT_PTR;
      lpNewItem: LPCWSTR): WINBOOL {.stdcall, dynlib: "user32", importc.}
when not declared(TrackPopupMenu):
  proc TrackPopupMenu(hMenu: HMENU; uFlags: UINT; x: int32; y: int32;
      nReserved: int32; hWnd: HWND; prcRect: ptr RECT): int32 {.stdcall,
      dynlib: "user32", importc.}
when not declared(DestroyMenu):
  proc DestroyMenu(hMenu: HMENU): WINBOOL {.stdcall, dynlib: "user32", importc.}
when not declared(CheckMenuItem):
  proc CheckMenuItem(hMenu: HMENU; uIDCheckItem: UINT; uCheck: UINT): DWORD {.
      stdcall, dynlib: "user32", importc.}
when not declared(SetWindowLongPtrW):
  proc SetWindowLongPtrW(hWnd: HWND; nIndex: int32; dwNewLong: LONG_PTR): LONG_PTR
      {.stdcall, dynlib: "user32", importc.}
when not declared(GetClientRect):
  proc GetClientRect(hWnd: HWND; lpRect: ptr RECT): WINBOOL {.stdcall,
      dynlib: "user32", importc.}
when not declared(DwmRegisterThumbnail):
  proc DwmRegisterThumbnail(hwndDestination: HWND; hwndSource: HWND;
      phThumbnailId: ptr HANDLE): HRESULT {.stdcall, dynlib: "dwmapi", importc.}
when not declared(DwmUnregisterThumbnail):
  proc DwmUnregisterThumbnail(hThumbnailId: HANDLE): HRESULT {.stdcall,
      dynlib: "dwmapi", importc.}
when not declared(DwmUpdateThumbnailProperties):
  proc DwmUpdateThumbnailProperties(hThumbnailId: HANDLE;
      ptnProperties: ptr DWM_THUMBNAIL_PROPERTIES): HRESULT {.stdcall,
      dynlib: "dwmapi", importc.}
when not declared(DwmQueryThumbnailSourceSize):
  proc DwmQueryThumbnailSourceSize(hThumbnail: HANDLE; pSize: ptr SIZE): HRESULT
      {.stdcall, dynlib: "dwmapi", importc.}
when not declared(GetAsyncKeyState):
  proc GetAsyncKeyState(vKey: int32): int16 {.stdcall, dynlib: "user32", importc.}
when not declared(IsIconic):
  proc IsIconic(hWnd: HWND): WINBOOL {.stdcall, dynlib: "user32", importc.}
when not declared(SetForegroundWindow):
  proc SetForegroundWindow(hWnd: HWND): WINBOOL {.stdcall, dynlib: "user32",
      importc.}
when not declared(SetTimer):
  proc SetTimer(hwnd: HWND; nIDEvent: UINT_PTR; uElapse: UINT;
      lpTimerFunc: pointer): UINT_PTR {.stdcall, dynlib: "user32", importc.}
when not declared(KillTimer):
  proc KillTimer(hwnd: HWND; uIDEvent: UINT_PTR): WINBOOL {.stdcall,
      dynlib: "user32", importc.}
when not declared(IsWindow):
  proc IsWindow(hWnd: HWND): WINBOOL {.stdcall, dynlib: "user32", importc.}
when not declared(IsWindowVisible):
  proc IsWindowVisible(hWnd: HWND): WINBOOL {.stdcall, dynlib: "user32",
      importc.}
when not declared(MessageBoxW):
  proc MessageBoxW(hWnd: HWND; lpText: LPCWSTR; lpCaption: LPCWSTR;
      uType: UINT): int32 {.stdcall, dynlib: "user32", importc.}
when not declared(GetWindowTextLengthW):
  proc GetWindowTextLengthW(hWnd: HWND): int32 {.stdcall, dynlib: "user32",
      importc.}
when not declared(GetWindowTextW):
  proc GetWindowTextW(hWnd: HWND; lpString: LPWSTR; nMaxCount: int32): int32 {.
      stdcall, dynlib: "user32", importc.}
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
when not declared(EnumWindows):
  type
    EnumWindowsProc = proc(hwnd: HWND; lParam: LPARAM): WINBOOL {.stdcall.}
  proc EnumWindows(lpEnumFunc: EnumWindowsProc; lParam: LPARAM): WINBOOL {.
      stdcall, dynlib: "user32", importc.}

type
  DWM_THUMBNAIL_PROPERTIES {.pure.} = object
    dwFlags: DWORD
    rcDestination: RECT
    rcSource: RECT
    opacity: BYTE
    fVisible: WINBOOL
    fSourceClientAreaOnly: WINBOOL

import config/storage

const
  className = wideCString"NimOTROverlayClass"
  windowTitle = wideCString"Nim OTR Overlay"
  idToggleTopMost = 1001
  idToggleBorderless = 1002
  idExit = 1003

  menuTopFlags = MF_STRING
  menuChecked = MF_CHECKED
  menuUnchecked = MF_UNCHECKED
  menuByCommand = MF_BYCOMMAND

  styleStandard = WS_OVERLAPPEDWINDOW
  styleBorderless = WS_POPUP or WS_THICKFRAME or WS_MINIMIZEBOX or WS_MAXIMIZEBOX
  DWM_TNP_RECTDESTINATION = 0x1
  DWM_TNP_RECTSOURCE = 0x2
  DWM_TNP_OPACITY = 0x4
  DWM_TNP_VISIBLE = 0x8
  DWM_TNP_SOURCECLIENTAREAONLY = 0x10
  VK_SHIFT = 0x10
  HTTRANSPARENT = -1
  SW_RESTORE = 9
  validationTimerId = 2001
  validationIntervalMs = 750
  MB_OK = 0x0
  MB_ICONINFORMATION = 0x40
  PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
  enableClickForwarding = false ## Future flag: forward shift-clicks to the source window.

let
  menuLabelTopMost = wideCString"Always on Top"
  menuLabelBorderless = wideCString"Borderless"
  menuLabelExit = wideCString"Exit"

type
  WindowIdentity = object
    hwnd: HWND
    title: string
    processName: string

  AppState = object
    cfg: OverlayConfig
    hInstance: HINSTANCE
    hwnd: HWND
    targetHwnd: HWND
    thumbnail: HANDLE
    cropRect: RECT
    hasCrop: bool
    opacity: BYTE
    thumbnailVisible: bool
    thumbnailSuppressed: bool
    promptedForReselect: bool
    validationTimerRunning: bool
    contextMenu: HMENU

var appState: AppState = AppState(opacity: 255.BYTE, thumbnailVisible: true)

proc toIntRect(rect: RECT): IntRect =
  IntRect(
    left: rect.left.int,
    top: rect.top.int,
    right: rect.right.int,
    bottom: rect.bottom.int
  )

proc toWinRect(rect: IntRect): RECT =
  RECT(
    left: LONG(rect.left),
    top: LONG(rect.top),
    right: LONG(rect.right),
    bottom: LONG(rect.bottom)
  )

proc saveCropToConfig(rect: RECT; active: bool) =
  appState.cfg.cropActive = active
  appState.cfg.cropLeft = rect.left
  appState.cfg.cropTop = rect.top
  appState.cfg.cropWidth = rect.right - rect.left
  appState.cfg.cropHeight = rect.bottom - rect.top

proc configCropRect(cfg: OverlayConfig): RECT =
  RECT(
    left: cfg.cropLeft,
    top: cfg.cropTop,
    right: cfg.cropLeft + cfg.cropWidth,
    bottom: cfg.cropTop + cfg.cropHeight
  )

proc loWord(value: WPARAM): UINT {.inline.} = UINT(value and 0xFFFF)
proc loWordL(value: LPARAM): UINT {.inline.} = UINT(value and 0xFFFF)
proc hiWordL(value: LPARAM): UINT {.inline.} = UINT((value shr 16) and 0xFFFF)

proc shiftHeld(): bool =
  (GetAsyncKeyState(VK_SHIFT) and 0x8000'i16) != 0

proc windowTitle(hwnd: HWND): string =
  let length = GetWindowTextLengthW(hwnd)
  if length <= 0:
    return
  var buf = newWideCString(length + 1)
  discard GetWindowTextW(hwnd, buf, length + 1)
  $buf

proc windowProcessName(hwnd: HWND): string =
  var pid: DWORD
  discard GetWindowThreadProcessId(hwnd, addr pid)
  if pid == 0:
    return ""

  let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
  if handle == 0:
    return ""

  var size = 260.DWORD
  var buffer = newWideCString(int(size))
  if QueryFullProcessImageNameW(handle, 0, buffer, addr size) != 0:
    let path = $buffer
    result = splitFile(path).name
  discard CloseHandle(handle)

proc collectWindowIdentity(hwnd: HWND): WindowIdentity =
  WindowIdentity(
    hwnd: hwnd,
    title: windowTitle(hwnd),
    processName: windowProcessName(hwnd)
  )

proc matchesStoredWindow(win: WindowIdentity; cfg: OverlayConfig): bool =
  let processMatches = cfg.targetProcess.len > 0 and
      cmpIgnoreCase(win.processName, cfg.targetProcess) == 0
  let titleMatches = cfg.targetTitle.len > 0 and win.title == cfg.targetTitle

  if cfg.targetProcess.len > 0 and cfg.targetTitle.len > 0:
    processMatches and titleMatches
  elif cfg.targetProcess.len > 0:
    processMatches
  else:
    titleMatches

proc findWindowByIdentity(cfg: OverlayConfig): HWND =
  if cfg.targetTitle.len == 0 and cfg.targetProcess.len == 0:
    return 0

  var found: HWND = 0

  proc callback(hwnd: HWND; lParam: LPARAM): WINBOOL {.stdcall.} =
    if IsWindowVisible(hwnd) == 0:
      return 1
    let identity = collectWindowIdentity(hwnd)
    if matchesStoredWindow(identity, cfg):
      found = hwnd
      return 0
    1

  discard EnumWindows(callback, 0)
  found

proc restoreAndFocusTarget() =
  let target = appState.targetHwnd
  if target == 0:
    return
  if IsIconic(target) != 0:
    discard ShowWindow(target, SW_RESTORE)
  discard SetForegroundWindow(target)
  if appState.thumbnailSuppressed:
    appState.thumbnailSuppressed = false
    updateThumbnailProperties()
  when enableClickForwarding:
    ## Future: forward the click to the source window when enabled.
    discard

proc createContextMenu() =
  if appState.contextMenu != 0:
    return

  let menu = CreatePopupMenu()
  if menu == 0:
    return

  appState.contextMenu = menu
  discard AppendMenuW(menu, menuTopFlags, idToggleTopMost, menuLabelTopMost)
  discard AppendMenuW(menu, menuTopFlags, idToggleBorderless, menuLabelBorderless)

  discard AppendMenuW(menu, MF_SEPARATOR, 0, nil)
  discard AppendMenuW(menu, menuTopFlags, idExit, menuLabelExit)

proc updateContextMenuChecks() =
  if appState.contextMenu == 0:
    return

  let topFlags = if appState.cfg.topMost: menuByCommand or menuChecked else: menuByCommand or menuUnchecked
  discard CheckMenuItem(appState.contextMenu, idToggleTopMost, topFlags)

  let borderFlags = if appState.cfg.borderless: menuByCommand or menuChecked else: menuByCommand or menuUnchecked
  discard CheckMenuItem(appState.contextMenu, idToggleBorderless, borderFlags)

proc destroyContextMenu() =
  if appState.contextMenu == 0:
    return
  discard DestroyMenu(appState.contextMenu)
  appState.contextMenu = 0

proc applyTopMost(hwnd: HWND) =
  let insertAfter = if appState.cfg.topMost: HWND_TOPMOST else: HWND_NOTOPMOST
  discard SetWindowPos(
    hwnd,
    insertAfter,
    0,
    0,
    0,
    0,
    SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE
  )

proc currentStyle(): DWORD =
  if appState.cfg.borderless: styleBorderless else: styleStandard

proc applyStyle(hwnd: HWND) =
  let style = currentStyle()
  discard SetWindowLongPtrW(hwnd, GWL_STYLE, style)
  discard SetWindowPos(
    hwnd,
    HWND_TOP,
    0,
    0,
    0,
    0,
    SWP_NOMOVE or SWP_NOSIZE or SWP_FRAMECHANGED or SWP_NOACTIVATE or SWP_NOZORDER
  )

proc handleSize(lParam: LPARAM) =
  appState.cfg.width = int(loWordL(lParam))
  appState.cfg.height = int(hiWordL(lParam))

proc handleMove(lParam: LPARAM) =
  appState.cfg.x = int(int16(loWordL(lParam)))
  appState.cfg.y = int(int16(hiWordL(lParam)))

proc clientRect(hwnd: HWND): RECT =
  var rect: RECT
  if GetClientRect(hwnd, addr rect) != 0:
    rect

proc unregisterThumbnail() =
  if appState.thumbnail != 0:
    discard DwmUnregisterThumbnail(appState.thumbnail)
    appState.thumbnail = 0

proc updateThumbnailProperties() =
  if appState.thumbnail == 0:
    return
  let destRect = clientRect(appState.hwnd)
  var props: DWM_THUMBNAIL_PROPERTIES
  props.dwFlags = DWM_TNP_VISIBLE or DWM_TNP_OPACITY or DWM_TNP_RECTDESTINATION or
      DWM_TNP_RECTSOURCE or DWM_TNP_SOURCECLIENTAREAONLY
  props.rcDestination = destRect
  props.rcSource = appState.cropRect
  props.opacity = appState.opacity
  props.fVisible = (if appState.thumbnailVisible and not appState.thumbnailSuppressed: 1 else: 0)
  props.fSourceClientAreaOnly = 1
  discard DwmUpdateThumbnailProperties(appState.thumbnail, addr props)

proc thumbnailHandleValid(): bool =
  if appState.thumbnail == 0:
    return false
  var size: SIZE
  DwmQueryThumbnailSourceSize(appState.thumbnail, addr size) == 0

proc promptForReselect() =
  if appState.promptedForReselect:
    return
  appState.promptedForReselect = true
  discard MessageBoxW(
    appState.hwnd,
    wideCString"The mirrored window is no longer available. Please reselect a source window.",
    windowTitle,
    MB_OK or MB_ICONINFORMATION
  )

proc detachTarget(promptUser: bool) =
  if appState.thumbnail != 0:
    unregisterThumbnail()
  appState.targetHwnd = 0
  appState.hasCrop = false
  appState.thumbnailSuppressed = false
  stopValidationTimer()
  if promptUser:
    promptForReselect()

proc validateTargetState() =
  let target = appState.targetHwnd
  if target == 0:
    return

  if IsWindow(target) == 0:
    detachTarget(true)
    return

  if not thumbnailHandleValid():
    registerThumbnail(target)

  let minimized = IsIconic(target) != 0
  let visible = IsWindowVisible(target) != 0
  let shouldSuppress = minimized or not visible

  if appState.thumbnailSuppressed != shouldSuppress:
    appState.thumbnailSuppressed = shouldSuppress
    updateThumbnailProperties()

  if not shouldSuppress and appState.thumbnail == 0:
    registerThumbnail(target)
  elif not shouldSuppress:
    updateThumbnailProperties()

proc setDefaultCrop(target: HWND) =
  let rect = clientRect(target)
  appState.cropRect = rect
  appState.hasCrop = true
  saveCropToConfig(rect, false)

proc applySavedCrop(target: HWND) =
  let sourceRect = clientRect(target)
  if not appState.cfg.cropActive:
    setDefaultCrop(target)
    return
  let rectFromConfig = configCropRect(appState.cfg)
  appState.cropRect = clampRect(rectFromConfig.toIntRect, sourceRect.toIntRect).toWinRect
  appState.hasCrop = true

proc registerThumbnail(target: HWND) =
  unregisterThumbnail()
  appState.targetHwnd = 0
  if target == 0:
    return

  var thumbnailId: HANDLE
  if DwmRegisterThumbnail(appState.hwnd, target, addr thumbnailId) == 0:
    appState.thumbnail = thumbnailId
    appState.targetHwnd = target
    let identity = collectWindowIdentity(target)
    appState.cfg.targetHwnd = cast[int](identity.hwnd)
    appState.cfg.targetTitle = identity.title
    appState.cfg.targetProcess = identity.processName
    if not appState.hasCrop:
      applySavedCrop(target)
    updateThumbnailProperties()
    startValidationTimer()

proc mapOverlayToSource(overlayRect: RECT): RECT =
  # The thumbnail is stretched to fill the overlay client area; map linearly without
  # letterboxing.
  let destRect = clientRect(appState.hwnd).toIntRect
  let sourceRect = clientRect(appState.targetHwnd).toIntRect
  mapRectToSource(overlayRect.toIntRect, destRect, sourceRect).toWinRect

## Sets the target window whose client area will be mirrored by the overlay.
proc setTargetWindow*(target: HWND) =
  if target != appState.targetHwnd:
    appState.hasCrop = false
    appState.thumbnailSuppressed = false
    appState.promptedForReselect = false
    registerThumbnail(target)
    if appState.targetHwnd != 0:
      let identity = collectWindowIdentity(appState.targetHwnd)
      appState.cfg.targetHwnd = cast[int](identity.hwnd)
      appState.cfg.targetTitle = identity.title
      appState.cfg.targetProcess = identity.processName

## Applies a crop rectangle using source window coordinates.
proc setCrop*(rect: RECT) =
  if appState.targetHwnd == 0:
    return
  let sourceRect = clientRect(appState.targetHwnd)
  let clamped = clampRect(rect.toIntRect, sourceRect.toIntRect)
  appState.cropRect = clamped.toWinRect
  appState.hasCrop = true
  saveCropToConfig(clamped.toWinRect, true)
  updateThumbnailProperties()

## Maps an overlay client-area rectangle to the source window and applies the crop.
proc setCropFromOverlayRect*(rect: RECT) =
  if appState.targetHwnd == 0:
    return
  setCrop(mapOverlayToSource(rect))

## Restores the crop to the full source window.
proc resetCrop*() =
  if appState.targetHwnd == 0:
    return
  setDefaultCrop(appState.targetHwnd)
  updateThumbnailProperties()

## Adjusts DWM thumbnail opacity for the overlay.
proc setOpacity*(value: BYTE) =
  appState.opacity = value
  appState.cfg.opacity = int(value)
  updateThumbnailProperties()

## Toggles thumbnail visibility on the overlay window.
proc setThumbnailVisible*(visible: bool) =
  appState.thumbnailVisible = visible
  updateThumbnailProperties()

proc handleDpiChanged(hwnd: HWND, lParam: LPARAM) =
  let suggested = cast[ptr RECT](lParam)
  let width = suggested.right - suggested.left
  let height = suggested.bottom - suggested.top
  discard SetWindowPos(
    hwnd,
    0,
    suggested.left,
    suggested.top,
    width,
    height,
    SWP_NOZORDER or SWP_NOACTIVATE
  )

proc handleCommand(hwnd: HWND, wParam: WPARAM) =
  case loWord(wParam)
  of idToggleTopMost:
    appState.cfg.topMost = not appState.cfg.topMost
    applyTopMost(hwnd)
  of idToggleBorderless:
    appState.cfg.borderless = not appState.cfg.borderless
    applyStyle(hwnd)
  of idExit:
    discard PostMessageW(hwnd, WM_CLOSE, 0, 0)
  else:
    discard

proc handleContextMenu(hwnd: HWND, lParam: LPARAM) =
  createContextMenu()
  updateContextMenuChecks()
  if appState.contextMenu == 0:
    return
  let x = int32(loWordL(lParam))
  let y = int32(hiWordL(lParam))
  discard TrackPopupMenu(
    appState.contextMenu,
    TPM_LEFTALIGN or TPM_TOPALIGN or TPM_RIGHTBUTTON,
    x,
    y,
    0,
    hwnd,
    nil
  )

proc saveStateOnClose() =
  saveOverlayConfig(appState.cfg)

proc startValidationTimer() =
  if appState.validationTimerRunning or appState.hwnd == 0 or appState.targetHwnd == 0:
    return
  if SetTimer(appState.hwnd, validationTimerId, validationIntervalMs, nil) != 0:
    appState.validationTimerRunning = true

proc stopValidationTimer() =
  if not appState.validationTimerRunning:
    return
  discard KillTimer(appState.hwnd, validationTimerId)
  appState.validationTimerRunning = false

proc wndProc(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.} =
  case msg
  of WM_SIZE:
    handleSize(lParam)
    updateThumbnailProperties()
    return 0
  of WM_MOVE:
    handleMove(lParam)
    return 0
  of WM_DPICHANGED:
    handleDpiChanged(hwnd, lParam)
    return 0
  of WM_COMMAND:
    handleCommand(hwnd, wParam)
    return 0
  of WM_CONTEXTMENU:
    handleContextMenu(hwnd, lParam)
    return 0
  of WM_NCHITTEST:
    if not shiftHeld():
      return HTTRANSPARENT
  of WM_LBUTTONDOWN:
    if shiftHeld():
      restoreAndFocusTarget()
    return DefWindowProcW(hwnd, msg, wParam, lParam)
  of WM_TIMER:
    if wParam == validationTimerId:
      validateTargetState()
      return 0
  of WM_DESTROY:
    stopValidationTimer()
    unregisterThumbnail()
    destroyContextMenu()
    saveStateOnClose()
    PostQuitMessage(0)
    return 0
  else:
    discard
  result = DefWindowProcW(hwnd, msg, wParam, lParam)

proc createWindow(hInstance: HINSTANCE): HWND =
  var wc: WNDCLASSEXW
  wc.cbSize = sizeof(WNDCLASSEXW).UINT
  wc.style = CS_HREDRAW or CS_VREDRAW
  wc.lpfnWndProc = wndProc
  wc.hInstance = hInstance
  wc.hCursor = LoadCursorW(0, IDC_ARROW)
  wc.hbrBackground = cast[HBRUSH](COLOR_WINDOW + 1)
  wc.lpszClassName = className

  if RegisterClassExW(wc) == 0:
    return 0

  let useDefault = not hasValidPosition(appState.cfg)
  let xpos = if useDefault: CW_USEDEFAULT else: appState.cfg.x
  let ypos = if useDefault: CW_USEDEFAULT else: appState.cfg.y

  result = CreateWindowExW(
    0,
    className,
    windowTitle,
    currentStyle(),
    xpos,
    ypos,
    appState.cfg.width,
    appState.cfg.height,
    0,
    0,
    hInstance,
    nil
  )

proc run() =
  appState.cfg = loadOverlayConfig()
  let storedOpacity = max(min(appState.cfg.opacity, 255), 0)
  appState.opacity = BYTE(storedOpacity)
  appState.hInstance = GetModuleHandleW(nil)
  appState.hwnd = createWindow(appState.hInstance)
  if appState.hwnd == 0:
    return

  applyStyle(appState.hwnd)
  applyTopMost(appState.hwnd)

  let storedTarget = HWND(appState.cfg.targetHwnd)
  if storedTarget != 0 and IsWindow(storedTarget) != 0:
    registerThumbnail(storedTarget)
  elif appState.targetHwnd == 0:
    registerThumbnail(findWindowByIdentity(appState.cfg))

  discard ShowWindow(appState.hwnd, SW_SHOWNORMAL)
  discard UpdateWindow(appState.hwnd)

  var msg: MSG
  while GetMessageW(addr msg, 0, 0, 0) != 0:
    discard TranslateMessage(addr msg)
    discard DispatchMessageW(addr msg)

  saveStateOnClose()

when isMainModule:
  run()
