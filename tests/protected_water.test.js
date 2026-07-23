const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('protected water helper exposes required zone functions', () => {
  const helper = read('modules/shared/protected_water.lua');

  for (const name of [
    'IsPointInProtectedWater',
    'GetProtectedWaterZoneAt',
    'GetDistanceToProtectedWaterZone',
    'DoesRadiusOverlapProtectedWater',
    'ShouldSkipWaterModification',
    'ClampModifyWaterRadiusNearProtectedZones',
    'SafeModifyWater',
    'RestoreProtectedWaterBodies',
    'GetProtectedRestoreHeight',
    'DebugDrawProtectedWaterBodies',
  ]) {
    assert.match(helper, new RegExp(`function protectedWater\\.${name}\\b`));
  }
});

test('protected water bodies are configured and shipped as resource data', () => {
  const config = read('shared/config.lua');
  const manifest = read('fxmanifest.lua');
  const data = JSON.parse(read('shared/data/protected_water.json'));

  assert.match(config, /Config\.ProtectedWater\s*=/);
  assert.match(config, /restoreAfterApply\s*=\s*true/);
  assert.match(manifest, /shared\/data\/protected_water\.json/);
  assert.ok(Array.isArray(data.bodies));
  assert.ok(data.bodies.length > 0);
});

test('sea level apply path skips and restores protected quads', () => {
  const seaLevel = read('modules/client/sea_level.lua');

  assert.match(seaLevel, /GetWaterQuadBounds/);
  assert.match(seaLevel, /protectedWater\.isQuadProtected/);
  assert.match(seaLevel, /protectedWater\.RestoreProtectedWaterBodies\(\)/);
  assert.match(seaLevel, /protectedWater\.CaptureProtectedRestoreHeights\(\)/);
  assert.match(seaLevel, /setAllLevels\(level, mode\)/);
  assert.match(seaLevel, /applyEffectiveFloodLevel\(effectiveFloodLevel, globalFloodMode, false\)/);
  assert.match(seaLevel, /floodignoredebug/);
});

test('flood command treats numeric argument as offset', () => {
  const commands = read('modules/server/commands.lua');
  const serverSeaLevel = read('modules/server/sea_level.lua');
  const config = read('shared/config.lua');

  assert.match(commands, /RegisterCommand\('flood'/);
  assert.match(commands, /height = tonumber\(args\[1\]\)/);
  assert.match(commands, /seaLevel\.flood\(getActorName\(src\), 'offset', height\)/);
  assert.match(serverSeaLevel, /function seaLevel\.flood\(actor, mode, level, profile\)/);
  assert.match(config, /floodMode = 'offset'/);
  assert.match(config, /floodHeight = 2\.0/);
  assert.match(config, /floodIncreaseRate = 0\.02/);
});

test('sequence flood event forces thunder and restores its snapshot', () => {
  const floodEvent = read('modules/server/flood_event.lua');
  const config = read('shared/config.lua');

  assert.match(config, /thunderWeather = 'THUNDER'/);
  assert.match(floodEvent, /applyStormToAllZones/);
  assert.match(floodEvent, /currentWeather = w/);
  assert.match(floodEvent, /restoreSnapshot/);
  assert.match(floodEvent, /return cfg\(\)\.thunderWeather or 'THUNDER'/);
});

test('weather editor draws and saves flood-ignore zones', () => {
  const editor = read('web/src/Editor.jsx');
  const map = read('web/src/Map.jsx');
  const floodPanel = read('web/src/FloodPanel.jsx');
  const sidebar = read('web/src/Sidebar.jsx');
  const nui = read('modules/client/nui.lua');
  const commands = read('modules/server/commands.lua');
  const storage = read('modules/server/storage.lua');

  assert.match(editor, /floodIgnoreZones/);
  assert.match(editor, /dw_saveFloodIgnoreZones/);
  assert.match(map, /FloodIgnorePolygon/);
  assert.match(floodPanel, /Flood Ignore Zone controls/);
  assert.match(sidebar, /Flood Ignore Zone/);
  assert.match(nui, /dw_saveFloodIgnoreZones/);
  assert.match(commands, /saveFloodIgnoreZones/);
  assert.match(storage, /flood_ignore_zones\.json/);
});
