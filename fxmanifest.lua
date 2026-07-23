fx_version 'cerulean'
game 'gta5'
lua54 'yes'

dependency 'es_lib'

author 'Everest Studios'
description 'Cortex Dynamic Weather - Multi-zone weather system with seamless transitions'
version '1.0.0'

shared_scripts {
    '@es_lib/init.lua',
    'shared/config.lua',
    'shared/lang.lua',
}

client_scripts {
    'init.lua',
    'modules/client/sync.lua',
    'modules/client/zones.lua',
    'modules/client/engine.lua',
    'modules/client/global_state.lua',
    'modules/client/sea_level.lua',
    'modules/client/hurricane_debris.lua',
    'modules/client/storm_props.lua',
    'modules/client/lightning_pole.lua',
    'modules/client/debug_panel.lua',
    'modules/client/nui.lua',
}

server_scripts {
    'modules/server/storage.lua',
    'modules/server/sequence.lua',
    'modules/server/sync.lua',
    'modules/server/sea_level.lua',
    'modules/server/flood_event.lua',
    'modules/server/hurricane.lua',
    'modules/server/commands.lua',
    'modules/server/debug_callback.lua',
    'modules/server/main.lua',
    'modules/server/lightning_pole.lua',
    'modules/server/weather_data.lua',
    'modules/server/exports_extended.lua',
    'modules/server/hud_callback.lua',
}

ui_page 'web/dist/index.html'

files {
    'web/dist/index.html',
    'web/dist/assets/*',
    'flood.xml',
    'flood_calm.xml',
    'water_levels/*.xml',
    'shared/data/zones.json',
    'shared/data/sequences.json',
    'shared/data/flood_settings.json',
    'shared/data/flood_ignore_zones.json',
    'shared/data/protected_water.json',
    'modules/client/*.lua',
    'modules/server/*.lua',
    'modules/shared/*.lua',
}

exports {
    'getHudWeatherSnapshot',
    'getPlayerWeather',
    'getCurrentWeather',
    'getWeatherForceFast',
    'getForcedWeather',
    'isWeatherForceLocked',
    'forceWeatherFast',
    'clearForceWeatherFast',
    'getSeason',
    'getBlackout',
    'getNearestZoneEdgeDistance',
    'getZoneAt',
    'getAllZones',
    'isEditorOpen',
    'reloadZones',
    'isFloodEventActive',
    'getFloodEventState',
}

server_exports {
    'GetCurrentWeather',
    'GetActiveWeatherZones',
    'GetWeatherAtCoords',
    'GetForecast',
    'GetForecastForRegion',
    'GetActiveAlerts',
    'GetRoadConditionAtCoords',
    'CreateWeatherAlert',
    'ClearWeatherAlert',
    'setZoneWeather',
    'reloadZones',
    'getSeason',
    'setSeason',
    'getBlackout',
    'setBlackout',
    'clearBlackout',
    'getZoneWeather',
    'getAllZoneStates',
    'forceAdvanceZoneWeather',
    'forceWeatherFastForPlayer',
    'clearForceWeatherFastForPlayer',
    'forceWeatherFastForAll',
    'clearForceWeatherFastForAll',
    'syncWeatherToPlayer',
    'CreateDispatchIncident',
    'IsFloodEventActive',
    'GetFloodEventState',
    'EndFloodEvent',
    'StartFloodEvent',
    'IsHurricaneActive',
    'GetHurricaneState',
    'StartHurricane',
    'EndHurricane',
}
