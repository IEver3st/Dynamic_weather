local commandsModule = {}
local editorActive = false
local editorUser = nil

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
    TriggerClientEvent('es_lib:notify', src, data)
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

local function hasSeaLevelPermission(src)
    local cfg = Config.SeaLevel or {}
    if cfg.adminOnly == false then return true end
    if src <= 0 then return true end
    return hasPermission(src, 'weather.sealevel') or hasPermission(src, 'weather.debug')
end

local function parseNumber(value)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then
        return nil
    end
    return n
end

local function parseSeaLevelMode(args, numberIndex)
    local mode = 'absolute'
    local rawMode = args and args[numberIndex + 1]
    if type(rawMode) == 'string' then rawMode = string.lower(rawMode) end

    if rawMode == 'offset' or rawMode == 'relative' then
        mode = 'offset'
    elseif rawMode == 'absolute' or rawMode == 'abs' then
        mode = 'absolute'
    elseif args and type(args[1]) == 'string' and (string.lower(args[1]) == 'offset' or string.lower(args[1]) == 'relative') then
        mode = 'offset'
    end

    return mode
end

local function sendEditorSnapshot(src)
    local storage = lib.require('modules.server.storage')

    TriggerClientEvent('dynamic_weather:editorData', src, {
        zones = storage.getRawZones(),
        states = storage.getZoneStates(),
        sequences = storage.getSequences(),
    })
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

    if editorActive and not force then
        TriggerClientEvent('dynamic_weather:editorBlocked', src)
        return
    end

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
    if not hasPermission(src, 'weather.editor') then return end

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
    sendEditorSnapshot(src)
end)

RegisterNetEvent('dynamic_weather:server:editorSetZoneWeather', function(zoneId, weatherType)
    local src = source
    if not hasPermission(src, 'weather.editor') then return end
    if type(zoneId) ~= 'string' or type(weatherType) ~= 'string' then return end

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
    if not hasPermission(src, 'weather.editor') then return end
    if type(zoneId) ~= 'string' or #zoneId == 0 then return end

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

RegisterCommand('sealevel', function(source, args)
    local src = source > 0 and source or 0
    if not hasSeaLevelPermission(src) then
        notifyPlayer(src, { title = 'Sea Level', description = Lang.no_permission, type = 'error' })
        return
    end

    local level = parseNumber(args and args[1])
    local mode = parseSeaLevelMode(args, 1)
    local firstArg = args and args[1] and string.lower(args[1]) or nil
    if not level and (firstArg == 'offset' or firstArg == 'relative' or firstArg == 'absolute' or firstArg == 'abs') then
        mode = (firstArg == 'offset' or firstArg == 'relative') and 'offset' or 'absolute'
        level = parseNumber(args[2])
    end

    if not level then
        notifyOrPrint(src, { title = 'Sea Level', description = 'Usage: /sealevel <height> [absolute|offset] or /sealevel offset <delta>', type = 'error' })
        return
    end

    local seaLevel = lib.require('modules.server.sea_level')
    local ok, result = seaLevel.setLevel(level, getActorName(src), mode)
    if not ok then
        notifyOrPrint(src, { title = 'Sea Level', description = result or 'Sea level failed', type = 'error' })
        return
    end

    notifyOrPrint(src, {
        title = 'Sea Level',
        description = ('Sea level set to %.2f (%s)'):format(result, mode),
        type = 'success',
    })
end, false)

RegisterCommand('sealevelsmooth', function(source, args)
    local src = source > 0 and source or 0
    if not hasSeaLevelPermission(src) then
        notifyPlayer(src, { title = 'Sea Level', description = Lang.no_permission, type = 'error' })
        return
    end

    local level = parseNumber(args and args[1])
    local seconds = parseNumber(args and args[2])
    local mode = parseSeaLevelMode(args, 2)
    local firstArg = args and args[1] and string.lower(args[1]) or nil
    if not level and (firstArg == 'offset' or firstArg == 'relative' or firstArg == 'absolute' or firstArg == 'abs') then
        mode = (firstArg == 'offset' or firstArg == 'relative') and 'offset' or 'absolute'
        level = parseNumber(args[2])
        seconds = parseNumber(args[3])
    end

    if not level then
        notifyOrPrint(src, { title = 'Sea Level', description = 'Usage: /sealevelsmooth <height> [seconds] [absolute|offset]', type = 'error' })
        return
    end

    local seaLevel = lib.require('modules.server.sea_level')
    local ok, target, duration = seaLevel.smoothTo(level, seconds, getActorName(src), mode)
    if not ok then
        notifyOrPrint(src, { title = 'Sea Level', description = target or 'Sea level smooth failed', type = 'error' })
        return
    end

    notifyOrPrint(src, {
        title = 'Sea Level',
        description = ('Sea level smoothing to %.2f over %.1fs (%s)'):format(target, duration, mode),
        type = 'success',
    })
end, false)

RegisterCommand('sealevelreset', function(source)
    local src = source > 0 and source or 0
    if not hasSeaLevelPermission(src) then
        notifyPlayer(src, { title = 'Sea Level', description = Lang.no_permission, type = 'error' })
        return
    end

    local seaLevel = lib.require('modules.server.sea_level')
    seaLevel.reset(getActorName(src))
    notifyOrPrint(src, { title = 'Sea Level', description = 'Sea level reset', type = 'success' })
end, false)

RegisterCommand('sealevelstatus', function(source)
    local src = source > 0 and source or 0
    if not hasSeaLevelPermission(src) then
        notifyPlayer(src, { title = 'Sea Level', description = Lang.no_permission, type = 'error' })
        return
    end

    local seaLevel = lib.require('modules.server.sea_level')
    local status = seaLevel.getStatus()
    local value = status.currentLevel and ('%.2f'):format(status.currentLevel) or 'default'
    local message = ('Sea level: %s mode=%s (enabled=%s, clamp %.2f..%.2f safeMax=%.2f)'):format(
        value,
        status.currentMode or 'absolute',
        tostring(status.enabled),
        tonumber(status.minSeaLevel) or -10.0,
        tonumber(status.maxSeaLevel) or 400.0,
        tonumber(status.maxSafeSeaLevel) or tonumber(status.maxSeaLevel) or 80.0
    )

    print(('[weather] %s'):format(message))
    if src > 0 then
        notifyPlayer(src, { title = 'Sea Level', description = message, type = 'info' })
    end
end, false)

RegisterCommand('loadwater', function(source)
    local src = source > 0 and source or 0
    if not hasSeaLevelPermission(src) then
        notifyPlayer(src, { title = 'Sea Level', description = Lang.no_permission, type = 'error' })
        return
    end

    local seaLevel = lib.require('modules.server.sea_level')
    local ok, err = seaLevel.loadWater(getActorName(src))
    if not ok then
        notifyOrPrint(src, { title = 'Sea Level', description = err or 'Load water failed', type = 'error' })
        return
    end

    notifyOrPrint(src, { title = 'Sea Level', description = 'Loaded full-map flood water', type = 'success' })
end, false)

RegisterCommand('resetwater', function(source)
    local src = source > 0 and source or 0
    if not hasSeaLevelPermission(src) then
        notifyPlayer(src, { title = 'Sea Level', description = Lang.no_permission, type = 'error' })
        return
    end

    local seaLevel = lib.require('modules.server.sea_level')
    seaLevel.reset(getActorName(src))
    notifyOrPrint(src, { title = 'Sea Level', description = 'Water reset', type = 'success' })
end, false)

RegisterCommand('flood', function(source)
    local src = source > 0 and source or 0
    if not hasSeaLevelPermission(src) then
        notifyPlayer(src, { title = 'Sea Level', description = Lang.no_permission, type = 'error' })
        return
    end

    local seaLevel = lib.require('modules.server.sea_level')
    local ok, target, mode = seaLevel.flood(getActorName(src))
    if not ok then
        notifyOrPrint(src, { title = 'Sea Level', description = target or 'Flood failed', type = 'error' })
        return
    end

    notifyOrPrint(src, {
        title = 'Sea Level',
        description = ('Flood rising to %.2f (%s)'):format(target, mode or 'absolute'),
        type = 'success',
    })
end, false)

RegisterCommand('lightningpole', function(source, args)
    local lightningPole = lib.require('modules.server.lightning_pole')
    lightningPole.handleCommand(source, args, hasPermission, notifyPlayer)
end, false)

RegisterCommand('strikepole', function(source, args)
    local lightningPole = lib.require('modules.server.lightning_pole')
    lightningPole.handleCommand(source, args, hasPermission, notifyPlayer)
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
