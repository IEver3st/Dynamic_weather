local resourceName = GetCurrentResourceName()

local function startEngine()
    local engine = lib.require('modules.client.engine')
    if engine then engine.start() end
end

local function startStormProps()
    local stormProps = lib.require('modules.client.storm_props')
    if stormProps then stormProps.start() end
end

local function startSeaLevel()
    local seaLevel = lib.require('modules.client.sea_level')
    if seaLevel then seaLevel.start() end
end

local function startLightningPole()
    local lightningPole = lib.require('modules.client.lightning_pole')
    if lightningPole then lightningPole.start() end
end

local function startSync()
    local sync = lib.require('modules.client.sync')
    if sync then sync.start() end
end

AddEventHandler('onClientResourceStart', function(name)
    if name ~= resourceName then return end
    startSync()
    Wait(500)
    startEngine()
    startSeaLevel()
    startStormProps()
    startLightningPole()
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= resourceName then return end
    local engine = lib.require('modules.client.engine')
    if engine then engine.stop() end
    local seaLevel = lib.require('modules.client.sea_level')
    if seaLevel then seaLevel.stop() end
    local stormProps = lib.require('modules.client.storm_props')
    if stormProps then stormProps.stop() end
    local lightningPole = lib.require('modules.client.lightning_pole')
    if lightningPole then lightningPole.stop() end
    local sync = lib.require('modules.client.sync')
    if sync then sync.stop() end
end)

function getPlayerWeather(src)
    local engine = lib.require('modules.client.engine')
    if engine then return engine.getState() end
end

function getZoneAt(x, y)
    local engine = lib.require('modules.client.engine')
    if engine then return engine.findPlayerZone(x, y) end
end

function getAllZones()
    local zones = lib.require('modules.client.zones')
    if zones then return zones.getAllZones() end
end

function isEditorOpen()
    local nui = lib.require('modules.client.nui')
    if nui then return nui.isOpen() end
    return false
end

function reloadZones()
    TriggerServerEvent('dynamic_weather:requestSync')
    return true
end

function getCurrentWeather()
    local engine = lib.require('modules.client.engine')
    if engine and engine.getCurrentWeather then
        return engine.getCurrentWeather()
    end
    return Config.globalFallbackWeather
end

---Alias: effective GTA weather string (includes client force lock).
function getWeatherForceFast()
    return getCurrentWeather()
end

function getForcedWeather()
    local engine = lib.require('modules.client.engine')
    if engine and engine.getForcedWeather then
        return engine.getForcedWeather()
    end
end

function isWeatherForceLocked()
    local engine = lib.require('modules.client.engine')
    if engine and engine.isWeatherForceLocked then
        return engine.isWeatherForceLocked()
    end
    return false
end

function forceWeatherFast(weatherType)
    local engine = lib.require('modules.client.engine')
    if engine and engine.forceWeatherFast then
        return engine.forceWeatherFast(weatherType)
    end
    return false
end

function clearForceWeatherFast()
    local engine = lib.require('modules.client.engine')
    if engine and engine.clearForceWeatherFast then
        return engine.clearForceWeatherFast()
    end
    return false
end

function getSeason()
    local s = GlobalState.dynamic_weather_season
    if type(s) == 'string' and #s > 0 then
        return s
    end
    return Config.defaultSeason or 'summer'
end

function getBlackout()
    return GlobalState.dynamic_weather_blackout == true
end

---@return number|nil distance, string|nil nearestZoneId, string|nil nearestZoneLabel
function getNearestZoneEdgeDistance(x, y)
    local engine = lib.require('modules.client.engine')
    if engine and engine.nearestZoneEdgeDistance then
        return engine.nearestZoneEdgeDistance(x, y)
    end
end

lib.require('modules.client.hud_integration')
