---Random regional flood: storm weather in all zones, then sea flood. Snapshot restored on end.
local floodEvent = {}

local active = false
local phase ---@type 'storm'|'flooding'|nil
local startedAt ---@type integer|nil
local floodTriggeredAt ---@type integer|nil
local snapshot ---@type table<string, table>|nil

local function cfg()
    return Config.FloodEvent or {}
end

local function rollChance()
    local c = cfg()
    local flat = tonumber(c.chance)
    if flat then return math.max(0.0, math.min(1.0, flat)) end
    local lo = tonumber(c.chanceMin) or 0.05
    local hi = tonumber(c.chanceMax) or lo
    if hi < lo then lo, hi = hi, lo end
    return math.max(0.0, math.min(1.0, lo + math.random() * (hi - lo)))
end

local function pickStormWeather()
    return cfg().thunderWeather or 'THUNDER'
end

local function severityForWeather(w)
    w = type(w) == 'string' and string.upper(w) or 'RAIN'
    if w == 'THUNDER' then return 4 end
    return 3
end

local function takeSnapshot()
    local storage = lib.require('modules.server.storage')
    local states = storage.getZoneStates()
    local snap = {}
    for zoneId, state in pairs(states or {}) do
        snap[zoneId] = {
            currentWeather = state.currentWeather,
            nextWeather = state.nextWeather,
            windSpeed = state.windSpeed,
            windDirection = state.windDirection,
            severity = state.severity,
            timeUntilAdvance = state.timeUntilAdvance,
            lastUpdated = state.lastUpdated,
        }
    end
    return snap
end

local function applyStormToAllZones()
    local storage = lib.require('modules.server.storage')
    local zones = storage.getZones()
    local weatherData = lib.require('modules.server.weather_data')
    local currentTime = os.time()

    for zoneId, zone in pairs(zones or {}) do
        if zone.enabled ~= false then
            local prev = storage.getZoneStates()[zoneId] or {}
            local w = pickStormWeather()
            local state = {
                currentWeather = w,
                nextWeather = w,
                windSpeed = prev.windSpeed or 5.0,
                windDirection = prev.windDirection or 0.0,
                severity = severityForWeather(w),
                lastUpdated = currentTime,
            }
            if prev.timeUntilAdvance ~= nil then
                state.timeUntilAdvance = prev.timeUntilAdvance
            else
                local sequences = storage.getSequences()
                local seq = zone.sequence and sequences[zone.sequence]
                state.timeUntilAdvance = (seq and seq.intervalMinutes or 15) * 60
            end
            storage.updateZoneState(zoneId, state)
            TriggerClientEvent('dynamic_weather:zoneUpdate', -1, zoneId, state)
            weatherData.notifyStateUpdated(zoneId, state)
        end
    end
end

local function thunderConditionMet()
    local c = cfg()
    if c.requireThunder == false then return true end

    local storage = lib.require('modules.server.storage')
    local zones = storage.getZones()
    local states = storage.getZoneStates()
    local targetWeather = string.upper(c.thunderWeather or 'THUNDER')
    local enabledCount = 0
    local thunderCount = 0

    for zoneId, zone in pairs(zones or {}) do
        if zone.enabled ~= false then
            enabledCount = enabledCount + 1
            local state = states[zoneId] or {}
            local current = type(state.currentWeather) == 'string' and string.upper(state.currentWeather) or ''
            local nextWeather = type(state.nextWeather) == 'string' and string.upper(state.nextWeather) or ''
            if current == targetWeather or nextWeather == targetWeather then
                thunderCount = thunderCount + 1
            end
        end
    end

    if enabledCount == 0 then return false end
    if c.thunderCondition == 'all_zones' then
        return thunderCount == enabledCount
    end
    return thunderCount > 0
end

local function restoreSnapshot()
    if not snapshot then return end
    local storage = lib.require('modules.server.storage')
    local weatherData = lib.require('modules.server.weather_data')
    local currentTime = os.time()

    for zoneId, prev in pairs(snapshot) do
        local zone = storage.getZones()[zoneId]
        if zone and zone.enabled ~= false then
            local state = {
                currentWeather = prev.currentWeather,
                nextWeather = prev.nextWeather or prev.currentWeather,
                windSpeed = prev.windSpeed or 5.0,
                windDirection = prev.windDirection or 0.0,
                severity = prev.severity,
                lastUpdated = currentTime,
            }
            if prev.timeUntilAdvance ~= nil then
                state.timeUntilAdvance = prev.timeUntilAdvance
            end
            storage.updateZoneState(zoneId, state)
            TriggerClientEvent('dynamic_weather:zoneUpdate', -1, zoneId, state)
            weatherData.notifyStateUpdated(zoneId, state)
        end
    end

    snapshot = nil
end

local function setGlobalActive(on)
    GlobalState.dynamic_weather_flood_active = on == true
    if on then
        GlobalState.dynamic_weather_flood_phase = phase or 'storm'
        GlobalState.dynamic_weather_flood_started_at = startedAt
    else
        GlobalState.dynamic_weather_flood_phase = nil
        GlobalState.dynamic_weather_flood_started_at = nil
    end
end

local function maybeDispatch()
    local c = cfg()
    if c.autoDispatch == false then return end
    local wd = lib.require('modules.server.weather_data')
    local dc = c.dispatchCoords
    local coords = nil
    if type(dc) == 'table' and tonumber(dc.x) and tonumber(dc.y) then
        coords = vector3(tonumber(dc.x), tonumber(dc.y), tonumber(dc.z) or 30.0)
    else
        coords = vector3(-200.0, -900.0, 30.0)
    end
    wd.createDispatchIncident({
        type = c.dispatchType or 'WEATHER_FLOOD',
        title = c.dispatchTitle or 'Coastal flooding emergency',
        message = c.dispatchMessage or 'Severe coastal flooding in progress. Avoid low-lying areas.',
        coords = coords,
        severity = tonumber(c.dispatchSeverity) or 5,
        weather = 'THUNDER',
    })
end

local function fireStartHook()
    local name = cfg().serverEventOnStart
    if type(name) == 'string' and #name > 0 then
        TriggerEvent(name, floodEvent.getState())
    end
    TriggerEvent('dynamic_weather:floodEventStarted', floodEvent.getState())
end

local function fireEndHook(reason)
    local name = cfg().serverEventOnEnd
    if type(name) == 'string' and #name > 0 then
        TriggerEvent(name, reason, floodEvent.getState())
    end
    TriggerEvent('dynamic_weather:floodEventEnded', reason, floodEvent.getState())
end

function floodEvent.isActive()
    return active == true
end

function floodEvent.getPhase()
    return phase
end

---Used by sequence engine: freeze random weather advances while a scripted flood runs.
function floodEvent.blocksSequenceAdvance()
    return active == true
end

function floodEvent.getState()
    return {
        active = active,
        phase = phase,
        startedAt = startedAt,
        floodTriggeredAt = floodTriggeredAt,
    }
end

function floodEvent.maybeRoll()
    if active then return end
    local c = cfg()
    if c.enabled == false then return end

    local sea = lib.require('modules.server.sea_level')
    if not sea.isEnabled() then return end
    if not thunderConditionMet() then return end

    if math.random() >= rollChance() then return end

    floodEvent.startRandomEvent('sequence_roll')
end

---@param actor string|nil
function floodEvent.startRandomEvent(actor)
    if active then return false, 'already active' end
    local c = cfg()
    if c.enabled == false then return false, 'disabled' end

    local sea = lib.require('modules.server.sea_level')
    if not sea.isEnabled() then return false, 'sea level disabled' end

    snapshot = takeSnapshot()
    active = true
    phase = 'storm'
    startedAt = os.time()
    floodTriggeredAt = nil
    setGlobalActive(true)

    applyStormToAllZones()
    maybeDispatch()
    fireStartHook()

    if Config.debugLog then
        print(('^3[weather] Flood event started (%s) — storm phase, flood in %ds^0'):format(
            actor or 'unknown',
            math.floor(tonumber(cfg().stormLeadSeconds) or 45)))
    end

    local leadMs = math.floor((tonumber(cfg().stormLeadSeconds) or 45) * 1000)
    if leadMs < 0 then leadMs = 0 end

    CreateThread(function()
        Wait(leadMs)
        if not active then return end
        local ok, res = sea.flood(actor or 'flood_event', nil)
        if not active then return end
        if not ok then
            if Config.debugLog then
                print(('^1[weather] Flood event sea flood failed: %s^0'):format(tostring(res)))
            end
        else
            phase = 'flooding'
            floodTriggeredAt = os.time()
            setGlobalActive(true)
        end
    end)

    return true
end

---@param actor string|nil
function floodEvent.endEvent(actor)
    if not active then return false, 'not active' end

    active = false
    phase = nil
    startedAt = nil
    floodTriggeredAt = nil
    setGlobalActive(false)

    local sea = lib.require('modules.server.sea_level')
    sea.reset(actor or 'flood_event_end')

    restoreSnapshot()

    fireEndHook('ended')

    if Config.debugLog then
        print(('^2[weather] Flood event ended (%s)^0'):format(actor or 'unknown'))
    end

    return true
end

function floodEvent.onResourceStop()
    if not active then return end
    active = false
    phase = nil
    setGlobalActive(false)
    restoreSnapshot()
    fireEndHook('resource_stop')
end

AddEventHandler('dynamic_weather:internal:seaLevelOp', function(op)
    if not active then return end
    if op == 'flood' then return end

    active = false
    phase = nil
    startedAt = nil
    floodTriggeredAt = nil
    setGlobalActive(false)
    restoreSnapshot()
    fireEndHook('sea_level_' .. tostring(op or 'change'))
end)

return floodEvent
