local syncModule = {}
local syncActive = false

local function broadcast()
    local storage = lib.require('modules.server.storage')
    local zones = storage.getClientZones()
    local states = storage.getZoneStates()
    TriggerClientEvent('dynamic_weather:sync', -1, zones, states)
end

function syncModule.start()
    if syncActive then return end

    local interval = Config.syncBroadcastInterval or 10000
    if interval <= 0 then
        if Config.debugLog then
            print('^2[weather] Sync broadcaster disabled (event-driven only)^0')
        end
        return
    end

    syncActive = true
    CreateThread(function()
        while syncActive do
            Wait(interval)
            if syncActive then
                local players = GetPlayers()
                if players and #players > 0 then
                    broadcast()
                end
            end
        end
    end)

    if Config.debugLog then
        print(('^2[weather] Sync broadcaster started (interval: %dms)^0'):format(interval))
    end
end

function syncModule.stop()
    syncActive = false
end

function syncModule.sendToPlayer(src)
    local storage = lib.require('modules.server.storage')
    local zones = storage.getClientZones()
    local states = storage.getZoneStates()
    TriggerClientEvent('dynamic_weather:sync', src, zones, states)
end

function syncModule.broadcastImmediate()
    broadcast()
end

return syncModule
