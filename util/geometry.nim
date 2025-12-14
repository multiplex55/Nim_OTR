## Pure geometry helpers for mapping overlay selections to source window coordinates.

## Axis-aligned rectangle used by geometry helpers.
type IntRect* = object
  left*: int
  top*: int
  right*: int
  bottom*: int

proc width*(rect: IntRect): int =
  rect.right - rect.left

proc height*(rect: IntRect): int =
  rect.bottom - rect.top

## Clamps `rect` to stay within the provided `bounds` rectangle.
proc clampRect*(rect, bounds: IntRect): IntRect =
  result.left = max(rect.left, bounds.left)
  result.top = max(rect.top, bounds.top)
  result.right = min(rect.right, bounds.right)
  result.bottom = min(rect.bottom, bounds.bottom)

  if result.right < result.left:
    result.right = result.left
  if result.bottom < result.top:
    result.bottom = result.top

## Maps an overlay selection rectangle to source coordinates using linear scaling.
proc mapRectToSource*(overlayRect, destRect, sourceRect: IntRect): IntRect =
  let destWidth = destRect.width
  let destHeight = destRect.height
  if destWidth == 0 or destHeight == 0:
    return sourceRect

  let scaleX = sourceRect.width.float / destWidth.float
  let scaleY = sourceRect.height.float / destHeight.float

  var mapped: IntRect
  mapped.left = sourceRect.left + int((overlayRect.left - destRect.left).float * scaleX)
  mapped.top = sourceRect.top + int((overlayRect.top - destRect.top).float * scaleY)
  mapped.right = sourceRect.left + int((overlayRect.right - destRect.left).float * scaleX)
  mapped.bottom = sourceRect.top + int((overlayRect.bottom - destRect.top).float * scaleY)

  clampRect(mapped, sourceRect)
