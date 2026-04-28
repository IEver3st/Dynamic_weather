# Sea Level Control

`/sealevel <height>` runs global absolute mode. Every loaded `WaterQuad` on every client is forced to same Z level.

`/sealevel offset <delta>` runs offset mode. Each loaded `WaterQuad` uses resource-start level plus delta.

`/sealevelsmooth <height> [seconds] [absolute|offset]` cancels current sea-level animation, then applies new target over time.

`/flood` loads `flood.xml` with `LoadWaterFromPath`, then raises the full-map flood water by `Config.SeaLevel.floodHeight` in offset mode. Default flood height is `2.0`.

`/sealevelreset` and `/resetwater` call `ResetWater`, then recapture GTA water defaults.

Clients enumerate loaded water quads from index `0` through `GetWaterQuadCount() - 1`, store original levels, then log:

- total quads found
- changed count
- failed count
- original min/max
- target level

`Config.SeaLevel.maxSafeSeaLevel` clamps runtime flood height. Very high mountain-height flooding exposes GTA water LOD/tile limits: visible seams, rectangular far-water chunks, and inconsistent distant water can still appear even when all loaded quads share one level.

`SetWaterAreaClipRect` is not used by sea-level commands. `flood.xml` is not registered as a startup `WATER_FILE`; it is loaded only when flood mode starts so normal gameplay does not spawn the full-map flood plane.
