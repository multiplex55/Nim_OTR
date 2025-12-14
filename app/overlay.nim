## Overlay window entry point that manages DWM thumbnails and crop state.
import std/[options, os, strutils, widestrs]
import winim/lean
import ../util/geometry
import ../picker/core

when not declared(DWM_THUMBNAIL_PROPERTIES):
  type
    DWM_THUMBNAIL_PROPERTIES {.pure.} = object
      dwFlags: DWORD
      rcDestination: RECT
      rcSource: RECT
      opacity: BYTE
      fVisible: WINBOOL
      fSourceClientAreaOnly: WINBOOL

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
when not declared(RegisterHotKey):
  proc RegisterHotKey(hWnd: HWND; id: int32; fsModifiers: UINT; vk: UINT): WINBOOL
      {.stdcall, dynlib: "user32", importc.}
when not declared(UnregisterHotKey):
  proc UnregisterHotKey(hWnd: HWND; id: int32): WINBOOL {.stdcall,
      dynlib: "user32", importc.}
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

import ../config/storage

## Forward declarations for routines used before their definitions.
proc clientRect(hwnd: HWND): RECT
proc updateThumbnailProperties()
proc registerThumbnail(target: HWND)
proc startValidationTimer()
proc stopValidationTimer()
proc setCrop*(rect: RECT)
proc resetCrop*()
proc cropDialogWndProc(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.}

const
  className = L"NimOTROverlayClass"
  overlayTitle = L"Nim OTR Overlay"
  idSelectWindow = 1000
  idToggleTopMost = 1001
  idToggleBorderless = 1002
  idEditCrop = 1003
  idResetCrop = 1004
  idExit = 1005

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
  styleBorderless = WS_POPUP or WS_THICKFRAME or WS_MINIMIZEBOX or WS_MAXIMIZEBOX
  exStyleLayered = WS_EX_LAYERED
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
  hotkeySelectWindowId = 3001
  MOD_CONTROL = 0x0002
  MOD_SHIFT = 0x0004
  VK_P = 0x50
  enableClickForwarding = false ## Future flag: forward shift-clicks to the source window.

when not declared(WM_DPICHANGED):
  const WM_DPICHANGED = 0x02E0

let
  menuLabelSelectWindow = L"Select Window… (Ctrl+Shift+P)"
  menuLabelTopMost = L"Always on Top"
  menuLabelBorderless = L"Borderless"
  menuLabelCrop = L"Crop…"
  menuLabelResetCrop = L"Reset Crop"
  menuLabelExit = L"Exit"

  cropDialogClass = L"NimOTRCropDialog"
  cropDialogWidth = 280
  cropDialogHeight = 210

type
  CropDialogState = object
    hwnd: HWND
    editLeft: HWND
    editTop: HWND
    editWidth: HWND
    editHeight: HWND

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
    cropDialog: CropDialogState
    clickThroughEnabled: bool
    selectingTarget: bool
    statusText: string

var appState: AppState = AppState(
  opacity: 255.BYTE,
  thumbnailVisible: true,
  clickThroughEnabled: true
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

proc matchesStoredWindow(win: core.WindowInfo; cfg: OverlayConfig): bool =
  let processMatches = cfg.targetProcess.len > 0 and
      cmpIgnoreCase(win.processName, cfg.targetProcess) == 0
  let titleMatches = cfg.targetTitle.len > 0 and win.title == cfg.targetTitle

  if cfg.targetProcess.len > 0 and cfg.targetTitle.len > 0:
    processMatches and titleMatches
  elif cfg.targetProcess.len > 0:
    processMatches
  else:
    titleMatches

proc findWindowByIdentity*(cfg: OverlayConfig; opts: WindowEligibilityOptions): HWND =
  if cfg.targetTitle.len == 0 and cfg.targetProcess.len == 0:
    return 0

  for win in enumTopLevelWindows(opts):
    if matchesStoredWindow(win, cfg):
      return win.hwnd
  0

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
  discard AppendMenuW(menu, menuTopFlags, idSelectWindow, menuLabelSelectWindow)
  discard AppendMenuW(menu, MF_SEPARATOR, 0, nil)
  discard AppendMenuW(menu, menuTopFlags, idToggleTopMost, menuLabelTopMost)
  discard AppendMenuW(menu, menuTopFlags, idToggleBorderless, menuLabelBorderless)

  discard AppendMenuW(menu, MF_SEPARATOR, 0, nil)
  discard AppendMenuW(menu, menuTopFlags, idEditCrop, menuLabelCrop)
  discard AppendMenuW(menu, menuTopFlags, idResetCrop, menuLabelResetCrop)

  discard AppendMenuW(menu, MF_SEPARATOR, 0, nil)
  discard AppendMenuW(menu, menuTopFlags, idExit, menuLabelExit)

proc updateContextMenuChecks() =
  if appState.contextMenu == 0:
    return

  let topFlags: UINT = UINT(if appState.cfg.topMost: menuByCommand or menuChecked else: menuByCommand or menuUnchecked)
  discard CheckMenuItem(appState.contextMenu, idToggleTopMost, topFlags)

  let borderFlags: UINT = UINT(if appState.cfg.borderless: menuByCommand or menuChecked else: menuByCommand or menuUnchecked)
  discard CheckMenuItem(appState.contextMenu, idToggleBorderless, borderFlags)

proc destroyContextMenu() =
  if appState.contextMenu == 0:
    return
  discard DestroyMenu(appState.contextMenu)
  appState.contextMenu = 0

proc currentStyle(): DWORD =
  if appState.cfg.borderless: styleBorderless else: styleStandard

proc applyWindowStyles(hwnd: HWND) =
  let style = currentStyle()
  discard SetWindowLongPtrW(hwnd, GWL_STYLE, style)
  let currentEx = DWORD(GetWindowLongPtrW(hwnd, GWL_EXSTYLE))
  discard SetWindowLongPtrW(hwnd, GWL_EXSTYLE, LONG_PTR(currentEx or exStyleLayered))

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

proc handleSize(lParam: LPARAM) =
  appState.cfg.width = int(loWordL(lParam))
  appState.cfg.height = int(hiWordL(lParam))

proc handleMove(lParam: LPARAM) =
  appState.cfg.x = int(int16(loWordL(lParam)))
  appState.cfg.y = int(int16(hiWordL(lParam)))

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
    return "No window selected. " & selectAction

  if appState.thumbnailSuppressed:
    return "Source is minimized or hidden. Restore it or " & selectAction

  ""

proc updateStatusText() =
  let nextStatus = computeStatusText()
  if nextStatus != appState.statusText:
    appState.statusText = nextStatus
    invalidateStatus()

proc paintStatus(hwnd: HWND) =
  var ps: PAINTSTRUCT
  let hdc = BeginPaint(hwnd, addr ps)
  defer:
    discard EndPaint(hwnd, addr ps)

  let status = appState.statusText
  if status.len == 0:
    return

  var rect = clientRect(hwnd)
  discard FillRect(hdc, addr rect, cast[HBRUSH](COLOR_WINDOW + 1))
  discard SetBkMode(hdc, TRANSPARENT)
  discard SetTextColor(hdc, GetSysColor(COLOR_WINDOWTEXT))
  discard DrawTextW(
    hdc,
    status.newWideCString,
    -1,
    addr rect,
    DT_CENTER or DT_VCENTER or DT_WORDBREAK or DT_NOPREFIX
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
  updateStatusText()
  updateCropDialogFields()

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
    updateStatusText()

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
  updateStatusText()

proc mapOverlayToSource(overlayRect: RECT): RECT =
  # The thumbnail is stretched to fill the overlay client area; map linearly without
  # letterboxing.
  let destRect = clientRect(appState.hwnd).toIntRect
  let sourceRect = clientRect(appState.targetHwnd).toIntRect
  mapRectToSource(overlayRect.toIntRect, destRect, sourceRect).toWinRect

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
  of WM_CLOSE:
    discard DestroyWindow(hwnd)
    return 0
  of WM_DESTROY:
    if appState.cropDialog.hwnd == hwnd:
      appState.cropDialog = CropDialogState()
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
      WS_EX_TOOLWINDOW,
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
    setTargetWindow(win.hwnd)

proc handleCommand(hwnd: HWND, wParam: WPARAM) =
  case loWord(wParam)
  of idSelectWindow:
    selectTarget()
  of idToggleTopMost:
    appState.cfg.topMost = not appState.cfg.topMost
    applyWindowStyles(hwnd)
  of idToggleBorderless:
    appState.cfg.borderless = not appState.cfg.borderless
    applyWindowStyles(hwnd)
  of idEditCrop:
    showCropDialog()
  of idResetCrop:
    resetCropFromDialog()
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
  of WM_HOTKEY:
    if int32(wParam) == hotkeySelectWindowId:
      selectTarget()
      return 0
  of WM_CONTEXTMENU:
    handleContextMenu(hwnd, lParam)
    return 0
  of WM_PAINT:
    paintStatus(hwnd)
    return 0
  of WM_NCHITTEST:
    if appState.clickThroughEnabled and not shiftHeld():
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
    unregisterHotkeys()
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
  let xpos = if useDefault: CW_USEDEFAULT else: int32(appState.cfg.x)
  let ypos = if useDefault: CW_USEDEFAULT else: int32(appState.cfg.y)

  result = CreateWindowExW(
    exStyleLayered,
    className,
    overlayTitle,
    currentStyle(),
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
  let storedOpacity = max(min(appState.cfg.opacity, 255), 0)
  appState.opacity = BYTE(storedOpacity)
  appState.hInstance = GetModuleHandleW(nil)
  appState.hwnd = createWindow(appState.hInstance)
  if appState.hwnd == 0:
    return false

  applyWindowStyles(appState.hwnd)
  applyWindowOpacity()
  registerHotkeys()

  discard ShowWindow(appState.hwnd, SW_SHOWNORMAL)
  discard UpdateWindow(appState.hwnd)
  updateStatusText()

  result = true

proc runOverlayLoop*() =
  if appState.hwnd == 0:
    return

  var msg: MSG
  while GetMessageW(addr msg, 0, 0, 0) != 0:
    discard TranslateMessage(addr msg)
    discard DispatchMessageW(addr msg)

  saveStateOnClose()
