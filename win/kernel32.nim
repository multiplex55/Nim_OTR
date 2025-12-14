import winim/lean

## Shared kernel32 wrappers for process and timing utilities.

when not declared(OpenProcess):
  proc OpenProcess*(dwDesiredAccess: DWORD; bInheritHandle: WINBOOL; dwProcessId: DWORD): HANDLE
      {.stdcall, dynlib: "kernel32", importc.}

when not declared(CloseHandle):
  proc CloseHandle*(hObject: HANDLE): WINBOOL {.stdcall, dynlib: "kernel32", importc.}

when not declared(QueryFullProcessImageNameW):
  proc QueryFullProcessImageNameW*(hProcess: HANDLE; dwFlags: DWORD; lpExeName: LPWSTR;
      lpdwSize: ptr DWORD): WINBOOL {.stdcall, dynlib: "kernel32", importc.}

when not declared(Sleep):
  proc Sleep*(dwMilliseconds: DWORD) {.stdcall, dynlib: "kernel32", importc.}

const
  PROCESS_QUERY_LIMITED_INFORMATION* = 0x1000
