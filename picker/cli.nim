## CLI helper that enumerates visible windows and lets users pick a target HWND.

import std/[options, strformat, strutils]

import core

proc printWindowList(windows: seq[WindowInfo]) =
  echo "Available windows:"
  for i, win in windows:
    let hwndHex = cast[int](win.hwnd).toHex.toUpperAscii()
    echo &"{i + 1}. {win.title} ({win.processName}) [HWND=0x{hwndHex}]"

## Interactive selection entry point that returns a chosen window, if any.
proc pickWindow*(): Option[WindowInfo] =
  var windows = enumTopLevelWindows()
  if windows.len == 0:
    echo "No eligible windows found."
    return

  printWindowList(windows)
  echo "\nEnter number to pick, or 'c' for click-to-pick (Esc to cancel):"

  while true:
    let input = stdin.readLine().strip()
    if input.len == 0:
      echo "Please enter a selection."
      continue
    if input.len == 1 and (input[0] == 'c' or input[0] == 'C'):
      echo "Click-to-pick: hover a window and click or press Enter to select. Press Esc to cancel."
      let selection = clickToPickWindow()
      if selection.isNone:
        echo "Selection cancelled."
        return
      return selection
    if input.len == 1 and (input[0] == 'q' or input[0] == 'Q' or input[0] == 'x' or
        input[0] == 'X'):
      return
    if input.allCharsInSet(Digits):
      let idx = parseInt(input) - 1
      if idx >= 0 and idx < windows.len:
        return some(windows[idx])
    echo "Invalid selection. Enter a number or 'c' for click-to-pick."

when isMainModule:
  let selection = pickWindow()
  if selection.isSome:
    let win = selection.get()
    echo &"Selected: {win.title} ({win.processName}) [HWND=0x{cast[int](win.hwnd).toHex.toUpperAscii()}]"
