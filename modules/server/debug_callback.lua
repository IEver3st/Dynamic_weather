local function hasDebugPermission(src)
    if IsPlayerAceAllowed(src, Config.Permissions.all) then
        return true
    end

    local perm = Config.ActionPermissions['weather.debug']
    if perm and IsPlayerAceAllowed(src, perm) then
        return true
    end

    if Config.Permissions.weather and IsPlayerAceAllowed(src, Config.Permissions.weather) then
        return true
    end

    return false
end

local function registerDebugCallback()
    local ok, err = pcall(function()
        exports.es_lib:registerCallback('dynamic_weather:getZoneSequenceDebug', function(playerSrc, zoneId)
            if not hasDebugPermission(playerSrc) then
                return { ok = false, denied = true }
            end

            if type(zoneId) ~= 'string' or #zoneId == 0 then
                return { ok = false }
            end

            local storage = lib.require('modules.server.storage')
            local zones = storage.getZones()
            local states = storage.getZoneStates()
            local sequences = storage.getSequences()

            local zone = zones[zoneId]
            local state = states[zoneId]
            if not state then
                return { ok = false }
            end

            local seq = zone and sequences[zone.sequence]
            local intervalMinutes = seq and seq.intervalMinutes or 15

            return {
                ok = true,
                currentWeather = state.currentWeather,
                nextWeather = state.nextWeather or state.currentWeather,
                timeUntilAdvance = state.timeUntilAdvance,
                intervalMinutes = intervalMinutes,
            }
        end)
    end)
    if not ok then
        print(('^1[Dynamic_weather] registerCallback getZoneSequenceDebug failed: %s^0'):format(tostring(err)))
    end
end

AddEventHandler('onResourceStart', function(name)
    if name ~= GetCurrentResourceName() then
        return
    end
    CreateThread(function()
        Wait(0)
        registerDebugCallback()
    end)
end)
