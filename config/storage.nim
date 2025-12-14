## Persisted configuration for overlay window position, target, and crop state.

import std/[json, os]

const
  configFileName = "overlay_config.json"
  invalidCoord = -1

type
  ## User-configurable overlay layout and crop settings persisted on disk.
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
    opacity*: int
    targetHwnd*: int
    targetTitle*: string
    targetProcess*: string
    targetProcessPath*: string
    includeCloaked*: bool

proc readIntField(data: JsonNode; key: string; dest: var int) =
  let node = data.getOrDefault(key)
  if node.kind != JNull:
    dest = node.getInt()

proc readBoolField(data: JsonNode; key: string; dest: var bool) =
  let node = data.getOrDefault(key)
  if node.kind != JNull:
    dest = node.getBool()

proc readStringField(data: JsonNode; key: string; dest: var string) =
  let node = data.getOrDefault(key)
  if node.kind != JNull:
    dest = node.getStr()

## Provides default dimensions and state for a fresh overlay configuration.
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
    cropHeight: 0,
    opacity: 255,
    targetHwnd: 0,
    targetTitle: "",
    targetProcess: "",
    targetProcessPath: "",
    includeCloaked: false
  )

## Path to the overlay configuration file, creating the config directory if needed.
proc configPath*(): string =
  let base = getAppDir() / "config"
  if not dirExists(base):
    createDir(base)
  base / configFileName

## Reads configuration from disk, falling back to defaults on missing or invalid files.
proc loadOverlayConfig*(): OverlayConfig =
  let path = configPath()
  if fileExists(path):
    try:
      let data = parseJson(readFile(path))
      result = defaultOverlayConfig()
      readIntField(data, "x", result.x)
      readIntField(data, "y", result.y)
      readIntField(data, "width", result.width)
      readIntField(data, "height", result.height)
      readBoolField(data, "topMost", result.topMost)
      readBoolField(data, "borderless", result.borderless)
      readBoolField(data, "cropActive", result.cropActive)
      readIntField(data, "cropLeft", result.cropLeft)
      readIntField(data, "cropTop", result.cropTop)
      readIntField(data, "cropWidth", result.cropWidth)
      readIntField(data, "cropHeight", result.cropHeight)
      readIntField(data, "opacity", result.opacity)
      readIntField(data, "targetHwnd", result.targetHwnd)
      readStringField(data, "targetTitle", result.targetTitle)
      readStringField(data, "targetProcess", result.targetProcess)
      readStringField(data, "targetProcessPath", result.targetProcessPath)
      readBoolField(data, "includeCloaked", result.includeCloaked)
      if result.cropActive and (result.cropWidth <= 0 or result.cropHeight <= 0):
        ## Prevent restoring a zero-area active crop on launch.
        result.cropActive = false
        result.cropWidth = 0
        result.cropHeight = 0
      return
    except CatchableError:
      discard
  result = defaultOverlayConfig()

## Writes the provided configuration object back to disk as JSON.
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
    "cropHeight": cfg.cropHeight,
    "opacity": cfg.opacity,
    "targetHwnd": cfg.targetHwnd,
    "targetTitle": cfg.targetTitle,
    "targetProcess": cfg.targetProcess,
    "targetProcessPath": cfg.targetProcessPath,
    "includeCloaked": cfg.includeCloaked
  }
  writeFile(configPath(), node.pretty())

## Determines whether the stored window coordinates are valid values.
proc hasValidPosition*(cfg: OverlayConfig): bool =
  cfg.x != invalidCoord and cfg.y != invalidCoord
