local lightningPole = {}
local handlersRegistered = false
local recentStrikes = {}
local lastStrikeBySource = {}
local lastRequestBySource = {}
local poleModelCache = nil

local GetEntityCoords = GetEntityCoords
local GetGameTimer = GetGameTimer
local GetPlayerPed = GetPlayerPed
local GetPlayerName = GetPlayerName
local TriggerClientEvent = TriggerClientEvent
local ipairs = ipairs
local tonumber = tonumber
local type = type

local function isFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function lightningConfig()
    return Config.LightningPoleStrike or {}
end

local function distSq(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

local function hasDebugPermission(src)
    if src <= 0 then return true end
    if IsPlayerAceAllowed(src, Config.Permissions.all) then
        return true
    end

    local debugPerm = Config.ActionPermissions and Config.ActionPermissions['weather.debug']
    if debugPerm and IsPlayerAceAllowed(src, debugPerm) then
        return true
    end

    local weatherPerm = Config.Permissions and Config.Permissions.weather
    return weatherPerm and IsPlayerAceAllowed(src, weatherPerm) or false
end

local function notify(src, notifyPlayer, title, description, notifyType)
    if src <= 0 or type(notifyPlayer) ~= 'function' then return end
    notifyPlayer(src, {
        title = title,
        description = description,
        type = notifyType or 'info',
    })
end

local function toVector3(payload)
    if type(payload) ~= 'table' then return nil end

    local x = tonumber(payload.x)
    local y = tonumber(payload.y)
    local z = tonumber(payload.z)
    if not isFiniteNumber(x) or not isFiniteNumber(y) or not isFiniteNumber(z) then return nil end
    if math.abs(x) > 20000.0 or math.abs(y) > 20000.0 or z < -2000.0 or z > 5000.0 then return nil end

    return vector3(x + 0.0, y + 0.0, z + 0.0)
end

local function buildPoleModelCache()
    local cfg = lightningConfig()
    local cache = {
        hashes = {},
        names = {},
    }

    for hash, enabled in pairs(cfg.powerPoleModelHashes or {}) do
        if enabled == true and type(hash) == 'number' and cache.names[hash] == nil then
            cache.hashes[#cache.hashes + 1] = hash
            cache.names[hash] = tostring(hash)
        end
    end

    for _, modelName in ipairs(cfg.powerPoleModels or {}) do
        local hash = type(modelName) == 'number' and modelName or joaat(modelName)
        if hash and cache.names[hash] == nil then
            cache.hashes[#cache.hashes + 1] = hash
        end
        if hash then cache.names[hash] = modelName end
    end

    poleModelCache = cache
    return cache
end

local function getPoleModelCache()
    if poleModelCache then return poleModelCache end
    return buildPoleModelCache()
end

local function isAllowedPoleModel(model)
    return getPoleModelCache().names[model] ~= nil
end

local function cleanupRecentStrikes(now)
    local expiry = math.max(lightningConfig().cooldown or 180000, 60000)

    for index = #recentStrikes, 1, -1 do
        if now - recentStrikes[index].at > expiry then
            table.remove(recentStrikes, index)
        end
    end
end

local function isDuplicateStrike(coords)
    local cfg = lightningConfig()
    local dedupeRadius = cfg.searchRadius or 160.0
    local dedupeRadiusSq = dedupeRadius * dedupeRadius

    for _, strike in ipairs(recentStrikes) do
        if distSq(coords, strike.coords) <= dedupeRadiusSq then
            return true
        end
    end

    return false
end

local function isStormEligible(coords)
    local weatherData = lib.require('modules.server.weather_data')
    local profile = weatherData.getWeatherAtCoords(coords.x, coords.y)
    if type(profile) ~= 'table' then return false end

    local cfg = lightningConfig()
    local weatherTypes = cfg.weatherTypes or {}
    local weather = type(profile.weather) == 'string' and string.upper(profile.weather) or Config.globalFallbackWeather
    local severity = tonumber(profile.severity) or 1

    if weatherTypes[weather] ~= true then
        return false
    end

    return severity >= (cfg.minSeverity or 4)
end

local function broadcastStrike(strikeCoords, payload, sourceBucket)
    local syncRadius = lightningConfig().syncRadius or 400.0
    local syncRadiusSq = syncRadius * syncRadius

    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if target and GetPlayerName(target) and GetPlayerRoutingBucket(target) == sourceBucket then
            local ped = GetPlayerPed(target)
            if ped and ped ~= 0 then
                local pedCoords = GetEntityCoords(ped)
                if distSq(pedCoords, strikeCoords) <= syncRadiusSq then
                    TriggerClientEvent('dynamic_weather:client:doLightningPoleStrike', target, payload)
                end
            end
        end
    end
end

local function registerHandlers()
    if handlersRegistered then return end
    handlersRegistered = true

    RegisterNetEvent('dynamic_weather:server:requestLightningPoleStrike', function(data)
        local src = source
        local cfg = lightningConfig()
        if type(data) ~= 'table' then return end

        local now = GetGameTimer()
        if now - (lastRequestBySource[src] or 0) < 500 then return end
        lastRequestBySource[src] = now

        local debugStrike = data.debug == true and hasDebugPermission(src)
        if cfg.enabled == false and not debugStrike then return end

        local strikeCoords = toVector3(data.strikeCoords)
        local poleCoords = toVector3(data.poleCoords)
        local model = tonumber(data.model)
        if not strikeCoords or not poleCoords or not model then return end
        if not isFiniteNumber(model) or model ~= math.floor(model) then return end
        if not isAllowedPoleModel(model) then return end

        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then return end

        local playerCoords = GetEntityCoords(ped)
        local maxSourceDistance = (cfg.searchRadius or 160.0) + 45.0
        local maxSourceDistanceSq = maxSourceDistance * maxSourceDistance
        if distSq(playerCoords, poleCoords) > maxSourceDistanceSq then return end

        local maxOffsetSq = ((cfg.defaultStrikeOffset and cfg.defaultStrikeOffset.z or 11.0) + 20.0)
        maxOffsetSq = maxOffsetSq * maxOffsetSq
        if distSq(poleCoords, strikeCoords) > maxOffsetSq then return end

        cleanupRecentStrikes(now)

        if not debugStrike then
            local cooldown = cfg.cooldown or 180000
            if now - (lastStrikeBySource[src] or 0) < cooldown then
                return
            end

            if not isStormEligible(playerCoords) then
                return
            end

            if isDuplicateStrike(strikeCoords) then
                return
            end
        end

        lastStrikeBySource[src] = now
        recentStrikes[#recentStrikes + 1] = {
            at = now,
            coords = strikeCoords,
        }

        local blackoutMin = cfg.blackoutMin or 3500
        local blackoutMax = math.max(blackoutMin, cfg.blackoutMax or blackoutMin)
        local impactDelayMin = cfg.impactDelayMin or 120
        local impactDelayMax = math.max(impactDelayMin, cfg.impactDelayMax or impactDelayMin)
        local fireDurationMin = cfg.fireDurationMin or 1400
        local fireDurationMax = math.max(fireDurationMin, cfg.fireDurationMax or fireDurationMin)

        local payload = {
            strikeCoords = {
                x = strikeCoords.x,
                y = strikeCoords.y,
                z = strikeCoords.z,
            },
            poleCoords = {
                x = poleCoords.x,
                y = poleCoords.y,
                z = poleCoords.z,
            },
            model = model,
            blackoutDuration = math.random(blackoutMin, blackoutMax),
            blackoutRadius = cfg.blackoutRadius or 175.0,
            impactDelay = math.random(impactDelayMin, impactDelayMax),
            impactExplosionType = cfg.impactExplosionType or 2,
            impactExplosionScale = cfg.impactExplosionScale or 0.0,
            cameraShake = cfg.cameraShake or 0.35,
            cameraShakeRadius = cfg.cameraShakeRadius or 140.0,
            triggerVehicleAlarms = (cfg.vehicleAlarmRadius or 0.0) > 0.0,
            vehicleAlarmRadius = cfg.vehicleAlarmRadius or 45.0,
            triggerFire = (cfg.fireChance or 0) > 0 and math.random(1, 100) <= (cfg.fireChance or 0),
            fireDuration = math.random(fireDurationMin, fireDurationMax),
            debug = debugStrike,
        }

        broadcastStrike(strikeCoords, payload, GetPlayerRoutingBucket(src))
    end)
end

function lightningPole.start()
    registerHandlers()
end

function lightningPole.stop()
    recentStrikes = {}
    lastStrikeBySource = {}
    lastRequestBySource = {}
end

function lightningPole.handleCommand(source, args, hasPermission, notifyPlayer)
    local src = source > 0 and source or 0
    if src <= 0 then
        print('^3[weather] /lightningpole must be used in-game.^0')
        return
    end

    if type(hasPermission) ~= 'function' or not hasPermission(src, 'weather.debug') then
        notify(src, notifyPlayer, 'Lightning Pole', Lang.no_permission, 'error')
        return
    end

    local sub = args and args[1] and string.lower(args[1]) or 'nearest'
    if sub ~= 'nearest' and sub ~= 'scan' and sub ~= 'debugscan' and sub ~= 'debug' and sub ~= 'export' then
        notify(src, notifyPlayer, 'Lightning Pole', 'Usage: /lightningpole [nearest|scan|debugscan|debug|export] [radius]', 'error')
        return
    end

    local radius = tonumber(args and args[2])
    if not isFiniteNumber(radius) then
        radius = lightningConfig().searchRadius or 160.0
    end
    radius = math.max(5.0, math.min(radius, 500.0))

    TriggerClientEvent('dynamic_weather:client:runLightningPoleCommand', src, {
        action = sub,
        radius = radius,
    })
end

AddEventHandler('playerDropped', function()
    local src = source
    lastStrikeBySource[src] = nil
    lastRequestBySource[src] = nil
end)

return lightningPole
