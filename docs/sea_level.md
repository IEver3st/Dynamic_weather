# Sea Level Control

`/sealevel <height>` runs global absolute mode. Every loaded `WaterQuad` on every client is forced to same Z level.

`/sealevel offset <delta>` runs offset mode. Each loaded `WaterQuad` uses resource-start level plus delta.

`/sealevelsmooth <height> [seconds] [absolute|offset]` cancels current sea-level animation, then applies new target over time.

`/flood [offset]` runs the live global sea-level flood path. Default offset comes from `Config.SeaLevel.floodHeight` (`2.0`). `/flood 2` means raise sea level by +2 meters, not absolute world Z `2.0`.

Flood rise is stepped by `Config.SeaLevel.floodIncreaseRate` (`0.02`) every `Config.SeaLevel.floodTickMs` (`2000`). It keeps applying the next sea-level offset until it reaches the target. `Config.SeaLevel.floodForceThunder = true` forces every enabled weather zone to `THUNDER` when flood starts. `Config.SeaLevel.restoreWeatherAfterFlood = true` restores previous zone weather after `/endflood` recession completes or water is reset.

Protected vanilla water bodies are drawn in the weather editor under `Debug options`. Save writes `shared/data/protected_water.json`, then broadcasts those bodies to clients. Protected quads are skipped and restored during global sea-level apply/reset. Protected body restore never falls back to `0.0`; missing sampled/configured height logs a debug warning instead.

Use the editor map to draw the Alamo Sea, Land Act Dam Reservoir, and river channels manually. Set each body's restore height/radius/padding in the inspector; `Config.ProtectedWaterBodies` remains an empty fallback for static hand-authored zones.

`/sealevelreset` and `/resetwater` call `ResetWater`, recapture GTA water defaults, then run protected restore.

Clients enumerate loaded water quads from index `0` through `GetWaterQuadCount() - 1`, store original levels, then log:

- total quads found
- changed count
- failed count
- original min/max
- target level

`Config.SeaLevel.maxSafeSeaLevel` clamps runtime flood height. Very high mountain-height flooding exposes GTA water LOD/tile limits: visible seams, rectangular far-water chunks, and inconsistent distant water can still appear even when all loaded quads share one level.

`SetWaterAreaClipRect` is not used by flood commands. `flood.xml` is not registered as a startup `WATER_FILE`. `/flood` does not load `flood.xml` unless `Config.SeaLevel.loadFloodWaterFile` is explicitly enabled.

Debug commands:

- `/flooddebugwater` toggles verbose `[FloodDebug]` water modification logging.
- `/waterheight` and `/waterdebugsample` print player coords, `GetWaterHeight`, optional no-wave height, protected zone, nearest protected zone, and distance.
- `/protectedwaterdebug` and `/waterprotectviz` toggle protected-zone XY drawing near the player.
- `/floodcellinfo` prints current flood offset/mode, captured original sea-level range, player coords, and nearest protected water zone.
