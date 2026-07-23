# Sea Level Control

`/sealevel <height>` runs global absolute mode. Every loaded `WaterQuad` on every client is forced to same Z level.

`/sealevel offset <delta>` runs offset mode. Each loaded `WaterQuad` uses resource-start level plus delta.

`/sealevelsmooth <height> [seconds] [absolute|offset]` cancels current sea-level animation, then applies new target over time.

`/flood [offset]` runs the live global sea-level flood path. Default offset comes from `Config.SeaLevel.floodHeight` (`2.0`). `/flood 2` means raise sea level by +2 meters, not absolute world Z `2.0`.

Flood rise is stepped by `Config.SeaLevel.floodIncreaseRate` (`0.02`) every `Config.SeaLevel.floodTickMs` (`2000`). It keeps applying the next sea-level offset until it reaches the target. The sequence-driven flood event snapshots zone weather, forces every enabled zone to `THUNDER`, and restores the snapshot when that event ends. The manual `/flood` command changes water only.

Protected vanilla water bodies are loaded from `shared/data/protected_water.json`. Protected quads are skipped and sampled water heights are restored during sea-level application. Protected body restore never falls back to `0.0`; missing sampled/configured height logs a debug warning instead.

The weather editor manages weather zones, flood settings, and flood-ignore zones. Edit protected-water polygons and restore points in `shared/data/protected_water.json`; `Config.ProtectedWaterBodies` remains an optional static fallback.

`/sealevelreset` and `/resetwater` call `ResetWater` and recapture GTA water defaults.

Clients enumerate loaded water quads from index `0` through `GetWaterQuadCount() - 1`, store original levels, then log:

- total quads found
- changed count
- failed count
- original min/max
- target level

`Config.SeaLevel.maxSafeSeaLevel` clamps runtime flood height. Very high mountain-height flooding exposes GTA water LOD/tile limits: visible seams, rectangular far-water chunks, and inconsistent distant water can still appear even when all loaded quads share one level.

`SetWaterAreaClipRect` is not used by flood commands. `flood.xml` is not registered as a startup `WATER_FILE`. `/flood` does not load `flood.xml` unless `Config.SeaLevel.loadFloodWaterFile` is explicitly enabled.

Debug commands:

- `/floodignoredebug [on|off|draw]` toggles flood-ignore status logging and polygon drawing.
