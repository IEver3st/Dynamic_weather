---Must register on cortex-lib (not lib.callback.register here): otherwise a second
---`cortex-lib:callback` handler runs in this resource, cortex-lib responds first with nil,
---and the client await resolves before our handler runs.
local lastRequestBySource = {}

local function registerHudCallback()
    local ok, err = pcall(function()
        exports['cortex-lib']:registerCallback('dynamic_weather:getHudWeatherSnapshot', function(source)
            local now = GetGameTimer()
            if (now - (lastRequestBySource[source] or 0)) < 500 then
                return { ok = false, error = 'rate_limited' }
            end
            lastRequestBySource[source] = now

            local ped = GetPlayerPed(source)
            if not ped or ped == 0 then
                return { ok = false, error = 'player_unavailable' }
            end

            local coords = GetEntityCoords(ped)
            local wd = lib.require('modules.server.weather_data')
            return wd.getHudSnapshot(nil, coords.x, coords.y)
        end)
    end)
    if not ok then
        print(('^1[Dynamic_weather] registerCallback getHudWeatherSnapshot failed: %s^0'):format(tostring(err)))
    end
end

AddEventHandler('onResourceStart', function(name)
    if name ~= GetCurrentResourceName() then
        return
    end
    CreateThread(function()
        Wait(0)
        registerHudCallback()
    end)
end)

AddEventHandler('playerDropped', function()
    lastRequestBySource[source] = nil
end)
