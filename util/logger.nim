## Simple structured logging for overlay events, gated by configuration or debug builds.
import std/[json, times]
import ../config/storage

var loggingEnabledState = false

proc initLogger*(cfg: OverlayConfig) =
  loggingEnabledState = defined(debug) or cfg.debugLogging

proc loggingEnabled*(): bool =
  loggingEnabledState

proc logEvent*(event: string; fields: openArray[(string, JsonNode)] = []) =
  if not loggingEnabled():
    return

  var node = %*{
    "event": event,
    "timestamp": now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  }
  for (key, value) in fields:
    node[key] = value

  echo $node
