local zonesModule = {}

function zonesModule.getZoneAt(x, y)
    local engine = lib.require('modules.client.engine')
    return engine.findPlayerZone(x, y)
end

function zonesModule.getAllZones()
    local sync = lib.require('modules.client.sync')
    return sync.getZoneDefs()
end

function zonesModule.isInsideZone(zoneId)
    local engine = lib.require('modules.client.engine')
    local state = engine.getState()
    return state.zone == zoneId
end

return zonesModule
