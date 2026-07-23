local resourceName = GetCurrentResourceName()

local function weatherData()
    return lib.require('modules.server.weather_data')
end

local function normalizeSeason(raw)
    if type(raw) ~= 'string' or #raw == 0 then return nil end
    local s = string.lower(raw)
    if s == 'fall' then s = 'autumn' end
    if not (Config.validSeasons and Config.validSeasons[s]) then
        return nil
    end
    return s
end

local function ensureGlobalDefaults()
    if GlobalState.dynamic_weather_season == nil then
        GlobalState.dynamic_weather_season = normalizeSeason(Config.defaultSeason or 'summer') or 'summer'
    end
    if GlobalState.dynamic_weather_blackout == nil then
        GlobalState.dynamic_weather_blackout = false
    end
    if GlobalState.dynamic_weather_flood_active == nil then
        GlobalState.dynamic_weather_flood_active = false
    end
end

AddEventHandler('onResourceStart', function(name)
    if name ~= resourceName then return end
    ensureGlobalDefaults()
end)

function getSeason()
    ensureGlobalDefaults()
    return GlobalState.dynamic_weather_season
end

---@param season string spring|summer|autumn|fall|winter
---@return boolean ok, string|nil err
function setSeason(season)
    local s = normalizeSeason(season)
    if not s then
        return false, 'invalid season'
    end
    GlobalState.dynamic_weather_season = s
    return true
end

function getBlackout()
    ensureGlobalDefaults()
    return GlobalState.dynamic_weather_blackout == true
end

function setBlackout(enabled)
    ensureGlobalDefaults()
    local on = enabled == true
    GlobalState.dynamic_weather_blackout = on
    TriggerClientEvent('dynamic_weather:applyBlackout', -1, on)
    return true
end

function clearBlackout()
    return setBlackout(false)
end

function getZoneWeather(zoneId)
    if type(zoneId) ~= 'string' or #zoneId == 0 then return nil end
    local storage = lib.require('modules.server.storage')
    local states = storage.getZoneStates()
    return states[zoneId]
end

function getAllZoneStates()
    local storage = lib.require('modules.server.storage')
    return storage.getZoneStates()
end

function forceAdvanceZoneWeather(zoneId)
    if type(zoneId) ~= 'string' or #zoneId == 0 then return false, 'invalid zone' end
    local sequence = lib.require('modules.server.sequence')
    local ok, newWeather = sequence.forceAdvance(zoneId)
    if not ok then
        return false, 'zone not found'
    end
    return true, newWeather
end

---@param targetServerId number
---@param weatherType string GTA weather name
function forceWeatherFastForPlayer(targetServerId, weatherType)
    if type(targetServerId) ~= 'number' or targetServerId <= 0 then
        return false, 'invalid player'
    end
    if type(weatherType) ~= 'string' or #weatherType == 0 then
        return false, 'invalid weather'
    end
    if not GetPlayerName(targetServerId) then
        return false, 'player not online'
    end
    TriggerClientEvent('dynamic_weather:clientForceWeather', targetServerId, string.upper(weatherType))
    return true
end

function clearForceWeatherFastForPlayer(targetServerId)
    if type(targetServerId) ~= 'number' or targetServerId <= 0 then
        return false, 'invalid player'
    end
    if not GetPlayerName(targetServerId) then
        return false, 'player not online'
    end
    TriggerClientEvent('dynamic_weather:clientClearForceWeather', targetServerId)
    return true
end

function forceWeatherFastForAll(weatherType)
    if type(weatherType) ~= 'string' or #weatherType == 0 then
        return false, 'invalid weather'
    end
    TriggerClientEvent('dynamic_weather:clientForceWeather', -1, string.upper(weatherType))
    return true
end

function clearForceWeatherFastForAll()
    TriggerClientEvent('dynamic_weather:clientClearForceWeather', -1)
    return true
end

function syncWeatherToPlayer(targetServerId)
    if type(targetServerId) ~= 'number' or targetServerId <= 0 then
        return false, 'invalid player'
    end
    if not GetPlayerName(targetServerId) then
        return false, 'player not online'
    end
    local sync = lib.require('modules.server.sync')
    sync.sendToPlayer(targetServerId)
    return true
end

function GetCurrentWeather()
    return weatherData().getCurrentWeather()
end

function GetActiveWeatherZones()
    return weatherData().getActiveWeatherZones()
end

function GetWeatherAtCoords(x, y)
    return weatherData().getWeatherAtCoords(x, y)
end

function GetForecast()
    return weatherData().getForecast()
end

function GetForecastForRegion(regionId)
    return weatherData().getForecastForRegion(regionId)
end

function GetActiveAlerts()
    return weatherData().getActiveAlerts()
end

function GetRoadConditionAtCoords(x, y)
    return weatherData().getRoadConditionAtCoords(x, y)
end

function CreateWeatherAlert(data)
    return weatherData().createWeatherAlert(data)
end

function ClearWeatherAlert(alertId)
    return weatherData().clearWeatherAlert(alertId)
end

function CreateDispatchIncident(data)
    return weatherData().createDispatchIncident(data)
end

function IsFloodEventActive()
    return lib.require('modules.server.flood_event').isActive() == true
end

function GetFloodEventState()
    return lib.require('modules.server.flood_event').getState()
end

---@param actor string|nil
function EndFloodEvent(actor)
    return lib.require('modules.server.flood_event').endEvent(actor)
end

---@param actor string|nil
function StartFloodEvent(actor)
    return lib.require('modules.server.flood_event').startRandomEvent(actor or 'export')
end

function IsHurricaneActive()
    return lib.require('modules.server.hurricane').isActive() == true
end

function GetHurricaneState()
    return lib.require('modules.server.hurricane').getState()
end

function StartHurricane(opts, actor)
    return lib.require('modules.server.hurricane').startHurricane(opts, actor or 'export')
end

function EndHurricane(actor)
    return lib.require('modules.server.hurricane').endHurricane(actor or 'export')
end
