const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('flood ignore zones persist and sync through existing editor flow', () => {
  const manifest = read('fxmanifest.lua');
  const storage = read('modules/server/storage.lua');
  const commands = read('modules/server/commands.lua');
  const clientSync = read('modules/client/sync.lua');
  const nui = read('modules/client/nui.lua');

  assert.match(manifest, /shared\/data\/flood_ignore_zones\.json/);
  assert.match(storage, /floodIgnoreZones/);
  assert.match(storage, /loadFloodIgnoreZones/);
  assert.match(storage, /saveFloodIgnoreZones/);
  assert.match(commands, /floodIgnoreZones\s*=\s*storage\.getFloodIgnoreZones\(\)/);
  assert.match(commands, /dynamic_weather:server:saveFloodIgnoreZones/);
  assert.match(clientSync, /floodIgnoreZones/);
  assert.match(clientSync, /getFloodIgnoreZones/);
  assert.match(nui, /dw_saveFloodIgnoreZones/);
});

test('client sea level applies ignore multiplier to the local flood target', () => {
  const seaLevel = read('modules/client/sea_level.lua');

  assert.match(seaLevel, /globalFloodLevel/);
  assert.match(seaLevel, /effectiveFloodLevel/);
  assert.match(seaLevel, /floodZoneMultiplier/);
  assert.match(seaLevel, /calculateFloodZoneMultiplier/);
  assert.match(seaLevel, /local targetEffective = nextLevel \* floodZoneMultiplier/);
  assert.match(seaLevel, /activeIgnoreZoneName/);
  assert.match(seaLevel, /floodignoredebug/);
  assert.match(seaLevel, /DebugDrawFloodIgnoreZones/);
});

test('client sea level skips small ignored water quads and leaves huge flood quads to local multiplier', () => {
  const seaLevel = read('modules/client/sea_level.lua');
  const helper = read('modules/shared/flood_ignore_zones.lua');
  const config = read('shared/config.lua');

  assert.match(helper, /function floodIgnoreZones\.IsQuadIgnored\b/);
  assert.match(helper, /area <= maxArea/);
  assert.match(config, /floodIgnoreMaxQuadArea = 2500000\.0/);
  assert.match(seaLevel, /GetWaterQuadBounds/);
  assert.match(seaLevel, /floodIgnoreHelper\.IsQuadIgnored/);
  assert.match(seaLevel, /ignored=/);
});

test('Save persists weather zones and flood ignore zones together', () => {
  const editor = read('web/src/Editor.jsx');
  const saveBlock = editor.match(/const handleSave = useCallback\(async \(\) => \{[\s\S]*?\n  \}, \[[^\]]+\]\)/)?.[0] || '';

  assert.match(saveBlock, /await postNui\('dw_saveZones', \{ zones \}\)/);
  assert.match(saveBlock, /await postNui\('dw_saveFloodSettings', \{ floodSettings \}\)/);
  assert.match(saveBlock, /await postNui\('dw_saveFloodIgnoreZones', \{ floodIgnoreZones \}\)/);
  assert.doesNotMatch(saveBlock, /activeLayer/);
});

test('Flood page can create, edit, delete, and visualize ignore zones', () => {
  const editor = read('web/src/Editor.jsx');
  const floodPanel = read('web/src/FloodPanel.jsx');
  const map = read('web/src/Map.jsx');
  const sidebar = read('web/src/Sidebar.jsx');
  const app = read('web/src/App.jsx');

  assert.match(editor, /floodIgnoreZones/);
  assert.match(editor, /handleAddFloodIgnoreZone/);
  assert.match(editor, /dw_saveFloodIgnoreZones/);
  assert.match(floodPanel, /Flood Ignore Zone/);
  assert.match(floodPanel, /fadeDistance/);
  assert.match(map, /FloodIgnorePolygon/);
  assert.match(sidebar, /floodIgnoreZones/);
  assert.match(app, /floodIgnoreZones/);
});
