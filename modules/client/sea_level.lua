local seaLevel = {}

local originalLevels = {}
local originalBounds = {}
local originalMinLevel = nil
local originalMaxLevel = nil
local currentLevel = nil
local smoothToken = 0
local started = false
local pedWaterThreadActive = false
local floodWaterLoaded = false
local floodWaterFileLoaded = nil
local globalFloodLevel = nil
local globalFloodMode = 'offset'
local globalFloodProgressLevel = nil
local effectiveFloodLevel = 0.0
local floodZoneMultiplier = 1.0
local activeIgnoreZoneName = nil
local activeIgnoreZoneInside = false
local lastAppliedEffectiveFloodLevel = nil
local lastEffectiveApplyAt = 0
local floodIgnoreDebug = false
local floodIgnoreDraw = false
local hurricaneFloodActive = false

local function getConfig()
    return Config.SeaLevel or {}
end

local function updateHurricaneFloodState(state)
    if type(state) == 'table' then
        hurricaneFloodActive = state.active == true
    end
end

local function isHurricaneActive()
    local state = GlobalState.dynamic_weather_hurricane
    if type(state) == 'table' then
        return state.active == true
    end

    return hurricaneFloodActive == true
end

local function normalizeFloodProfile(profile)
    if type(profile) == 'string' then
        profile = string.lower(profile)
    else
        profile = getConfig().defaultFloodWaterProfile or 'flash'
    end

    if profile == 'hurricane' or profile == 'rough' then
        return 'hurricane'
    end

    if isHurricaneActive() then
        return 'hurricane'
    end

    return 'flash'
end

local function getFloodWaterFile(profile)
    local cfg = getConfig()
    local resolvedProfile = normalizeFloodProfile(profile)

    if resolvedProfile == 'hurricane' then
        return cfg.hurricaneFloodWaterFile or 'flood.xml', resolvedProfile
    end

    return cfg.flashFloodWaterFile or 'flood_calm.xml', resolvedProfile
end

local function getFloodWaveQuadIds()
    local ids = getConfig().floodWaveQuadIds
    if type(ids) == 'table' and #ids > 0 then
        return ids
    end

    return { 0 }
end

local function applyFloodWaveProfile(profile)
    local cfg = getConfig()
    local resolvedProfile = normalizeFloodProfile(profile)
    if type(SetWaveQuadAmplitude) ~= 'function' then
        print(('^1[weather] Flood wave profile=%s skipped: SetWaveQuadAmplitude unavailable^0'):format(resolvedProfile))
        return
    end

    local amplitude = 0.0
    if resolvedProfile == 'hurricane' then
        amplitude = tonumber(cfg.hurricaneFloodWaveAmplitude) or 1.0
    else
        amplitude = tonumber(cfg.flashFloodWaveAmplitude) or 0.0
    end

    local changed = 0
    local skipped = 0
    for _, waveQuad in ipairs(getFloodWaveQuadIds()) do
        local ok, success = pcall(SetWaveQuadAmplitude, tonumber(waveQuad) or 0, amplitude)
        if ok and success then
            changed = changed + 1
        else
            skipped = skipped + 1
        end
    end

    if resolvedProfile == 'hurricane' and changed == 0 then
        print(('^1[weather] Flood waves requested but no wave quads accepted amplitude %.2f^0'):format(amplitude))
    end

    print(('[weather] Flood wave profile=%s amplitude=%.2f changed=%d skipped=%d'):format(
        resolvedProfile,
        amplitude,
        changed,
        skipped
    ))
end

local function getMaxSafeSeaLevel()
    local cfg = getConfig()
    return tonumber(cfg.maxSafeSeaLevel) or tonumber(cfg.maxSeaLevel) or 80.0
end

local function getFloodIgnoreHelper()
    return lib.require('modules.shared.flood_ignore_zones')
end

local function getProtectedWaterHelper()
    return lib.require('modules.shared.protected_water')
end

local function getFloodIgnoreZones()
    local sync = lib.require('modules.client.sync')
    if sync and sync.getFloodIgnoreZones then
        return sync.getFloodIgnoreZones() or {}
    end
    return {}
end

local function getWaterQuadBounds(index)
    if originalBounds[index] then return originalBounds[index] end
    if type(GetWaterQuadBounds) ~= 'function' then return nil end

    local ok, success, minX, minY, maxX, maxY = pcall(GetWaterQuadBounds, index)
    if not ok or not success then return nil end
    if type(minX) ~= 'number' or type(minY) ~= 'number' or type(maxX) ~= 'number' or type(maxY) ~= 'number' then
        return nil
    end

    local bounds = {
        minX = math.min(minX, maxX),
        minY = math.min(minY, maxY),
        maxX = math.max(minX, maxX),
        maxY = math.max(minY, maxY),
    }
    originalBounds[index] = bounds
    return bounds
end

local function captureProtectedRestoreHeights()
    local protectedWater = getProtectedWaterHelper()
    local sampled, missed = protectedWater.CaptureProtectedRestoreHeights()
    if sampled > 0 or missed > 0 then
        print(('[weather] Protected water sampled=%d missed=%d'):format(sampled, missed))
    end
end

local function clampLevel(level)
    local cfg = getConfig()
    local minLevel = tonumber(cfg.minSeaLevel) or -10.0
    local maxLevel = getMaxSafeSeaLevel()

    if level < minLevel then return minLevel, true end
    if level > maxLevel then return maxLevel, true end
    return level, false
end

local function getQuadCount()
    local ok, count = pcall(GetWaterQuadCount)
    if not ok or type(count) ~= 'number' then
        print('^1[weather] Sea level unavailable: GetWaterQuadCount failed^0')
        return 0
    end
    return count
end

local function getOriginalCount()
    local count = 0
    for _ in pairs(originalLevels) do
        count = count + 1
    end
    return count
end

local function captureOriginalLevels()
    originalLevels = {}
    originalBounds = {}
    originalMinLevel = nil
    originalMaxLevel = nil

    local count = getQuadCount()
    for i = 0, count - 1, 1 do
        getWaterQuadBounds(i)
        local ok, success, level = pcall(GetWaterQuadLevel, i)
        if ok then
            if (success == true or success == 1) and type(level) == 'number' then
                originalLevels[i] = level
            elseif type(success) == 'number' then
                originalLevels[i] = success
            end

            local original = originalLevels[i]
            if type(original) == 'number' then
                if not originalMinLevel or original < originalMinLevel then originalMinLevel = original end
                if not originalMaxLevel or original > originalMaxLevel then originalMaxLevel = original end
            end
        end
    end

    print(('[weather] Sea level captured quads=%d originals=%d min=%.2f max=%.2f'):format(
        count,
        getOriginalCount(),
        originalMinLevel or 0.0,
        originalMaxLevel or 0.0
    ))
end

local function loadFloodWater(profile)
    local waterFile, resolvedProfile = getFloodWaterFile(profile)
    if floodWaterLoaded and floodWaterFileLoaded == waterFile then
        applyFloodWaveProfile(resolvedProfile)
        return true
    end

    if floodWaterLoaded and floodWaterFileLoaded ~= waterFile then
        pcall(ResetWater)
        originalLevels = {}
        currentLevel = nil
        floodWaterLoaded = false
        floodWaterFileLoaded = nil
    end

    local ok, success = pcall(LoadWaterFromPath, GetCurrentResourceName(), waterFile)
    if not ok or success ~= 1 then
        print(('^1[weather] Sea level flood water load failed: %s unavailable^0'):format(waterFile))
        return false
    end

    floodWaterLoaded = true
    floodWaterFileLoaded = waterFile
    captureOriginalLevels()
    applyFloodWaveProfile(resolvedProfile)
    print(('[weather] Sea level flood water loaded profile=%s file=%s'):format(resolvedProfile, waterFile))
    return true
end

local function ensureOriginalLevels()
    if next(originalLevels) == nil then
        captureOriginalLevels()
    end
end

local function logApply(mode, target, changed, failed, count)
    print(('[weather] Sea level apply mode=%s quads=%d changed=%d failed=%d originalMin=%.2f originalMax=%.2f target=%.2f'):format(
        mode,
        count,
        changed,
        failed,
        originalMinLevel or 0.0,
        originalMaxLevel or 0.0,
        target
    ))
end

local function setAllLevels(targetLevel, mode)
    ensureOriginalLevels()

    local target, clamped = clampLevel(targetLevel)
    local count = getQuadCount()
    local changed = 0
    local failed = 0
    local ignored = 0
    local restoredIgnored = 0
    local ignoreZones = getFloodIgnoreZones()
    local floodIgnoreHelper = getFloodIgnoreHelper()
    local protectedWater = getProtectedWaterHelper()
    local protected = 0
    local restoredProtected = 0
    mode = mode == 'offset' and 'offset' or 'absolute'

    if clamped then
        print(('[weather] Sea level target %.2f clamped to safe max %.2f. Extreme mountain-height flooding exposes GTA water LOD/tile seams.'):format(
            targetLevel,
            target
        ))
    end

    for i = 0, count - 1, 1 do
        local bounds = getWaterQuadBounds(i)
        local isIgnored = bounds and floodIgnoreHelper.IsQuadIgnored(ignoreZones, bounds)
        local isProtected = bounds and protectedWater.isQuadProtected(bounds)
        if isIgnored or isProtected then
            if isIgnored then ignored = ignored + 1 end
            if isProtected then protected = protected + 1 end
            local originalLevel = originalLevels[i]
            if type(originalLevel) == 'number' then
                local ok, success = pcall(SetWaterQuadLevel, i, originalLevel)
                if ok and success then
                    if isIgnored then restoredIgnored = restoredIgnored + 1 end
                    if isProtected then restoredProtected = restoredProtected + 1 end
                else
                    failed = failed + 1
                end
            end
        else
            local level = target
            if mode == 'offset' then
                level = (originalLevels[i] or 0.0) + target
                level = clampLevel(level)
            end

            local ok, success = pcall(SetWaterQuadLevel, i, level)
            if ok and success then
                changed = changed + 1
            else
                failed = failed + 1
            end
        end
    end

    local restoredBodies, restoreFailures = protectedWater.RestoreProtectedWaterBodies()
    failed = failed + restoreFailures
    currentLevel = target
    logApply(mode, target, changed, failed, count)
    if ignored > 0 or floodIgnoreDebug then
        print(('[FloodIgnore] water quads ignored=%d restored=%d total=%d'):format(ignored, restoredIgnored, count))
    end
    if protected > 0 or restoredBodies > 0 or restoreFailures > 0 then
        print(('[ProtectedWater] quads=%d restoredQuads=%d restoredBodies=%d failed=%d'):format(
            protected,
            restoredProtected,
            restoredBodies,
            restoreFailures
        ))
    end
    return changed, failed, count, target
end

local function moveTowards(current, target, maxDelta)
    current = tonumber(current) or 0.0
    target = tonumber(target) or 0.0
    maxDelta = math.max(0.0, tonumber(maxDelta) or 0.0)

    if math.abs(target - current) <= maxDelta then return target end
    if target > current then return current + maxDelta end
    return current - maxDelta
end

local function calculateFloodZoneMultiplier(coords)
    if not coords then
        floodZoneMultiplier = 1.0
        activeIgnoreZoneName = nil
        activeIgnoreZoneInside = false
        return floodZoneMultiplier
    end

    local helper = getFloodIgnoreHelper()
    local result = helper.CalculateMultiplier(getFloodIgnoreZones(), coords.x, coords.y)
    floodZoneMultiplier = tonumber(result.multiplier) or 1.0
    activeIgnoreZoneName = result.zoneName
    activeIgnoreZoneInside = result.inside == true
    return floodZoneMultiplier, result
end

local function applyEffectiveFloodLevel(level, mode, force)
    local cfg = getConfig()
    local threshold = tonumber(cfg.floodIgnoreApplyThreshold) or 0.02
    local maxInterval = tonumber(cfg.floodIgnoreMaxApplyIntervalMs) or 10000
    local now = GetGameTimer()

    if not force and type(lastAppliedEffectiveFloodLevel) == 'number' then
        local delta = math.abs(level - lastAppliedEffectiveFloodLevel)
        if delta < threshold and (now - lastEffectiveApplyAt) < maxInterval then
            effectiveFloodLevel = level
            return false
        end
    end

    setAllLevels(level, mode)
    effectiveFloodLevel = level
    lastAppliedEffectiveFloodLevel = level
    lastEffectiveApplyAt = now
    return true
end

local function clearFloodState()
    globalFloodLevel = nil
    globalFloodMode = 'offset'
    globalFloodProgressLevel = nil
    effectiveFloodLevel = 0.0
    floodZoneMultiplier = 1.0
    activeIgnoreZoneName = nil
    activeIgnoreZoneInside = false
    lastAppliedEffectiveFloodLevel = nil
    lastEffectiveApplyAt = 0
end

local function cancelAnimation()
    smoothToken = smoothToken + 1
end

local function resetAllLevels()
    cancelAnimation()
    pedWaterThreadActive = false
    clearFloodState()
    local ok = pcall(ResetWater)
    if not ok then
        print('^1[weather] Sea level reset failed: ResetWater unavailable^0')
    end
    floodWaterLoaded = false
    floodWaterFileLoaded = nil
    currentLevel = nil
    captureProtectedRestoreHeights()
    captureOriginalLevels()
    print('[weather] Sea level reset to GTA water defaults')
end

local function applyLevel(level, mode)
    cancelAnimation()
    clearFloodState()
    setAllLevels(level, mode)
end

local function startPedWaterThread()
    if pedWaterThreadActive then return end
    pedWaterThreadActive = true

    CreateThread(function()
        while pedWaterThreadActive do
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)
            local wCoords = GetWaterQuadAtCoords_3d(pCoords.x, pCoords.y, pCoords.z)

            if wCoords ~= -1 then
                local allPeds = GetGamePool('CPed')
                for i = 1, #allPeds do
                    SetPedConfigFlag(allPeds[i], 65, true)
                    SetPedDiesInWater(allPeds[i], true)
                end
            end

            Wait(5000)
        end
    end)
end

local function smoothByBraveRate(targetLevel, mode, profile)
    cancelAnimation()
    local token = smoothToken
    local cfg = getConfig()
    local increaseRate = tonumber(cfg.floodIncreaseRate) or tonumber(cfg.braveFloodIncreaseRate) or 0.02
    local tickMs = math.max(1000, tonumber(cfg.floodTickMs) or tonumber(cfg.smoothTickMs) or 2000)
    local smoothStep = math.max(0.01, tonumber(cfg.floodIgnoreSmoothingStep) or 0.05)

    if not loadFloodWater(profile) then return end
    startPedWaterThread()
    globalFloodLevel = clampLevel(targetLevel)
    globalFloodMode = mode == 'offset' and 'offset' or 'absolute'

    CreateThread(function()
        local target = globalFloodLevel
        local nextLevel = globalFloodProgressLevel or currentLevel or 0.0
        local printedComplete = false

        print(('[weather] Sea level flood smoothing target=%.2f mode=%s tick=%dms rate=%.3f ignoreStep=%.3f'):format(
            target,
            globalFloodMode,
            tickMs,
            increaseRate,
            smoothStep
        ))

        while token == smoothToken and type(globalFloodLevel) == 'number' do
            target = globalFloodLevel
            if nextLevel < target then
                nextLevel = math.min(target, nextLevel + increaseRate)
            elseif nextLevel > target then
                nextLevel = math.max(target, nextLevel - increaseRate)
            end
            globalFloodProgressLevel = nextLevel

            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)
            calculateFloodZoneMultiplier(pCoords)

            local targetEffective = nextLevel * floodZoneMultiplier
            effectiveFloodLevel = moveTowards(effectiveFloodLevel or currentLevel or 0.0, targetEffective, smoothStep)
            applyEffectiveFloodLevel(effectiveFloodLevel, globalFloodMode, false)

            if floodIgnoreDebug then
                print(('[FloodIgnore] global=%.2f effective=%.2f multiplier=%.3f inside=%s zone=%s'):format(
                    globalFloodLevel,
                    effectiveFloodLevel,
                    floodZoneMultiplier,
                    tostring(activeIgnoreZoneInside),
                    activeIgnoreZoneName or 'none'
                ))
            end

            if nextLevel >= target and not printedComplete then
                print(('[weather] Sea level flood complete target=%.2f; local ignore monitor active'):format(target))
                printedComplete = true
            end

            Wait(tickMs)
        end
    end)
end

local function smoothToLevel(targetLevel, seconds, mode)
    cancelAnimation()
    clearFloodState()
    local token = smoothToken
    local cfg = getConfig()
    local tickMs = math.max(250, tonumber(cfg.smoothTickMs) or 1000)
    local durationMs = math.max(0, math.floor((tonumber(seconds) or cfg.defaultSmoothSeconds or 60) * 1000))
    local startLevel = currentLevel

    if type(startLevel) ~= 'number' then
        startLevel = 0.0
        for _, level in pairs(originalLevels) do
            startLevel = level
            break
        end
    end

    if durationMs <= 0 then
        applyLevel(targetLevel, mode)
        return
    end

    CreateThread(function()
        ensureOriginalLevels()
        local startedAt = GetGameTimer()
        local target = clampLevel(targetLevel)
        print(('[weather] Sea level smoothing %.2f -> %.2f over %.1fs mode=%s'):format(startLevel, target, durationMs / 1000, mode or 'absolute'))

        while token == smoothToken do
            local elapsed = GetGameTimer() - startedAt
            local t = math.min(1.0, elapsed / durationMs)
            local level = startLevel + ((target - startLevel) * t)
            setAllLevels(level, mode)

            if t >= 1.0 then
                print(('[weather] Sea level smooth complete at %.2f'):format(target))
                break
            end

            Wait(tickMs)
        end
    end)
end

RegisterNetEvent('dynamic_weather:seaLevel:set', function(level, mode)
    if not getConfig().enabled then return end
    if type(level) ~= 'number' then return end
    pedWaterThreadActive = false
    clearFloodState()
    applyLevel(level, mode)
end)

RegisterNetEvent('dynamic_weather:seaLevel:smooth', function(level, seconds, mode)
    if not getConfig().enabled then return end
    if type(level) ~= 'number' then return end
    pedWaterThreadActive = false
    clearFloodState()
    smoothToLevel(level, seconds, mode)
end)

RegisterNetEvent('dynamic_weather:seaLevel:reset', function()
    resetAllLevels()
end)

RegisterNetEvent('dynamic_weather:seaLevel:loadWater', function()
    pedWaterThreadActive = false
    clearFloodState()
    loadFloodWater()
end)

RegisterNetEvent('dynamic_weather:seaLevel:flood', function(level, mode, profile)
    if not getConfig().enabled then return end
    smoothByBraveRate(type(level) == 'number' and level or (getConfig().braveFloodHeight or 400.0), mode, profile)
end)

RegisterNetEvent('dynamic_weather:hurricane:set', updateHurricaneFloodState)

function seaLevel.start()
    if started then return end
    started = true
    updateHurricaneFloodState(GlobalState.dynamic_weather_hurricane)
    pcall(ResetWater)
    floodWaterLoaded = false
    floodWaterFileLoaded = nil
    captureProtectedRestoreHeights()
    captureOriginalLevels()
    TriggerServerEvent('dynamic_weather:seaLevel:requestState')
end

function seaLevel.stop()
    pedWaterThreadActive = false
    resetAllLevels()
    started = false
end

RegisterCommand('floodignoredebug', function(_, args)
    local sub = args and args[1] and string.lower(tostring(args[1])) or 'status'
    if sub == 'on' then
        floodIgnoreDebug = true
    elseif sub == 'off' then
        floodIgnoreDebug = false
        floodIgnoreDraw = false
    elseif sub == 'draw' then
        floodIgnoreDraw = not floodIgnoreDraw
    else
        floodIgnoreDebug = not floodIgnoreDebug
    end

    print(('[FloodIgnore] global=%.2f effective=%.2f multiplier=%.3f inside=%s zone=%s debug=%s draw=%s zones=%d'):format(
        globalFloodLevel or 0.0,
        effectiveFloodLevel or 0.0,
        floodZoneMultiplier or 1.0,
        tostring(activeIgnoreZoneInside),
        activeIgnoreZoneName or 'none',
        tostring(floodIgnoreDebug),
        tostring(floodIgnoreDraw),
        #getFloodIgnoreZones()
    ))
end, false)

CreateThread(function()
    while true do
        if floodIgnoreDraw then
            local helper = getFloodIgnoreHelper()
            helper.DebugDrawFloodIgnoreZones(getFloodIgnoreZones(), 40.0)
            Wait(0)
        else
            Wait(1000)
        end
    end
end)

return seaLevel
