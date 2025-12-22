## Pure geometry helpers for mapping overlay selections to source window coordinates.

import std/math

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

## Calculates an aspect-correct rectangle that fits inside `bounds` while preserving the
## original `contentSize` aspect ratio. The result is centered within `bounds` and may
## introduce letterboxing/pillarboxing when necessary.
proc aspectFitRect*(bounds: IntRect; contentSize: tuple[width,
    height: int]): IntRect =
  let boundsWidth = bounds.width
  let boundsHeight = bounds.height
  if boundsWidth <= 0 or boundsHeight <= 0 or contentSize.width <= 0 or
      contentSize.height <= 0:
    return bounds

  let scale = min(boundsWidth.float / contentSize.width.float,
      boundsHeight.float / contentSize.height.float)
  let scaledWidth = int(round(contentSize.width.float * scale))
  let scaledHeight = int(round(contentSize.height.float * scale))
  let offsetX = (boundsWidth - scaledWidth) div 2
  let offsetY = (boundsHeight - scaledHeight) div 2

  IntRect(
    left: bounds.left + offsetX,
    top: bounds.top + offsetY,
    right: bounds.left + offsetX + scaledWidth,
    bottom: bounds.top + offsetY + scaledHeight
  )

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
  mapped.right = sourceRect.left + int((overlayRect.right -
      destRect.left).float * scaleX)
  mapped.bottom = sourceRect.top + int((overlayRect.bottom -
      destRect.top).float * scaleY)

  clampRect(mapped, sourceRect)
