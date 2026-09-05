# Cortex Dynamic Weather — `Dynamic_weather`

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![fx_version](https://img.shields.io/badge/fx__version-cerulean-green)
![Game](https://img.shields.io/badge/game-gta5-orange)
![Lua](https://img.shields.io/badge/lua-5.4-blue)
![React](https://img.shields.io/badge/react-19-61DAFB?logo=react)
![Vite](https://img.shields.io/badge/vite-6-646CFF?logo=vite)

> Multi-zone dynamic weather system for FiveM with seamless transitions, seasonal control, hurricanes, wind debris, lightning pole strikes, and an in-game NUI editor.

---

## What it does

`Cortex Dynamic Weather` is a server-side and client-side FiveM resource that divides the map into configurable polygon weather zones. Each zone follows a time-of-day based sequence to transition between GTA weather types (`CLEAR`, `RAIN`, `THUNDER`, `FOGGY`, `SMOG`, etc.) and can be overridden, forced, or edited live through a React/Leaflet NUI panel.

Optional subsystems can be enabled in `shared/config.lua`:

- **Sequence engine** — advances zone weather on a configurable interval using per-zone timelines.
- **Hurricane events** — scripted high-wind storms with intensity-scaled wind and lightning.
- **Wind debris / storm props** — animates nearby world props and spawns client-side debris during storms.
- **Lightning pole strikes** — lightning can strike configured power/utility pole models, with optional blackouts, fires, camera shake, and vehicle alarms.
- **Weather alerts & dispatch** — generates in-world alerts and MDT/dispatch style advisories for configured jobs.
- **NUI editor** — draw, save, and reload weather zones from an in-game map.

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
| `WeatherData` | Forecast periods, alert cleanup, dispatch jobs |
| `RoadConditions` | Advisory text strings for MDT/weather data exports |
| `WindDebris` / `StormProps` | Debris models, wind thresholds, gust intervals, heavy prop rules |
| `Hurricane` | Intensity tables for wind speed, severity, and lightning multiplier |
| `HurricaneDebris` | Per-intensity spawn limits and fly-by physics |
| `LightningPoleStrike` | Pole models, strike chance, blackout radius, fire chance |

Weather zones and sequences are stored in JSON:

- `shared/data/zones.json` — polygon definitions, weather pools, and assigned sequence.
- `shared/data/sequences.json` — named timeline presets (`urban_coastal`, `desert_inland`, etc.).

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
- **Global state** — `dynamic_weather_season`, `dynamic_weather_blackout`, and `dynamic_weather_hurricane` are replicated to clients via FiveM `GlobalState`.
- **Exports** — both client exports and `server_exports` are declared in `fxmanifest.lua` for integration with other resources.

---

## Commands

All admin commands use the ACE permissions defined in `Config.Permissions` and `Config.ActionPermissions`. Console (`source == 0`) bypasses player permission checks where noted.

| Command | Permission | Description |
|---------|------------|-------------|
| `/weathereditor` | `weather.editor` | Open the NUI weather-zone editor |
| `/weather reload` | `weather.reload` | Reload zones and broadcast state |
| `/weather force <zoneId> <weatherType>` | `weather.force` | Force a zone to a specific weather |
| `/weatherstate` | `weather.debug` | Print active zone state as JSON |
| `/weatherforecast [region]` | `weather.debug` | Print forecast for region or all |
| `/weatheralerts` | `weather.debug` | Print active alerts |
| `/weatheralerttest <zoneId> [severity]` | `weather.debug` | Create a test alert |
| `/hurricane [start\|stop\|status] [intensity] [direction]` | `weather.hurricane` | Start/stop hurricane event |
| `/hurricanestatus` | `weather.debug` / `weather.hurricane` | Print hurricane state |
| `/lightningpole` | `weather.debug` | Lightning pole debug commands |
| `/strikepole` | `weather.debug` | Strike a pole |
| `/findpole [radius]` | `weather.debug` | Scan for nearby poles |
| `/debugpole [radius]` | `weather.debug` | Visual pole scan debug |

## Client & Server Exports

The manifest exposes client exports such as `getCurrentWeather`, `getSeason`, `getBlackout`, and `isEditorOpen`, plus server exports including `GetCurrentWeather`, `GetForecast`, `CreateWeatherAlert`, `StartHurricane`, and `syncWeatherToPlayer`. See [`fxmanifest.lua`](fxmanifest.lua) for the complete list.

---

## Limitations & Notes

- **UI build required** — `web/dist` is the runtime NUI path but is generated by `vite build`; it is ignored from source control. Make sure to build before deploying.
- **Offline NUI** — the editor uses a local coordinate grid and system fonts; it makes no runtime CDN requests.
- **One editor at a time** — the NUI editor is single-user; a second opening player is blocked until the first closes or drops.
- **Local-only debris** — spawned storm/hurricane debris is client-side for performance; networked debris is not supported.
- **Dependency** — `cortex-lib` must be present and started; notifications and `lib.require` depend on it.

---

## License

Released under the [MIT License](LICENSE).

---

## Disclaimer

This is an independent FiveM resource. It is **not affiliated with, endorsed by, or sponsored by Rockstar Games, Take-Two Interactive Software, Inc., or Cfx.re**. Grand Theft Auto and GTA Online are trademarks of Take-Two Interactive. FiveM is a third-party multiplayer platform by Cfx.re.
