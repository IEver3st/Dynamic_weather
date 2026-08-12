local resourceName = GetCurrentResourceName()

---@return table|nil
function getHudWeatherSnapshot()
    local engine = lib.require('modules.client.engine')
    if not engine then
        return nil
    end

    local ped = PlayerPedId()
    if ped == 0 then
        return nil
    end

    local coords = GetEntityCoords(ped)
    local zone = engine.findPlayerZone(coords.x, coords.y)

    if not lib.callback or not lib.callback.await then
        return nil
    end

    local snap = lib.callback.await('dynamic_weather:getHudWeatherSnapshot', false, {})

    if type(snap) ~= 'table' or not snap.ok then
        return nil
    end

    snap.clientDisplay = exports[resourceName]:getCurrentWeather()
    snap.season = exports[resourceName]:getSeason()
    snap.zoneLocalLabel = zone and zone.label or nil
    snap.resource = resourceName
    return snap
end

exports('getHudWeatherSnapshot', getHudWeatherSnapshot)
