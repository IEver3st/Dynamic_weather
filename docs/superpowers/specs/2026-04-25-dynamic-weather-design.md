# Dynamic Weather System — Design Spec

**Date:** 2026-04-25  
**Resource:** `Dynamic_weather`  
**Type:** Standalone FiveM resource  
**Dependencies:** es_lib (utility, UI tokens), ox_tiles CDN (map imagery)

---

## 1. Purpose

A dynamic weather system for FiveM that divides the GTA V map into multiple weather zones. Each zone independently cycles through realistic weather sequences with configurable weather pools. Players in different zones experience different weather simultaneously. Smooth cross-zone transitions. Admin-editable via a Leaflet-based map UI.

---

## 2. Architecture

Four logical layers:

```
React UI (NUI)          →  Admin zone editor on Leaflet map
Client Lua (Engine)     →  Per-player weather application + zone detection
Server Lua (Sync)       →  Sequence engine, zone CRUD, state broadcast
Config (File)           →  Zone definitions, sequence presets, settings
```

**Data flow:**
1. Server loads zone definitions from config at startup
2. Server runs weather sequence engine — advances each zone through realistic timeline patterns
3. Server periodically broadcasts zone weather states to all connected clients
4. Each client detects which zone(s) the local player occupies and applies weather via natives
5. When player crosses zones, client smoothly transitions weather over configurable duration
6. Admin opens UI → reads zones from server → edits → saves back to file → server reloads

---

## 3. Directory Structure

```
Dynamic_weather/
├── fxmanifest.lua
├── init.lua                    # Client init (module boot)
├── shared/
│   ├── config.lua              # Weather types, defaults, settings
│   ├── data/
│   │   ├── zones.json          # Default zone definitions
│   │   └── sequences.json      # Weather sequence presets
│   └── lang.lua                # Localization strings
├── modules/
│   ├── client/
│   │   ├── engine.lua          # Per-player weather application + transitions
│   │   ├── zones.lua           # Polygon zone detection (point-in-polygon)
│   │   ├── nui.lua             # NUI callbacks for editor
│   │   └── sync.lua            # Client-side state sync handler
│   ├── server/
│   │   ├── main.lua            # Server init + exports
│   │   ├── sequence.lua        # Weather sequence engine (realistic patterns)
│   │   ├── storage.lua         # Zone CRUD (file I/O)
│   │   ├── sync.lua            # Broadcast zone states to clients
│   │   └── commands.lua        # Admin commands (/weather editor)
│   └── shared/
│       ├── types.lua           # Zone data structures, weather type enum
│       └── math.lua            # Geometry helpers (point-in-polygon, distance)
├── web/
│   ├── package.json            # Dependencies (react, leaflet, react-leaflet)
│   ├── vite.config.js          # Vite build config
│   ├── index.html              # NUI entry point
│   ├── public/
│   └── src/
│       ├── main.jsx            # React entry
│       ├── App.jsx             # Main app shell
│       ├── index.css           # All styles (dark theme)
│       ├── nui.js              # NUI communication layer
│       ├── Editor.jsx          # Main editor component
│       ├── Map.jsx             # Leaflet map with zone polygons
│       ├── Sidebar.jsx         # Zone list + properties panel
│       ├── Toolbar.jsx         # Save/load/zoom/add zone controls
│       ├── ZoneForm.jsx        # Zone property editor
│       └── constants.js        # Map bounds, tile URL, coordinate conversion
├── stream/                     # (reserved for future models/textures)
└── docs/superpowers/specs/     # Design documents
```

All Lua files use the module convention: `init.lua` boots, `modules/` contains subsystems.

---

## 4. Data Model

### 4.1 Zone Definition (`shared/data/zones.json`)

```lua
{
  id = "downtown_rain",           -- Unique string ID
  label = "Downtown",              -- Display name
  points = {                       -- Polygon vertices (GTA world coordinates)
    {x = 200.0, y = -300.0},
    {x = 450.0, y = -300.0},
    {x = 450.0, y = -600.0},
    {x = 200.0, y = -600.0},
  },
  sequence = "urban_coastal",      -- References a sequence preset
  weatherPool = {                  -- Allowed weather types for this zone
    "CLEAR", "CLOUDS", "EXTRASUNNY", "SMOG",
    "FOGGY", "OVERCAST", "RAIN", "THUNDER"
  },
  transitionDuration = 15,         -- Seconds to fade between weather states
  thickness = 50.0,                -- Z-axis height range for detection
  enabled = true,
}
```

**Zones must have at least 3 points.** Points must enclose a valid area. Overlapping zones are allowed — the player is assigned to the zone whose edge they are farthest from (deepest inside).

### 4.2 Sequence Preset (`shared/data/sequences.json`)

```lua
["urban_coastal"] = {
  label = "Urban Coastal",
  timeline = {
    {hour = 5,  weather = "FOGGY",     chance = 0.6},
    {hour = 7,  weather = "CLEAR",     chance = 0.7},
    {hour = 10, weather = "CLOUDS",    chance = 0.5},
    {hour = 14, weather = "OVERCAST",  chance = 0.4},
    {hour = 17, weather = "CLEAR",     chance = 0.6},
    {hour = 20, weather = "RAIN",      chance = 0.3},
    {hour = 23, weather = "CLEAR",     chance = 0.8},
  },
  intervalMinutes = 15,           -- How often to advance through the sequence
}
```

The sequence engine picks a weather from the pool using the timeline chance + random roll at each interval.

### 4.3 Server-Side Runtime State

```lua
-- Per-zone runtime state (tracked by server, broadcast to clients)
zoneState[zoneId] = {
  currentWeather = "CLEAR",       -- Current active weather
  nextWeather = "CLOUDS",         -- Upcoming weather (for pre-loading on clients)
  timeUntilAdvance = 720,         -- Seconds until next sequence tick
  windSpeed = 8.5,                -- m/s
  windDirection = 180.0,          -- degrees
  lastUpdated = os.time(),
}
```

---

## 5. Weather Engine (Client)

### 5.1 Zone Detection

Runs every 500ms (configurable via `Config.tickRate`):

1. Get local player position via `GetEntityCoords(PlayerPedId())`
2. Iterate all enabled zones
3. For each zone, run point-in-polygon test (ray casting algorithm) in `modules/shared/math.lua`
4. If player is in multiple zones, compute distance from position to each polygon edge, pick the zone with the largest minimum edge distance (deepest inside)
5. If in no zones, use `Config.globalFallbackWeather`

**Performance:** Ray casting is O(n*m) where n = zones, m = average points per zone. At 500ms, even 50 zones with 10 points each is trivial.

### 5.2 Weather Transition

When `zoneState.currentWeather` changes for the player:

```lua
-- modules/client/engine.lua
SetWeatherTypeOvertimeNow(newWeather, transitionDuration)
```

The native handles all visual interpolation (cloud density, sky color, rain effects) over the specified duration. The engine tracks:
- `currentWeather` — what's displayed now
- `targetWeather` — where we're transitioning toward
- `transitionProgress` — 0.0 to 1.0 during fade

**Transition triggers:**
- Player enters a different zone
- Zone's sequence advances to a new weather
- Admin forces a zone's weather

### 5.3 Wind & Particles

Applied locally alongside weather type:
```lua
SetWindSpeed(windSpeed)
SetWindDirection(windDirection)
-- Rain/snow particles are automatically handled by weather type
```

---

## 6. Sequence Engine (Server)

### 6.1 Operation

Runs every `Config.sequenceInterval` milliseconds (default 60s):

1. Get current game time via `GetGameTimer()` or `os.time()`
2. For each enabled zone:
   - Look up the zone's assigned sequence preset
   - Find the matching timeline slot based on current hour
   - Roll against the slot's `chance` value
   - If roll passes, pick from zone's `weatherPool` (weighted toward timeline slot's weather)
   - If roll fails, advance to next timeline slot
3. Update `zoneState[zoneId]`
4. Flag zones where weather changed for broadcast

### 6.2 Pre-set Sequence Presets

| Preset ID | Label | Typical pattern |
|-----------|-------|-----------------|
| `urban_coastal` | Urban Coastal | Morning fog → clear → afternoon clouds → evening overcast → night clear |
| `desert_inland` | Desert Inland | Clear mornings → extreme sun midday → evening dust → cold clear nights |
| `mountain_alpine` | Mountain Alpine | Foggy dawn → clouds midday → afternoon storms → snow possible at night |
| `rural_farmland` | Rural Farmland | Morning mist → clear day → evening overcast → scattered showers |
| `tropical_coast` | Tropical Coast | Warm clear → afternoon heat → evening thunderstorms → humid night |

Servers can add custom presets in `sequences.json`.

---

## 7. Server Sync

### 7.1 Broadcast Protocol

Every `Config.syncBroadcastInterval` ms (default 10s), the server sends to all clients:

```lua
TriggerClientEvent('dynamic_weather:sync', -1, zoneStates)
```

### 7.2 Player Join Sync

On `playerJoining`, send the current zone states immediately to the new player so they don't wait for the next broadcast cycle.

### 7.3 Zone Update (Admin Edit)

When an admin saves zones via the editor:
1. Client sends zones to server via NUI callback
2. Server validates structure (minimum 3 points, valid weather types, etc.)
3. Server writes to `shared/data/zones.json`
4. Server reloads zone definitions into memory
5. Server triggers immediate sync broadcast

---

## 8. UI — Admin Zone Editor

### 8.1 Technology

- **Framework:** React 19 + Vite
- **Map:** Leaflet 1.9 + react-leaflet 5 with L.CRS.Simple
- **Tiles:** `https://s.rsg.sc/sc/images/games/GTAV/map/game/{z}/{x}/{y}.jpg`
- **Coordinate mapping:** Same projection as cortex_mdt
- **Styles:** Custom dark theme matching cortex_mdt aesthetic
- **Communication:** NUI callbacks via `fetch()` to `GetParentResourceName()`

### 8.2 Coordinate System

```js
// constants.js
const OX_TILE_URL = 'https://s.rsg.sc/sc/images/games/GTAV/map/game/{z}/{x}/{y}.jpg'
const OX_MAP_CENTER = [-119.43, 58.84]
const OX_LAT_PR_100 = 1.421
const OX_MIN_ZOOM = 2
const OX_MAX_ZOOM = 7
const OX_STARTUP_ZOOM = 5

const OX_MAP_BOUNDS = L.latLngBounds(
  L.latLng(0.0, 128.0),      // SW
  L.latLng(-192.0, 0.0)      // NE
)

const gameToMap = (x, y) => [
  OX_MAP_CENTER[0] + (OX_LAT_PR_100 / 100) * y,
  OX_MAP_CENTER[1] + (OX_LAT_PR_100 / 100) * x,
]

const mapToGame = (lat, lng) => ({
  x: (lng - OX_MAP_CENTER[1]) / (OX_LAT_PR_100 / 100),
  y: (lat - OX_MAP_CENTER[0]) / (OX_LAT_PR_100 / 100),
})
```

### 8.3 Layout

```
┌──────────────────────────────────────────────────────┐
│  Toolbar: [Add Zone] [Save] [Load] [Zoom In/Out] [X] │  ← 48px
├────────────┬─────────────────────────────────────────┤
│  Sidebar   │  Leaflet Map (L.CRS.Simple)             │
│  ───────── │                                         │
│  Zone List │  Polygon overlays with editable vertices │
│  (scroll)  │  Drag vertices / pan map / zoom          │
│            │                                         │
│  Selected  │  Tiles: CDN GTA V map tiles             │
│  Zone      │  Bounds: calibrated to world coords      │
│  Config    │                                         │
│  Panel     │                                         │
└────────────┴─────────────────────────────────────────┘
```

**Sidebar width:** `320px` (scaled by `--es-ui-scale`)

### 8.4 Editor Features

- **Polygon drawing:** Click "Add Zone" → click points on map → close polygon → zone created
- **Vertex editing:** Drag existing vertices to reshape zones
- **Delete zone:** Click delete button on zone list item (with confirmation)
- **Zone config:** Edit label, sequence preset, weather pool checkboxes, transition duration
- **Points panel:** Table showing all vertex coordinates with manual edit fields
- **Save/Load:** Save to server file, load loads from server (with unsaved changes warning)
- **Calibration:** Two-point calibration for verifying coordinate accuracy

### 8.5 Visual States

Each zone polygon on the map reflects its current weather:
- **Clear/Sunny:** Yellow/amber border with low-opacity fill
- **Clouds/Overcast:** Gray border with light gray fill
- **Rain:** Blue border with medium-opacity fill
- **Thunder:** Blue-purple animated border
- **Fog:** White border with blurry-style fill
- **Selected:** Cyan accent border, highlighted

### 8.6 Color Palette

```css
:root {
  --dw-bg: #060809;
  --dw-surface: rgba(12,14,18,0.92);
  --dw-accent: #00e5bf;
  --dw-accent-dim: rgba(0,229,191,0.1);
  --dw-text: rgba(220,225,235,0.94);
  --dw-text-dim: rgba(160,170,190,0.72);
  --dw-line: rgba(255,255,255,0.06);
  --dw-radius: calc(3px * var(--es-ui-scale));
  --ease: cubic-bezier(0.16, 1, 0.3, 1);
  --font-mono: "Share Tech Mono", "Consolas", monospace;
  --font-ui: "Outfit", sans-serif;
}
```

### 8.7 Admin Access

Editor is opened via `/weathereditor` command. Requires ACE permission `es_admin.weather.editor` (or specified in config). Only one player can have the editor open at a time (server-side guard).

---

## 9. Exports

| Export | Side | Arguments | Returns | Description |
|--------|------|-----------|---------|-------------|
| `getPlayerWeather` | Client | `src` | `{zone, weather, target, progress}` | Current weather state for player |
| `getZoneAt` | Client | `x, y` | `zone \| nil` | Which zone a world position is in |
| `getAllZones` | Client | — | `zones[]` | All zone definitions |
| `setZoneWeather` | Server | `zoneId, weatherType` | `true \| nil, err` | Force a zone to a specific weather |
| `reloadZones` | Server | — | `true` | Reload zone definitions from file |
| `isEditorOpen` | Client | `src` | `boolean` | Whether the admin editor is open |

---

## 10. Commands

| Command | Args | Permission | Description |
|---------|------|------------|-------------|
| `/weathereditor` | — | `es_admin.weather.editor` | Open the zone editor UI |
| `/weather reload` | — | `es_admin.weather.reload` | Reload zones from files |
| `/weather info` | — | Any player | Show current zone + weather info |

---

## 11. Config (`shared/config.lua`)

```lua
Config = {
  -- Engine
  tickRate = 500,                  -- Zone detection interval (ms)
  defaultTransitionDuration = 15,  -- Default fade time (seconds)
  globalFallbackWeather = 'CLEAR', -- Weather when not in any zone
  excludedWeatherTypes = {},       -- Globally disallowed weather (e.g. snow)

  -- Sequence Engine
  sequenceInterval = 60000,        -- How often sequence advances (ms)
  sequenceRandomWeight = 0.3,      -- Random factor in weather selection

  -- Sync
  syncBroadcastInterval = 10000,   -- How often server pushes weather (ms)
  syncOnJoinImmediate = true,      -- Send state immediately on player join

  -- Editor
  editorRequiresAce = 'es_admin.weather.editor',
  editorAllowMultipleUsers = false, -- Only one admin at a time

  -- Debug
  debugPolygons = false,           -- Draw zone boundaries in-world
  debugLog = false,                -- Verbose console logging
}
```

---

## 12. es_admin Integration (Future)

When es_admin is ready to integrate:

```lua
-- In es_admin shared/actions.lua
{
  id = 'weather.editor',
  label = 'Weather Zones',
  description = 'Open the dynamic weather zone editor',
  category = 'world',
  icon = 'cloud',
}

-- In es_admin shared/config.lua
['weather.editor'] = 'es_admin.weather.editor',
['weather.reload'] = 'es_admin.weather.reload',
['weather.set']    = 'es_admin.weather.set',
```

The editor can be launched from es_admin's world panel using `TriggerEvent('dynamic_weather:openEditor')`.

---

## 13. Implementation Order

1. **Phase 1: Scaffold** — fxmanifest.lua, init.lua, config, module placeholders, web project skeleton
2. **Phase 2: Core Engine** — Zone detection, point-in-polygon, per-player weather application, transitions
3. **Phase 3: Server Sync** — Sequence engine, broadcast protocol, player join sync, commands
4. **Phase 4: Storage** — Zone CRUD, file I/O, validation, reload
5. **Phase 5: UI** — React + Vite + Leaflet app, map, sidebar, zone editor, toolbar, save/load
6. **Phase 6: Integration** — Exports, es_admin hooks, polish, testing

---

## 14. Technical Constraints

- **FiveM weather limitation:** GTA V can only display one weather type per player at a time. Per-zone weather is achieved by setting weather per-player (not per-frame region).
- **Zone crossing speed:** Vehicles at high speed may cross zones faster than the 500ms tick. A 1-second debounce prevents rapid toggling.
- **Tile CDN dependency:** The map tiles are externally hosted. If the CDN is down, the editor map will show grey tiles but zone polygons will still render.
- **No database:** All persistence is file-based. Large zone counts (50+) may benefit from future DB migration.
- **Build tool:** Must use `bun install` and `bun run build` per AGENTS.md requirements.
