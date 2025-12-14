import winim/lean

## Shared dwmapi wrappers for thumbnail and attribute queries.

when not declared(DWM_THUMBNAIL_PROPERTIES):
  type
    DWM_THUMBNAIL_PROPERTIES* {.pure.} = object
      dwFlags*: DWORD
      rcDestination*: RECT
      rcSource*: RECT
      opacity*: BYTE
      fVisible*: WINBOOL
      fSourceClientAreaOnly*: WINBOOL

when not declared(DwmRegisterThumbnail):
  proc DwmRegisterThumbnail*(hwndDestination: HWND; hwndSource: HWND; phThumbnailId: ptr HANDLE): HRESULT
      {.stdcall, dynlib: "dwmapi", importc.}

when not declared(DwmUnregisterThumbnail):
  proc DwmUnregisterThumbnail*(hThumbnailId: HANDLE): HRESULT {.stdcall,
      dynlib: "dwmapi", importc.}

when not declared(DwmUpdateThumbnailProperties):
  proc DwmUpdateThumbnailProperties*(hThumbnailId: HANDLE; ptnProperties: ptr DWM_THUMBNAIL_PROPERTIES): HRESULT
      {.stdcall, dynlib: "dwmapi", importc.}

when not declared(DwmQueryThumbnailSourceSize):
  proc DwmQueryThumbnailSourceSize*(hThumbnail: HANDLE; pSize: ptr SIZE): HRESULT {.stdcall,
      dynlib: "dwmapi", importc.}

when not declared(DwmGetWindowAttribute):
  proc DwmGetWindowAttribute*(hwnd: HWND; dwAttribute: DWORD; pvAttribute: pointer; cbAttribute: DWORD): HRESULT
      {.stdcall, dynlib: "dwmapi", importc.}

const
  DWM_TNP_RECTDESTINATION* = 0x1
  DWM_TNP_RECTSOURCE* = 0x2
  DWM_TNP_OPACITY* = 0x4
  DWM_TNP_VISIBLE* = 0x8
  DWM_TNP_SOURCECLIENTAREAONLY* = 0x10
  DWMWA_EXTENDED_FRAME_BOUNDS* = 9
  DWMWA_CLOAKED* = 14
