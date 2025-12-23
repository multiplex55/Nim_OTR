## Overlay window entry point that manages DWM thumbnails and crop state.
import std/[json, options, strutils, math]
import winim/lean
import ../config/storage
import ../util/[geometry, virtualdesktop, winutils]
import ../util/logger
import ../win/dwmapi
import ../picker/core

## Forward declarations for routines used before their definitions.
proc clientRect(hwnd: HWND): RECT
proc updateThumbnailProperties()
proc applyAspectLock()
proc overlayDestinationRect(): IntRect
proc updateStatusText()
proc boolLabel(flag: bool): string
proc registerThumbnail(target: HWND)
proc startValidationTimer()
proc stopValidationTimer()
proc createSelectionOverlayWindow(): HWND
proc updateSelectionOverlayBounds()
proc selectionOverlayWndProc(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.}
proc setCrop*(rect: RECT)
proc setCropFromOverlayRect*(rect: RECT)
proc resetCrop*()
proc cropDialogWndProc(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.}
proc restoreAndFocusTarget()

const
  className = L"NimOTROverlayClass"
  overlayTitle = L"Nim OTR Overlay"
  selectionOverlayClassName = L"NimOTRSelectionOverlayClass"
  idSelectWindow = 1000
  idToggleTopMost = 1001
  idToggleBorderless = 1002
  idToggleAspectLock = 1003
  idEditCrop = 1004
  idResetCrop = 1005
  idShowDebugInfo = 1006
  idMouseCrop = 1007
  idExit = 1008
  idWindowMenuNone = 1100
  idWindowMenuStart = 1101

  idCropLeft = 2001
  idCropTop = 2002
  idCropWidth = 2003
  idCropHeight = 2004
  idCropApply = 2005
  idCropResetButton = 2006

  menuTopFlags = MF_STRING
  menuChecked = MF_CHECKED
  menuUnchecked = MF_UNCHECKED
  menuByCommand = MF_BYCOMMAND

  styleStandard = WS_OVERLAPPEDWINDOW
  exStyleLayered = WS_EX_LAYERED
  minSelectionSize = 8
  selectionOverlayColorKey = COLORREF(0x00FF00)
  VK_SHIFT = 0x10
  VK_ESCAPE = 0x1B
  HTTRANSPARENT = -1
  SW_RESTORE = 9
  validationTimerId = 2001
  validationIntervalMs = 750
  MB_OK = 0x0
  MB_ICONINFORMATION = 0x40
  hotkeySelectWindowId = 3001
  MOD_CONTROL = 0x0002
  MOD_SHIFT = 0x0004
  VK_P = 0x50
  enableClickForwarding = false ## Future flag: forward shift-clicks to the source window.

when not declared(WM_DPICHANGED):
  const WM_DPICHANGED = 0x02E0

let
  menuLabelSelectWindow = L"Select Window… (Ctrl+Shift+P)"
  menuLabelWindowList = L"Target Window"
  menuLabelWindowNone = L"None"
  menuLabelTopMost = L"Always on Top"
  menuLabelBorderless = L"Borderless"
  menuLabelAspectLock = L"Lock Aspect to Source"
  menuLabelCrop = L"Crop…"
  menuLabelMouseCrop = L"Mouse Crop"
  menuLabelResetCrop = L"Reset Crop"
  menuLabelDebugInfo = L"Debug Info"
  menuLabelExit = L"Exit"

  cropDialogClass = L"NimOTRCropDialog"
  cropDialogWidth = 320
  cropDialogHeight = 240

type
  CropDialogState = object
    hwnd: HWND
    editLeft: HWND
    editTop: HWND
    editWidth: HWND
    editHeight: HWND
    applyButton: HWND
    resetButton: HWND

  WindowIdentity = object
    hwnd: HWND
    title: string
    processName: string
    processPath: string

  AppState = object
    cfg: OverlayConfig
    hInstance: HINSTANCE
    hwnd: HWND
    targetHwnd: HWND
    thumbnail: HANDLE
    cropRect: RECT
    targetClientRect: RECT
    hasCrop: bool
    opacity: BYTE
    thumbnailVisible: bool
    thumbnailSuppressed: bool
    promptedForReselect: bool
    validationTimerRunning: bool
    contextMenu: HMENU
    cropDialog: CropDialogState
    clickThroughEnabled: bool
    selectingTarget: bool
    statusText: string
    dragSelecting: bool
    dragStart: POINT
    dragCurrent: POINT
    mouseCropEnabled: bool
    lastDragBlockReason: string
    lastDragPreview: Option[RECT]
    draggingWindow: bool
    dragWindowOffset: POINT
    baseStyle: DWORD
    baseExStyle: DWORD
    windowSelectionMenu: HMENU
    windowMenuItems: seq[HWND]
    selectionOverlay: HWND

var appState: AppState = AppState(
  opacity: 255.BYTE,
  thumbnailVisible: true,
  clickThroughEnabled: false,
  baseStyle: DWORD(styleStandard),
  windowMenuItems: @[]
)

proc eligibilityOptions*(cfg: OverlayConfig): WindowEligibilityOptions =
  WindowEligibilityOptions(includeCloaked: cfg.includeCloaked)

proc currentEligibilityOptions(): WindowEligibilityOptions =
  eligibilityOptions(appState.cfg)

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

proc toPoint(x, y: int32): POINT =
  POINT(x: LONG(x), y: LONG(y))

proc loWord(value: WPARAM): UINT {.inline.} = UINT(value and 0xFFFF)
proc loWordL(value: LPARAM): UINT {.inline.} = UINT(value and 0xFFFF)
proc hiWord(value: WPARAM): UINT {.inline.} = UINT((value shr 16) and 0xFFFF)
proc hiWordL(value: LPARAM): UINT {.inline.} = UINT((value shr 16) and 0xFFFF)

proc shiftHeld(): bool =
  (GetAsyncKeyState(VK_SHIFT) and 0x8000'i16) != 0

proc rectEquals(a, b: RECT): bool =
  a.left == b.left and a.top == b.top and a.right == b.right and a.bottom == b.bottom

proc rectWidth(rect: RECT): int =
  (rect.right - rect.left).int

proc rectHeight(rect: RECT): int =
  (rect.bottom - rect.top).int

proc clampPointToRect(point: POINT; bounds: RECT): POINT =
  POINT(
    x: max(bounds.left, min(point.x, bounds.right)),
    y: max(bounds.top, min(point.y, bounds.bottom))
  )

proc selectionBounds(): Option[RECT] =
  let bounds = overlayDestinationRect().toWinRect
  if rectWidth(bounds) <= 0 or rectHeight(bounds) <= 0:
    return
  some(bounds)

proc selectionPreviewRect(): Option[RECT] =
  if not appState.dragSelecting:
    return
  let bounds = selectionBounds()
  if bounds.isNone:
    return

  let clampedStart = clampPointToRect(appState.dragStart, bounds.get())
  let clampedCurrent = clampPointToRect(appState.dragCurrent, bounds.get())

  some(RECT(
    left: min(clampedStart.x, clampedCurrent.x),
    top: min(clampedStart.y, clampedCurrent.y),
    right: max(clampedStart.x, clampedCurrent.x),
    bottom: max(clampedStart.y, clampedCurrent.y)
  ))

proc cropDialogVisible(): bool =
  appState.cropDialog.hwnd != 0 and IsWindowVisible(appState.cropDialog.hwnd) != 0

proc dragSelectionAllowed(reason: var string): bool =
  if appState.targetHwnd == 0:
    reason = "no_target"
    return false

  if not appState.mouseCropEnabled:
    reason = "mouse_crop_disabled"
    return false

  appState.lastDragBlockReason = ""
  reason = "ok"
  true

proc overlayClientOffset(): POINT =
  var offset = POINT()
  if appState.hwnd == 0:
    return offset

  var windowRect: RECT
  if GetWindowRect(appState.hwnd, addr windowRect) == 0:
    return offset

  var clientOrigin = POINT()
  if ClientToScreen(appState.hwnd, addr clientOrigin) == 0:
    return offset

  POINT(
    x: clientOrigin.x - windowRect.left,
    y: clientOrigin.y - windowRect.top
  )

proc invalidatePreviewRect(rect: Option[RECT]) =
  if appState.selectionOverlay == 0 or rect.isNone:
    return

  var bounds = rect.get()
  let offset = overlayClientOffset()
  discard OffsetRect(addr bounds, offset.x, offset.y)

  discard InvalidateRect(appState.selectionOverlay, addr bounds, TRUE)
  discard RedrawWindow(
    appState.selectionOverlay,
    nil,
    0,
    RDW_INVALIDATE or RDW_UPDATENOW or RDW_NOCHILDREN
  )

proc drawPreviewRect(hdc: HDC; rect: RECT) =
  discard SetBkMode(hdc, TRANSPARENT)
  let pen = CreatePen(PS_SOLID, 3, RGB(0, 120, 215))
  let brush = GetStockObject(NULL_BRUSH)
  let oldPen = SelectObject(hdc, pen)
  let oldBrush = SelectObject(hdc, brush)

  discard Rectangle(hdc, rect.left, rect.top, rect.right, rect.bottom)

  discard SelectObject(hdc, oldPen)
  discard SelectObject(hdc, oldBrush)
  discard DeleteObject(pen)

proc refreshDragPreview() =
  let preview = selectionPreviewRect()
  let previous = appState.lastDragPreview
  appState.lastDragPreview = preview

  if previous.isSome:
    invalidatePreviewRect(previous)

  if preview.isSome and (previous.isNone or not rectEquals(previous.get(), preview.get())):
    invalidatePreviewRect(preview)

proc clearDragSelection(invalidate: bool = true) =
  let lastPreview = appState.lastDragPreview
  appState.dragSelecting = false
  appState.dragStart = POINT()
  appState.dragCurrent = POINT()
  appState.lastDragPreview = none(RECT)
  updateStatusText()
  if invalidate and appState.hwnd != 0:
    invalidatePreviewRect(lastPreview)
    discard InvalidateRect(appState.hwnd, nil, FALSE)

proc cancelDragSelection() =
  if not appState.dragSelecting:
    return
  if GetCapture() == appState.hwnd:
    discard ReleaseCapture()
  clearDragSelection()

proc beginDragSelection(hwnd: HWND; lParam: LPARAM): bool =
  var reason = ""
  if not dragSelectionAllowed(reason):
    appState.lastDragBlockReason = reason
    logEvent("mouse_crop", [("action", %*"begin"), ("result", %*"blocked"), ("reason", %*reason)])
    return false

  let bounds = selectionBounds()
  if bounds.isNone:
    appState.lastDragBlockReason = "no_bounds"
    logEvent("mouse_crop", [("action", %*"begin"), ("result", %*"blocked"), ("reason", %*"no_bounds")])
    return false

  var start = toPoint(int16(loWordL(lParam)), int16(hiWordL(lParam)))
  start = clampPointToRect(start, bounds.get())

  appState.dragSelecting = true
  appState.dragStart = start
  appState.dragCurrent = start
  appState.lastDragBlockReason = ""
  updateStatusText()
  discard SetCapture(hwnd)
  refreshDragPreview()
  logEvent(
    "mouse_crop",
    [
      ("action", %*"begin"),
      ("result", %*"started"),
      ("x", %*int(start.x)),
      ("y", %*int(start.y))
    ]
  )
  true

proc updateDragSelection(lParam: LPARAM): bool =
  if not appState.dragSelecting:
    return false

  let bounds = selectionBounds()
  if bounds.isNone:
    logEvent("mouse_crop", [("action", %*"update"), ("result", %*"blocked"), ("reason", %*"no_bounds")])
    return true

  let nextPoint = clampPointToRect(toPoint(int16(loWordL(lParam)), int16(hiWordL(lParam))), bounds.get())
  if nextPoint.x != appState.dragCurrent.x or nextPoint.y != appState.dragCurrent.y:
    appState.dragCurrent = nextPoint
    refreshDragPreview()
  true

proc finalizeDragSelection(): bool =
  if not appState.dragSelecting:
    return false

  if GetCapture() == appState.hwnd:
    discard ReleaseCapture()

  let preview = selectionPreviewRect()
  clearDragSelection(false)

  if preview.isNone:
    appState.lastDragBlockReason = "no_preview"
    logEvent("mouse_crop", [("action", %*"finalize"), ("result", %*"no_preview")])
    discard InvalidateRect(appState.hwnd, nil, FALSE)
    return true

  let rect = preview.get()
  if rectWidth(rect) < minSelectionSize or rectHeight(rect) < minSelectionSize:
    appState.lastDragBlockReason = "too_small"
    logEvent(
      "mouse_crop",
      [
        ("action", %*"finalize"),
        ("result", %*"too_small"),
        ("width", %*rectWidth(rect)),
        ("height", %*rectHeight(rect))
      ]
    )
    if shiftHeld():
      restoreAndFocusTarget()
    discard InvalidateRect(appState.hwnd, nil, FALSE)
    return true

  setCropFromOverlayRect(rect)
  logEvent(
    "mouse_crop",
    [
      ("action", %*"finalize"),
      ("result", %*"applied"),
      ("left", %*int(rect.left)),
      ("top", %*int(rect.top)),
      ("right", %*int(rect.right)),
      ("bottom", %*int(rect.bottom))
    ]
  )
  discard InvalidateRect(appState.hwnd, nil, FALSE)
  true

proc beginWindowDrag(hwnd: HWND; lParam: LPARAM): bool =
  if appState.mouseCropEnabled or shiftHeld():
    return false

  var windowRect: RECT
  if GetWindowRect(hwnd, addr windowRect) == 0:
    return false

  var cursor = toPoint(int16(loWordL(lParam)), int16(hiWordL(lParam)))
  discard ClientToScreen(hwnd, addr cursor)

  appState.draggingWindow = true
  appState.dragWindowOffset = toPoint(cursor.x - windowRect.left, cursor.y - windowRect.top)
  discard SetCapture(hwnd)
  true

proc updateWindowDrag(): bool =
  if not appState.draggingWindow:
    return false

  var cursor: POINT
  if GetCursorPos(addr cursor) == 0:
    return true

  let nextLeft = cursor.x - appState.dragWindowOffset.x
  let nextTop = cursor.y - appState.dragWindowOffset.y

  discard SetWindowPos(
    appState.hwnd,
    0,
    nextLeft,
    nextTop,
    0,
    0,
    SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE
  )
  true

proc endWindowDrag(): bool =
  if not appState.draggingWindow:
    return false

  appState.draggingWindow = false
  appState.dragWindowOffset = POINT()
  if GetCapture() == appState.hwnd:
    discard ReleaseCapture()
  true

proc saveCropToConfig(rect: RECT; active: bool) =
  let width = (rect.right - rect.left).int
  let height = (rect.bottom - rect.top).int
  if width <= 0 or height <= 0:
    appState.cfg.cropActive = false
    appState.cfg.cropLeft = 0
    appState.cfg.cropTop = 0
    appState.cfg.cropWidth = 0
    appState.cfg.cropHeight = 0
    return

  appState.cfg.cropActive = active
  appState.cfg.cropLeft = rect.left.int
  appState.cfg.cropTop = rect.top.int
  appState.cfg.cropWidth = width
  appState.cfg.cropHeight = height

proc configCropRect(cfg: OverlayConfig): RECT =
  RECT(
    left: LONG(cfg.cropLeft),
    top: LONG(cfg.cropTop),
    right: LONG(cfg.cropLeft + cfg.cropWidth),
    bottom: LONG(cfg.cropTop + cfg.cropHeight)
  )

proc currentCropRect(): RECT =
  if appState.targetHwnd == 0:
    RECT()
  elif appState.hasCrop:
    appState.cropRect
  else:
    clientRect(appState.targetHwnd)

proc setEditText(handle: HWND; value: int) =
  if handle != 0:
    discard SetWindowTextW(handle, ($value).newWideCString)

proc readEditInt(handle: HWND): Option[int] =
  if handle == 0:
    return

  let length = GetWindowTextLengthW(handle)
  if length == 0:
    return none(int)

  var buffer = newWideCString(length + 1)
  discard GetWindowTextW(handle, buffer, length + 1)

  try:
    some(parseInt($buffer))
  except ValueError:
    none(int)

proc updateCropDialogFields() =
  if appState.cropDialog.hwnd == 0:
    return

  let rect = currentCropRect()
  let width = (rect.right - rect.left).int
  let height = (rect.bottom - rect.top).int

  setEditText(appState.cropDialog.editLeft, rect.left.int)
  setEditText(appState.cropDialog.editTop, rect.top.int)
  setEditText(appState.cropDialog.editWidth, width)
  setEditText(appState.cropDialog.editHeight, height)

proc collectWindowIdentity(hwnd: HWND): WindowIdentity =
  let procInfo = processIdentity(hwnd, "")
  WindowIdentity(
    hwnd: hwnd,
    title: windowTitle(hwnd),
    processName: procInfo.name,
    processPath: procInfo.path
  )

proc windowDesktopLabel(hwnd: HWND): string =
  var desktopManager = initVirtualDesktopManager()
  var desktopManagerPtr: ptr VirtualDesktopManager = nil
  if desktopManager.valid:
    desktopManagerPtr = addr desktopManager

  let id = windowDesktopId(desktopManagerPtr, hwnd)
  let label =
    if id.isSome:
      formatDesktopId(id.get())
    else:
      "unknown"

  shutdown(desktopManager)
  label

proc processMatches(cfg: OverlayConfig; winProcess: string; winPath: string): bool =
  if cfg.targetProcessPath.len > 0:
    return cmpIgnoreCase(winPath, cfg.targetProcessPath) == 0
  if cfg.targetProcess.len > 0:
    return cmpIgnoreCase(winProcess, cfg.targetProcess) == 0
  false

proc fullIdentityMatches(win: core.WindowInfo; cfg: OverlayConfig): bool =
  cfg.targetTitle.len > 0 and win.title == cfg.targetTitle and
      processMatches(cfg, win.processName, win.processPath)

proc findWindowByIdentity*(cfg: OverlayConfig; opts: WindowEligibilityOptions): Option[HWND] =
  if cfg.targetTitle.len == 0 and cfg.targetProcess.len == 0 and cfg.targetProcessPath.len == 0:
    return

  var processMatchesOnly: seq[HWND] = @[]
  for win in enumTopLevelWindows(opts):
    if fullIdentityMatches(win, cfg):
      return some(win.hwnd)

    if processMatches(cfg, win.processName, win.processPath):
      processMatchesOnly.add(win.hwnd)

  if processMatchesOnly.len == 1:
    return some(processMatchesOnly[0])

proc validateStoredHandle*(cfg: OverlayConfig; opts: WindowEligibilityOptions): Option[HWND] =
  let stored = HWND(cfg.targetHwnd)
  if stored == 0 or IsWindow(stored) == 0:
    return

  if not shouldIncludeWindow(stored, opts):
    if not shouldIncludeWindow(stored, opts, nil, false):
      return

  let identity = collectWindowIdentity(stored)
  if not processMatches(cfg, identity.processName, identity.processPath):
    return

  if cfg.targetTitle.len > 0 and identity.title != cfg.targetTitle:
    return

  some(stored)

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

proc clearWindowSelectionMenu() =
  if appState.windowSelectionMenu == 0:
    return

  let count = GetMenuItemCount(appState.windowSelectionMenu)
  if count == UINT(-1) or count == 0:
    appState.windowMenuItems.setLen(0)
    return

  for i in countdown(int(count) - 1, 0):
    discard RemoveMenu(appState.windowSelectionMenu, UINT(i), MF_BYPOSITION)

  appState.windowMenuItems.setLen(0)

proc populateWindowSelectionMenu() =
  if appState.contextMenu == 0:
    return

  if appState.windowSelectionMenu == 0:
    appState.windowSelectionMenu = CreatePopupMenu()
    if appState.windowSelectionMenu == 0:
      return

    discard AppendMenuW(
      appState.contextMenu,
      MF_POPUP or menuTopFlags,
      cast[UINT_PTR](appState.windowSelectionMenu),
      menuLabelWindowList
    )

  clearWindowSelectionMenu()
  discard AppendMenuW(appState.windowSelectionMenu, menuTopFlags, idWindowMenuNone, menuLabelWindowNone)

  let windows = enumTopLevelWindows(currentEligibilityOptions())
  var nextId: UINT = idWindowMenuStart
  for win in windows:
    let title = if win.title.len > 0: win.title else: "(No Title)"
    let desktopLabel =
      if win.desktopId.isSome:
        win.desktopId.get()
      else:
        windowDesktopLabel(win.hwnd)
    let label = title & " — " & win.processName & " [" & desktopLabel & "]"

    if AppendMenuW(appState.windowSelectionMenu, menuTopFlags, nextId, label.newWideCString) != 0:
      appState.windowMenuItems.add(win.hwnd)
      inc nextId

proc createContextMenu() =
  if appState.contextMenu != 0:
    return

  let menu = CreatePopupMenu()
  if menu == 0:
    return

  appState.contextMenu = menu
  populateWindowSelectionMenu()
  discard AppendMenuW(menu, menuTopFlags, idSelectWindow, menuLabelSelectWindow)
  discard AppendMenuW(menu, MF_SEPARATOR, 0, nil)
  discard AppendMenuW(menu, menuTopFlags, idToggleTopMost, menuLabelTopMost)
  discard AppendMenuW(menu, menuTopFlags, idToggleBorderless, menuLabelBorderless)
  discard AppendMenuW(menu, menuTopFlags, idToggleAspectLock, menuLabelAspectLock)

  discard AppendMenuW(menu, MF_SEPARATOR, 0, nil)
  discard AppendMenuW(menu, menuTopFlags, idEditCrop, menuLabelCrop)
  discard AppendMenuW(menu, menuTopFlags, idMouseCrop, menuLabelMouseCrop)
  discard AppendMenuW(menu, menuTopFlags, idResetCrop, menuLabelResetCrop)

  discard AppendMenuW(menu, MF_SEPARATOR, 0, nil)
  discard AppendMenuW(menu, menuTopFlags, idShowDebugInfo, menuLabelDebugInfo)
  discard AppendMenuW(menu, MF_SEPARATOR, 0, nil)
  discard AppendMenuW(menu, menuTopFlags, idExit, menuLabelExit)

proc updateContextMenuChecks() =
  if appState.contextMenu == 0:
    return

  let topFlags: UINT = UINT(if appState.cfg.topMost: menuByCommand or menuChecked else: menuByCommand or menuUnchecked)
  discard CheckMenuItem(appState.contextMenu, idToggleTopMost, topFlags)

  let borderFlags: UINT = UINT(if appState.cfg.borderless: menuByCommand or menuChecked else: menuByCommand or menuUnchecked)
  discard CheckMenuItem(appState.contextMenu, idToggleBorderless, borderFlags)

  let aspectFlags: UINT = UINT(if appState.cfg.lockAspect: menuByCommand or menuChecked else: menuByCommand or menuUnchecked)
  discard CheckMenuItem(appState.contextMenu, idToggleAspectLock, aspectFlags)

  let mouseCropFlags: UINT = UINT(if appState.mouseCropEnabled: menuByCommand or menuChecked else: menuByCommand or menuUnchecked)
  discard CheckMenuItem(appState.contextMenu, idMouseCrop, mouseCropFlags)

proc showSelectionOverlay() =
  if appState.selectionOverlay == 0:
    appState.selectionOverlay = createSelectionOverlayWindow()
  if appState.selectionOverlay == 0:
    return

  updateSelectionOverlayBounds()
  discard ShowWindow(appState.selectionOverlay, SW_SHOWNOACTIVATE)

proc hideSelectionOverlay() =
  if appState.selectionOverlay == 0:
    return

  discard ShowWindow(appState.selectionOverlay, SW_HIDE)

proc setMouseCropEnabled(enabled: bool; source: string = "menu") =
  if appState.mouseCropEnabled == enabled:
    return
  appState.mouseCropEnabled = enabled
  if enabled and appState.clickThroughEnabled:
    appState.clickThroughEnabled = false
  if not enabled:
    cancelDragSelection()
    hideSelectionOverlay()
  else:
    showSelectionOverlay()
  updateContextMenuChecks()
  updateStatusText()
  logEvent(
    "mouse_crop",
    [
      ("action", %*"mode_toggle"),
      ("enabled", %*enabled),
      ("source", %*source),
      ("clickThrough", %*appState.clickThroughEnabled)
    ]
  )

proc destroyContextMenu() =
  if appState.contextMenu == 0:
    return
  appState.windowSelectionMenu = 0
  appState.windowMenuItems.setLen(0)
  discard DestroyMenu(appState.contextMenu)
  appState.contextMenu = 0

proc rememberRestorableStyle(hwnd: HWND) =
  let current = DWORD(GetWindowLongPtrW(hwnd, GWL_STYLE))
  if current != 0:
    appState.baseStyle = current

proc captureBaseStyles(hwnd: HWND) =
  if appState.baseExStyle == 0:
    appState.baseExStyle = DWORD(GetWindowLongPtrW(hwnd, GWL_EXSTYLE))

proc visibleStyleFlags(hwnd: HWND): DWORD =
  let current = DWORD(GetWindowLongPtrW(hwnd, GWL_STYLE))
  let isVisible = IsWindowVisible(hwnd) != 0
  let currentVisible = current and WS_VISIBLE
  if isVisible and currentVisible == 0:
    WS_VISIBLE
  else:
    currentVisible

proc currentStyle(hwnd: HWND): DWORD =
  let baseFlags = if appState.baseStyle != 0: appState.baseStyle else: styleStandard
  let style = baseFlags or visibleStyleFlags(hwnd)
  if appState.cfg.borderless:
    style and not WS_CAPTION and not WS_SYSMENU
  else:
    style

proc applyWindowStyles(hwnd: HWND) =
  captureBaseStyles(hwnd)

  let wasVisible = IsWindowVisible(hwnd) != 0
  let style = currentStyle(hwnd)
  discard SetWindowLongPtrW(hwnd, GWL_STYLE, LONG_PTR(style))

  let currentEx = DWORD(GetWindowLongPtrW(hwnd, GWL_EXSTYLE))
  if appState.baseExStyle == 0:
    appState.baseExStyle = currentEx
  let desiredEx = appState.baseExStyle or (currentEx and WS_EX_TRANSPARENT) or exStyleLayered
  discard SetWindowLongPtrW(hwnd, GWL_EXSTYLE, LONG_PTR(desiredEx))

  let insertAfter = if appState.cfg.topMost: HWND_TOPMOST else: HWND_NOTOPMOST
  discard SetWindowPos(
    hwnd,
    insertAfter,
    0,
    0,
    0,
    0,
    SWP_NOMOVE or SWP_NOSIZE or SWP_FRAMECHANGED or SWP_NOACTIVATE
  )

  if wasVisible:
    discard ShowWindow(hwnd, SW_SHOWNOACTIVATE)
  updateSelectionOverlayBounds()

proc setClientSize(hwnd: HWND; clientWidth, clientHeight: int) =
  var rect = RECT(left: 0, top: 0, right: LONG(clientWidth), bottom: LONG(clientHeight))
  let style = DWORD(GetWindowLongPtrW(hwnd, GWL_STYLE))
  let exStyle = DWORD(GetWindowLongPtrW(hwnd, GWL_EXSTYLE))

  if AdjustWindowRectEx(addr rect, style, FALSE, exStyle) != 0:
    let windowWidth = rect.right - rect.left
    let windowHeight = rect.bottom - rect.top
    discard SetWindowPos(
      hwnd,
      0,
      0,
      0,
      windowWidth,
      windowHeight,
      SWP_NOMOVE or SWP_NOZORDER or SWP_NOACTIVATE
    )
  else:
    discard SetWindowPos(
      hwnd,
      0,
      0,
      0,
      int32(clientWidth),
      int32(clientHeight),
      SWP_NOMOVE or SWP_NOZORDER or SWP_NOACTIVATE
    )

proc handleSize(lParam: LPARAM) =
  appState.cfg.width = int(loWordL(lParam))
  appState.cfg.height = int(hiWordL(lParam))
  updateSelectionOverlayBounds()

proc handleMove(lParam: LPARAM) =
  appState.cfg.x = int(int16(loWordL(lParam)))
  appState.cfg.y = int(int16(hiWordL(lParam)))
  updateSelectionOverlayBounds()

proc updateSelectionOverlayBounds() =
  if appState.selectionOverlay == 0 or appState.hwnd == 0:
    return

  var windowRect: RECT
  if GetWindowRect(appState.hwnd, addr windowRect) == 0:
    return

  let width = windowRect.right - windowRect.left
  let height = windowRect.bottom - windowRect.top

  discard SetWindowPos(
    appState.selectionOverlay,
    appState.hwnd,
    windowRect.left,
    windowRect.top,
    width,
    height,
    SWP_NOACTIVATE
  )

proc overlayDestinationRect(): IntRect =
  let client = clientRect(appState.hwnd).toIntRect
  let crop = appState.cropRect.toIntRect
  if width(crop) <= 0 or height(crop) <= 0:
    return client
  aspectFitRect(client, (width: width(crop), height: height(crop)))

proc clientRect(hwnd: HWND): RECT =
  var rect: RECT
  if GetClientRect(hwnd, addr rect) != 0:
    result = rect

proc unregisterThumbnail() =
  if appState.thumbnail != 0:
    discard DwmUnregisterThumbnail(appState.thumbnail)
    appState.thumbnail = 0

proc invalidateStatus() =
  discard InvalidateRect(appState.hwnd, nil, true)

proc updateThumbnailProperties() =
  if appState.thumbnail == 0:
    return
  let destRect = overlayDestinationRect().toWinRect
  var props: DWM_THUMBNAIL_PROPERTIES
  props.dwFlags = DWM_TNP_VISIBLE or DWM_TNP_OPACITY or DWM_TNP_RECTDESTINATION or
      DWM_TNP_RECTSOURCE or DWM_TNP_SOURCECLIENTAREAONLY
  props.rcDestination = destRect
  props.rcSource = appState.cropRect
  props.opacity = appState.opacity
  props.fVisible = (if appState.thumbnailVisible and not appState.thumbnailSuppressed: 1 else: 0)
  props.fSourceClientAreaOnly = 1
  discard DwmUpdateThumbnailProperties(appState.thumbnail, addr props)

proc currentTargetAspect(): Option[float] =
  let sourceRect = currentCropRect()
  let sourceWidth = rectWidth(sourceRect)
  let sourceHeight = rectHeight(sourceRect)
  if sourceWidth <= 0 or sourceHeight <= 0:
    return
  some(sourceWidth.float / sourceHeight.float)

proc applyAspectLock() =
  if not appState.cfg.lockAspect or appState.hwnd == 0:
    return

  let targetAspectOpt = currentTargetAspect()
  if targetAspectOpt.isNone:
    return

  let targetAspect = targetAspectOpt.get()
  let client = clientRect(appState.hwnd)
  let clientWidth = rectWidth(client)
  let clientHeight = rectHeight(client)
  if clientWidth <= 0 or clientHeight <= 0:
    return

  let widthFromHeight = int(round(clientHeight.float * targetAspect))
  let heightFromWidth = int(round(clientWidth.float / targetAspect))
  var newWidth = clientWidth
  var newHeight = clientHeight

  let widthDelta = abs(widthFromHeight - clientWidth)
  let heightDelta = abs(heightFromWidth - clientHeight)
  if widthDelta <= heightDelta:
    newWidth = widthFromHeight
  else:
    newHeight = heightFromWidth

  if newWidth <= 0 or newHeight <= 0:
    return

  if newWidth == clientWidth and newHeight == clientHeight:
    return

  setClientSize(appState.hwnd, newWidth, newHeight)
  updateThumbnailProperties()

proc adjustSizingRectForAspect(rect: var RECT; edge: UINT) =
  let targetAspectOpt = currentTargetAspect()
  if targetAspectOpt.isNone:
    return

  let targetAspect = targetAspectOpt.get()
  let width = rectWidth(rect)
  let height = rectHeight(rect)
  if width <= 0 or height <= 0:
    return

  let widthFromHeight = int(round(height.float * targetAspect))
  let heightFromWidth = int(round(width.float / targetAspect))

  var newWidth = width
  var newHeight = height
  let widthDelta = abs(widthFromHeight - width)
  let heightDelta = abs(heightFromWidth - height)

  if widthDelta <= heightDelta:
    newWidth = widthFromHeight
  else:
    newHeight = heightFromWidth

  case edge
  of WMSZ_LEFT:
    rect.left = rect.right - LONG(newWidth)
    rect.bottom = rect.top + LONG(newHeight)
  of WMSZ_RIGHT:
    rect.right = rect.left + LONG(newWidth)
    rect.bottom = rect.top + LONG(newHeight)
  of WMSZ_TOP:
    rect.top = rect.bottom - LONG(newHeight)
    rect.right = rect.left + LONG(newWidth)
  of WMSZ_BOTTOM:
    rect.bottom = rect.top + LONG(newHeight)
    rect.right = rect.left + LONG(newWidth)
  of WMSZ_TOPLEFT:
    rect.left = rect.right - LONG(newWidth)
    rect.top = rect.bottom - LONG(newHeight)
  of WMSZ_TOPRIGHT:
    rect.right = rect.left + LONG(newWidth)
    rect.top = rect.bottom - LONG(newHeight)
  of WMSZ_BOTTOMLEFT:
    rect.left = rect.right - LONG(newWidth)
    rect.bottom = rect.top + LONG(newHeight)
  of WMSZ_BOTTOMRIGHT:
    rect.right = rect.left + LONG(newWidth)
    rect.bottom = rect.top + LONG(newHeight)
  else:
    discard

proc mouseOverOverlay(lParam: LPARAM): bool =
  ## WM_MOUSEWHEEL provides screen coordinates in lParam; ensure the topmost
  ## window at that location is our overlay before acting on the scroll.
  var point = POINT(
    x: LONG(int16(loWordL(lParam))),
    y: LONG(int16(hiWordL(lParam)))
  )
  WindowFromPoint(point) == appState.hwnd

proc adjustOverlaySizeFromScroll(wheelDelta: int16) =
  if wheelDelta == 0:
    return

  if appState.targetHwnd == 0:
    return

  let crop = currentCropRect().toIntRect
  let cropWidth = width(crop)
  let cropHeight = height(crop)
  if cropWidth <= 0 or cropHeight <= 0:
    return

  let client = clientRect(appState.hwnd).toIntRect
  let clientWidth = width(client)
  let clientHeight = height(client)
  if clientWidth <= 0 or clientHeight <= 0:
    return

  let currentScale = min(clientWidth.float / cropWidth.float, clientHeight.float / cropHeight.float)
  if currentScale <= 0:
    return

  let scaleStep = 1.1
  let newScale = max(currentScale * (if wheelDelta > 0: scaleStep else: 1.0 / scaleStep), 0.05)
  let aspect = cropWidth.float / cropHeight.float

  var newClientWidth = int(round(cropWidth.float * newScale))
  var newClientHeight = int(round(cropHeight.float * newScale))

  let minClientSize = 100
  if newClientWidth < minClientSize:
    newClientWidth = minClientSize
    newClientHeight = int(round(minClientSize.float / aspect))

  if newClientHeight < minClientSize:
    newClientHeight = minClientSize
    newClientWidth = int(round(minClientSize.float * aspect))

  setClientSize(appState.hwnd, newClientWidth, newClientHeight)

proc applyWindowOpacity() =
  if appState.hwnd == 0:
    return
  discard SetLayeredWindowAttributes(appState.hwnd, 0, appState.opacity, LWA_ALPHA)

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
    L"The mirrored window is no longer available. Please reselect a source window.",
    overlayTitle,
    MB_OK or MB_ICONINFORMATION
  )

proc computeStatusText(): string =
  let selectAction = "Right-click → Select Window… (Ctrl+Shift+P)"
  if appState.targetHwnd == 0:
    if appState.promptedForReselect:
      return "Source window closed. " & selectAction
    return "Right-click here to start… (Ctrl+Shift+P)"

  if appState.thumbnailSuppressed:
    return "Source is minimized or hidden. Restore it or " & selectAction

  var status = ""
  if appState.mouseCropEnabled or cropDialogVisible():
    let dragState = if appState.dragSelecting: "Dragging selection…" else: "Mouse crop enabled. Drag to select a region."
    let clickState = if appState.clickThroughEnabled: "Click-through temporarily ignored while cropping." else: "Click-through off."
    status = dragState & " " & clickState & " ESC cancels."
  elif appState.targetHwnd != 0:
    status = "Mouse crop off. Right-click → Mouse Crop to drag a selection."
  status

proc rectDescription(rect: RECT): string =
  "L:" & $rect.left & " T:" & $rect.top & " R:" & $rect.right & " B:" & $rect.bottom

proc boolLabel(flag: bool): string =
  if flag:
    "Yes"
  else:
    "No"

proc showDebugInfo() =
  var lines: seq[string] = @[]
  if appState.targetHwnd == 0:
    lines.add("Target: None")
  else:
    let identity = collectWindowIdentity(appState.targetHwnd)
    lines.add("HWND: 0x" & toHex(int(identity.hwnd), 8))
    lines.add("Title: " & identity.title)
    lines.add("Process: " & identity.processName)
    lines.add("Process Path: " & identity.processPath)

  lines.add("Thumbnail Registered: " & boolLabel(appState.thumbnail != 0))
  lines.add(
    "Thumbnail Visible: " & boolLabel(appState.thumbnailVisible and not appState.thumbnailSuppressed)
  )
  lines.add("Thumbnail Suppressed: " & boolLabel(appState.thumbnailSuppressed))
  let crop = currentCropRect()
  lines.add("Crop: " & rectDescription(crop))
  lines.add("Opacity: " & $int(appState.opacity))
  lines.add("Mouse Crop Enabled: " & boolLabel(appState.mouseCropEnabled))
  lines.add("Drag Selecting: " & boolLabel(appState.dragSelecting))
  lines.add("Click-through Enabled: " & boolLabel(appState.clickThroughEnabled))
  lines.add("Drag Block Reason: " & (if appState.lastDragBlockReason.len > 0: appState.lastDragBlockReason else: "None"))
  lines.add("Crop Dialog Visible: " & boolLabel(cropDialogVisible()))
  let captureOwner = GetCapture()
  lines.add("Has Capture: " & boolLabel(captureOwner == appState.hwnd) &
      " (owner: 0x" & toHex(int(captureOwner), 8) & ")")
  let foreground = GetForegroundWindow()
  lines.add(
    "Foreground: 0x" & toHex(int(foreground), 8) &
    " (overlay: " & boolLabel(foreground == appState.hwnd) &
    ", crop dialog: " & boolLabel(foreground == appState.cropDialog.hwnd) & ")"
  )
  if appState.dragSelecting:
    lines.add(
      "Drag Start: " & $appState.dragStart.x & "," & $appState.dragStart.y &
      " Current: " & $appState.dragCurrent.x & "," & $appState.dragCurrent.y
    )

  discard MessageBoxW(
    appState.hwnd,
    lines.join("\n").newWideCString,
    L"Debug Info",
    MB_OK or MB_ICONINFORMATION
  )

proc updateStatusText() =
  let nextStatus = computeStatusText()
  if nextStatus != appState.statusText:
    appState.statusText = nextStatus
    invalidateStatus()

proc drawSelectionPreview(hdc: HDC; offset: POINT = POINT()) =
  let preview = selectionPreviewRect()
  if preview.isNone:
    return

  var rect = preview.get()
  discard OffsetRect(addr rect, offset.x, offset.y)
  drawPreviewRect(hdc, rect)

proc paintStatus(hwnd: HWND) =
  var ps: PAINTSTRUCT
  let hdc = BeginPaint(hwnd, addr ps)
  defer:
    discard EndPaint(hwnd, addr ps)

  let status = appState.statusText
  var rect = clientRect(hwnd)
  discard FillRect(hdc, addr rect, cast[HBRUSH](COLOR_WINDOW + 1))

  if status.len > 0:
    discard SetBkMode(hdc, TRANSPARENT)
    discard SetTextColor(hdc, GetSysColor(COLOR_WINDOWTEXT))
    discard DrawTextW(
      hdc,
      status.newWideCString,
      -1,
      addr rect,
      DT_CENTER or DT_VCENTER or DT_WORDBREAK or DT_NOPREFIX
    )

proc createSelectionOverlayWindow(): HWND =
  var wc: WNDCLASSEXW
  wc.cbSize = sizeof(WNDCLASSEXW).UINT
  wc.style = CS_HREDRAW or CS_VREDRAW
  wc.lpfnWndProc = selectionOverlayWndProc
  wc.hInstance = appState.hInstance
  wc.hCursor = LoadCursorW(0, IDC_ARROW)
  wc.hbrBackground = 0
  wc.lpszClassName = selectionOverlayClassName

  if RegisterClassExW(wc) == 0 and GetLastError() != ERROR_CLASS_ALREADY_EXISTS:
    return 0

  var windowRect: RECT
  discard GetWindowRect(appState.hwnd, addr windowRect)

  result = CreateWindowExW(
    WS_EX_LAYERED or WS_EX_TRANSPARENT or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW,
    selectionOverlayClassName,
    nil,
    WS_POPUP,
    windowRect.left,
    windowRect.top,
    windowRect.right - windowRect.left,
    windowRect.bottom - windowRect.top,
    appState.hwnd,
    0,
    appState.hInstance,
    nil
  )

  if result != 0:
    discard SetLayeredWindowAttributes(result, selectionOverlayColorKey, 255, LWA_COLORKEY)
    discard ShowWindow(result, SW_HIDE)

proc selectionOverlayWndProc(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.} =
  case msg
  of WM_NCHITTEST:
    return HTTRANSPARENT
  of WM_ERASEBKGND:
    return 1
  of WM_PAINT:
    var ps: PAINTSTRUCT
    let hdc = BeginPaint(hwnd, addr ps)
    defer:
      discard EndPaint(hwnd, addr ps)

    var rect = clientRect(hwnd)
    let bgBrush = CreateSolidBrush(selectionOverlayColorKey)
    discard FillRect(hdc, addr rect, bgBrush)
    discard DeleteObject(bgBrush)

    drawSelectionPreview(hdc, overlayClientOffset())
    return 0
  else:
    discard
  result = DefWindowProcW(hwnd, msg, wParam, lParam)

proc detachTarget(promptUser: bool) =
  if appState.thumbnail != 0:
    unregisterThumbnail()
  appState.targetHwnd = 0
  appState.targetClientRect = RECT()
  appState.hasCrop = false
  appState.thumbnailSuppressed = false
  stopValidationTimer()
  if promptUser:
    promptForReselect()
  updateStatusText()
  updateCropDialogFields()

proc refreshCropForSourceResize(newClient: RECT)

proc validateTargetState() =
  let target = appState.targetHwnd
  if target == 0:
    return

  if IsWindow(target) == 0:
    logEvent("validation", [("hwnd", %*int(target)), ("exists", %*false)])
    detachTarget(true)
    return

  let minimized = IsIconic(target) != 0
  let visible = IsWindowVisible(target) != 0
  let shouldSuppress = minimized or not visible
  let validThumbnail = thumbnailHandleValid()
  logEvent(
    "validation",
    [
      ("hwnd", %*int(target)),
      ("exists", %*true),
      ("thumbnailValid", %*validThumbnail),
      ("minimized", %*minimized),
      ("visible", %*visible),
      ("suppressed", %*shouldSuppress)
    ]
  )

  if not thumbnailHandleValid():
    registerThumbnail(target)

  if appState.thumbnailSuppressed != shouldSuppress:
    appState.thumbnailSuppressed = shouldSuppress
    updateThumbnailProperties()
    updateStatusText()
    logEvent(
      "thumbnail_suppression",
      [
        ("hwnd", %*int(target)),
        ("suppressed", %*shouldSuppress),
        ("reason", %*(if minimized: "minimized" else: "hidden"))
      ]
    )

  if not shouldSuppress and appState.thumbnail == 0:
    registerThumbnail(target)
  elif not shouldSuppress:
    updateThumbnailProperties()

  if not shouldSuppress:
    refreshCropForSourceResize(clientRect(target))

proc setDefaultCrop(target: HWND) =
  let rect = clientRect(target)
  appState.cropRect = rect
  appState.targetClientRect = rect
  appState.hasCrop = true
  saveCropToConfig(rect, false)

proc applySavedCrop(target: HWND) =
  let sourceRect = clientRect(target)
  appState.targetClientRect = sourceRect
  if not appState.cfg.cropActive:
    setDefaultCrop(target)
    updateCropDialogFields()
    return
  let rectFromConfig = configCropRect(appState.cfg)
  let clamped = clampRect(rectFromConfig.toIntRect, sourceRect.toIntRect)
  if width(clamped) == 0 or height(clamped) == 0:
    setDefaultCrop(target)
  else:
    appState.cropRect = clamped.toWinRect
    appState.hasCrop = true
  updateCropDialogFields()

proc registerThumbnail(target: HWND) =
  unregisterThumbnail()
  appState.targetHwnd = 0
  if target == 0:
    logEvent("thumbnail_registration", [("status", %*"cleared")])
    return

  var thumbnailId: HANDLE
  if DwmRegisterThumbnail(appState.hwnd, target, addr thumbnailId) == 0:
    appState.thumbnail = thumbnailId
    appState.targetHwnd = target
    appState.targetClientRect = clientRect(target)
    let identity = collectWindowIdentity(target)
    appState.cfg.targetHwnd = cast[int](identity.hwnd)
    appState.cfg.targetTitle = identity.title
    appState.cfg.targetProcess = identity.processName
    appState.cfg.targetProcessPath = identity.processPath
    if not appState.hasCrop:
      applySavedCrop(target)
    updateThumbnailProperties()
    applyAspectLock()
    startValidationTimer()
    logEvent(
      "thumbnail_registration",
      [
        ("status", %*"registered"),
        ("hwnd", %*int(identity.hwnd)),
        ("title", %*identity.title),
        ("process", %*identity.processName),
        ("processPath", %*identity.processPath)
      ]
    )
  else:
    logEvent(
      "thumbnail_registration",
      [
        ("status", %*"failed"),
        ("hwnd", %*int(target))
      ]
    )
  updateStatusText()

proc mapOverlayToSource(overlayRect: RECT): RECT =
  let destRect = overlayDestinationRect()
  let sourceRect = currentCropRect().toIntRect
  mapRectToSource(overlayRect.toIntRect, destRect, sourceRect).toWinRect

proc refreshCropForSourceResize(newClient: RECT) =
  if appState.targetHwnd == 0 or rectEquals(newClient, appState.targetClientRect):
    return

  appState.targetClientRect = newClient
  let sourceRect = newClient.toIntRect
  let currentCrop = appState.cropRect.toIntRect
  let clamped = clampRect(currentCrop, sourceRect)

  if not appState.cfg.cropActive or width(clamped) == 0 or height(clamped) == 0:
    appState.cropRect = newClient
    appState.hasCrop = true
    saveCropToConfig(newClient, false)
  else:
    appState.cropRect = clamped.toWinRect
    appState.hasCrop = true
    saveCropToConfig(appState.cropRect, true)

  updateThumbnailProperties()
  applyAspectLock()
  updateCropDialogFields()

var cropDialogClassRegistered = false

proc registerCropDialogClass(): bool =
  if cropDialogClassRegistered:
    return true

  var wc: WNDCLASSEXW
  wc.cbSize = sizeof(WNDCLASSEXW).UINT
  wc.style = CS_HREDRAW or CS_VREDRAW
  wc.lpfnWndProc = cropDialogWndProc
  wc.hInstance = appState.hInstance
  wc.hCursor = LoadCursorW(0, IDC_ARROW)
  wc.hbrBackground = cast[HBRUSH](COLOR_WINDOW + 1)
  wc.lpszClassName = cropDialogClass

  cropDialogClassRegistered = RegisterClassExW(wc) != 0
  cropDialogClassRegistered

proc setControlFont(handle: HWND) =
  if handle != 0:
    let font = GetStockObject(DEFAULT_GUI_FONT)
    discard SendMessageW(handle, WM_SETFONT, WPARAM(font), LPARAM(1))

proc initCropDialogControls(hwnd: HWND) =
  appState.cropDialog.hwnd = hwnd

  let labelX: int32 = 16
  let editX: int32 = 90
  let editWidth: int32 = 150
  let rowHeight: int32 = 32

  let labels = ["X:", "Y:", "Width:", "Height:"]
  let editIds = [idCropLeft, idCropTop, idCropWidth, idCropHeight]

  var y: int32 = 16
  for i, label in labels:
    discard CreateWindowExW(
      0,
      L"STATIC",
      label.newWideCString,
      WS_CHILD or WS_VISIBLE,
      labelX,
      y,
      60,
      20,
      hwnd,
      0,
      appState.hInstance,
      nil
    )

    let edit = CreateWindowExW(
      WS_EX_CLIENTEDGE,
      L"EDIT",
      nil,
      WS_CHILD or WS_VISIBLE or WS_TABSTOP or ES_NUMBER,
      editX,
      y - 4,
      editWidth,
      24,
      hwnd,
      cast[HMENU](editIds[i]),
      appState.hInstance,
      nil
    )

    case editIds[i]
    of idCropLeft:
      appState.cropDialog.editLeft = edit
    of idCropTop:
      appState.cropDialog.editTop = edit
    of idCropWidth:
      appState.cropDialog.editWidth = edit
    else:
      appState.cropDialog.editHeight = edit

    y += rowHeight
  setControlFont(appState.cropDialog.editLeft)
  setControlFont(appState.cropDialog.editTop)
  setControlFont(appState.cropDialog.editWidth)
  setControlFont(appState.cropDialog.editHeight)

  let applyBtn = CreateWindowExW(
    0,
    L"BUTTON",
    L"Apply",
    WS_CHILD or WS_VISIBLE or WS_TABSTOP,
    labelX,
    y + 8,
    100,
    28,
    hwnd,
    cast[HMENU](idCropApply),
    appState.hInstance,
    nil
  )
  setControlFont(applyBtn)
  appState.cropDialog.applyButton = applyBtn
  discard SendMessageW(appState.cropDialog.applyButton, BM_SETSTYLE, WPARAM(BS_DEFPUSHBUTTON), LPARAM(TRUE))

  let resetBtn = CreateWindowExW(
    0,
    L"BUTTON",
    L"Reset",
    WS_CHILD or WS_VISIBLE or WS_TABSTOP,
    editX,
    y + 8,
    100,
    28,
    hwnd,
    cast[HMENU](idCropResetButton),
    appState.hInstance,
    nil
  )
  setControlFont(resetBtn)
  appState.cropDialog.resetButton = resetBtn
  discard SendMessageW(appState.cropDialog.resetButton, BM_SETSTYLE, WPARAM(BS_PUSHBUTTON), LPARAM(TRUE))

proc showCropValidation(message: string) =
  discard MessageBoxW(
    if appState.cropDialog.hwnd != 0: appState.cropDialog.hwnd else: appState.hwnd,
    message.newWideCString,
    L"Crop",
    MB_OK or MB_ICONINFORMATION
  )

proc applyCropFromDialog() =
  if appState.targetHwnd == 0:
    showCropValidation("Select a window before applying a crop.")
    return

  let left = readEditInt(appState.cropDialog.editLeft)
  let top = readEditInt(appState.cropDialog.editTop)
  let width = readEditInt(appState.cropDialog.editWidth)
  let height = readEditInt(appState.cropDialog.editHeight)

  if left.isNone or top.isNone or width.isNone or height.isNone:
    showCropValidation("Enter numeric values for all crop fields.")
    return

  if width.get <= 0 or height.get <= 0:
    showCropValidation("Width and height must be greater than zero.")
    return

  let rect = RECT(
    left: LONG(left.get),
    top: LONG(top.get),
    right: LONG(left.get + width.get),
    bottom: LONG(top.get + height.get)
  )
  setCrop(rect)
  updateCropDialogFields()

proc resetCropFromDialog() =
  if appState.targetHwnd == 0:
    showCropValidation("Select a window before resetting the crop.")
    return
  resetCrop()
  updateCropDialogFields()

proc cropDialogWndProc(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.} =
  case msg
  of WM_CREATE:
    initCropDialogControls(hwnd)
    updateCropDialogFields()
    return 0
  of WM_COMMAND:
    case loWord(wParam)
    of idCropApply:
      applyCropFromDialog()
    of idCropResetButton:
      resetCropFromDialog()
    else:
      discard
    return 0
  of WM_KEYDOWN:
    if int32(wParam) == VK_RETURN:
      applyCropFromDialog()
      return 0
    elif int32(wParam) == VK_ESCAPE:
      ## Allow closing the crop dialog with Escape to run standard cleanup.
      discard DestroyWindow(hwnd)
      return 0
  of WM_CLOSE:
    discard DestroyWindow(hwnd)
    return 0
  of WM_DESTROY:
    if appState.cropDialog.hwnd == hwnd:
      appState.cropDialog = CropDialogState()
      updateStatusText()
    return 0
  else:
    discard
  result = DefWindowProcW(hwnd, msg, wParam, lParam)

proc showCropDialog() =
  if not registerCropDialogClass():
    return

  if appState.cropDialog.hwnd != 0:
    discard SetForegroundWindow(appState.cropDialog.hwnd)
    updateCropDialogFields()
    return

  let hwnd = CreateWindowExW(
    WS_EX_TOOLWINDOW or WS_EX_CONTROLPARENT,
    cropDialogClass,
    L"Crop",
    WS_OVERLAPPED or WS_CAPTION or WS_SYSMENU,
    CW_USEDEFAULT,
    CW_USEDEFAULT,
    int32(cropDialogWidth),
    int32(cropDialogHeight),
    appState.hwnd,
    0,
    appState.hInstance,
    nil
  )

  if hwnd != 0:
    discard ShowWindow(hwnd, SW_SHOWNORMAL)
    discard UpdateWindow(hwnd)
    discard SetForegroundWindow(hwnd)

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
      appState.cfg.targetProcessPath = identity.processPath
      logEvent(
        "selection",
        [
          ("hwnd", %*int(identity.hwnd)),
          ("title", %*identity.title),
          ("process", %*identity.processName),
          ("processPath", %*identity.processPath)
        ]
      )
    updateStatusText()
    updateCropDialogFields()

## Applies a crop rectangle using source window coordinates.
proc setCrop*(rect: RECT) =
  if appState.targetHwnd == 0:
    return
  let sourceRect = clientRect(appState.targetHwnd)
  let clamped = clampRect(rect.toIntRect, sourceRect.toIntRect)
  if width(clamped) == 0 or height(clamped) == 0:
    setDefaultCrop(appState.targetHwnd)
    updateCropDialogFields()
    return
  appState.cropRect = clamped.toWinRect
  appState.hasCrop = true
  saveCropToConfig(clamped.toWinRect, true)
  updateThumbnailProperties()
  updateCropDialogFields()

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
  updateCropDialogFields()

## Adjusts DWM thumbnail opacity for the overlay.
proc setOpacity*(value: BYTE) =
  appState.opacity = value
  appState.cfg.opacity = int(value)
  updateThumbnailProperties()
  applyWindowOpacity()

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
  updateSelectionOverlayBounds()

proc registerHotkeys() =
  discard RegisterHotKey(appState.hwnd, hotkeySelectWindowId, MOD_CONTROL or MOD_SHIFT, VK_P)

proc unregisterHotkeys() =
  discard UnregisterHotKey(appState.hwnd, hotkeySelectWindowId)

proc selectTarget() =
  if appState.selectingTarget:
    return
  appState.selectingTarget = true
  let previousClickThrough = appState.clickThroughEnabled
  appState.clickThroughEnabled = false
  defer:
    appState.clickThroughEnabled = previousClickThrough
    appState.selectingTarget = false

  let selection = clickToPickWindow(currentEligibilityOptions())
  if selection.isSome:
    let win = selection.get()
    logEvent("selection", [
      ("status", %*"chosen"),
      ("title", %*win.title),
      ("process", %*win.processName),
      ("virtual_desktop", %*windowDesktopLabel(win.hwnd))
    ])
    setTargetWindow(win.hwnd)
  else:
    logEvent("selection", [("status", %*"cancelled")])

proc handleCommand(hwnd: HWND, wParam: WPARAM) =
  let commandId = loWord(wParam)
  case commandId
  of idSelectWindow:
    selectTarget()
  of idToggleTopMost:
    appState.cfg.topMost = not appState.cfg.topMost
    applyWindowStyles(hwnd)
  of idToggleBorderless:
    if not appState.cfg.borderless:
      rememberRestorableStyle(hwnd)
    appState.cfg.borderless = not appState.cfg.borderless
    applyWindowStyles(hwnd)
  of idToggleAspectLock:
    appState.cfg.lockAspect = not appState.cfg.lockAspect
    applyAspectLock()
  of idEditCrop:
    setMouseCropEnabled(true, "crop_dialog_command")
    showCropDialog()
  of idMouseCrop:
    setMouseCropEnabled(not appState.mouseCropEnabled)
    if appState.mouseCropEnabled:
      showCropDialog()
  of idResetCrop:
    resetCropFromDialog()
  of idShowDebugInfo:
    showDebugInfo()
  of idExit:
    discard PostMessageW(hwnd, WM_CLOSE, 0, 0)
  else:
    if commandId == idWindowMenuNone:
      setTargetWindow(0)
    elif int(commandId) >= idWindowMenuStart:
      let index = int(commandId) - idWindowMenuStart
      if index >= 0 and index < appState.windowMenuItems.len:
        setTargetWindow(appState.windowMenuItems[index])

proc handleContextMenu(hwnd: HWND, lParam: LPARAM) =
  if appState.dragSelecting:
    cancelDragSelection()

  createContextMenu()
  populateWindowSelectionMenu()
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
  of WM_SIZING:
    if appState.cfg.lockAspect and lParam != 0:
      let rectPtr = cast[ptr RECT](lParam)
      if rectPtr != nil:
        adjustSizingRectForAspect(rectPtr[], UINT(wParam))
        return TRUE
    discard
  of WM_SIZE:
    handleSize(lParam)
    updateThumbnailProperties()
    return 0
  of WM_MOVE:
    handleMove(lParam)
    return 0
  of WM_MOUSEWHEEL:
    if mouseOverOverlay(lParam):
      adjustOverlaySizeFromScroll(int16(hiWord(wParam)))
      return 0
  of WM_DPICHANGED:
    handleDpiChanged(hwnd, lParam)
    return 0
  of WM_COMMAND:
    handleCommand(hwnd, wParam)
    return 0
  of WM_HOTKEY:
    if int32(wParam) == hotkeySelectWindowId:
      selectTarget()
      return 0
  of WM_CONTEXTMENU:
    handleContextMenu(hwnd, lParam)
    return 0
  of WM_RBUTTONDOWN:
    if shiftHeld():
      if appState.mouseCropEnabled:
        logEvent("mouse_crop", [("action", %*"clickthrough_toggle"), ("result", %*"ignored_in_crop_mode")])
      else:
        appState.clickThroughEnabled = not appState.clickThroughEnabled
        updateStatusText()
      return 0
  of WM_PAINT:
    paintStatus(hwnd)
    return 0
  of WM_MOUSEMOVE:
    if updateDragSelection(lParam):
      return 0
    if updateWindowDrag():
      return 0
  of WM_NCHITTEST:
    let hit = DefWindowProcW(hwnd, msg, wParam, lParam)
    if appState.clickThroughEnabled and not appState.mouseCropEnabled and not appState.dragSelecting and not shiftHeld() and hit == HTCLIENT:
      return HTTRANSPARENT
    return hit
  of WM_LBUTTONDOWN:
    if beginDragSelection(hwnd, lParam):
      return 0
    if shiftHeld() and not appState.mouseCropEnabled:
      restoreAndFocusTarget()
    elif not appState.mouseCropEnabled and beginWindowDrag(hwnd, lParam):
      return 0
    return DefWindowProcW(hwnd, msg, wParam, lParam)
  of WM_LBUTTONUP:
    if finalizeDragSelection():
      return 0
    if endWindowDrag():
      return 0
  of WM_TIMER:
    if wParam == validationTimerId:
      validateTargetState()
      return 0
  of WM_KEYDOWN:
    if int32(wParam) == VK_ESCAPE:
      cancelDragSelection()
      return 0
  of WM_DESTROY:
    stopValidationTimer()
    unregisterThumbnail()
    unregisterHotkeys()
    destroyContextMenu()
    if appState.selectionOverlay != 0:
      discard DestroyWindow(appState.selectionOverlay)
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
  let xpos = if useDefault: CW_USEDEFAULT else: int32(appState.cfg.x)
  let ypos = if useDefault: CW_USEDEFAULT else: int32(appState.cfg.y)

  result = CreateWindowExW(
    exStyleLayered,
    className,
    overlayTitle,
    currentStyle(0),
    xpos,
    ypos,
    int32(appState.cfg.width),
    int32(appState.cfg.height),
    0,
    0,
    hInstance,
    nil
  )

proc initOverlay*(cfg: OverlayConfig): bool =
  appState.cfg = cfg
  initLogger(appState.cfg)
  let storedOpacity = max(min(appState.cfg.opacity, 255), 0)
  appState.opacity = BYTE(storedOpacity)
  appState.hInstance = GetModuleHandleW(nil)
  appState.hwnd = createWindow(appState.hInstance)
  if appState.hwnd == 0:
    return false

  appState.selectionOverlay = createSelectionOverlayWindow()
  updateSelectionOverlayBounds()

  applyWindowStyles(appState.hwnd)
  applyWindowOpacity()
  registerHotkeys()

  discard ShowWindow(appState.hwnd, SW_SHOWNORMAL)
  discard UpdateWindow(appState.hwnd)
  updateStatusText()

  if appState.mouseCropEnabled:
    showSelectionOverlay()

  result = true

proc runOverlayLoop*() =
  if appState.hwnd == 0:
    return

  var msg: MSG
  while GetMessageW(addr msg, 0, 0, 0) != 0:
    if appState.cropDialog.hwnd != 0 and IsDialogMessageW(appState.cropDialog.hwnd, addr msg) != 0:
      continue
    discard TranslateMessage(addr msg)
    discard DispatchMessageW(addr msg)
