import winim/lean

## COM bindings for the Windows Virtual Desktop Manager.
## Based on IVirtualDesktopManager documentation.

const
  CLSID_VirtualDesktopManager* = GUID(D1: 0xAA509086'i32, D2: 0x5CA9'i16,
      D3: 0x4C25'i16, D4: [0x8F'u8, 0x95, 0x58, 0x9D, 0x3C, 0x07, 0xB4, 0x8A])
  IID_IVirtualDesktopManager* = GUID(D1: 0xA5CD92FF'i32, D2: 0x29BE'i16,
      D3: 0x454C'i16, D4: [0x8D'u8, 0x04, 0xD8, 0x28, 0x79, 0xFB, 0x3F, 0x1B])

  CLSCTX_ALL = CLSCTX_INPROC_SERVER or CLSCTX_INPROC_HANDLER or CLSCTX_LOCAL_SERVER

type
  IVirtualDesktopManagerVtbl* = object
    QueryInterface*: proc(self: ptr IVirtualDesktopManager; riid: REFIID;
        ppvObject: ptr pointer): HRESULT {.stdcall.}
    AddRef*: proc(self: ptr IVirtualDesktopManager): ULONG {.stdcall.}
    Release*: proc(self: ptr IVirtualDesktopManager): ULONG {.stdcall.}
    IsWindowOnCurrentVirtualDesktop*: proc(self: ptr IVirtualDesktopManager;
        topLevelWindow: HWND; onCurrentDesktop: ptr WINBOOL): HRESULT {.stdcall.}
    GetWindowDesktopId*: proc(self: ptr IVirtualDesktopManager;
        topLevelWindow: HWND; desktopId: ptr GUID): HRESULT {.stdcall.}
    MoveWindowToDesktop*: proc(self: ptr IVirtualDesktopManager;
        topLevelWindow: HWND; desktopId: REFGUID): HRESULT {.stdcall.}

  IVirtualDesktopManager* = object
    lpVtbl*: ptr IVirtualDesktopManagerVtbl

proc CreateVirtualDesktopManager*(manager: ptr ptr IVirtualDesktopManager): HRESULT =
  CoCreateInstance(CLSID_VirtualDesktopManager, nil, CLSCTX_ALL, IID_IVirtualDesktopManager,
      cast[ptr pointer](manager))
