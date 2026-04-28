local active = false
local threads = {}
local spawnedDebris = {}
local affectedWorldObjects = {}
local allowedWindModels = {}
local windHeading = nil
local nextBurstWindowAt = 0

local Wait = Wait
local PlayerPedId = PlayerPedId
local GetGameTimer = GetGameTimer
local GetEntityCoords = GetEntityCoords
local GetEntityHeading = GetEntityHeading
local GetEntityModel = GetEntityModel
local GetEntitySpeed = GetEntitySpeed
local GetGamePool = GetGamePool
local DoesEntityExist = DoesEntityExist
local GetHashKey = GetHashKey
local NetworkGetEntityIsNetworked = NetworkGetEntityIsNetworked
local NetworkHasControlOfEntity = NetworkHasControlOfEntity
local mathMin = math.min
local mathMax = math.max
local mathFloor = math.floor
local mathRandom = math.random

local worldObjectCount

local function cfg()
    return Config.WindDebris or Config.StormProps or {}
end

local function debugPrint(message)
    if cfg().debug then
        print(('[WindDebris] %s'):format(message))
    end
end

local function currentWeather()
    local engine = lib.require('modules.client.engine')
    return engine and engine.getCurrentWeather and engine.getCurrentWeather() or Config.globalFallbackWeather
end

local function currentZoneState()
    local engine = lib.require('modules.client.engine')
    local sync = lib.require('modules.client.sync')
    local zone = engine and engine.findPlayerZone and engine.findPlayerZone()
    local states = sync and sync.getZoneStates and sync.getZoneStates() or {}
    return zone, zone and states[zone.id] or nil
end

local function getStormIntensity()
    local settings = cfg()
    local weather = currentWeather()
    local weatherTypes = settings.weatherTypes or {}
    local intensity = weatherTypes[weather]
    local _, state = currentZoneState()
    local severity = tonumber(state and state.severity)
    local severityIntensity = severity and math.min(100, math.max(0, severity * 20)) or nil

    if type(intensity) == 'number' then
        return math.max(intensity, severityIntensity or 0), weather
    end

    if intensity == true then
        if weather == 'THUNDER' then return math.max(70, severityIntensity or 0), weather end
        if weather == 'RAIN' or weather == 'CLEARING' then return math.max(45, severityIntensity or 0), weather end
    end

    if severityIntensity then
        return severityIntensity, weather
    end

    return 0, weather
end

local function buildAllowlist()
    allowedWindModels = {}
    local settings = cfg()

    for _, model in ipairs(settings.lightModels or {}) do
        allowedWindModels[model] = 'light'
    end

    for _, model in ipairs(settings.mediumModels or {}) do
        allowedWindModels[model] = 'medium'
    end

    for _, model in ipairs(settings.heavyModels or {}) do
        allowedWindModels[model] = 'heavy'
    end

    for _, model in ipairs(settings.shoppingCartModels or {}) do
        allowedWindModels[model] = 'cart'
    end
end

local function isBlacklisted(model)
    local blacklist = Config.BlacklistedWindProps or {}
    if blacklist[model] == true or blacklist[tostring(model)] == true then return true end

    for name, enabled in pairs(blacklist) do
        if enabled == true and type(name) == 'string' and GetHashKey(name) == model then
            return true
        end
    end

    return false
end

local function getWindModelTier(model)
    if isBlacklisted(model) then return nil end
    return allowedWindModels[model]
end

local function getTierIntervals(tier, settings)
    if tier == 'cart' then
        return settings.cartGustMinInterval or 12000, settings.cartGustMaxInterval or 28000
    end

    if tier == 'medium' then
        return settings.mediumGustMinInterval or 5500, settings.mediumGustMaxInterval or 11000
    end

    if tier == 'heavy' then
        return settings.heavyCheckMinInterval or 5000, settings.heavyCheckMaxInterval or 12000
    end

    return settings.gustMinInterval or 2200, settings.gustMaxInterval or 6500
end

local function getBurstDeferRange(tier, settings)
    if tier == 'cart' then
        return settings.cartBurstDeferMin or 2200, settings.cartBurstDeferMax or 5000
    end

    if tier == 'heavy' then
        return settings.heavyBurstDeferMin or 900, settings.heavyBurstDeferMax or 1800
    end

    return settings.gustBurstDeferMin or 180, settings.gustBurstDeferMax or 650
end

local function getMinEventSpacing(tier, settings)
    if tier == 'cart' then
        return settings.cartMinEventSpacing or 15000
    end

    if tier == 'heavy' then
        return settings.heavyMinEventSpacing or 4000
    end

    if tier == 'medium' then
        return settings.mediumMinEventSpacing or 1200
    end

    return settings.lightMinEventSpacing or 700
end

local function getTierSpeedCap(tier, settings)
    if tier == 'cart' then
        return settings.maxCartEntitySpeed or 2.2
    end

    if tier == 'heavy' then
        return settings.maxHeavyEntitySpeed or 4.8
    end

    if tier == 'medium' then
        return settings.maxMediumEntitySpeed or 8.0
    end

    return settings.maxLightEntitySpeed or 11.0
end

local function scheduleNextTierCheck(data, tier, settings, now, cooldownMs)
    local minInterval, maxInterval = getTierIntervals(tier, settings)
    local delay = cooldownMs or mathRandom(minInterval, maxInterval)
    data.nextGustAt = now + delay
end

local function deferWindState(data, tier, settings, now)
    local minDelay, maxDelay = getBurstDeferRange(tier, settings)
    data.nextGustAt = now + mathRandom(minDelay, maxDelay)
end

local function makeWindState(tier)
    local now = GetGameTimer()
    local settings = cfg()
    local data = {
        tier = tier,
        createdAt = now,
        lastSeen = now,
        lastAppliedAt = 0,
        heavyCooldownUntil = 0,
    }

    scheduleNextTierCheck(data, tier, settings, now)
    return data
end

local function ensureWindState(data, tier)
    if not data then
        data = makeWindState(tier)
    else
        data.tier = tier or data.tier
        data.lastSeen = GetGameTimer()
        data.lastAppliedAt = data.lastAppliedAt or 0
        data.heavyCooldownUntil = data.heavyCooldownUntil or 0

        if not data.nextGustAt then
            scheduleNextTierCheck(data, data.tier, cfg(), GetGameTimer())
        end
    end

    return data
end

local function isValidWindEntity(entity)
    if not entity or entity == 0 then return false end
    if not DoesEntityExist(entity) then return false end
    if IsEntityAttached(entity) then return false end
    if IsEntityAPed(entity) or IsEntityAVehicle(entity) then return false end
    if NetworkGetEntityIsNetworked(entity) and not NetworkHasControlOfEntity(entity) then return false end

    local model = GetEntityModel(entity)
    local tier = getWindModelTier(model)
    if not tier then return false end

    return true, tier
end

local function countSpawnedByTier(tier)
    local count = 0

    for _, data in ipairs(spawnedDebris) do
        if data.tier == tier and data.entity and DoesEntityExist(data.entity) then
            count = count + 1
        end
    end

    return count
end

local function tierCountsAsHeavy(tier)
    return tier == 'heavy' or tier == 'cart'
end

local function totalManagedObjects()
    return #spawnedDebris + worldObjectCount()
end

local function trimWorldObjectsToLimit()
    local settings = cfg()
    local maxTracked = settings.maxTrackedWorldObjects or 10
    local count = worldObjectCount()

    if count <= maxTracked then return end

    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local ranked = {}

    for entity, data in pairs(affectedWorldObjects) do
        if DoesEntityExist(entity) then
            ranked[#ranked + 1] = {
                entity = entity,
                dist = #(GetEntityCoords(entity) - pCoords),
                lastSeen = data.lastSeen or 0,
            }
        else
            affectedWorldObjects[entity] = nil
        end
    end

    table.sort(ranked, function(a, b)
        if a.dist == b.dist then
            return a.lastSeen > b.lastSeen
        end

        return a.dist < b.dist
    end)

    for i = maxTracked + 1, #ranked do
        affectedWorldObjects[ranked[i].entity] = nil
    end

    debugPrint(('trimmed tracked world objects from %d to %d'):format(count, maxTracked))
end

local function getSpawnedDebrisState(entity)
    for _, data in ipairs(spawnedDebris) do
        if data.entity == entity and DoesEntityExist(entity) then
            return data
        end
    end

    return nil
end

local function cleanupSpawnedDebris(deleteAll)
    local settings = cfg()
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local now = GetGameTimer()
    local kept = {}

    for _, data in ipairs(spawnedDebris) do
        local entity = data.entity

        if entity and DoesEntityExist(entity) then
            local coords = GetEntityCoords(entity)
            local dist = #(coords - pCoords)
            local stale = now - (data.createdAt or now) > (settings.maxLifetime or 90000)

            if deleteAll or dist > (settings.deleteRadius or 95.0) or stale then
                SetEntityAsMissionEntity(entity, true, true)
                DeleteEntity(entity)
            else
                kept[#kept + 1] = data
            end
        end
    end

    spawnedDebris = deleteAll and {} or kept
end

local function cleanupWorldObjects()
    local now = GetGameTimer()

    for entity, data in pairs(affectedWorldObjects) do
        if not DoesEntityExist(entity) or now - (data.lastSeen or 0) > 15000 then
            affectedWorldObjects[entity] = nil
        end
    end

    trimWorldObjectsToLimit()
end

local function scanNearbyWindObjects()
    local settings = cfg()
    if settings.scanExistingObjects == false then return 0 end

    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local radius = settings.scanRadius or 55.0
    local maxTracked = settings.maxTrackedWorldObjects or 10
    local maxFoundPerScan = settings.maxWorldObjectsAddedPerScan or mathMax(1, maxTracked)
    local found = 0

    for _, object in ipairs(GetGamePool('CObject')) do
        if worldObjectCount() >= maxTracked then break end
        if found >= maxFoundPerScan then break end

        local valid, tier = isValidWindEntity(object)

        if valid and not getSpawnedDebrisState(object) then
            local coords = GetEntityCoords(object)
            if #(coords - pCoords) <= radius then
                local data = ensureWindState(affectedWorldObjects[object], tier)
                data.lastSeen = GetGameTimer()
                affectedWorldObjects[object] = data
                found = found + 1
            end
        end
    end

    trimWorldObjectsToLimit()

    debugPrint(('scanned world objects, found %d valid objects'):format(found))
    return found
end

local function getRandomDebrisModel(stormIntensity)
    local settings = cfg()

    if stormIntensity >= (settings.minStormIntensity or 45) then
        local models = settings.mediumModels or {}
        if math.random(1, 100) <= 25 and countSpawnedByTier('medium') < (settings.maxMediumDebris or 7) and #models > 0 then
            return models[math.random(#models)], 'medium'
        end
    end

    local models = settings.lightModels or {}
    if countSpawnedByTier('light') < (settings.maxLightDebris or 20) and #models > 0 then
        return models[math.random(#models)], 'light'
    end
end

local function getDebrisSpawnCoords()
    local settings = cfg()
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local behind = math.rad(heading + 180.0 + math.random(-90, 90))
    local dist = mathRandom(
        mathFloor(settings.spawnRadiusMin or 18.0),
        mathFloor(settings.spawnRadiusMax or 42.0)
    )
    local x = pCoords.x + math.cos(behind) * dist
    local y = pCoords.y + math.sin(behind) * dist
    local z = pCoords.z + 20.0
    local found, groundZ = GetGroundZFor_3dCoord(x, y, z, false)

    if not found then return nil end
    return vector3(x, y, groundZ + 0.15)
end

local function loadModel(model)
    RequestModel(model)
    local timeout = GetGameTimer() + 3000

    while not HasModelLoaded(model) do
        Wait(0)
        if GetGameTimer() > timeout then
            debugPrint(('failed to load model %s'):format(model))
            return false
        end
    end

    return true
end

local function shouldSkipForceForSpeed(entity, tier, data, settings, now)
    local speedCap = getTierSpeedCap(tier, settings)
    local currentSpeed = GetEntitySpeed(entity)

    if currentSpeed <= speedCap then return false end

    data.lastSeen = now
    deferWindState(data, tier, settings, now)
    debugPrint(('skipped %s gust entity=%s speed=%.2f cap=%.2f'):format(tier, entity, currentSpeed, speedCap))
    return true
end

local function makeBurstBudget(settings, stormIntensity)
    local now = GetGameTimer()
    if now < nextBurstWindowAt then
        return {
            totalLimit = 0,
            heavyLimit = 0,
            used = 0,
            heavyUsed = 0,
        }
    end

    local totalLimit = settings.maxBurstEvents or 2

    if stormIntensity >= (settings.minStormIntensity or 45) then
        totalLimit = settings.maxBurstEventsStorm or totalLimit
    end

    return {
        totalLimit = mathMax(1, totalLimit),
        heavyLimit = mathMax(0, settings.maxHeavyBurstEvents or 1),
        used = 0,
        heavyUsed = 0,
    }
end

local function reserveBurstSlot(budget, entity, tier, data, settings, now)
    if not budget then return true end

    local hitBudget = budget.used >= budget.totalLimit
        or (tierCountsAsHeavy(tier) and budget.heavyUsed >= budget.heavyLimit)

    if hitBudget then
        deferWindState(data, tier, settings, now)
        debugPrint(('deferred %s entity=%s burst=%d/%d heavy=%d/%d'):format(
            tier,
            entity,
            budget.used,
            budget.totalLimit,
            budget.heavyUsed,
            budget.heavyLimit
        ))
        return false
    end

    budget.used = budget.used + 1
    if tierCountsAsHeavy(tier) then
        budget.heavyUsed = budget.heavyUsed + 1
    end

    nextBurstWindowAt = now + (settings.minBurstWindowMs or 900)

    return true
end

local function spawnWindDebris(stormIntensity, forcedModel, forcedTier)
    local settings = cfg()
    if #spawnedDebris >= (settings.maxTotalDebris or 28) then return false end
    if totalManagedObjects() >= (settings.maxManagedObjects or 18) then return false end

    local model, tier = forcedModel, forcedTier
    if not model then
        model, tier = getRandomDebrisModel(stormIntensity)
    end
    if not model or isBlacklisted(model) then return false end

    local coords = getDebrisSpawnCoords()
    if not coords then return false end
    if not loadModel(model) then return false end

    local object = CreateObject(model, coords.x, coords.y, coords.z, false, false, true)
    SetModelAsNoLongerNeeded(model)

    if not object or object == 0 or not DoesEntityExist(object) then
        return false
    end

    SetEntityAsMissionEntity(object, true, true)
    SetEntityDynamic(object, true)
    ActivatePhysics(object)
    SetEntityCollision(object, true, true)
    SetEntityHasGravity(object, true)
    FreezeEntityPosition(object, false)

    spawnedDebris[#spawnedDebris + 1] = {
        entity = object,
        tier = tier,
        createdAt = GetGameTimer(),
        nextGustAt = makeWindState(tier).nextGustAt,
        lastAppliedAt = 0,
        heavyCooldownUntil = 0,
    }

    debugPrint(('spawned %s debris model=%s total=%d'):format(tier, model, #spawnedDebris))
    return true
end

local function getWindVector()
    local settings = cfg()
    local _, state = currentZoneState()
    local syncedHeading = tonumber(state and state.windDirection)

    if not windHeading then
        windHeading = syncedHeading or settings.windDirection or 240.0
    elseif syncedHeading then
        windHeading = (windHeading * 0.85) + (syncedHeading * 0.15)
    end

    local sway = settings.windDirectionSway or 15
    windHeading = windHeading + mathRandom(-sway, sway)

    local rad = math.rad(windHeading)
    return vector3(math.cos(rad), math.sin(rad), 0.0)
end

local function randomForce(min, max)
    return mathRandom(mathFloor(min * 10), mathFloor(max * 10)) / 10.0
end

local function getForceForTier(tier, stormIntensity)
    local settings = cfg()
    local scale = mathMax(0.2, mathMin(stormIntensity / 100.0, 1.4))

    if tier == 'heavy' then
        return randomForce(settings.heavyForceMin or 6.0, settings.heavyForceMax or 14.0) * scale
    end

    if tier == 'medium' then
        return randomForce(settings.mediumForceMin or 4.0, settings.mediumForceMax or 10.0) * scale
    end

    return randomForce(settings.lightForceMin or 2.5, settings.lightForceMax or 7.5) * scale
end

local function getHeavyRollVelocity(stormIntensity)
    local settings = cfg()
    local wind = getWindVector()
    local maxRollSpeed = settings.maxHeavyRollSpeed or 4.2
    local scale = mathMax(0.65, mathMin(stormIntensity / 100.0, 1.0))
    local rollSpeed = randomForce(math.max(1.2, maxRollSpeed * 0.45), maxRollSpeed) * scale
    local sideDrift = mathRandom(-30, 30) / 100.0
    local lift = mathRandom(5, 16) / 100.0

    return (wind.x * rollSpeed) + sideDrift, (wind.y * rollSpeed) - sideDrift, lift
end

local function getCartRollVelocity(entity, stormIntensity)
    local settings = cfg()
    local wind = getWindVector()
    local heading = math.rad(GetEntityHeading(entity))
    local forwardX = math.cos(heading)
    local forwardY = math.sin(heading)
    local dot = (wind.x * forwardX) + (wind.y * forwardY)
    local direction = dot >= 0.0 and 1.0 or -1.0
    local maxRollSpeed = settings.maxCartRollSpeed or 1.4
    local scale = mathMax(0.35, mathMin(stormIntensity / 100.0, 0.85))
    local rollSpeed = randomForce(math.max(0.25, maxRollSpeed * 0.35), maxRollSpeed) * scale

    return forwardX * direction * rollSpeed, forwardY * direction * rollSpeed, 0.0
end

local function applyHeavyWindEvent(entity, data, stormIntensity, forced, budget)
    local settings = cfg()
    local now = GetGameTimer()

    data = ensureWindState(data, 'heavy')

    if settings.enableHeavyPropWind == false then return false end
    if stormIntensity < (settings.heavyPropMinStormIntensity or 90) then return false end
    if not forced and now < (data.heavyCooldownUntil or 0) then return false end
    if not forced and now < (data.nextGustAt or 0) then return false end
    if not forced and now - (data.lastAppliedAt or 0) < getMinEventSpacing('heavy', settings) then return false end

    if not forced then
        local moveChance = settings.heavyPropMoveChance or 14
        if mathRandom(1, 100) > moveChance then
            scheduleNextTierCheck(data, 'heavy', settings, now)
            return false
        end
    end

    if not forced and not reserveBurstSlot(budget, entity, 'heavy', data, settings, now) then return false end
    if not forced and shouldSkipForceForSpeed(entity, 'heavy', data, settings, now) then return false end

    SetEntityDynamic(entity, true)
    ActivatePhysics(entity)
    SetEntityHasGravity(entity, true)
    SetEntityCollision(entity, true, true)
    FreezeEntityPosition(entity, false)

    local velX, velY, velZ = getHeavyRollVelocity(stormIntensity)
    SetEntityVelocity(entity, velX, velY, velZ)

    local cooldownMs = settings.heavyPropCooldown or 20000
    data.heavyCooldownUntil = now + cooldownMs
    data.lastAppliedAt = now
    scheduleNextTierCheck(data, 'heavy', settings, now, cooldownMs + mathRandom(1500, 5000))

    debugPrint(('heavy wind event entity=%s cooldown=%dms velocity=%.2f/%.2f/%.2f'):format(entity, cooldownMs, velX, velY, velZ))
    return true
end

local function applyCartWindEvent(entity, data, stormIntensity, forced, budget)
    local settings = cfg()
    local now = GetGameTimer()

    data = ensureWindState(data, 'cart')

    if settings.enableShoppingCartWind == false then return false end
    if stormIntensity < (settings.cartMinStormIntensity or 80) then return false end
    if not forced and now < (data.heavyCooldownUntil or 0) then return false end
    if not forced and now < (data.nextGustAt or 0) then return false end
    if not forced and now - (data.lastAppliedAt or 0) < getMinEventSpacing('cart', settings) then return false end

    if not forced then
        local moveChance = settings.cartMoveChance or 5
        if mathRandom(1, 100) > moveChance then
            scheduleNextTierCheck(data, 'cart', settings, now)
            return false
        end
    end

    if not forced and not reserveBurstSlot(budget, entity, 'cart', data, settings, now) then return false end
    if not forced and shouldSkipForceForSpeed(entity, 'cart', data, settings, now) then return false end

    SetEntityDynamic(entity, true)
    ActivatePhysics(entity)
    SetEntityHasGravity(entity, true)
    SetEntityCollision(entity, true, true)
    FreezeEntityPosition(entity, false)

    local velX, velY, velZ = getCartRollVelocity(entity, stormIntensity)
    SetEntityVelocity(entity, velX, velY, velZ)

    local cooldownMs = settings.cartCooldown or 25000
    data.heavyCooldownUntil = now + cooldownMs
    data.lastAppliedAt = now
    scheduleNextTierCheck(data, 'cart', settings, now, cooldownMs + mathRandom(3000, 9000))

    debugPrint(('cart wind event entity=%s cooldown=%dms velocity=%.2f/%.2f/%.2f'):format(entity, cooldownMs, velX, velY, velZ))
    return true
end

local function applyWindGust(entity, tier, stormIntensity, data, budget)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if IsEntityAttached(entity) or IsEntityAPed(entity) or IsEntityAVehicle(entity) then return false end
    if NetworkGetEntityIsNetworked(entity) and not NetworkHasControlOfEntity(entity) then return false end

    local settings = cfg()
    local now = GetGameTimer()
    data = ensureWindState(data, tier)

    if tier == 'cart' then
        return applyCartWindEvent(entity, data, stormIntensity, false, budget)
    end

    if tier == 'heavy' then
        return applyHeavyWindEvent(entity, data, stormIntensity, false, budget)
    end

    if now < (data.nextGustAt or 0) then return false end
    if now - (data.lastAppliedAt or 0) < getMinEventSpacing(tier, settings) then return false end
    if not reserveBurstSlot(budget, entity, tier, data, settings, now) then return false end
    if shouldSkipForceForSpeed(entity, tier, data, settings, now) then return false end

    local wind = getWindVector()
    local force = getForceForTier(tier, stormIntensity)
    local sideDrift = mathRandom(-20, 20) / 100.0
    local upward = mathRandom(5, 30) / 100.0

    SetEntityDynamic(entity, true)
    ActivatePhysics(entity)
    SetEntityHasGravity(entity, true)
    SetEntityCollision(entity, true, true)
    FreezeEntityPosition(entity, false)

    ApplyForceToEntity(
        entity,
        1,
        (wind.x + sideDrift) * force,
        (wind.y - sideDrift) * force,
        upward * force,
        0.0,
        0.0,
        0.0,
        0,
        false,
        true,
        true,
        false,
        true
    )

    data.lastAppliedAt = now
    scheduleNextTierCheck(data, tier, settings, now)

    return true
end

local function findNearestHeavyWindEntity(radius)
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local bestEntity, bestData, bestDist

    for _, object in ipairs(GetGamePool('CObject')) do
        local valid, tier = isValidWindEntity(object)
        if valid and tier == 'heavy' then
            local coords = GetEntityCoords(object)
            local dist = #(coords - pCoords)
            if dist <= radius and (not bestDist or dist < bestDist) then
                bestEntity = object
                bestDist = dist
                bestData = ensureWindState(getSpawnedDebrisState(object) or affectedWorldObjects[object], 'heavy')
            end
        end
    end

    if bestEntity and not getSpawnedDebrisState(bestEntity) then
        affectedWorldObjects[bestEntity] = bestData
    end

    return bestEntity, bestData, bestDist
end

worldObjectCount = function()
    local count = 0
    for _ in pairs(affectedWorldObjects) do
        count = count + 1
    end
    return count
end

local function gustAll(stormIntensity)
    local affected = 0
    local budget = makeBurstBudget(cfg(), stormIntensity)

    for i = #spawnedDebris, 1, -1 do
        local data = spawnedDebris[i]
        if not data.entity or not DoesEntityExist(data.entity) then
            table.remove(spawnedDebris, i)
        elseif applyWindGust(data.entity, data.tier, stormIntensity, data, budget) then
            affected = affected + 1
        end
    end

    for entity, data in pairs(affectedWorldObjects) do
        if DoesEntityExist(entity) then
            if getSpawnedDebrisState(entity) then
                affectedWorldObjects[entity] = nil
            elseif applyWindGust(entity, data.tier, stormIntensity, data, budget) then
                affected = affected + 1
            end
        else
            affectedWorldObjects[entity] = nil
        end
    end

    debugPrint(('gust affected %d entities, spawned=%d world=%d'):format(affected, #spawnedDebris, worldObjectCount()))
    return affected
end

local function startThread(fn)
    threads[#threads + 1] = CreateThread(fn)
end

local stormProps = {}

function stormProps.start()
    if active then return end

    buildAllowlist()
    active = true

    startThread(function()
        while active do
            local settings = cfg()
            Wait(settings.scanInterval or 5000)

            local stormIntensity = getStormIntensity()
            if settings.enabled ~= false and stormIntensity >= (settings.minStormIntensity or 45) then
                scanNearbyWindObjects()
            else
                affectedWorldObjects = {}
            end
        end
    end)

    startThread(function()
        while active do
            local settings = cfg()
            Wait(settings.spawnInterval or 2500)

            local stormIntensity = getStormIntensity()
            local shouldSpawn = worldObjectCount() < (settings.minWorldObjectsBeforeSpawn or 4)
                or settings.spawnEvenWithWorldObjects == true

            if settings.enabled ~= false
                and settings.spawnClientDebris ~= false
                and stormIntensity >= (settings.minStormIntensity or 45)
                and shouldSpawn then
                spawnWindDebris(stormIntensity)
            end
        end
    end)

    startThread(function()
        while active do
            local settings = cfg()
            local stormIntensity = getStormIntensity()
            if settings.enabled ~= false and stormIntensity >= (settings.minStormIntensity or 45) then
                Wait(settings.gustTickInterval or 250)
                gustAll(stormIntensity)
            else
                Wait(settings.idleGustTickInterval or 1500)
            end
        end
    end)

    startThread(function()
        while active do
            Wait(5000)
            local stormIntensity = getStormIntensity()
            cleanupWorldObjects()
            cleanupSpawnedDebris(stormIntensity < (cfg().minStormIntensity or 45))
        end
    end)
end

function stormProps.stop()
    active = false
    threads = {}
    affectedWorldObjects = {}
    nextBurstWindowAt = 0
    cleanupSpawnedDebris(true)
end

RegisterCommand('winddebug', function()
    Config.WindDebris = Config.WindDebris or {}
    Config.WindDebris.debug = not Config.WindDebris.debug
    print(('[WindDebris] debug=%s'):format(tostring(Config.WindDebris.debug)))
end, false)

RegisterCommand('windspawn', function()
    local settings = cfg()
    local models = settings.lightModels or {}
    if #models == 0 then
        print('[WindDebris] windspawn failed: no lightModels configured')
        return
    end

    local model = models[math.random(#models)]
    local ok = model and spawnWindDebris(100, model, 'light')
    print(('[WindDebris] windspawn %s spawned=%d'):format(ok and 'ok' or 'failed', #spawnedDebris))
end, false)

RegisterCommand('windgust', function()
    local affected = gustAll(100)
    print(('[WindDebris] forced gust applied, affected=%d spawned=%d world=%d'):format(affected, #spawnedDebris, worldObjectCount()))
end, false)

RegisterCommand('windheavy', function()
    local settings = cfg()
    local radius = settings.debugHeavySearchRadius or 20.0
    local entity, data, dist = findNearestHeavyWindEntity(radius)

    if not entity then
        print(('[WindDebris] windheavy failed: no heavy wind prop within %.1fm'):format(radius))
        return
    end

    local ok = applyHeavyWindEvent(entity, data, 100, true)
    print(('[WindDebris] windheavy %s entity=%s dist=%.1f cooldown=%dms'):format(
        ok and 'ok' or 'skipped',
        entity,
        dist or -1.0,
        settings.heavyPropCooldown or 20000
    ))
end, false)

RegisterCommand('windscan', function()
    local found = scanNearbyWindObjects()
    print(('[WindDebris] scan found=%d trackedWorld=%d spawned=%d'):format(found, worldObjectCount(), #spawnedDebris))
end, false)

RegisterCommand('windclear', function()
    cleanupSpawnedDebris(true)
    affectedWorldObjects = {}
    print('[WindDebris] cleared spawned debris and tracked world objects')
end, false)

return stormProps
