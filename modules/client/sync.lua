local zoneDefs = {}
local zoneStates = {}
local revision = 0

local syncModule = {}

local function tableLength(t)
    local count = 0
    for _ in pairs(t or {}) do
        count = count + 1
    end
    return count
end

function syncModule.start()
    RegisterNetEvent('dynamic_weather:sync', function(zones, states)
        zoneDefs = zones or {}
        zoneStates = states or {}
        revision = revision + 1
        if Config.debugLog then
            print(('^3[weather] Sync received: %d zones, %d states^0'):format(
                #zoneDefs, tableLength(zoneStates)))
        end
    end)

    RegisterNetEvent('dynamic_weather:zoneUpdate', function(zoneId, state)
        zoneStates[zoneId] = state
        revision = revision + 1
    end)

    TriggerServerEvent('dynamic_weather:requestSync')
end

function syncModule.stop()
    zoneDefs = {}
    zoneStates = {}
    revision = revision + 1
end

function syncModule.getZoneDefs()
    return zoneDefs
end

function syncModule.getZoneStates()
    return zoneStates
end

function syncModule.getRevision()
    return revision
end

return syncModule
