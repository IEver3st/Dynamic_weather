local seaLevel = {}
local lastStateRequestBySource = {}

local currentLevel = nil
local currentMode = 'absolute'
local smoothTarget = nil
local smoothSeconds = nil
local floodActive = false
local floodProfile = nil

local function getConfig()
    return Config.SeaLevel or {}
end

local function clampLevel(level)
    local cfg = getConfig()
    local minLevel = tonumber(cfg.minSeaLevel) or -10.0
    local maxLevel = tonumber(cfg.maxSafeSeaLevel) or tonumber(cfg.maxSeaLevel) or 80.0

    if level < minLevel then return minLevel end
    if level > maxLevel then return maxLevel end
    return level
end

local function normalizeMode(mode)
    if type(mode) == 'string' then
        mode = string.lower(mode)
    end
    return mode == 'offset' and 'offset' or 'absolute'
end

local function getFloodHeight()
    local cfg = getConfig()
    return tonumber(cfg.floodHeight) or tonumber(cfg.braveFloodHeight) or 2.0
end

local function getFloodMode()
    local cfg = getConfig()
    return normalizeMode(cfg.floodMode or 'offset')
end

local function isHurricaneActive()
    local state = GlobalState.dynamic_weather_hurricane
    if type(state) == 'table' and state.active == true then
        return true
    end

    local ok, hurricane = pcall(lib.require, 'modules.server.hurricane')
    if ok and type(hurricane) == 'table' and type(hurricane.isActive) == 'function' then
        return hurricane.isActive() == true
    end

    return false
end

local function normalizeFloodProfile(profile)
    if type(profile) == 'string' then
        profile = string.lower(profile)
    end

    if profile == 'hurricane' or profile == 'rough' then
        return 'hurricane'
    end

    if isHurricaneActive() then
        return 'hurricane'
    end

    return 'flash'
end

local function broadcastSet(level, mode)
    TriggerClientEvent('dynamic_weather:seaLevel:set', -1, level, mode)
end

local function broadcastSmooth(level, seconds, mode)
    TriggerClientEvent('dynamic_weather:seaLevel:smooth', -1, level, seconds, mode)
end

local function broadcastReset()
    TriggerClientEvent('dynamic_weather:seaLevel:reset', -1)
end

local function broadcastLoadWater()
    TriggerClientEvent('dynamic_weather:seaLevel:loadWater', -1)
end

local function broadcastFlood(level, mode, profile)
    TriggerClientEvent('dynamic_weather:seaLevel:flood', -1, level, mode, profile)
end

local function logChange(message)
    print(('^3[weather] Sea level %s^0'):format(message))
end

function seaLevel.isEnabled()
    return getConfig().enabled == true
end

function seaLevel.setLevel(level, actor, mode)
    if not seaLevel.isEnabled() then return false, 'sea level control disabled' end
    if type(level) ~= 'number' then return false, 'invalid sea level' end

    local clamped = clampLevel(level)
    local requestedMode = normalizeMode(mode)
    currentLevel = clamped
    currentMode = requestedMode
    smoothTarget = nil
    smoothSeconds = nil
    floodActive = false
    floodProfile = nil
    broadcastSet(clamped, requestedMode)
    logChange(('set to %.2f mode=%s by %s'):format(clamped, requestedMode, actor or 'server'))
    return true, clamped
end

function seaLevel.smoothTo(level, seconds, actor, mode)
    if not seaLevel.isEnabled() then return false, 'sea level control disabled' end
    if type(level) ~= 'number' then return false, 'invalid sea level' end

    local cfg = getConfig()
    local clamped = clampLevel(level)
    local requestedMode = normalizeMode(mode)
    local duration = tonumber(seconds) or tonumber(cfg.defaultSmoothSeconds) or 60
    duration = math.max(0, duration)

    currentLevel = clamped
    currentMode = requestedMode
    smoothTarget = clamped
    smoothSeconds = duration
    floodActive = false
    floodProfile = nil
    broadcastSmooth(clamped, duration, requestedMode)
    logChange(('smoothing to %.2f over %.1fs mode=%s by %s'):format(clamped, duration, requestedMode, actor or 'server'))
    return true, clamped, duration
end

function seaLevel.reset(actor)
    currentLevel = nil
    currentMode = 'absolute'
    smoothTarget = nil
    smoothSeconds = nil
    floodActive = false
    floodProfile = nil
    broadcastReset()
    logChange(('reset by %s'):format(actor or 'server'))
    return true
end

function seaLevel.getStatus()
    return {
        enabled = seaLevel.isEnabled(),
        currentLevel = currentLevel,
        currentMode = currentMode,
        smoothTarget = smoothTarget,
        smoothSeconds = smoothSeconds,
        floodActive = floodActive,
        floodProfile = floodProfile,
        minSeaLevel = getConfig().minSeaLevel,
        maxSeaLevel = getConfig().maxSeaLevel,
        maxSafeSeaLevel = getConfig().maxSafeSeaLevel,
    }
end

function seaLevel.loadWater(actor)
    if not seaLevel.isEnabled() then return false, 'sea level control disabled' end
    currentLevel = nil
    currentMode = 'absolute'
    smoothTarget = nil
    smoothSeconds = nil
    floodActive = false
    floodProfile = nil
    broadcastLoadWater()
    logChange(('loaded full-map flood water by %s'):format(actor or 'server'))
    return true
end

function seaLevel.flood(actor, mode, level, profile)
    if not seaLevel.isEnabled() then return false, 'sea level control disabled' end

    local target = clampLevel(type(level) == 'number' and level or getFloodHeight())
    local requestedMode = normalizeMode(mode or getFloodMode())
    local requestedProfile = normalizeFloodProfile(profile)
    currentLevel = target
    currentMode = requestedMode
    smoothTarget = target
    smoothSeconds = nil
    floodActive = true
    floodProfile = requestedProfile
    broadcastFlood(target, requestedMode, requestedProfile)
    logChange(('flood to %.2f mode=%s profile=%s by %s'):format(target, requestedMode, requestedProfile, actor or 'server'))
    return true, target, requestedMode, requestedProfile
end

function seaLevel.sendToPlayer(src)
    if not seaLevel.isEnabled() then return end
    if type(currentLevel) == 'number' then
        if floodActive then
            TriggerClientEvent('dynamic_weather:seaLevel:flood', src, currentLevel, currentMode, floodProfile or 'flash')
        else
            TriggerClientEvent('dynamic_weather:seaLevel:set', src, currentLevel, currentMode)
        end
    else
        TriggerClientEvent('dynamic_weather:seaLevel:reset', src)
    end
end

RegisterNetEvent('dynamic_weather:seaLevel:requestState', function()
    local src = source
    local now = GetGameTimer()
    if now - (lastStateRequestBySource[src] or 0) < 1000 then return end
    lastStateRequestBySource[src] = now
    seaLevel.sendToPlayer(src)
end)

AddEventHandler('playerDropped', function()
    lastStateRequestBySource[source] = nil
end)

return seaLevel
