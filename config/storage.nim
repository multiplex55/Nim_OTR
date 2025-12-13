import std/[json, os, strutils]

const
  configFileName = "overlay_config.json"
  invalidCoord = -1

type
  OverlayConfig* = object
    x*: int
    y*: int
    width*: int
    height*: int
    topMost*: bool
    borderless*: bool

proc defaultOverlayConfig*(): OverlayConfig =
  OverlayConfig(
    x: invalidCoord,
    y: invalidCoord,
    width: 960,
    height: 540,
    topMost: false,
    borderless: false
  )

proc configPath*(): string =
  let base = getAppDir() / "config"
  if not dirExists(base):
    createDir(base)
  base / configFileName

proc loadOverlayConfig*(): OverlayConfig =
  let path = configPath()
  if fileExists(path):
    try:
      let data = parseJson(readFile(path))
      result = defaultOverlayConfig()
      result.x = data.getOrDefault("x", result.x).getInt()
      result.y = data.getOrDefault("y", result.y).getInt()
      result.width = data.getOrDefault("width", result.width).getInt()
      result.height = data.getOrDefault("height", result.height).getInt()
      result.topMost = data.getOrDefault("topMost", result.topMost).getBool()
      result.borderless = data.getOrDefault("borderless", result.borderless).getBool()
      return
    except CatchableError:
      discard
  result = defaultOverlayConfig()

proc saveOverlayConfig*(cfg: OverlayConfig) =
  let node = %*{
    "x": cfg.x,
    "y": cfg.y,
    "width": cfg.width,
    "height": cfg.height,
    "topMost": cfg.topMost,
    "borderless": cfg.borderless
  }
  writeFile(configPath(), node.pretty())

proc hasValidPosition*(cfg: OverlayConfig): bool =
  cfg.x != invalidCoord and cfg.y != invalidCoord
