local editorOpen = false
local editorLastPing = 0
local editorHadPing = false

local function forceCloseEditor(reason)
    if not editorOpen then
        SetNuiFocus(false, false)
        return
    end

    editorOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'closeEditor' })
    TriggerServerEvent('dynamic_weather:editorClosed')

    if reason == 'stale' then
        lib.notify({ title = 'Weather Editor', description = Lang.editor_auto_closed, type = 'warning' })
    elseif reason == 'emergency_key' then
        lib.notify({ title = 'Weather Editor', description = Lang.editor_emergency_closed, type = 'inform' })
    end
end

local nuiModule = {}

-- Release stuck input if CEF hiccuped during load (editor is never open in first 250ms of resource start in practice)
CreateThread(function()
    Wait(250)
    SetNuiFocus(false, false)
end)

RegisterNUICallback('dw_editorPing', function(_, cb)
    editorLastPing = GetGameTimer()
    editorHadPing = true
    cb('ok')
end)

RegisterNUICallback('dw_saveZones', function(data, cb)
    local zones = data.zones
    if not zones or type(zones) ~= 'table' then
        cb('error')
        return
    end
    TriggerServerEvent('dynamic_weather:server:saveZones', zones)
    cb('ok')
end)

RegisterNUICallback('dw_loadZones', function(data, cb)
    TriggerServerEvent('dynamic_weather:server:loadZones')
    cb('ok')
end)

RegisterNUICallback('dw_requestZones', function(data, cb)
    local sync = lib.require('modules.client.sync')
    local defs = sync.getZoneDefs()
    local states = sync.getZoneStates()
    cb({ zones = defs, states = states })
end)

RegisterNUICallback('dw_closeEditor', function(data, cb)
    forceCloseEditor(nil)
    cb('ok')
end)

RegisterNUICallback('dw_editorSetZoneWeather', function(data, cb)
    local zoneId = data and data.zoneId
    local weather = data and data.weather
    if type(zoneId) ~= 'string' or type(weather) ~= 'string' then
        cb({ ok = false })
        return
    end
    TriggerServerEvent('dynamic_weather:server:editorSetZoneWeather', zoneId, weather)
    cb({ ok = true })
end)

RegisterNUICallback('dw_editorAdvanceZone', function(data, cb)
    local zoneId = data and data.zoneId
    if type(zoneId) ~= 'string' then
        cb({ ok = false })
        return
    end
    TriggerServerEvent('dynamic_weather:server:editorAdvanceZone', zoneId)
    cb({ ok = true })
end)

RegisterNetEvent('dynamic_weather:editorBlocked', function()
    lib.notify({ title = 'Weather Editor', description = Lang.editor_busy, type = 'error' })
end)

RegisterNetEvent('dynamic_weather:editorOpen', function(payload)
    editorOpen = true
    editorHadPing = false
    editorLastPing = GetGameTimer()
    SetNuiFocus(true, true)
    SendNUIMessage({
        type = 'openEditor',
        payload = payload or {}
    })
end)

RegisterNetEvent('dynamic_weather:editorData', function(payload)
    SendNUIMessage({
        type = 'editorData',
        payload = payload or {}
    })
end)

RegisterNetEvent('dynamic_weather:editorClose', function()
    editorOpen = false
    editorHadPing = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'closeEditor' })
end)

function nuiModule.isOpen()
    return editorOpen
end

function nuiModule.open(force)
    TriggerServerEvent('dynamic_weather:server:openEditor', force)
end

RegisterCommand('dynamic_weather_emergency_close_editor', function()
    if not editorOpen then
        SetNuiFocus(false, false)
        return
    end
    forceCloseEditor('emergency_key')
end, false)

RegisterKeyMapping(
    'dynamic_weather_emergency_close_editor',
    'Dynamic Weather: emergency close editor (if UI frozen)',
    'keyboard',
    'F10'
)

CreateThread(function()
    local staleAfterPing = Config.editorStaleAfterPingMs or 20000
    local staleBeforeFirst = Config.editorStaleBeforeFirstPingMs or 60000

    while true do
        if editorOpen then
            Wait(500)

            local now = GetGameTimer()
            local limit = editorHadPing and staleAfterPing or staleBeforeFirst
            if (now - editorLastPing) > limit then
                forceCloseEditor('stale')
            end
        else
            Wait(2500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    if editorOpen then
        editorOpen = false
        editorHadPing = false
        TriggerServerEvent('dynamic_weather:editorClosed')
    end
end)

return nuiModule
