import winim/lean

## COM bindings for the Windows Virtual Desktop Manager.
## Based on IVirtualDesktopManager documentation.

const
  CLSID_VirtualDesktopManager* = GUID(Data1: 0xAA509086'u32, Data2: 0x5CA9'u16,
      Data3: 0x4C25'u16, Data4: [0x8F'u8, 0x95, 0x58, 0x9D, 0x3C, 0x07, 0xB4,
          0x8A])
  IID_IVirtualDesktopManager* = GUID(Data1: 0xA5CD92FF'u32, Data2: 0x29BE'u16,
      Data3: 0x454C'u16, Data4: [0x8D'u8, 0x04, 0xD8, 0x28, 0x79, 0xFB, 0x3F,
          0x1B])

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
