## Persisted configuration for overlay window position, target, and crop state.

import std/[json, os, strutils]

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
    targetProcess: ""
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
      result.opacity = data.getOrDefault("opacity", result.opacity).getInt()
      result.targetHwnd = data.getOrDefault("targetHwnd", result.targetHwnd).getInt()
      result.targetTitle = data.getOrDefault("targetTitle", result.targetTitle).getStr()
      result.targetProcess = data.getOrDefault("targetProcess", result.targetProcess).getStr()
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
    "targetProcess": cfg.targetProcess
  }
  writeFile(configPath(), node.pretty())

## Determines whether the stored window coordinates are valid values.
proc hasValidPosition*(cfg: OverlayConfig): bool =
  cfg.x != invalidCoord and cfg.y != invalidCoord
