local hurricane = {}
local lastStateRequestBySource = {}

local active = false
local state = {
    active = false,
    intensity = 0,
    windDirection = 0.0,
    windSpeed = 0.0,
    lightningMultiplier = 1.0,
}
local snapshot = nil

local function cfg()
    return Config.Hurricane or {}
end

local function clampIntensity(value)
    local n = tonumber(value) or tonumber(cfg().defaultIntensity) or 4
    if n < 1 then return 1 end
    if n > 5 then return 5 end
    return math.floor(n)
end

local function tableValueByIntensity(name, intensity, fallback)
    local t = cfg()[name] or {}
    return tonumber(t[intensity]) or fallback
end

local function normalizeDirection(value)
    local n = tonumber(value)
    if not n then
        return math.random(0, 359) + 0.0
    end
    n = n % 360.0
    if n < 0.0 then n = n + 360.0 end
    return n
end

local function copyStateForClient()
    return {
        active = state.active == true,
        intensity = state.intensity or 0,
        windDirection = state.windDirection or 0.0,
        windSpeed = state.windSpeed or 0.0,
        lightningMultiplier = state.lightningMultiplier or 1.0,
        startedAt = state.startedAt,
    }
end

local function publishState(target)
    local payload = copyStateForClient()
    GlobalState.dynamic_weather_hurricane = payload
    TriggerClientEvent('dynamic_weather:hurricane:set', target or -1, payload)
end

local function takeSnapshot()
    local storage = lib.require('modules.server.storage')
    local states = storage.getZoneStates()
    local snap = {}

    for zoneId, zoneState in pairs(states or {}) do
        snap[zoneId] = {
            currentWeather = zoneState.currentWeather,
            nextWeather = zoneState.nextWeather,
            windSpeed = zoneState.windSpeed,
            windDirection = zoneState.windDirection,
            severity = zoneState.severity,
            timeUntilAdvance = zoneState.timeUntilAdvance,
            lastUpdated = zoneState.lastUpdated,
        }
    end

    return snap
end

local function applyHurricaneWeather()
    local storage = lib.require('modules.server.storage')
    local weatherData = lib.require('modules.server.weather_data')
    local zones = storage.getZones()
    local states = storage.getZoneStates()
    local currentTime = os.time()
    local weatherType = cfg().weatherType or 'THUNDER'
    local severity = tableValueByIntensity('severityByIntensity', state.intensity, 5)

    for zoneId, zone in pairs(zones or {}) do
        if zone.enabled ~= false then
            local prev = states[zoneId] or {}
            local zoneState = {
                currentWeather = weatherType,
                nextWeather = weatherType,
                windSpeed = state.windSpeed,
                windDirection = state.windDirection,
                severity = severity,
                lastUpdated = currentTime,
            }

            if prev.timeUntilAdvance ~= nil then
                zoneState.timeUntilAdvance = prev.timeUntilAdvance
            end

            storage.updateZoneState(zoneId, zoneState)
            TriggerClientEvent('dynamic_weather:zoneUpdate', -1, zoneId, zoneState)
            weatherData.notifyStateUpdated(zoneId, zoneState)
        end
    end
end

local function restoreSnapshot()
    if not snapshot then return end

    local storage = lib.require('modules.server.storage')
    local weatherData = lib.require('modules.server.weather_data')
    local zones = storage.getZones()
    local currentTime = os.time()

    for zoneId, prev in pairs(snapshot) do
        local zone = zones[zoneId]
        if zone and zone.enabled ~= false then
            local zoneState = {
                currentWeather = prev.currentWeather,
                nextWeather = prev.nextWeather or prev.currentWeather,
                windSpeed = prev.windSpeed or 5.0,
                windDirection = prev.windDirection or 0.0,
                severity = prev.severity,
                lastUpdated = currentTime,
            }

            if prev.timeUntilAdvance ~= nil then
                zoneState.timeUntilAdvance = prev.timeUntilAdvance
            end

            storage.updateZoneState(zoneId, zoneState)
            TriggerClientEvent('dynamic_weather:zoneUpdate', -1, zoneId, zoneState)
            weatherData.notifyStateUpdated(zoneId, zoneState)
        end
    end

    snapshot = nil
end

function hurricane.start()
    if GlobalState.dynamic_weather_hurricane == nil then
        GlobalState.dynamic_weather_hurricane = copyStateForClient()
    end
end

function hurricane.stop()
    if active then
        hurricane.endHurricane('resource stop')
    else
        publishState(-1)
    end
end

function hurricane.isActive()
    return active == true
end

function hurricane.getState()
    return copyStateForClient()
end

function hurricane.sendToPlayer(src)
    publishState(src)
end

function hurricane.startHurricane(opts, actor)
    if cfg().enabled == false then
        return false, 'hurricane disabled'
    end

    opts = type(opts) == 'table' and opts or {}
    local intensity = clampIntensity(opts.intensity)
    local windSpeed = tonumber(opts.windSpeed) or tableValueByIntensity('windSpeedByIntensity', intensity, 32.0)
    local windDirection = normalizeDirection(opts.windDirection)
    local lightningMultiplier = tonumber(opts.lightningMultiplier) or tableValueByIntensity('lightningMultiplierByIntensity', intensity, 2.4)

    if not active or not snapshot then
        snapshot = takeSnapshot()
    end

    active = true
    state = {
        active = true,
        intensity = intensity,
        windDirection = windDirection,
        windSpeed = windSpeed,
        lightningMultiplier = lightningMultiplier,
        startedAt = os.time(),
    }

    applyHurricaneWeather()
    publishState(-1)
    TriggerEvent('dynamic_weather:hurricaneStarted', copyStateForClient())

    print(('^3[weather] Hurricane started intensity=%d wind=%.1f direction=%.1f actor=%s^0'):format(
        intensity,
        windSpeed,
        windDirection,
        actor or 'unknown'
    ))

    return true, copyStateForClient()
end

function hurricane.endHurricane(actor)
    if not active then
        return false, 'not active'
    end

    active = false
    state.active = false
    state.intensity = 0
    publishState(-1)
    restoreSnapshot()
    TriggerEvent('dynamic_weather:hurricaneEnded', actor or 'unknown')
    print(('^2[weather] Hurricane ended actor=%s^0'):format(actor or 'unknown'))
    return true, copyStateForClient()
end

RegisterNetEvent('dynamic_weather:hurricane:requestState', function()
    local src = source
    local now = GetGameTimer()
    if now - (lastStateRequestBySource[src] or 0) < 1000 then return end
    lastStateRequestBySource[src] = now
    hurricane.sendToPlayer(src)
end)

AddEventHandler('playerDropped', function()
    lastStateRequestBySource[source] = nil
end)

return hurricane
