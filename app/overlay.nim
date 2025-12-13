import std/widestrs
import winlean

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
when not declared(GetAsyncKeyState):
  proc GetAsyncKeyState(vKey: int32): int16 {.stdcall, dynlib: "user32", importc.}
when not declared(IsIconic):
  proc IsIconic(hWnd: HWND): WINBOOL {.stdcall, dynlib: "user32", importc.}
when not declared(SetForegroundWindow):
  proc SetForegroundWindow(hWnd: HWND): WINBOOL {.stdcall, dynlib: "user32",
      importc.}

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
  enableClickForwarding = false ## Future flag: forward shift-clicks to the source window.

type
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

var appState: AppState = AppState(opacity: 255.BYTE, thumbnailVisible: true)

proc clampRect(rect, bounds: RECT): RECT =
  result.left = max(rect.left, bounds.left)
  result.top = max(rect.top, bounds.top)
  result.right = min(rect.right, bounds.right)
  result.bottom = min(rect.bottom, bounds.bottom)
  if result.right < result.left:
    result.right = result.left
  if result.bottom < result.top:
    result.bottom = result.top

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

proc restoreAndFocusTarget() =
  let target = appState.targetHwnd
  if target == 0:
    return
  if IsIconic(target) != 0:
    discard ShowWindow(target, SW_RESTORE)
  discard SetForegroundWindow(target)
  when enableClickForwarding:
    ## Future: forward the click to the source window when enabled.
    discard

proc createContextMenu(): HMENU =
  result = CreatePopupMenu()
  var topFlags = menuTopFlags
  if appState.cfg.topMost:
    topFlags = topFlags or menuChecked
  discard AppendMenuW(result, topFlags, idToggleTopMost, wideCString"Always on Top")

  var borderFlags = menuTopFlags
  if appState.cfg.borderless:
    borderFlags = borderFlags or menuChecked
  discard AppendMenuW(result, borderFlags, idToggleBorderless, wideCString"Borderless")

  discard AppendMenuW(result, MF_SEPARATOR, 0, nil)
  discard AppendMenuW(result, menuTopFlags, idExit, wideCString"Exit")

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
  props.fVisible = (if appState.thumbnailVisible: 1 else: 0)
  props.fSourceClientAreaOnly = 1
  discard DwmUpdateThumbnailProperties(appState.thumbnail, addr props)

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
  appState.cropRect = clampRect(rectFromConfig, sourceRect)
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
    if not appState.hasCrop:
      applySavedCrop(target)
    updateThumbnailProperties()

proc mapOverlayToSource(overlayRect: RECT): RECT =
  # The thumbnail is stretched to fill the overlay client area; map linearly without
  # letterboxing.
  let destRect = clientRect(appState.hwnd)
  let sourceRect = clientRect(appState.targetHwnd)
  let destWidth = destRect.right - destRect.left
  let destHeight = destRect.bottom - destRect.top
  if destWidth == 0 or destHeight == 0:
    return sourceRect

  let scaleX = (sourceRect.right - sourceRect.left).float / destWidth.float
  let scaleY = (sourceRect.bottom - sourceRect.top).float / destHeight.float

  var mapped: RECT
  mapped.left = sourceRect.left + int((overlayRect.left - destRect.left).float * scaleX)
  mapped.top = sourceRect.top + int((overlayRect.top - destRect.top).float * scaleY)
  mapped.right = sourceRect.left + int((overlayRect.right - destRect.left).float * scaleX)
  mapped.bottom = sourceRect.top + int((overlayRect.bottom - destRect.top).float * scaleY)

  clampRect(mapped, sourceRect)

## Sets the target window whose client area will be mirrored by the overlay.
proc setTargetWindow*(target: HWND) =
  if target != appState.targetHwnd:
    appState.hasCrop = false
    registerThumbnail(target)

## Applies a crop rectangle using source window coordinates.
proc setCrop*(rect: RECT) =
  if appState.targetHwnd == 0:
    return
  let sourceRect = clientRect(appState.targetHwnd)
  let clamped = clampRect(rect, sourceRect)
  appState.cropRect = clamped
  appState.hasCrop = true
  saveCropToConfig(clamped, true)
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
  let menu = createContextMenu()
  let x = int32(loWordL(lParam))
  let y = int32(hiWordL(lParam))
  discard TrackPopupMenu(
    menu,
    TPM_LEFTALIGN or TPM_TOPALIGN or TPM_RIGHTBUTTON,
    x,
    y,
    0,
    hwnd,
    nil
  )
  discard DestroyMenu(menu)

proc saveStateOnClose() =
  saveOverlayConfig(appState.cfg)

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
  of WM_DESTROY:
    unregisterThumbnail()
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
  appState.hInstance = GetModuleHandleW(nil)
  appState.hwnd = createWindow(appState.hInstance)
  if appState.hwnd == 0:
    return

  applyStyle(appState.hwnd)
  applyTopMost(appState.hwnd)

  discard ShowWindow(appState.hwnd, SW_SHOWNORMAL)
  discard UpdateWindow(appState.hwnd)

  var msg: MSG
  while GetMessageW(addr msg, 0, 0, 0) != 0:
    discard TranslateMessage(addr msg)
    discard DispatchMessageW(addr msg)

  saveStateOnClose()

when isMainModule:
  run()
