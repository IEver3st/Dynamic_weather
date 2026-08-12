# Cortex Dynamic Weather — `Dynamic_weather`

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![fx_version](https://img.shields.io/badge/fx__version-cerulean-green)
![Game](https://img.shields.io/badge/game-gta5-orange)
![Lua](https://img.shields.io/badge/lua-5.4-blue)
![React](https://img.shields.io/badge/react-19-61DAFB?logo=react)
![Vite](https://img.shields.io/badge/vite-6-646CFF?logo=vite)

> Multi-zone dynamic weather system for FiveM with seamless transitions, seasonal control, floods, hurricanes, wind debris, lightning pole strikes, and an in-game NUI editor.

---

## What it does

`Cortex Dynamic Weather` is a server-side and client-side FiveM resource that divides the map into configurable polygon weather zones. Each zone follows a time-of-day based sequence to transition between GTA weather types (`CLEAR`, `RAIN`, `THUNDER`, `FOGGY`, `SMOG`, etc.) and can be overridden, forced, or edited live through a React/Leaflet NUI panel.

Optional subsystems can be enabled in `shared/config.lua`:

- **Sequence engine** — advances zone weather on a configurable interval using per-zone timelines.
- **Sea-level control** — raises or lowers all loaded `WaterQuad` levels globally or by offset, with optional smooth animation.
- **Random flood events** — sequence-driven coastal flooding that forces `THUNDER` and raises sea level.
- **Hurricane events** — scripted high-wind storms with intensity-scaled wind, flood target, and lightning multiplier.
- **Wind debris / storm props** — animates nearby world props and spawns client-side debris during storms.
- **Lightning pole strikes** — lightning can strike configured power/utility pole models, with optional blackouts, fires, camera shake, and vehicle alarms.
- **Weather alerts & dispatch** — generates in-world alerts and MDT/dispatch style advisories for configured jobs.
- **NUI editor** — draw, save, and reload weather zones, flood-ignore zones, and flood settings from an in-game map.

---

## Requirements

- A FiveM server running the `cerulean` artifact / FXServer.
- The [`cortex-lib`](https://github.com/IEver3st/cortex-lib) resource (`@cortex-lib/init.lua` is a hard dependency in `fxmanifest.lua`).
- `lua54 'yes'` is enabled in the manifest.
- The NUI is built with [Bun](https://bun.sh) (a `bun.lock` is present; `npm`/`yarn` also work).

---

## Installation

1. Place the `Dynamic_weather` folder inside your FiveM `resources` directory (for example under `resources/[eco]/`).
2. Make sure `cortex-lib` is started before this resource.
3. Add to `server.cfg`:

```cfg
ensure Dynamic_weather
```

4. Build the NUI (if you modify `web/src` or want to rebuild `web/dist`):

```bash
cd web
bun install
bun run build
```

5. Restart the server or run `refresh` and `ensure Dynamic_weather`.

The manifest points `ui_page` to `web/dist/index.html` and registers the bundled assets under `web/dist/assets/*`.

---

## Configuration

All runtime tuning lives in [`shared/config.lua`](shared/config.lua).

Major sections:

| Section | Purpose |
|---------|---------|
| `Engine` | `tickRate`, `defaultTransitionDuration`, `globalFallbackWeather` |
| `Sequence Engine` | `sequenceInterval` (ms), time-of-day timeline picks per zone |
| `Sync` | `syncBroadcastInterval`, `syncOnJoinImmediate` |
| `Editor` | stale-ping timeouts for the NUI editor |
| `Permissions` | ACE permission names (`cortex-admin.all`, `cortex-admin.world`, and `weather.*` action permissions) |
| `FloodEvent` | Random flood chance, thunder requirement, lead time, dispatch message |
| `SeaLevel` | Min/max levels, smooth duration, flood rate, protected water handling |
| `WeatherData` | Forecast periods, alert cleanup, dispatch jobs |
| `RoadConditions` | Advisory text strings for MDT/weather data exports |
| `WindDebris` / `StormProps` | Debris models, wind thresholds, gust intervals, heavy prop rules |
| `Hurricane` | Intensity tables for wind speed, flood target, and lightning multiplier |
| `HurricaneDebris` | Per-intensity spawn limits and fly-by physics |
| `LightningPoleStrike` | Pole models, strike chance, blackout radius, fire chance |

Weather zones and sequences are stored in JSON:

- `shared/data/zones.json` — polygon definitions, weather pools, and assigned sequence.
- `shared/data/sequences.json` — named timeline presets (`urban_coastal`, `desert_inland`, etc.).

The editor writes additional JSON files at runtime:

- `shared/data/flood_settings.json`
- `shared/data/flood_ignore_zones.json`
- `shared/data/protected_water.json`

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         SERVER                                  │
│  modules/server/main.lua        -- resource start/stop wiring    │
│  modules/server/storage.lua     -- JSON read/write               │
│  modules/server/sequence.lua  -- time-of-day weather advance    │
│  modules/server/sync.lua        -- broadcast zone state         │
│  modules/server/weather_data.lua -- alerts/forecasts/dispatch   │
│  modules/server/sea_level.lua   -- water quad set/reset         │
│  modules/server/flood_event.lua -- random/scripted flooding     │
│  modules/server/hurricane.lua   -- hurricane event state        │
│  modules/server/commands.lua    -- chat/console commands       │
│  modules/server/lightning_pole.lua -- pole strike commands     │
└──────────────────┬────────────────────────────────────────────┘
                   │  client events / GlobalState
┌──────────────────▼────────────────────────────────────────────┐
│                         CLIENT                                  │
│  modules/client/engine.lua       -- polygon zone detection,    │
│                                    weather blending             │
│  modules/client/sync.lua          -- server state caching      │
│  modules/client/sea_level.lua     -- water quad native writes   │
│  modules/client/storm_props.lua   -- world prop/debris physics │
│  modules/client/hurricane_debris.lua -- hurricane fly-by     │
│  modules/client/lightning_pole.lua -- strikes, blackouts     │
│  modules/client/nui.lua           -- React editor lifecycle    │
└─────────────────────────────────────────────────────────────────┘
                         web/
                         React + Leaflet + Vite NUI editor
```

- **Zone engine** — the client uses a point-in-polygon check against the player’s XY coordinates and selects the deepest (farthest from edge) matching zone.
- **Transitions** — uses `SetWeatherTypeOvertimePersist` with a configurable duration, capped at 60 seconds for native stability.
- **Global state** — `dynamic_weather_season`, `dynamic_weather_blackout`, `dynamic_weather_flood_active`, `dynamic_weather_hurricane` are replicated to clients via FiveM `GlobalState`.
- **Exports** — both client exports and `server_exports` are declared in `fxmanifest.lua` for integration with other resources.

---

## Commands

All admin commands use the ACE permissions defined in `Config.Permissions` and `Config.ActionPermissions`. Console (`source == 0`) bypasses player permission checks where noted.

| Command | Permission | Description |
|---------|------------|-------------|
| `/weathereditor` | `weather.editor` | Open the NUI zone/flood editor |
| `/weather reload` | `weather.reload` | Reload zones and broadcast state |
| `/weather force <zoneId> <weatherType>` | `weather.force` | Force a zone to a specific weather |
| `/weatherstate` | `weather.debug` | Print active zone state as JSON |
| `/weatherforecast [region]` | `weather.debug` | Print forecast for region or all |
| `/weatheralerts` | `weather.debug` | Print active alerts |
| `/weatheralerttest <zoneId> [severity]` | `weather.debug` | Create a test alert |
| `/sealevel <height> [absolute\|offset]` | sea level perm | Set sea level globally |
| `/sealevelsmooth <height> [seconds] [mode]` | sea level perm | Smoothly animate sea level |
| `/sealevelreset` | sea level perm | Reset water to defaults |
| `/sealevelstatus` | sea level perm | Print current sea level status |
| `/loadwater` | sea level perm | Load full-map flood water profile |
| `/resetwater` | sea level perm | Reset full-map water |
| `/flood [offset]` | sea level perm | Start a scripted flood |
| `/hurricane [start\|stop\|status] [intensity] [direction] [flood]` | `weather.hurricane` | Start/stop hurricane event |
| `/hurricanestatus` | `weather.debug` / `weather.hurricane` | Print hurricane state |
| `/lightningpole` | `weather.debug` | Lightning pole debug commands |
| `/strikepole` | `weather.debug` | Strike a pole |
| `/findpole [radius]` | `weather.debug` | Scan for nearby poles |
| `/debugpole [radius]` | `weather.debug` | Visual pole scan debug |

Sea-level permissions default to admin-only (`Config.SeaLevel.adminOnly = true`) and are also granted by `weather.sealevel`, `weather.debug`, or console.

---

## Client & Server Exports

The manifest exposes client exports (`getCurrentWeather`, `getSeason`, `getBlackout`, `isEditorOpen`, `isFloodEventActive`, etc.) and server exports (`GetCurrentWeather`, `GetForecast`, `CreateWeatherAlert`, `StartHurricane`, `EndFloodEvent`, `syncWeatherToPlayer`, etc.). See [`fxmanifest.lua`](fxmanifest.lua) lines 64–118 for the complete list.

---

## Limitations & Notes

- **UI build required** — `web/dist` is the runtime NUI path but is generated by `vite build`; it is ignored from source control. Make sure to build before deploying.
- **Offline NUI** — the editor uses a local coordinate grid and system fonts; it makes no runtime CDN requests.
- **GTA water limits** — very high flood offsets (`maxSafeSeaLevel` defaults to `80.0`) can expose water LOD seams and rectangular far-water tiles.
- **Protected water bodies** — inland lakes and reservoirs are configured in `shared/data/protected_water.json`; matching water quads are preserved during flood application.
- **One editor at a time** — the NUI editor is single-user; a second opening player is blocked until the first closes or drops.
- **Local-only debris** — spawned storm/hurricane debris is client-side for performance; networked debris is not supported.
- **Dependency** — `cortex-lib` must be present and started; notifications and `lib.require` depend on it.
- **Development tree** — the working tree currently contains uncommitted changes and untracked files; commit or clean those before a public release.

---

## License

Released under the [MIT License](LICENSE).

---

## Disclaimer

This is an independent FiveM resource. It is **not affiliated with, endorsed by, or sponsored by Rockstar Games, Take-Two Interactive Software, Inc., or Cfx.re**. Grand Theft Auto and GTA Online are trademarks of Take-Two Interactive. FiveM is a third-party multiplayer platform by Cfx.re.
