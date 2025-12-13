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
    cropActive*: bool
    cropLeft*: int
    cropTop*: int
    cropWidth*: int
    cropHeight*: int

proc defaultOverlayConfig*(): OverlayConfig =
  OverlayConfig(
    x: invalidCoord,
    y: invalidCoord,
    width: 960,
    height: 540,
    topMost: false,
    borderless: false,
    cropActive: false,
    cropLeft: 0,
    cropTop: 0,
    cropWidth: 0,
    cropHeight: 0
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
      result.cropActive = data.getOrDefault("cropActive", result.cropActive).getBool()
      result.cropLeft = data.getOrDefault("cropLeft", result.cropLeft).getInt()
      result.cropTop = data.getOrDefault("cropTop", result.cropTop).getInt()
      result.cropWidth = data.getOrDefault("cropWidth", result.cropWidth).getInt()
      result.cropHeight = data.getOrDefault("cropHeight", result.cropHeight).getInt()
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
    "borderless": cfg.borderless,
    "cropActive": cfg.cropActive,
    "cropLeft": cfg.cropLeft,
    "cropTop": cfg.cropTop,
    "cropWidth": cfg.cropWidth,
    "cropHeight": cfg.cropHeight
  }
  writeFile(configPath(), node.pretty())

proc hasValidPosition*(cfg: OverlayConfig): bool =
  cfg.x != invalidCoord and cfg.y != invalidCoord
