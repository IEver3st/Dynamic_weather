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

test('protected water bodies are configurable with tune notes', () => {
  const config = read('shared/config.lua');

  assert.match(config, /Config\.ProtectedWaterBodies\s*=/);
  assert.match(config, /Draw and tune protected bodies in the weather editor/);
  assert.doesNotMatch(config, /minX\s*=\s*800\.0/);
});

test('sea level apply path skips and restores protected quads', () => {
  const seaLevel = read('modules/client/sea_level.lua');

  assert.match(seaLevel, /GetWaterQuadBounds/);
  assert.match(seaLevel, /protectedWater\.isQuadProtected/);
  assert.match(seaLevel, /protectedWater\.GetProtectedRestoreHeight/);
  assert.match(seaLevel, /RestoreProtectedWaterBodies\(\)/);
  assert.match(seaLevel, /safeSetWaterQuadLevel/);
  assert.match(seaLevel, /setAllLevels\(nextLevel, mode\)/);
  assert.doesNotMatch(seaLevel, /applyFloodCells/);
  assert.match(seaLevel, /flooddebugwater/);
  assert.match(seaLevel, /waterheight/);
  assert.match(seaLevel, /protectedwaterdebug/);
  assert.match(seaLevel, /floodcellinfo/);
});

test('flood command treats numeric argument as offset', () => {
  const commands = read('modules/server/commands.lua');
  const serverSeaLevel = read('modules/server/sea_level.lua');
  const config = read('shared/config.lua');

  assert.match(commands, /RegisterCommand\('flood'/);
  assert.match(commands, /local mode = 'offset'/);
  assert.match(commands, /seaLevel\.flood\(getActorName\(src\), mode, height\)/);
  assert.match(serverSeaLevel, /function seaLevel\.flood\(actor, mode, height\)/);
  assert.match(config, /loadFloodWaterFile = false/);
  assert.match(config, /floodHeight = 2\.0/);
  assert.match(config, /floodIncreaseRate = 0\.02/);
  assert.doesNotMatch(config, /floodCellRadius/);
});

test('flood forces all weather zones to thunder', () => {
  const serverSeaLevel = read('modules/server/sea_level.lua');
  const floodEvent = read('modules/server/flood_event.lua');
  const config = read('shared/config.lua');

  assert.match(config, /floodForceThunder = true/);
  assert.match(serverSeaLevel, /applyThunderToAllZones/);
  assert.match(serverSeaLevel, /currentWeather = 'THUNDER'/);
  assert.match(serverSeaLevel, /restoreFloodWeather/);
  assert.match(floodEvent, /return 'THUNDER'/);
  assert.doesNotMatch(floodEvent, /math\.random\(1, 2\).*RAIN/);
});

test('weather editor can draw and save protected water bodies', () => {
  const editor = read('web/src/Editor.jsx');
  const map = read('web/src/Map.jsx');
  const inspector = read('web/src/ProtectedWaterInspector.jsx');
  const sidebar = read('web/src/Sidebar.jsx');
  const nui = read('modules/client/nui.lua');
  const commands = read('modules/server/commands.lua');
  const storage = read('modules/server/storage.lua');

  assert.match(editor, /protectedWaterBodies/);
  assert.match(editor, /protectedWaterBodiesForSave/);
  assert.match(editor, /dw_saveProtectedWater/);
  assert.match(editor, /Protected water zones/);
  assert.match(map, /ProtectionPolygon/);
  assert.doesNotMatch(inspector, /restoreHeight/);
  assert.match(inspector, /Auto lock/);
  assert.match(sidebar, /auto height lock/);
  assert.match(inspector, /restoreRadius/);
  assert.match(nui, /dw_saveProtectedWater/);
  assert.match(commands, /saveProtectedWater/);
  assert.match(storage, /protected_water\.json/);
});
