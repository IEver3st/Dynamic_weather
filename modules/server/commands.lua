local commandsModule = {}
local editorActive = false
local editorUser = nil
local requestRateState = {}

local function allowRequest(src, key, minimumIntervalMs)
    local now = GetGameTimer()
    local state = requestRateState[src]
    if not state then
        state = {}
        requestRateState[src] = state
    end

    local lastAt = state[key] or 0
    if (now - lastAt) < minimumIntervalMs then return false end
    state[key] = now
    return true
end

local function hasPermission(src, actionId)
    if IsPlayerAceAllowed(src, Config.Permissions.all) then
        return true
    end

    local actionPerm = Config.ActionPermissions[actionId]
    if actionPerm and IsPlayerAceAllowed(src, actionPerm) then
        return true
    end

    local weatherPerm = Config.Permissions.weather
    if weatherPerm and IsPlayerAceAllowed(src, weatherPerm) then
        return true
    end

    return false
end

local function notifyPlayer(src, data)
    TriggerClientEvent('cortex-lib:notify', src, data)
end

local function notifyOrPrint(src, data)
    if src > 0 then
        notifyPlayer(src, data)
    else
        print(('[weather] %s'):format(data.description or data.title or ''))
    end
end

local function getActorName(src)
    if src and src > 0 then
        return GetPlayerName(src) or ('player %d'):format(src)
    end
    return 'console'
end

local function parseNumber(value)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then
        return nil
    end
    return n
end

local function sendEditorSnapshot(src)
    local storage = lib.require('modules.server.storage')

    TriggerClientEvent('dynamic_weather:editorData', src, {
        zones = storage.getRawZones(),
        states = storage.getZoneStates(),
        sequences = storage.getSequences(),
    })
end

local function canUseEditor(src, actionKey, minimumIntervalMs)
    if not hasPermission(src, 'weather.editor') then return false end
    if not editorActive or editorUser ~= src then return false end
    return allowRequest(src, actionKey, minimumIntervalMs or 200)
end

RegisterCommand('weathereditor', function(source, args, raw)
    local src = source > 0 and source or 0
    if src > 0 then
        if not hasPermission(src, 'weather.editor') then
            notifyPlayer(src, {
                title = 'Weather Editor',
                description = Lang.no_permission,
                type = 'error'
            })
            return
        end

        if editorActive and editorUser ~= src then
            TriggerClientEvent('dynamic_weather:editorBlocked', src)
            return
        end

        editorActive = true
        editorUser = src

        notifyPlayer(src, {
            title = 'Weather Editor',
            description = Lang.editor_open,
            type = 'info'
        })

        TriggerClientEvent('dynamic_weather:editorOpen', src, {})
        sendEditorSnapshot(src)
    end
end, false)

RegisterNetEvent('dynamic_weather:server:openEditor', function(force)
    local src = source
    if not hasPermission(src, 'weather.editor') then
        TriggerClientEvent('dynamic_weather:editorBlocked', src)
        return
    end

    if editorActive and editorUser ~= src then
        TriggerClientEvent('dynamic_weather:editorBlocked', src)
        return
    end

    if not allowRequest(src, 'openEditor', 1000) then return end

    editorActive = true
    editorUser = src

    TriggerClientEvent('dynamic_weather:editorOpen', src, {})
    sendEditorSnapshot(src)

    if Config.debugLog then
        print(('^3[weather] Editor opened by %s^0'):format(GetPlayerName(src)))
    end
end)

RegisterNetEvent('dynamic_weather:server:saveZones', function(zones)
    local src = source
    if not canUseEditor(src, 'saveZones', 500) then return end

    local storage = lib.require('modules.server.storage')
    local ok, err = storage.saveZones(zones)
    if not ok then
        notifyPlayer(src, {
            title = 'Weather Editor',
            description = ('Save failed: %s'):format(err),
            type = 'error'
        })
        return
    end

    notifyPlayer(src, {
        title = 'Weather Editor',
        description = ('%d zones saved.'):format(#zones),
        type = 'success'
    })

    local sync = lib.require('modules.server.sync')
    sync.broadcastImmediate()
end)

RegisterNetEvent('dynamic_weather:server:loadZones', function()
    local src = source
    if not canUseEditor(src, 'loadZones', 500) then return end
    sendEditorSnapshot(src)
end)

RegisterNetEvent('dynamic_weather:server:editorSetZoneWeather', function(zoneId, weatherType)
    local src = source
    if not canUseEditor(src, 'setZoneWeather', 200) then return end
    if type(zoneId) ~= 'string' or #zoneId == 0 or #zoneId > 64 or type(weatherType) ~= 'string' or #weatherType == 0 or #weatherType > 32 then return end

    local ok, err = setZoneWeather(zoneId, string.upper(weatherType), { preserveRuntime = true })
    if not ok then
        notifyPlayer(src, {
            title = 'Weather Editor',
            description = err or 'Could not set weather',
            type = 'error',
        })
        return
    end

    sendEditorSnapshot(src)
end)

RegisterNetEvent('dynamic_weather:server:editorAdvanceZone', function(zoneId)
    local src = source
    if not canUseEditor(src, 'advanceZone', 500) then return end
    if type(zoneId) ~= 'string' or #zoneId == 0 or #zoneId > 64 then return end

    local sequence = lib.require('modules.server.sequence')
    local ok = sequence.forceAdvance(zoneId)
    if not ok then
        notifyPlayer(src, {
            title = 'Weather Editor',
            description = 'Zone not found',
            type = 'error',
        })
        return
    end

    sendEditorSnapshot(src)
end)

RegisterNetEvent('dynamic_weather:requestSync', function()
    local src = source
    if not allowRequest(src, 'requestSync', 1000) then return end
    local sync = lib.require('modules.server.sync')
    sync.sendToPlayer(src)
end)

RegisterCommand('weather', function(source, args, raw)
    if not args[1] then return end
    local src = source > 0 and source or 0
    local sub = args[1]

    if sub == 'reload' then
        if src > 0 and not hasPermission(src, 'weather.reload') then
            notifyPlayer(src, { title = 'Weather', description = Lang.no_permission, type = 'error' })
            return
        end
        local storage = lib.require('modules.server.storage')
        storage.loadZones()
        local sync = lib.require('modules.server.sync')
        sync.broadcastImmediate()
        if src > 0 then
            notifyPlayer(src, { title = 'Weather', description = Lang.reload_ok, type = 'success' })
        end
    elseif sub == 'force' then
        if src > 0 and not hasPermission(src, 'weather.force') then
            notifyPlayer(src, { title = 'Weather', description = Lang.no_permission, type = 'error' })
            return
        end

        local zoneId = args[2]
        local weatherType = args[3] and string.upper(args[3]) or nil
        if not zoneId or not weatherType then
            if src > 0 then
                notifyPlayer(src, {
                    title = 'Weather',
                    description = 'Usage: /weather force <zoneId> <weatherType>',
                    type = 'error'
                })
            end
            return
        end

        local ok, err = setZoneWeather(zoneId, weatherType)
        if not ok then
            if src > 0 then
                notifyPlayer(src, {
                    title = 'Weather',
                    description = ('Force failed: %s'):format(err or 'unknown error'),
                    type = 'error'
                })
            end
            return
        end

        if src > 0 then
            notifyPlayer(src, {
                title = 'Weather',
                description = ('Forced %s to %s'):format(zoneId, weatherType),
                type = 'success'
            })
        end
    end
end, false)

RegisterCommand('weatherstate', function(source)
    local src = source > 0 and source or 0
    if src > 0 and not hasPermission(src, 'weather.debug') then
        notifyPlayer(src, { title = 'Weather', description = Lang.no_permission, type = 'error' })
        return
    end

    local data = exports[GetCurrentResourceName()]:GetActiveWeatherZones()
    print(('[weather] active zones: %s'):format(json.encode(data)))
end, false)

RegisterCommand('weatherforecast', function(source, args)
    local src = source > 0 and source or 0
    if src > 0 and not hasPermission(src, 'weather.debug') then
        notifyPlayer(src, { title = 'Weather', description = Lang.no_permission, type = 'error' })
        return
    end

    local region = args and args[1]
    local data = region and exports[GetCurrentResourceName()]:GetForecastForRegion(region)
        or exports[GetCurrentResourceName()]:GetForecast()
    print(('[weather] forecast: %s'):format(json.encode(data)))
end, false)

RegisterCommand('weatheralerts', function(source)
    local src = source > 0 and source or 0
    if src > 0 and not hasPermission(src, 'weather.debug') then
        notifyPlayer(src, { title = 'Weather', description = Lang.no_permission, type = 'error' })
        return
    end

    print(('[weather] alerts: %s'):format(json.encode(exports[GetCurrentResourceName()]:GetActiveAlerts())))
end, false)

RegisterCommand('weatheralerttest', function(source, args)
    local src = source > 0 and source or 0
    if src > 0 and not hasPermission(src, 'weather.debug') then
        notifyPlayer(src, { title = 'Weather', description = Lang.no_permission, type = 'error' })
        return
    end

    local zoneId = args and args[1]
    local alert = exports[GetCurrentResourceName()]:CreateWeatherAlert({
        type = 'WEATHER_ADVISORY',
        title = 'Weather Advisory Test',
        zoneId = zoneId,
        severity = tonumber(args and args[2]) or 2,
        message = 'Test alert from Dynamic Weather.',
        recommendedActions = { 'Monitor conditions', 'Use caution' },
    })
    print(('[weather] alert created: %s'):format(json.encode(alert)))
end, false)

RegisterCommand('hurricane', function(source, args)
    local src = source > 0 and source or 0
    if src > 0 and not hasPermission(src, 'weather.hurricane') and not hasPermission(src, 'weather.force') then
        notifyPlayer(src, { title = 'Hurricane', description = Lang.no_permission, type = 'error' })
        return
    end

    local hurricane = lib.require('modules.server.hurricane')
    local sub = args and args[1] and string.lower(tostring(args[1])) or 'start'

    if sub == 'stop' or sub == 'end' then
        local ok, err = hurricane.endHurricane(getActorName(src))
        if not ok then
            notifyOrPrint(src, { title = 'Hurricane', description = err or 'Stop failed', type = 'error' })
            return
        end

        notifyOrPrint(src, { title = 'Hurricane', description = 'Hurricane stopped; debris cleanup broadcast', type = 'success' })
        return
    end

    if sub == 'status' then
        local state = hurricane.getState()
        local message = ('active=%s intensity=%s wind=%.1f direction=%.1f lightning=%.1f'):format(
            tostring(state.active),
            tostring(state.intensity),
            tonumber(state.windSpeed) or 0.0,
            tonumber(state.windDirection) or 0.0,
            tonumber(state.lightningMultiplier) or 1.0
        )
        print(('[weather] hurricane %s'):format(message))
        if src > 0 then
            notifyPlayer(src, { title = 'Hurricane', description = message, type = 'info' })
        end
        return
    end

    local offset = (sub == 'start') and 1 or 0
    local intensity = parseNumber(args and args[1 + offset])
    local windDirection = parseNumber(args and args[2 + offset])
    local ok, result = hurricane.startHurricane({
        intensity = intensity,
        windDirection = windDirection,
    }, getActorName(src))

    if not ok then
        notifyOrPrint(src, { title = 'Hurricane', description = result or 'Start failed', type = 'error' })
        return
    end

    notifyOrPrint(src, {
        title = 'Hurricane',
        description = ('Started intensity %d, wind %.1f, direction %.1f'):format(
            result.intensity,
            result.windSpeed,
            result.windDirection
        ),
        type = 'success',
    })
end, false)

RegisterCommand('hurricanestatus', function(source)
    local src = source > 0 and source or 0
    if src > 0 and not hasPermission(src, 'weather.debug') and not hasPermission(src, 'weather.hurricane') then
        notifyPlayer(src, { title = 'Hurricane', description = Lang.no_permission, type = 'error' })
        return
    end

    local state = lib.require('modules.server.hurricane').getState()
    print(('[weather] hurricane state: %s'):format(json.encode(state)))
end, false)

RegisterCommand('lightningpole', function(source, args)
    local lightningPole = lib.require('modules.server.lightning_pole')
    lightningPole.handleCommand(source, args, hasPermission, notifyPlayer)
end, false)

RegisterCommand('strikepole', function(source, args)
    local lightningPole = lib.require('modules.server.lightning_pole')
    lightningPole.handleCommand(source, args, hasPermission, notifyPlayer)
end, false)

RegisterCommand('findpole', function(source, args)
    local lightningPole = lib.require('modules.server.lightning_pole')
    lightningPole.handleCommand(source, { 'scan', args and args[1] }, hasPermission, notifyPlayer)
end, false)

RegisterCommand('debugpole', function(source, args)
    local lightningPole = lib.require('modules.server.lightning_pole')
    lightningPole.handleCommand(source, { 'debugscan', args and args[1] }, hasPermission, notifyPlayer)
end, false)

RegisterNetEvent('dynamic_weather:editorClosed', function()
    local src = source
    if editorUser == src then
        editorActive = false
        editorUser = nil
    end
    if Config.debugLog then
        print('^3[weather] Editor closed^0')
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    requestRateState[src] = nil
    if editorUser == src then
        editorActive = false
        editorUser = nil
    end
end)

function commandsModule.reload()
    local storage = lib.require('modules.server.storage')
    storage.loadZones()
    local sync = lib.require('modules.server.sync')
    sync.broadcastImmediate()
    return true
end

function commandsModule.isEditorActive()
    return editorActive
end

return commandsModule
