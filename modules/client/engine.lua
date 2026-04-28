local forcedWeather = nil ---@type string|nil When set, engine ignores zone sync for display until cleared.
local currentWeather = nil
local targetWeather = nil
local transitionStart = 0
local transitionDuration = 0
local currentZoneId = nil
local active = false
local engineThread = nil
local cachedZoneRevision = -1
local cachedZones = {}

local GetEntityCoords = GetEntityCoords
local PlayerPedId = PlayerPedId
local SetWeatherTypeNowPersist = SetWeatherTypeNowPersist
local SetWeatherTypeNow = SetWeatherTypeNow
local SetOverrideWeather = SetOverrideWeather
local SetRainFxIntensity = SetRainFxIntensity
local ClearOverrideWeather = ClearOverrideWeather
local ClearWeatherTypePersist = ClearWeatherTypePersist
local SetWeatherTypeOvertimePersist = SetWeatherTypeOvertimePersist

local function pointInPolygon(x, y, points)
    local count = #points
    local inside = false
    local j = count

    for i = 1, count do
        local xi, yi = points[i].x, points[i].y
        local xj, yj = points[j].x, points[j].y

        if (yi > y) ~= (yj > y) then
            local intersectX = ((xj - xi) * (y - yi) / (yj - yi)) + xi
            if x < intersectX then
                inside = not inside
            end
        end

        j = i
    end

    return inside
end

local function pointLineDistance(px, py, x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    local lenSq = dx * dx + dy * dy

    if lenSq == 0.0 then
        return math.sqrt((px - x1) * (px - x1) + (py - y1) * (py - y1))
    end

    local t = ((px - x1) * dx + (py - y1) * dy) / lenSq
    t = math.max(0.0, math.min(1.0, t))

    local projX = x1 + t * dx
    local projY = y1 + t * dy

    return math.sqrt((px - projX) * (px - projX) + (py - projY) * (py - projY))
end

local function distanceToZoneEdge(x, y, zone)
    local points = zone.points
    if not points or #points < 3 then return 0.0 end

    local minDist = math.huge
    local count = #points

    for i = 1, count do
        local j = i % count + 1
        local d = pointLineDistance(x, y,
            points[i].x, points[i].y,
            points[j].x, points[j].y)

        if d < minDist then
            minDist = d
        end
    end

    return minDist
end

local function applyWeatherImmediately(weather)
    SetWeatherTypeNowPersist(weather)
    SetWeatherTypeNow(weather)
    SetOverrideWeather(weather)
    SetRainFxIntensity((weather == 'RAIN' or weather == 'THUNDER' or weather == 'CLEARING') and 1.0 or 0.0)
end

---Blend to weather over `durationSec` (GTA does the interpolation). Does not set rain/override; finalize with applyWeatherImmediately.
local function applyWeatherOvertime(weather, durationSec)
    local sec = (durationSec and durationSec > 0) and durationSec or 0.0
    if not weather or sec <= 0.0 then
        if weather then
            applyWeatherImmediately(weather)
        end
        return
    end
    ClearOverrideWeather()
    -- Cap extremely long values (natives can misbehave); still plenty for smooth feel.
    local t = sec > 60.0 and 60.0 or sec
    SetWeatherTypeOvertimePersist(weather, t + 0.0)
end

local function clearWeatherOverride()
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    SetRainFxIntensity(0.0)
end

local function getZones()
    return lib.require('modules.client.sync').getZoneStates() or {}
end

local function getAllZoneDefs()
    return lib.require('modules.client.sync').getZoneDefs() or {}
end

local function getSyncRevision()
    local sync = lib.require('modules.client.sync')
    return sync.getRevision and sync.getRevision() or 0
end

local function rebuildZoneCache()
    local zones = getAllZoneDefs()
    local compiled = {}

    for _, zone in ipairs(zones) do
        local points = zone.points
        if zone.enabled ~= false and points and #points >= 3 then
            local minX, maxX = points[1].x, points[1].x
            local minY, maxY = points[1].y, points[1].y

            for i = 2, #points do
                local point = points[i]
                if point.x < minX then minX = point.x end
                if point.x > maxX then maxX = point.x end
                if point.y < minY then minY = point.y end
                if point.y > maxY then maxY = point.y end
            end

            compiled[#compiled + 1] = {
                zone = zone,
                minX = minX,
                maxX = maxX,
                minY = minY,
                maxY = maxY,
            }
        end
    end

    cachedZones = compiled
    cachedZoneRevision = getSyncRevision()
end

local function getCachedZones()
    local revision = getSyncRevision()
    if revision ~= cachedZoneRevision then
        rebuildZoneCache()
    end
    return cachedZones
end

local function findPlayerZone(x, y)
    local zones = getCachedZones()
    local bestZone = nil
    local bestDepth = -1.0

    for _, entry in ipairs(zones) do
        if x >= entry.minX and x <= entry.maxX and y >= entry.minY and y <= entry.maxY then
            local zone = entry.zone
            local inside = pointInPolygon(x, y, zone.points)
            if inside then
                local depth = distanceToZoneEdge(x, y, zone)
                if depth > bestDepth then
                    bestDepth = depth
                    bestZone = zone
                end
            end
        end
    end

    return bestZone
end

local function getWeatherForZone(zone)
    if not zone then return Config.globalFallbackWeather end
    local zoneStates = getZones()
    local state = zoneStates[zone.id]
    if state and state.currentWeather then
        return state.currentWeather
    end
    return zone.weatherPool and zone.weatherPool[1] or Config.globalFallbackWeather
end

local function getPlayerXY()
    local coords = GetEntityCoords(PlayerPedId())
    return coords.x, coords.y
end

local function startTransition(newWeather, duration)
    if not newWeather then
        return
    end
    -- Avoid resetting an in-progress blend when target unchanged.
    if newWeather == targetWeather and transitionDuration and transitionDuration > 0.0 then
        return
    end

    local fromWeather = targetWeather or currentWeather or Config.globalFallbackWeather
    currentWeather = fromWeather
    targetWeather = newWeather
    transitionDuration = duration or Config.defaultTransitionDuration or 15.0
    if transitionDuration < 0.0 then
        transitionDuration = 0.0
    end
    transitionStart = GetGameTimer()

    if transitionDuration <= 0.0 then
        applyWeatherImmediately(targetWeather)
        currentWeather = targetWeather
        transitionDuration = 0.0
    else
        if newWeather == fromWeather then
            -- Same type; no blend needed, lock state for rain/override.
            applyWeatherImmediately(targetWeather)
            currentWeather = targetWeather
            transitionDuration = 0.0
        else
            applyWeatherOvertime(targetWeather, transitionDuration)
        end
    end

    if Config.debugLog and transitionDuration > 0.0 then
        print(('^3[weather] Transition: %s → %s over %.0fs^0'):format(
            fromWeather, targetWeather, transitionDuration))
    end
end

local function engineTick()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local zone = findPlayerZone(coords.x, coords.y)

    local prevZoneId = currentZoneId
    local newZoneId = zone and zone.id or nil
    local zoneWeather = getWeatherForZone(zone)
    local desiredWeather = forcedWeather or zoneWeather

    if newZoneId ~= currentZoneId then
        if Config.debugLog then
            print(('^3[weather] Zone changed: %s → %s^0'):format(
                tostring(currentZoneId), tostring(newZoneId)))
        end
        currentZoneId = newZoneId

        local duration = forcedWeather and 0.0 or (zone and zone.transitionDuration or Config.defaultTransitionDuration)
        if desiredWeather ~= targetWeather then
            startTransition(desiredWeather, duration)
        end
    end

    -- Not in a zone, was not in a zone last tick (zone exit is handled by branch above).
    if not forcedWeather and not zone and prevZoneId == nil
        and currentZoneId == nil
        and currentWeather
        and currentWeather ~= Config.globalFallbackWeather then
        startTransition(Config.globalFallbackWeather, Config.defaultTransitionDuration)
    end

    if targetWeather and targetWeather ~= desiredWeather then
        local duration = forcedWeather and 0.0 or (zone and zone.transitionDuration or Config.defaultTransitionDuration)
        startTransition(desiredWeather, duration)
    end

    if currentWeather and transitionDuration > 0 then
        local elapsed = (GetGameTimer() - transitionStart) / 1000.0
        if elapsed >= transitionDuration then
            currentWeather = targetWeather
            if targetWeather then
                applyWeatherImmediately(targetWeather)
            end
            transitionDuration = 0.0
        end
    end
end

local engineModule = {}

function engineModule.start()
    if active then return end
    active = true
    local tickRate = Config.tickRate or 500
    engineThread = CreateThread(function()
        while active do
            engineTick()
            Wait(tickRate)
        end
    end)
    if Config.debugLog then
        print('^2[weather] Engine started^0')
    end
end

function engineModule.stop()
    active = false
    if engineThread then
        engineThread = nil
    end
    forcedWeather = nil
    currentWeather = nil
    targetWeather = nil
    currentZoneId = nil
    transitionStart = 0
    transitionDuration = 0
    clearWeatherOverride()
    if Config.debugLog then
        print('^1[weather] Engine stopped^0')
    end
end

function engineModule.getState()
    local coords = GetEntityCoords(PlayerPedId())
    local zone = findPlayerZone(coords.x, coords.y)

    return {
        zone = zone and zone.id or nil,
        zoneLabel = zone and zone.label or nil,
        weather = currentWeather,
        target = targetWeather,
        forcedWeather = forcedWeather,
        progress = transitionDuration > 0
            and math.min(1.0, (GetGameTimer() - transitionStart) / 1000 / transitionDuration)
            or 1.0,
    }
end

function engineModule.getCurrentWeather()
    if forcedWeather then
        return forcedWeather
    end
    return targetWeather or currentWeather or Config.globalFallbackWeather
end

function engineModule.getForcedWeather()
    return forcedWeather
end

function engineModule.isWeatherForceLocked()
    return forcedWeather ~= nil
end

function engineModule.forceWeatherFast(weatherType)
    if type(weatherType) ~= 'string' or #weatherType == 0 then
        return false
    end
    local w = string.upper(weatherType)
    forcedWeather = w
    startTransition(w, 0.0)
    return true
end

function engineModule.clearForceWeatherFast()
    if not forcedWeather then
        return false
    end
    forcedWeather = nil
    return true
end

function engineModule.findPlayerZone(x, y)
    if x and y then
        return findPlayerZone(x, y)
    end

    local px, py = getPlayerXY()
    return findPlayerZone(x or px, y or py)
end

---When outside all zones: shortest distance to any enabled zone polygon edge (meters, XY).
---@return number|nil distance, string|nil nearestZoneId, string|nil nearestZoneLabel
function engineModule.nearestZoneEdgeDistance(x, y)
    local px, py = x, y
    if not px or not py then
        local playerX, playerY = getPlayerXY()
        px = px or playerX
        py = py or playerY
    end

    if findPlayerZone(px, py) then
        return nil
    end

    local zones = getCachedZones()
    local best = math.huge
    local bestId, bestLabel = nil, nil

    for _, entry in ipairs(zones) do
        local zone = entry.zone
        if px >= entry.minX - best and px <= entry.maxX + best and py >= entry.minY - best and py <= entry.maxY + best then
            local d = distanceToZoneEdge(px, py, zone)
            if d < best then
                best = d
                bestId = zone.id
                bestLabel = zone.label
            end
        end
    end

    if best == math.huge then
        return nil
    end

    return best, bestId, bestLabel
end

return engineModule
