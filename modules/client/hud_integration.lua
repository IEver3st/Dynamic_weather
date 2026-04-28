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
    local x, y = coords.x, coords.y
    local zone = engine.findPlayerZone(x, y)
    local zoneId = zone and zone.id or nil

    if not lib.callback or not lib.callback.await then
        return nil
    end

    local snap = lib.callback.await('dynamic_weather:getHudWeatherSnapshot', false, {
        zoneId = zoneId,
        x = x,
        y = y,
    })

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
