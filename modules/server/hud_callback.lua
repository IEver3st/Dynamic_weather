---Must register on es_lib (not lib.callback.register here): otherwise a second
---`es_lib:callback` handler runs in this resource, es_lib responds first with nil,
---and the client await resolves before our handler runs.
local function registerHudCallback()
    local ok, err = pcall(function()
        exports.es_lib:registerCallback('dynamic_weather:getHudWeatherSnapshot', function(source, payload)
            local zoneId = payload and payload.zoneId
            local x = payload and payload.x
            local y = payload and payload.y
            local wd = lib.require('modules.server.weather_data')
            return wd.getHudSnapshot(zoneId, x, y)
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
