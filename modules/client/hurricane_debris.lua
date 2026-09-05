local hurricaneDebris = {}

local active = false
local debugDisplay = false
local hurricaneState = {
    active = false,
    intensity = 0,
    windDirection = 0.0,
    windSpeed = 0.0,
    lightningMultiplier = 1.0,
}

local debris = {}
local validModels = {}
local invalidModels = {}
local categoryByModel = {}
local lastSkippedSpawnReason = 'not started'
local cleanupCount = 0
local modelsValidated = false

local Wait = Wait
local PlayerPedId = PlayerPedId
local GetEntityCoords = GetEntityCoords
local GetEntityHeading = GetEntityHeading
local GetGameTimer = GetGameTimer
local GetHashKey = GetHashKey
local DoesEntityExist = DoesEntityExist
local mathMax = math.max
local mathMin = math.min
local mathFloor = math.floor
local mathRandom = math.random
local nativeIsModelAnObject = rawget(_G, 'IsModelAnObject')

local function cfg()
    return Config.HurricaneDebris or {}
end

local function clampIntensity(value)
    local settings = cfg()
    local minIntensity = tonumber(settings.minIntensity) or 1
    local maxIntensity = tonumber(settings.maxIntensity) or 5
    local n = tonumber(value) or 0
    if n < minIntensity then return minIntensity end
    if n > maxIntensity then return maxIntensity end
    return mathFloor(n)
end

local function randFloat(minValue, maxValue)
    local minN = tonumber(minValue) or 0.0
    local maxN = tonumber(maxValue) or minN
    if maxN < minN then minN, maxN = maxN, minN end
    return minN + (mathRandom() * (maxN - minN))
end

local function getMaxDebris()
    local settings = cfg()
    local byIntensity = settings.maxDebrisByIntensity or {}
    return tonumber(byIntensity[clampIntensity(hurricaneState.intensity)]) or 0
end

local function getSpawnInterval()
    local settings = cfg()
    local byIntensity = settings.spawnIntervalByIntensityMs or {}
    return tonumber(byIntensity[clampIntensity(hurricaneState.intensity)]) or 1000
end

local function addCategoryModels(category, names)
    if type(names) ~= 'table' then return end

    for _, name in ipairs(names) do
        if type(name) == 'string' and #name > 0 then
            categoryByModel[name] = category
        end
    end
end

local function buildCategoryIndex()
    categoryByModel = {}
    local categories = cfg().categories or {}
    addCategoryModels('common', categories.common)
    addCategoryModels('uncommon', categories.uncommon)
    addCategoryModels('rare', categories.rare)
    addCategoryModels('disabled', categories.disabled)
end

local function isConfiguredObjectModel(hash)
    if cfg().requireObjectModel == false then
        return true
    end

    if type(nativeIsModelAnObject) == 'function' then
        return nativeIsModelAnObject(hash)
    end

    return true
end

local function inferCategory(name)
    if categoryByModel[name] then return categoryByModel[name] end
    if name:find('can') or name:find('bottle') or name:find('snack') then return 'uncommon' end
    if name:find('box') or name:find('bag') or name:find('hat') or name:find('shirt') or name:find('shoe') or name:find('scrap') then return 'rare' end
    return 'common'
end

local function validateConfiguredModels()
    validModels = {}
    invalidModels = {}
    buildCategoryIndex()

    local seen = {}
    for _, name in ipairs(cfg().props or {}) do
        if type(name) == 'string' and #name > 0 and not seen[name] then
            seen[name] = true
            local category = inferCategory(name)
            local hash = GetHashKey(name)

            if category ~= 'disabled'
                and IsModelInCdimage(hash)
                and IsModelValid(hash)
                and isConfiguredObjectModel(hash) then
                validModels[#validModels + 1] = {
                    name = name,
                    hash = hash,
                    category = category,
                }
            else
                invalidModels[#invalidModels + 1] = name
            end
        end
    end

    modelsValidated = true
    if #validModels == 0 then
        lastSkippedSpawnReason = 'no valid models'
    else
        lastSkippedSpawnReason = 'ready'
    end
end

local function requestModel(hash)
    RequestModel(hash)
    local timeoutAt = GetGameTimer() + (tonumber(cfg().modelLoadTimeoutMs) or 1500)

    while not HasModelLoaded(hash) do
        Wait(0)
        if GetGameTimer() >= timeoutAt then
            SetModelAsNoLongerNeeded(hash)
            return false
        end
    end

    return true
end

local function getCategoryWeights()
    local settings = cfg()
    local byIntensity = settings.categoryWeightsByIntensity or {}
    return byIntensity[clampIntensity(hurricaneState.intensity)]
        or settings.defaultCategoryWeights
        or { common = 70, uncommon = 22, rare = 8 }
end

local function pickModel()
    if #validModels == 0 then return nil end

    local weights = getCategoryWeights()
    local weighted = {}
    local total = 0

    for _, entry in ipairs(validModels) do
        local weight = tonumber(weights[entry.category]) or 0
        if weight > 0 then
            total = total + weight
            weighted[#weighted + 1] = {
                entry = entry,
                upper = total,
            }
        end
    end

    if total <= 0 or #weighted == 0 then return nil end

    local roll = mathRandom(1, total)
    for _, item in ipairs(weighted) do
        if roll <= item.upper then
            return item.entry
        end
    end

    return weighted[#weighted].entry
end

local function getWindVector()
    local heading = tonumber(hurricaneState.windDirection) or 0.0
    local rad = math.rad(heading)
    return vector3(math.cos(rad), math.sin(rad), 0.0)
end

local function getSideVector(wind)
    return vector3(-wind.y, wind.x, 0.0)
end

local function getPlayerForwardVector()
    local heading = GetEntityHeading(PlayerPedId())
    local rad = math.rad(heading)

    return vector3(
        -math.sin(rad),
        math.cos(rad),
        0.0
    )
end

local function getGroundZAt(x, y, fallbackZ)
    local settings = cfg()
    local probeHeight = tonumber(settings.groundProbeHeight) or 60.0
    local found, groundZ = GetGroundZFor_3dCoord(x, y, (fallbackZ or 0.0) + probeHeight, false)

    if found then return groundZ end
    return fallbackZ
end

local function getPassTarget(coords, forward)
    local settings = cfg()
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local passDistance = randFloat(settings.flyPastDistanceMin or 22.0, settings.flyPastDistanceMax or 48.0)
    local side = getSideVector(forward)
    local targetSide = randFloat(-(settings.flyPastTargetSideJitter or 5.0), settings.flyPastTargetSideJitter or 5.0)
    local targetX = pCoords.x + (forward.x * passDistance) + (side.x * targetSide)
    local targetY = pCoords.y + (forward.y * passDistance) + (side.y * targetSide)
    local groundZ = getGroundZAt(targetX, targetY, pCoords.z)
    local targetLift = randFloat(settings.flyPastTargetLiftMin or 0.2, settings.flyPastTargetLiftMax or 0.8)
    local target = vector3(
        targetX,
        targetY,
        groundZ + targetLift
    )
    local delta = target - coords
    local length = mathMax(0.001, #(delta))

    return target, vector3(delta.x / length, delta.y / length, delta.z / length)
end

local function getFps()
    local frameTime = GetFrameTime()
    if not frameTime or frameTime <= 0.0 then return 999.0 end
    return 1.0 / frameTime
end

local function isSpawnUnsafeForPlayer(ped)
    local settings = cfg()

    if settings.noSpawnInInterior ~= false and GetInteriorFromEntity(ped) ~= 0 then
        return 'interior'
    end

    if settings.noSpawnInVehicle == true and IsPedInAnyVehicle(ped, false) then
        return 'player in vehicle'
    end

    local minFps = tonumber(settings.skipWhenFpsBelow) or 0
    if minFps > 0 and getFps() < minFps then
        return 'low fps'
    end

    if settings.noSpawnUnderwater ~= false and (IsPedSwimmingUnderWater(ped) or IsEntityInWater(ped)) then
        return 'player underwater'
    end
end

local function isCoordUnderwater(x, y, z)
    local settings = cfg()
    if settings.noSpawnUnderwater == false then return false end
    local probeHeight = tonumber(settings.waterProbeHeight) or 1.5
    local buffer = tonumber(settings.waterSpawnBuffer) or 0.2
    local hasWater, waterZ = GetWaterHeight(x, y, z + probeHeight)
    return hasWater == true and type(waterZ) == 'number' and waterZ >= z - buffer
end

local function getSpawnCoords()
    local ped = PlayerPedId()
    local unsafe = isSpawnUnsafeForPlayer(ped)
    if unsafe then
        return nil, unsafe
    end

    local settings = cfg()
    local pCoords = GetEntityCoords(ped)

    if settings.spawnBehindPlayer ~= false and settings.spawnBehindCamera ~= false then
        local forward = getPlayerForwardVector()
        local side = getSideVector(forward)
        local distance = randFloat(
            settings.playerSpawnBackMinDistance or settings.cameraSpawnBackMinDistance or 18.0,
            settings.playerSpawnBackMaxDistance or settings.cameraSpawnBackMaxDistance or 34.0
        )
        local sideJitterMax = settings.playerSpawnSideJitter or settings.cameraSpawnSideJitter or 10.0
        local sideJitter = randFloat(-sideJitterMax, sideJitterMax)
        local lift = randFloat(
            settings.playerSpawnHeightMin or settings.cameraSpawnHeightMin or 2.0,
            settings.playerSpawnHeightMax or settings.cameraSpawnHeightMax or 8.0
        )
        local coords = vector3(
            pCoords.x - (forward.x * distance) + (side.x * sideJitter),
            pCoords.y - (forward.y * distance) + (side.y * sideJitter),
            pCoords.z + lift
        )

        if isCoordUnderwater(coords.x, coords.y, coords.z) then
            return nil, 'underwater'
        end

        local target, direction = getPassTarget(coords, forward)
        return coords, nil, {
            enabled = true,
            target = target,
            direction = direction,
        }
    end

    local wind = getWindVector()
    local side = getSideVector(wind)
    local distance = randFloat(settings.spawnMinDistance or 8.0, settings.spawnMaxDistance or 30.0)
    local sideOffsetScale = tonumber(settings.spawnSideOffsetScale) or 0.55
    local sideOffset = randFloat(-distance * sideOffsetScale, distance * sideOffsetScale)
    local upwindChance = tonumber(settings.upwindSpawnChance) or 72
    local upwindBias = mathRandom(1, 100) <= upwindChance and -1.0 or 1.0
    local x = pCoords.x + (wind.x * distance * upwindBias) + (side.x * sideOffset)
    local y = pCoords.y + (wind.y * distance * upwindBias) + (side.y * sideOffset)
    local probeHeight = tonumber(settings.groundProbeHeight) or 60.0
    local found, groundZ = GetGroundZFor_3dCoord(x, y, pCoords.z + probeHeight, false)

    if not found then
        return nil, 'no ground'
    end

    local z = groundZ + randFloat(settings.spawnGroundOffsetMin or 0.2, settings.spawnGroundOffsetMax or 1.2)
    if isCoordUnderwater(x, y, z) then
        return nil, 'underwater'
    end

    return vector3(x, y, z)
end

local function setAngularTumble(entity)
    local settings = cfg()
    local minSpin = tonumber(settings.angularVelocityMin) or 1.5
    local maxSpin = tonumber(settings.angularVelocityMax) or 8.0
    SetEntityAngularVelocity(
        entity,
        randFloat(-maxSpin, maxSpin),
        randFloat(-maxSpin, maxSpin),
        randFloat(minSpin, maxSpin)
    )
end

local function getLift()
    local settings = cfg()
    local chance = tonumber(settings.verticalLiftChance) or 0.0
    if mathRandom() > chance then return 0.0 end
    return randFloat(settings.verticalLiftMin or 0.8, settings.verticalLiftMax or 4.0)
end

local function getFlyByLift()
    local settings = cfg()
    local chance = tonumber(settings.flyPastVerticalLiftChance) or 0.25
    if mathRandom() > chance then return 0.0 end
    return randFloat(settings.flyPastVerticalLiftMin or 0.0, settings.flyPastVerticalLiftMax or 1.0)
end

local function setInitialVelocity(entity, flyBy)
    local settings = cfg()
    local speed = randFloat(settings.initialVelocityMin or 4.0, settings.initialVelocityMax or 13.0)

    if flyBy and flyBy.enabled and flyBy.direction then
        SetEntityVelocity(
            entity,
            flyBy.direction.x * speed,
            flyBy.direction.y * speed,
            (flyBy.direction.z * speed) + getFlyByLift()
        )
        setAngularTumble(entity)
        return
    end

    local wind = getWindVector()
    local directionVariation = tonumber(settings.directionVariationDegrees) or 0.0
    if directionVariation > 0 then
        local angleOffset = math.rad(randFloat(-directionVariation, directionVariation))
        local cosOffset = math.cos(angleOffset)
        local sinOffset = math.sin(angleOffset)
        wind = vector3(
            wind.x * cosOffset - wind.y * sinOffset,
            wind.x * sinOffset + wind.y * cosOffset,
            wind.z
        )
    end
    local side = getSideVector(wind)
    local sideScale = tonumber(settings.initialSideVelocityScale) or 0.35
    local sideSpeed = randFloat(-speed * sideScale, speed * sideScale)

    SetEntityVelocity(
        entity,
        (wind.x * speed) + (side.x * sideSpeed),
        (wind.y * speed) + (side.y * sideSpeed),
        getLift()
    )
    setAngularTumble(entity)
end

local function deleteDebrisEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    SetEntityAsMissionEntity(entity, true, true)
    DeleteObject(entity)
    if DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
    if DoesEntityExist(entity) then
        SetEntityAsNoLongerNeeded(entity)
    end
end

local function cleanupDebris(deleteAll)
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local now = GetGameTimer()
    local kept = {}
    local settings = cfg()
    local deleteDistance = tonumber(settings.deleteDistance) or 65.0
    local deleteBelowZ = tonumber(settings.deleteBelowZ) or -50.0
    local deleteWhenInWater = settings.deleteWhenInWater ~= false

    for _, item in ipairs(debris) do
        local entity = item.entity
        local delete = deleteAll or not entity or entity == 0 or not DoesEntityExist(entity)

        if not delete then
            local coords = GetEntityCoords(entity)
            local dist = #(coords - pCoords)
            local passedPlayer = false

            if item.flyByDirection then
                local rel = coords - pCoords
                local forwardProgress = (rel.x * item.flyByDirection.x) + (rel.y * item.flyByDirection.y) + (rel.z * item.flyByDirection.z)
                local minAge = tonumber(settings.flyPastDespawnAfterMs) or 3000
                passedPlayer = forwardProgress >= (tonumber(settings.flyPastDespawnDistance) or 18.0)
                    and now - (item.createdAt or now) >= minAge
            end

            delete = dist > deleteDistance
                or passedPlayer
                or now >= (item.expiresAt or now)
                or coords.z < deleteBelowZ
                or (deleteWhenInWater and IsEntityInWater(entity))
        end

        if delete then
            deleteDebrisEntity(entity)
            cleanupCount = cleanupCount + 1
        else
            kept[#kept + 1] = item
        end
    end

    debris = deleteAll and {} or kept
end

local function spawnDebris()
    if cfg().enabled == false then
        lastSkippedSpawnReason = 'disabled'
        return false
    end

    if not hurricaneState.active then
        lastSkippedSpawnReason = 'hurricane inactive'
        return false
    end

    if #debris >= getMaxDebris() then
        lastSkippedSpawnReason = 'budget full'
        return false
    end

    if not modelsValidated then
        validateConfiguredModels()
    end

    local model = pickModel()
    if not model then
        lastSkippedSpawnReason = 'no valid model'
        return false
    end

    local coords, reason, flyBy = getSpawnCoords()
    if not coords then
        lastSkippedSpawnReason = reason or 'no spawn coords'
        return false
    end

    if not requestModel(model.hash) then
        lastSkippedSpawnReason = 'model load timeout'
        return false
    end

    local settings = cfg()
    local object = CreateObject(
        model.hash,
        coords.x,
        coords.y,
        coords.z,
        settings.createNetworked == true or settings.localOnly == false,
        settings.createScriptHostObject == true,
        settings.createDoorFlag == true
    )
    SetModelAsNoLongerNeeded(model.hash)

    if not object or object == 0 or not DoesEntityExist(object) then
        lastSkippedSpawnReason = 'create failed'
        return false
    end

    SetEntityAsMissionEntity(object, settings.setMissionEntity ~= false, settings.grabMissionEntity ~= false)
    SetEntityDynamic(object, settings.setDynamic ~= false)
    ActivatePhysics(object)
    SetEntityHasGravity(object, settings.enableGravity ~= false)
    SetEntityCollision(object, (settings.enableCollision ~= false) and settings.disableCollision ~= true, settings.keepPhysicsOnCollisionChange ~= false)
    if settings.placeOnGroundOnSpawn ~= false and not (flyBy and flyBy.enabled) then
        PlaceObjectOnGroundProperly(object)
    end
    FreezeEntityPosition(object, settings.freezeOnSpawn == true)
    if (settings.groundSettleWaitMs or 0) > 0 then
        Wait(settings.groundSettleWaitMs)
    end
    setInitialVelocity(object, flyBy)

    local now = GetGameTimer()
    local expiresAt = now + mathFloor(randFloat(settings.lifetimeMinMs or 4500, settings.lifetimeMaxMs or 9000))
    if flyBy and flyBy.enabled then
        expiresAt = mathMax(expiresAt, now + (tonumber(settings.flyPastMinLifetimeMs) or 10000))
    end

    debris[#debris + 1] = {
        entity = object,
        model = model.name,
        category = model.category,
        createdAt = now,
        expiresAt = expiresAt,
        nextGustAt = now + mathRandom(settings.firstGustMinMs or 250, settings.firstGustMaxMs or 900),
        flyByDirection = flyBy and flyBy.direction or nil,
    }

    lastSkippedSpawnReason = 'spawned'
    return true
end

local function applyGust(item, now)
    if now < (item.nextGustAt or 0) then return false end

    local settings = cfg()
    local chance = tonumber(settings.gustChance) or 42
    chance = chance + ((clampIntensity(hurricaneState.intensity) - 1) * (tonumber(settings.gustChancePerIntensity) or 5))
    if mathRandom(1, 100) > mathMin(chance, tonumber(settings.gustChanceMax) or 70) then
        item.nextGustAt = now + mathRandom(settings.gustCooldownMinMs or 350, settings.gustCooldownMaxMs or 1100)
        return false
    end

    local entity = item.entity
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end

    local wind = item.flyByDirection or getWindVector()
    local side = getSideVector(wind)
    local force = randFloat(settings.gustForceMin or 0.8, settings.gustForceMax or 4.5)
    local sideScale = item.flyByDirection and (tonumber(settings.flyPastGustSideForceScale) or 0.12)
        or (tonumber(settings.gustSideForceScale) or 0.35)
    local sideForce = randFloat(-force * sideScale, force * sideScale)
    local lift = item.flyByDirection
        and randFloat(settings.flyPastGustLiftMin or 0.0, settings.flyPastGustLiftMax or 0.8)
        or getLift()

    ApplyForceToEntity(
        entity,
        settings.applyForceType or 1,
        (wind.x * force) + (side.x * sideForce),
        (wind.y * force) + (side.y * sideForce),
        lift,
        0.0,
        0.0,
        0.0,
        settings.applyForceBoneIndex or 0,
        settings.applyForceRelative == true,
        settings.applyForceHighForce ~= false,
        settings.applyForceScaleByMass ~= false,
        settings.applyForcePlayAudio == true,
        settings.applyForceScaleByTimeWarp ~= false
    )

    setAngularTumble(entity)
    item.nextGustAt = now + mathRandom(settings.gustCooldownMinMs or 350, settings.gustCooldownMaxMs or 1100)
    return true
end

local function applyAmbientWind()
    if not hurricaneState.active then return end
    SetWindDirection(tonumber(hurricaneState.windDirection) or 0.0)
    SetWindSpeed(tonumber(hurricaneState.windSpeed) or 0.0)
end

local function maybeLightning()
    if not hurricaneState.active then return end
    local settings = cfg()
    local baseChance = tonumber(settings.lightningChancePerTick) or 10
    local mult = tonumber(hurricaneState.lightningMultiplier) or 1.0
    local chance = mathMin(tonumber(settings.lightningChanceMax) or 90, mathFloor(baseChance * mult))
    if mathRandom(1, 100) <= chance then
        ForceLightningFlash()
    end
end

local function drawTextLine(text, x, y)
    local settings = cfg()
    local color = settings.debugTextColor or { r = 230, g = 240, b = 255, a = 220 }
    local scale = tonumber(settings.debugTextScale) or 0.28
    SetTextFont(tonumber(settings.debugTextFont) or 0)
    SetTextScale(scale, scale)
    SetTextColour(color.r or 230, color.g or 240, color.b or 255, color.a or 220)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

local function drawDebug()
    local lines = {
        ('Hurricane debris active=%s count=%d/%d'):format(tostring(hurricaneState.active), #debris, getMaxDebris()),
        ('spawn=%dms wind=%.1f dir=%.1f'):format(getSpawnInterval(), tonumber(hurricaneState.windSpeed) or 0.0, tonumber(hurricaneState.windDirection) or 0.0),
        ('lastSkip=%s invalidModels=%d cleanup=%d'):format(lastSkippedSpawnReason, #invalidModels, cleanupCount),
    }

    for i, line in ipairs(lines) do
        local settings = cfg()
        drawTextLine(line, settings.debugTextX or 0.015, (settings.debugTextY or 0.68) + (i * (settings.debugLineHeight or 0.022)))
    end
end

local function printDebug()
    print(('[HurricaneDebris] active=%s count=%d max=%d spawnInterval=%dms windSpeed=%.1f windDirection=%.1f lastSkip=%s invalidModels=%d cleanup=%d'):format(
        tostring(hurricaneState.active),
        #debris,
        getMaxDebris(),
        getSpawnInterval(),
        tonumber(hurricaneState.windSpeed) or 0.0,
        tonumber(hurricaneState.windDirection) or 0.0,
        lastSkippedSpawnReason,
        #invalidModels,
        cleanupCount
    ))
end

local function setState(state)
    if type(state) ~= 'table' then return end
    hurricaneState = {
        active = state.active == true,
        intensity = clampIntensity(state.intensity or 1),
        windDirection = tonumber(state.windDirection) or 0.0,
        windSpeed = tonumber(state.windSpeed) or 0.0,
        lightningMultiplier = tonumber(state.lightningMultiplier) or 1.0,
        startedAt = state.startedAt,
    }

    if hurricaneState.active then
        applyAmbientWind()
    else
        cleanupDebris(true)
        SetWindSpeed(0.0)
    end
end

function hurricaneDebris.start()
    if active then return end
    active = true
    validateConfiguredModels()

    RegisterNetEvent('dynamic_weather:hurricane:set', setState)

    CreateThread(function()
        Wait(cfg().stateRequestDelayMs or 1000)
        TriggerServerEvent('dynamic_weather:hurricane:requestState')
    end)

    CreateThread(function()
        while active do
            if hurricaneState.active then
                applyAmbientWind()
                Wait(cfg().windApplyTickMs or 1000)
            else
                Wait(cfg().inactiveWindWaitMs or 1500)
            end
        end
    end)

    CreateThread(function()
        while active do
            if hurricaneState.active then
                spawnDebris()
                Wait(getSpawnInterval())
            else
                Wait(cfg().inactiveSpawnWaitMs or 1500)
            end
        end
    end)

    CreateThread(function()
        while active do
            if hurricaneState.active then
                local now = GetGameTimer()
                for _, item in ipairs(debris) do
                    applyGust(item, now)
                end
                Wait(cfg().physicsTickMs or 200)
            else
                Wait(cfg().inactivePhysicsWaitMs or 1000)
            end
        end
    end)

    CreateThread(function()
        while active do
            if hurricaneState.active then
                maybeLightning()
                Wait(cfg().lightningTickMs or 3500)
            else
                Wait(cfg().inactiveLightningWaitMs or 2000)
            end
        end
    end)

    CreateThread(function()
        while active do
            cleanupDebris(false)
            Wait(cfg().cleanupTickMs or 1000)
        end
    end)

    CreateThread(function()
        while active do
            if debugDisplay then
                drawDebug()
                Wait(0)
            else
                Wait(cfg().debugIdleWaitMs or 500)
            end
        end
    end)
end

function hurricaneDebris.stop()
    active = false
    debugDisplay = false
    cleanupDebris(true)
    SetWindSpeed(0.0)
end

RegisterCommand('hurricanedebrisdebug', function()
    debugDisplay = not debugDisplay
    printDebug()
    print(('[HurricaneDebris] debugDisplay=%s'):format(tostring(debugDisplay)))
end, false)

return hurricaneDebris
