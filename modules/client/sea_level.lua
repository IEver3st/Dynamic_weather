local seaLevel = {}

local originalLevels = {}
local originalMinLevel = nil
local originalMaxLevel = nil
local currentLevel = nil
local smoothToken = 0
local started = false
local pedWaterThreadActive = false
local floodWaterLoaded = false

local function getConfig()
    return Config.SeaLevel or {}
end

local function getMaxSafeSeaLevel()
    local cfg = getConfig()
    return tonumber(cfg.maxSafeSeaLevel) or tonumber(cfg.maxSeaLevel) or 80.0
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
    originalMinLevel = nil
    originalMaxLevel = nil

    local count = getQuadCount()
    for i = 0, count - 1, 1 do
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

local function loadFloodWater()
    local ok, success = pcall(LoadWaterFromPath, GetCurrentResourceName(), 'flood.xml')
    if not ok or success ~= 1 then
        print('^1[weather] Sea level flood water load failed: flood.xml unavailable^0')
        return false
    end

    floodWaterLoaded = true
    captureOriginalLevels()
    print('[weather] Sea level flood water loaded')
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
    mode = mode == 'offset' and 'offset' or 'absolute'

    if clamped then
        print(('[weather] Sea level target %.2f clamped to safe max %.2f. Extreme mountain-height flooding exposes GTA water LOD/tile seams.'):format(
            targetLevel,
            target
        ))
    end

    for i = 0, count - 1, 1 do
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

    currentLevel = target
    logApply(mode, target, changed, failed, count)
    return changed, failed, count, target
end

local function cancelAnimation()
    smoothToken = smoothToken + 1
end

local function resetAllLevels()
    cancelAnimation()
    pedWaterThreadActive = false
    local ok = pcall(ResetWater)
    if not ok then
        print('^1[weather] Sea level reset failed: ResetWater unavailable^0')
    end
    floodWaterLoaded = false
    currentLevel = nil
    captureOriginalLevels()
    print('[weather] Sea level reset to GTA water defaults')
end

local function applyLevel(level, mode)
    cancelAnimation()
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

local function smoothByBraveRate(targetLevel, mode)
    cancelAnimation()
    local token = smoothToken
    local cfg = getConfig()
    local increaseRate = tonumber(cfg.floodIncreaseRate) or tonumber(cfg.braveFloodIncreaseRate) or 0.02
    local tickMs = math.max(1000, tonumber(cfg.floodTickMs) or tonumber(cfg.smoothTickMs) or 2000)

    if not floodWaterLoaded and not loadFloodWater() then return end
    startPedWaterThread()

    CreateThread(function()
        local target = clampLevel(targetLevel)
        local nextLevel = currentLevel or 0.0

        print(('[weather] Sea level flood smoothing target=%.2f mode=%s tick=%dms rate=%.3f'):format(
            target,
            mode or 'absolute',
            tickMs,
            increaseRate
        ))

        while token == smoothToken do
            nextLevel = nextLevel + increaseRate
            if nextLevel >= target then
                nextLevel = target
            end

            setAllLevels(nextLevel, mode)

            if nextLevel >= target then
                print(('[weather] Sea level flood complete target=%.2f'):format(target))
                break
            end

            Wait(tickMs)
        end
    end)
end

local function smoothToLevel(targetLevel, seconds, mode)
    cancelAnimation()
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
    applyLevel(level, mode)
end)

RegisterNetEvent('dynamic_weather:seaLevel:smooth', function(level, seconds, mode)
    if not getConfig().enabled then return end
    if type(level) ~= 'number' then return end
    pedWaterThreadActive = false
    smoothToLevel(level, seconds, mode)
end)

RegisterNetEvent('dynamic_weather:seaLevel:reset', function()
    resetAllLevels()
end)

RegisterNetEvent('dynamic_weather:seaLevel:loadWater', function()
    pedWaterThreadActive = false
    loadFloodWater()
end)

RegisterNetEvent('dynamic_weather:seaLevel:flood', function(level, mode)
    if not getConfig().enabled then return end
    smoothByBraveRate(type(level) == 'number' and level or (getConfig().braveFloodHeight or 400.0), mode)
end)

function seaLevel.start()
    if started then return end
    started = true
    pcall(ResetWater)
    floodWaterLoaded = false
    captureOriginalLevels()
    TriggerServerEvent('dynamic_weather:seaLevel:requestState')
end

function seaLevel.stop()
    pedWaterThreadActive = false
    resetAllLevels()
    started = false
end

return seaLevel
