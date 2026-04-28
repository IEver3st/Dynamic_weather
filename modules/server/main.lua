local resourceName = GetCurrentResourceName()

AddEventHandler('onResourceStart', function(name)
    if name ~= resourceName then return end

    local storage = lib.require('modules.server.storage')
    storage.loadZones()

    local sequence = lib.require('modules.server.sequence')
    sequence.start()

    local sync = lib.require('modules.server.sync')
    sync.start()

    local weatherData = lib.require('modules.server.weather_data')
    weatherData.start()

    local lightningPole = lib.require('modules.server.lightning_pole')
    lightningPole.start()

    print('^2[weather] Cortex Dynamic Weather started^0')
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= resourceName then return end

    local sequence = lib.require('modules.server.sequence')
    sequence.stop()

    local sync = lib.require('modules.server.sync')
    sync.stop()

    local weatherData = lib.require('modules.server.weather_data')
    weatherData.stop()

    local lightningPole = lib.require('modules.server.lightning_pole')
    lightningPole.stop()

    local seaLevel = lib.require('modules.server.sea_level')
    seaLevel.reset('resource stop')

    print('^1[weather] Cortex Dynamic Weather stopped^0')
end)

if Config.syncOnJoinImmediate then
    AddEventHandler('playerJoining', function()
        local src = source
        CreateThread(function()
            Wait(2000)
            if GetPlayerName(src) then
                local sync = lib.require('modules.server.sync')
                sync.sendToPlayer(src)
                local seaLevel = lib.require('modules.server.sea_level')
                seaLevel.sendToPlayer(src)
            end
        end)
    end)
end

-- Server exports
---@param opts { preserveRuntime?: boolean }|nil If preserveRuntime, keep wind and sequence timer from existing state.
function setZoneWeather(zoneId, weatherType, opts)
    opts = opts or {}
    local storage = lib.require('modules.server.storage')
    local zones = storage.getZones()
    if not zones[zoneId] then return nil, 'zone not found' end

    local valid = false
    for _, w in ipairs(zones[zoneId].weatherPool or {}) do
        if w == weatherType then valid = true break end
    end
    if not valid then return nil, 'weather not in zone pool' end

    local states = storage.getZoneStates()
    local prev = states[zoneId] or {}

    local state = {
        currentWeather = weatherType,
        nextWeather = weatherType,
        windSpeed = opts.preserveRuntime and prev.windSpeed or 5.0,
        windDirection = opts.preserveRuntime and prev.windDirection or 0.0,
        severity = opts.severity or prev.severity,
        lastUpdated = os.time(),
    }
    if opts.preserveRuntime and prev.timeUntilAdvance ~= nil then
        state.timeUntilAdvance = prev.timeUntilAdvance
    end

    storage.updateZoneState(zoneId, state)
    TriggerClientEvent('dynamic_weather:zoneUpdate', -1, zoneId, state)
    local weatherData = lib.require('modules.server.weather_data')
    weatherData.notifyStateUpdated(zoneId, state)
    return true
end

function reloadZones()
    local storage = lib.require('modules.server.storage')
    storage.loadZones()
    local sync = lib.require('modules.server.sync')
    sync.broadcastImmediate()
    return true
end
