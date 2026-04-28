local lightningPole = {}
local active = false
local handlersRegistered = false
local ambientThread = nil
local markerThread = nil
local debugEnabled = false
local debugMarkers = {}
local blackoutActive = false
local blackoutGeneration = 0
local poleModelCache = nil
local lastAmbientAttemptAt = 0

local AddExplosion = AddExplosion
local DoesEntityExist = DoesEntityExist
local DrawMarker = DrawMarker
local ForceLightningFlash = ForceLightningFlash
local GetClosestObjectOfType = GetClosestObjectOfType
local GetEntityCoords = GetEntityCoords
local GetEntityModel = GetEntityModel
local GetGamePool = GetGamePool
local GetGameTimer = GetGameTimer
local GetInteriorFromEntity = GetInteriorFromEntity
local GetPlayerPed = GetPlayerPed
local PlayerPedId = PlayerPedId
local RemoveScriptFire = RemoveScriptFire
local SetArtificialLightsState = SetArtificialLightsState
local SetArtificialLightsStateAffectsVehicles = SetArtificialLightsStateAffectsVehicles
local SetVehicleAlarm = SetVehicleAlarm
local ShakeGameplayCam = ShakeGameplayCam
local StartScriptFire = StartScriptFire
local StartVehicleAlarm = StartVehicleAlarm
local StopGameplayCamShaking = StopGameplayCamShaking
local ipairs = ipairs
local math = math
local pairs = pairs
local type = type

local function lightningConfig()
    return Config.LightningPoleStrike or {}
end

local function distSq(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

local function buildPoleModelCache()
    local cfg = lightningConfig()
    local hashes = {}
    local names = {}
    local offsets = {}

    for _, modelName in ipairs(cfg.powerPoleModels or {}) do
        local hash = type(modelName) == 'number' and modelName or joaat(modelName)
        if hash and names[hash] == nil then
            hashes[#hashes + 1] = hash
            names[hash] = modelName
        end
    end

    for modelName, offset in pairs(cfg.modelStrikeOffsets or {}) do
        local hash = type(modelName) == 'number' and modelName or joaat(modelName)
        if hash and type(offset) == 'vector3' then
            offsets[hash] = offset
        end
    end

    poleModelCache = {
        hashes = hashes,
        names = names,
        offsets = offsets,
    }

    return poleModelCache
end

local function getPoleModelCache()
    if poleModelCache then return poleModelCache end
    return buildPoleModelCache()
end

local function currentZoneState()
    local engine = lib.require('modules.client.engine')
    local sync = lib.require('modules.client.sync')
    local zone = engine and engine.findPlayerZone and engine.findPlayerZone() or nil
    local states = sync and sync.getZoneStates and sync.getZoneStates() or {}
    return zone, zone and states[zone.id] or nil
end

local function normalizeWeather(weather)
    if type(weather) ~= 'string' or #weather == 0 then
        return Config.globalFallbackWeather or 'CLEAR'
    end

    return string.upper(weather)
end

local function resolveSeverity(weather, state)
    if state and state.severity ~= nil then
        local severity = tonumber(state.severity)
        if severity then return severity end
    end

    weather = normalizeWeather(weather)
    if weather == 'THUNDER' then return 4 end
    if weather == 'RAIN' then return 2 end
    return ((Config.WeatherData or {}).defaultSeverity or 1)
end

local function getStormProfile()
    local engine = lib.require('modules.client.engine')
    local weather = engine and engine.getCurrentWeather and engine.getCurrentWeather() or Config.globalFallbackWeather
    weather = normalizeWeather(weather)

    local zone, state = currentZoneState()
    local severity = resolveSeverity(weather, state)

    return {
        weather = weather,
        severity = severity,
        zoneId = zone and zone.id or nil,
    }
end

local function isStormEligible(debugRequested)
    if debugRequested then return true end

    local cfg = lightningConfig()
    if cfg.enabled == false then return false end
    if GetInteriorFromEntity(PlayerPedId()) ~= 0 then return false end

    local profile = getStormProfile()
    local weatherTypes = cfg.weatherTypes or {}
    if weatherTypes[profile.weather] ~= true then
        return false
    end

    return profile.severity >= (cfg.minSeverity or 4)
end

local function setLocalBlackoutState(on)
    on = on == true
    SetArtificialLightsState(on)
    if SetArtificialLightsStateAffectsVehicles then
        SetArtificialLightsStateAffectsVehicles(not on)
    end
end

local function restoreBaselineLighting()
    setLocalBlackoutState(GlobalState.dynamic_weather_blackout == true)
end

local function randomRange(minValue, maxValue)
    maxValue = math.max(minValue, maxValue)
    return math.random(minValue, maxValue)
end

local function pushDebugMarker(coords, duration)
    debugMarkers[#debugMarkers + 1] = {
        coords = coords,
        expiresAt = GetGameTimer() + (duration or 5000),
    }
end

local function trimDebugMarkers()
    local now = GetGameTimer()

    for index = #debugMarkers, 1, -1 do
        if now >= debugMarkers[index].expiresAt then
            table.remove(debugMarkers, index)
        end
    end
end

local function formatVector(coords)
    return ('vector3(%.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z)
end

local function getStrikeCoords(poleEntity, poleCoords)
    local cache = getPoleModelCache()
    local model = GetEntityModel(poleEntity)
    local offset = cache.offsets[model] or lightningConfig().defaultStrikeOffset or vector3(0.0, 0.0, 11.0)
    local coords = poleCoords or GetEntityCoords(poleEntity)

    return vector3(
        coords.x + offset.x,
        coords.y + offset.y,
        coords.z + offset.z
    )
end

local function findNearestPowerPole(radius, allowFullScan)
    local cfg = lightningConfig()
    local cache = getPoleModelCache()
    local pedCoords = GetEntityCoords(PlayerPedId())
    local nearestEntity = nil
    local nearestCoords = nil
    local nearestDistSq = radius * radius
    local sourceName = nil

    for _, model in ipairs(cache.hashes) do
        local object = GetClosestObjectOfType(
            pedCoords.x,
            pedCoords.y,
            pedCoords.z,
            radius,
            model,
            false,
            false,
            false
        )

        if object ~= 0 and DoesEntityExist(object) then
            local coords = GetEntityCoords(object)
            local distanceSq = distSq(coords, pedCoords)
            if distanceSq <= nearestDistSq then
                nearestEntity = object
                nearestCoords = coords
                nearestDistSq = distanceSq
                sourceName = 'closest_object'
            end
        end
    end

    if nearestEntity then
        local model = GetEntityModel(nearestEntity)
        return {
            entity = nearestEntity,
            coords = nearestCoords,
            model = model,
            modelName = cache.names[model] or tostring(model),
            distance = math.sqrt(nearestDistSq),
            source = sourceName,
        }
    end

    local pool = GetGamePool('CObject')
    local maxScanned = allowFullScan and #pool or math.min(#pool, cfg.poolScanLimit or 220)

    for index = 1, maxScanned do
        local object = pool[index]
        if DoesEntityExist(object) then
            local model = GetEntityModel(object)
            if cache.names[model] then
                local coords = GetEntityCoords(object)
                local distanceSq = distSq(coords, pedCoords)
                if distanceSq <= nearestDistSq then
                    nearestEntity = object
                    nearestCoords = coords
                    nearestDistSq = distanceSq
                    sourceName = 'pool_scan'
                end
            end
        end
    end

    if not nearestEntity then return nil end

    local model = GetEntityModel(nearestEntity)
    return {
        entity = nearestEntity,
        coords = nearestCoords,
        model = model,
        modelName = cache.names[model] or tostring(model),
        distance = math.sqrt(nearestDistSq),
        source = sourceName,
    }
end

local function scanNearbyPowerPoles(radius)
    local cache = getPoleModelCache()
    local pedCoords = GetEntityCoords(PlayerPedId())
    local radiusSq = radius * radius
    local poles = {}

    for _, object in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(object) then
            local model = GetEntityModel(object)
            if cache.names[model] then
                local coords = GetEntityCoords(object)
                local distanceSq = distSq(coords, pedCoords)
                if distanceSq <= radiusSq then
                    poles[#poles + 1] = {
                        entity = object,
                        coords = coords,
                        model = model,
                        modelName = cache.names[model] or tostring(model),
                        distance = math.sqrt(distanceSq),
                    }
                end
            end
        end
    end

    table.sort(poles, function(a, b)
        return a.distance < b.distance
    end)

    return poles
end

local function runBlackout(duration)
    if duration <= 0 or blackoutActive then return end

    blackoutActive = true
    blackoutGeneration = blackoutGeneration + 1
    local generation = blackoutGeneration
    local cfg = lightningConfig()
    local baseline = GlobalState.dynamic_weather_blackout == true
    local current = baseline

    local function isCurrent()
        return active and blackoutActive and generation == blackoutGeneration
    end

    local function applyState(on)
        current = on == true
        setLocalBlackoutState(current)
    end

    local function flicker(count)
        for _ = 1, count do
            if not isCurrent() then return false end
            applyState(not current)
            Wait(randomRange(cfg.flickerOnMin or 80, cfg.flickerOnMax or 180))
            if not isCurrent() then return false end
            applyState(not current)
            Wait(randomRange(cfg.flickerOffMin or 80, cfg.flickerOffMax or 240))
        end

        return true
    end

    CreateThread(function()
        if not flicker(cfg.flickerBursts or 3) then
            restoreBaselineLighting()
            blackoutActive = false
            return
        end

        if not isCurrent() then
            restoreBaselineLighting()
            blackoutActive = false
            return
        end

        applyState(true)
        Wait(duration)

        if not flicker(cfg.restoreFlickerBursts or 2) then
            restoreBaselineLighting()
            blackoutActive = false
            return
        end

        restoreBaselineLighting()
        blackoutActive = false
    end)
end

local function maybeTriggerVehicleAlarms(strikeCoords, radius)
    if radius <= 0.0 then return end

    local radiusSq = radius * radius
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) then
            local coords = GetEntityCoords(vehicle)
            if distSq(coords, strikeCoords) <= radiusSq then
                SetVehicleAlarm(vehicle, true)
                StartVehicleAlarm(vehicle)
            end
        end
    end
end

local function maybeTriggerFire(strikeCoords, duration)
    local fireHandle = StartScriptFire(strikeCoords.x, strikeCoords.y, strikeCoords.z, 1, false)
    if not fireHandle or fireHandle == 0 then return end

    CreateThread(function()
        Wait(duration)
        RemoveScriptFire(fireHandle)
    end)
end

local function handleStrike(data)
    if type(data) ~= 'table' or type(data.strikeCoords) ~= 'table' then return end

    local cfg = lightningConfig()
    local strikeCoords = vector3(data.strikeCoords.x + 0.0, data.strikeCoords.y + 0.0, data.strikeCoords.z + 0.0)
    local playerCoords = GetEntityCoords(PlayerPedId())
    local distance = math.sqrt(distSq(playerCoords, strikeCoords))

    ForceLightningFlash()
    Wait(tonumber(data.impactDelay) or randomRange(cfg.impactDelayMin or 120, cfg.impactDelayMax or 350))

    AddExplosion(
        strikeCoords.x,
        strikeCoords.y,
        strikeCoords.z,
        tonumber(data.impactExplosionType) or cfg.impactExplosionType or 2,
        tonumber(data.impactExplosionScale) or cfg.impactExplosionScale or 0.0,
        true,
        false,
        0.0
    )

    local cameraShakeRadius = tonumber(data.cameraShakeRadius) or cfg.cameraShakeRadius or 140.0
    if distance <= cameraShakeRadius then
        ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', tonumber(data.cameraShake) or cfg.cameraShake or 0.35)
        CreateThread(function()
            Wait(700)
            StopGameplayCamShaking(false)
        end)
    end

    if data.triggerVehicleAlarms == true then
        maybeTriggerVehicleAlarms(strikeCoords, tonumber(data.vehicleAlarmRadius) or cfg.vehicleAlarmRadius or 45.0)
    end

    if data.triggerFire == true then
        maybeTriggerFire(strikeCoords, tonumber(data.fireDuration) or cfg.fireDurationMin or 1400)
    end

    local blackoutRadius = tonumber(data.blackoutRadius) or cfg.blackoutRadius or 175.0
    if distance <= blackoutRadius then
        runBlackout(tonumber(data.blackoutDuration) or cfg.blackoutMin or 3500)
    end

    if debugEnabled or data.debug == true then
        pushDebugMarker(strikeCoords, 5000)
        print(('^3[weather] Lightning pole strike at %s^0'):format(formatVector(strikeCoords)))
    end
end

local function requestPoleStrike(debugRequested)
    local cfg = lightningConfig()
    if not isStormEligible(debugRequested) then
        if debugRequested then
            print('^3[weather] Lightning pole strike blocked: severe storm conditions not active.^0')
        end
        return false
    end

    local now = GetGameTimer()
    if not debugRequested then
        local cooldown = cfg.cooldown or 180000
        if now - lastAmbientAttemptAt < cooldown then
            return false
        end
    end

    local pole = findNearestPowerPole(cfg.searchRadius or 160.0, debugRequested == true)
    if not pole then
        if debugRequested then
            print('^3[weather] No nearby streamed power pole found.^0')
        end
        return false
    end

    local strikeCoords = getStrikeCoords(pole.entity, pole.coords)
    TriggerServerEvent('dynamic_weather:server:requestLightningPoleStrike', {
        strikeCoords = {
            x = strikeCoords.x,
            y = strikeCoords.y,
            z = strikeCoords.z,
        },
        poleCoords = {
            x = pole.coords.x,
            y = pole.coords.y,
            z = pole.coords.z,
        },
        model = pole.model,
        debug = debugRequested == true,
    })

    if debugEnabled or debugRequested then
        pushDebugMarker(strikeCoords, 5000)
        print(('^3[weather] Requested pole strike: %s via %s (%s)^0'):format(
            pole.modelName,
            formatVector(strikeCoords),
            pole.source or 'unknown'))
    end

    if not debugRequested then
        lastAmbientAttemptAt = now
    end

    return true
end

local function debugScan(radius, exportOnly)
    local poles = scanNearbyPowerPoles(radius)
    if #poles == 0 then
        print('^3[weather] No nearby streamed power poles found.^0')
        return
    end

    print(('^3[weather] Nearby power poles: %d^0'):format(#poles))
    for index, pole in ipairs(poles) do
        local strikeCoords = getStrikeCoords(pole.entity, pole.coords)
        if exportOnly then
            print(('{ model = %q, coords = %s, strike = %s },'):format(
                pole.modelName,
                formatVector(pole.coords),
                formatVector(strikeCoords)))
        else
            print(('%d. %s dist=%.1fm base=%s strike=%s'):format(
                index,
                pole.modelName,
                pole.distance,
                formatVector(pole.coords),
                formatVector(strikeCoords)))
        end

        if debugEnabled then
            pushDebugMarker(strikeCoords, 7000)
        end
    end
end

local function handleCommand(data)
    local action = type(data) == 'table' and data.action or 'nearest'
    if action == 'nearest' then
        requestPoleStrike(true)
        return
    end

    if action == 'scan' then
        debugScan(lightningConfig().searchRadius or 160.0, false)
        return
    end

    if action == 'export' then
        debugScan(lightningConfig().searchRadius or 160.0, true)
        return
    end

    if action == 'debug' then
        debugEnabled = not debugEnabled
        print(('^3[weather] Lightning pole debug %s^0'):format(debugEnabled and 'enabled' or 'disabled'))
    end
end

local function startMarkerThread()
    if markerThread then return end

    markerThread = CreateThread(function()
        while active do
            local sleep = 500

            if debugEnabled then
                trimDebugMarkers()
                if #debugMarkers > 0 then
                    sleep = 0
                    for _, marker in ipairs(debugMarkers) do
                        DrawMarker(
                            28,
                            marker.coords.x,
                            marker.coords.y,
                            marker.coords.z,
                            0.0,
                            0.0,
                            0.0,
                            0.0,
                            0.0,
                            0.0,
                            0.25,
                            0.25,
                            0.25,
                            255,
                            220,
                            120,
                            180,
                            false,
                            true,
                            2,
                            false,
                            nil,
                            nil,
                            false
                        )
                    end
                end
            end

            Wait(sleep)
        end

        markerThread = nil
    end)
end

local function startAmbientThread()
    if ambientThread then return end

    ambientThread = CreateThread(function()
        while active do
            local cfg = lightningConfig()
            local minInterval = cfg.minInterval or 20000
            local maxInterval = math.max(minInterval, cfg.maxInterval or minInterval)
            Wait(math.random(minInterval, maxInterval))

            if active and cfg.enabled ~= false and isStormEligible(false) then
                if math.random(1, 100) <= (cfg.chance or 6) then
                    requestPoleStrike(false)
                end
            end
        end

        ambientThread = nil
    end)
end

local function registerHandlers()
    if handlersRegistered then return end
    handlersRegistered = true

    RegisterNetEvent('dynamic_weather:client:runLightningPoleCommand', function(data)
        handleCommand(data)
    end)

    RegisterNetEvent('dynamic_weather:client:doLightningPoleStrike', function(data)
        handleStrike(data)
    end)
end

function lightningPole.start()
    if active then return end
    active = true
    debugEnabled = lightningConfig().debug == true
    registerHandlers()
    startMarkerThread()
    startAmbientThread()
end

function lightningPole.stop()
    active = false
    blackoutActive = false
    blackoutGeneration = blackoutGeneration + 1
    debugMarkers = {}
    restoreBaselineLighting()
    StopGameplayCamShaking(true)
end

return lightningPole