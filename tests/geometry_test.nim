import std/unittest
import util/geometry

template rect(l, t, r, b: int): IntRect =
  IntRect(left: l, top: t, right: r, bottom: b)

template assertRectEquals(actual, expected: IntRect) =
  check actual.left == expected.left
  check actual.top == expected.top
  check actual.right == expected.right
  check actual.bottom == expected.bottom

suite "geometry mapping":
  test "scales overlay selection proportionally":
    let overlayRect = rect(50, 50, 150, 150)
    let destRect = rect(0, 0, 200, 200)
    let sourceRect = rect(0, 0, 400, 400)
    let mapped = mapRectToSource(overlayRect, destRect, sourceRect)
    assertRectEquals(mapped, rect(100, 100, 300, 300))

  test "respects non-uniform scaling from DPI":
    let overlayRect = rect(110, 40, 210, 90)
    let destRect = rect(10, 20, 210, 120)
    let sourceRect = rect(0, 0, 800, 600)
    let mapped = mapRectToSource(overlayRect, destRect, sourceRect)
    assertRectEquals(mapped, rect(400, 120, 800, 420))

  test "clamps to source bounds when overlay extends beyond":
    let overlayRect = rect(-50, -25, 250, 125)
    let destRect = rect(0, 0, 200, 100)
    let sourceRect = rect(0, 0, 400, 200)
    let mapped = mapRectToSource(overlayRect, destRect, sourceRect)
    assertRectEquals(mapped, rect(0, 0, 400, 200))

suite "aspect fitting":
  test "adds horizontal letterboxing when bounds are wider":
    let bounds = rect(0, 0, 1920, 1080)
    let fitted = aspectFitRect(bounds, (width: 800, height: 600))
    assertRectEquals(fitted, rect(240, 0, 1680, 1080))

  test "adds vertical pillarboxing when bounds are taller":
    let bounds = rect(0, 0, 900, 1600)
    let fitted = aspectFitRect(bounds, (width: 800, height: 600))
    assertRectEquals(fitted, rect(0, 350, 900, 1250))
