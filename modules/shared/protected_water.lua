local protectedWater = {}
local runtimeZones = nil
local fileZones = nil
local fileZonesLoaded = false
local debugModifyWater = false
local sampledRestoreHeights = {}

local function getSettings()
    return Config.ProtectedWater or {}
end

local function getZones()
    if getSettings().enabled == false then return {} end
    if runtimeZones then return runtimeZones end

    if not fileZonesLoaded then
        fileZonesLoaded = true
        if type(LoadResourceFile) == 'function' and type(GetCurrentResourceName) == 'function' then
            local raw = LoadResourceFile(GetCurrentResourceName(), 'shared/data/protected_water.json')
            if raw and raw ~= '' and type(json) == 'table' and type(json.decode) == 'function' then
                local ok, decoded = pcall(json.decode, raw)
                if ok and type(decoded) == 'table' and type(decoded.bodies) == 'table' then
                    fileZones = decoded.bodies
                end
            end
        end
    end

    return fileZones or Config.ProtectedWaterBodies or {}
end

local function getPadding(zone, includePadding)
    if includePadding == false then return 0.0 end
    return tonumber(zone.padding) or tonumber(getSettings().defaultPadding) or 0.0
end

local function getBox(zone, includePadding)
    local padding = getPadding(zone, includePadding)
    return {
        minX = (tonumber(zone.minX) or 0.0) - padding,
        maxX = (tonumber(zone.maxX) or 0.0) + padding,
        minY = (tonumber(zone.minY) or 0.0) - padding,
        maxY = (tonumber(zone.maxY) or 0.0) + padding,
    }
end

local function pointInBox(x, y, box)
    return x >= box.minX and x <= box.maxX and y >= box.minY and y <= box.maxY
end

local function boxesOverlap(a, b)
    return a.minX <= b.maxX and a.maxX >= b.minX and a.minY <= b.maxY and a.maxY >= b.minY
end

local function getPointXY(point)
    if type(point) ~= 'table' and type(point) ~= 'vector2' then return nil, nil end
    return tonumber(point.x or point[1]), tonumber(point.y or point[2])
end

local function getZoneBounds(zone, includePadding)
    if type(zone) ~= 'table' then return nil end
    if zone.type ~= 'polygon' or type(zone.points) ~= 'table' then
        return getBox(zone, includePadding)
    end

    local minX, maxX, minY, maxY
    for _, point in ipairs(zone.points) do
        local x, y = getPointXY(point)
        if x and y then
            minX = minX and math.min(minX, x) or x
            maxX = maxX and math.max(maxX, x) or x
            minY = minY and math.min(minY, y) or y
            maxY = maxY and math.max(maxY, y) or y
        end
    end

    if not minX then return nil end
    local padding = getPadding(zone, includePadding)
    return {
        minX = minX - padding,
        maxX = maxX + padding,
        minY = minY - padding,
        maxY = maxY + padding,
    }
end

local function getZoneCenter(zone)
    local bounds = getZoneBounds(zone, false)
    if not bounds then return nil, nil end
    return (bounds.minX + bounds.maxX) * 0.5, (bounds.minY + bounds.maxY) * 0.5
end

local function getZoneKey(zone, index)
    return tostring(zone.id or zone.name or index or zone)
end

local function pointInPolygon(x, y, points)
    local inside = false
    local j = #points

    for i = 1, #points do
        local xi, yi = getPointXY(points[i])
        local xj, yj = getPointXY(points[j])
        if xi and yi and xj and yj then
            local intersects = ((yi > y) ~= (yj > y)) and (x < ((xj - xi) * (y - yi) / ((yj - yi) + 0.000001)) + xi)
            if intersects then inside = not inside end
        end
        j = i
    end

    return inside
end

local function distanceToBox(x, y, box)
    local dx = math.max(box.minX - x, 0.0, x - box.maxX)
    local dy = math.max(box.minY - y, 0.0, y - box.maxY)
    return math.sqrt((dx * dx) + (dy * dy))
end

local function distanceToSegment(px, py, ax, ay, bx, by)
    local vx = bx - ax
    local vy = by - ay
    local wx = px - ax
    local wy = py - ay
    local lenSq = (vx * vx) + (vy * vy)
    local t = lenSq > 0.0 and math.max(0.0, math.min(1.0, ((wx * vx) + (wy * vy)) / lenSq)) or 0.0
    local cx = ax + (t * vx)
    local cy = ay + (t * vy)
    local dx = px - cx
    local dy = py - cy
    return math.sqrt((dx * dx) + (dy * dy))
end

local function distanceToPolygon(x, y, points)
    if pointInPolygon(x, y, points) then return 0.0 end

    local best = nil
    local j = #points
    for i = 1, #points do
        local ax, ay = getPointXY(points[j])
        local bx, by = getPointXY(points[i])
        if ax and ay and bx and by then
            local distance = distanceToSegment(x, y, ax, ay, bx, by)
            if not best or distance < best then best = distance end
        end
        j = i
    end

    return best or math.huge
end

local function distanceToZone(zone, x, y, includePadding)
    local distance
    if zone.type == 'polygon' and type(zone.points) == 'table' then
        distance = distanceToPolygon(x, y, zone.points)
        if includePadding ~= false then
            distance = math.max(0.0, distance - getPadding(zone, true))
        end
        return distance
    end

    return distanceToBox(x, y, getBox(zone, includePadding))
end

local function isZoneEnabled(zone)
    return type(zone) == 'table' and zone.enabled ~= false
end

local function pointInZone(zone, x, y, includePadding)
    if type(zone) ~= 'table' then return false end
    if zone.type == 'polygon' and type(zone.points) == 'table' then
        if pointInPolygon(x, y, zone.points) then return true end
        if includePadding ~= false then
            local bounds = getZoneBounds(zone, true)
            return bounds and pointInBox(x, y, bounds) or false
        end
        return false
    end

    return pointInBox(x, y, getBox(zone, includePadding))
end

local function addRestorePoint(points, x, y, minDistance)
    if not x or not y then return false end

    for _, point in ipairs(points) do
        local px, py = getPointXY(point)
        if px and py then
            local dx = px - x
            local dy = py - y
            if ((dx * dx) + (dy * dy)) < (minDistance * minDistance) then
                return false
            end
        end
    end

    points[#points + 1] = { x = x, y = y }
    return true
end

local function getRestorePoints(zone)
    if type(zone.restorePoints) == 'table' and #zone.restorePoints > 0 then
        return zone.restorePoints
    end

    local points = {}
    local centerX, centerY = getZoneCenter(zone)
    local radius = tonumber(zone.restoreRadius) or tonumber(getSettings().defaultRestoreRadius) or 250.0
    local spacing = math.max(75.0, radius * (tonumber(getSettings().autoRestorePointSpacingScale) or 1.25))
    local minDistance = math.max(25.0, spacing * 0.35)
    local maxPoints = math.max(1, math.floor(tonumber(getSettings().maxAutoRestorePointsPerZone) or 16))

    addRestorePoint(points, centerX, centerY, minDistance)

    if getSettings().autoRestoreGrid ~= false then
        local bounds = getZoneBounds(zone, false)
        if bounds then
            local startX = bounds.minX + (spacing * 0.5)
            local startY = bounds.minY + (spacing * 0.5)

            local y = startY
            while y <= bounds.maxY and #points < maxPoints do
                local x = startX
                while x <= bounds.maxX and #points < maxPoints do
                    if pointInZone(zone, x, y, false) then
                        addRestorePoint(points, x, y, minDistance)
                    end
                    x = x + spacing
                end
                y = y + spacing
            end
        end
    end

    return points
end

local function parseWaterHeightResult(ok, success, height)
    if not ok then return nil end
    if success == true or success == 1 then return type(height) == 'number' and height or nil end
    if type(success) == 'number' then return success end
    return nil
end

local function sampleWaterHeightAt(x, y)
    local probeHeights = getSettings().restoreHeightProbeZs
    if type(probeHeights) ~= 'table' or #probeHeights == 0 then
        probeHeights = { 1000.0, 500.0, 250.0, 150.0, 100.0, 75.0, 50.0, 25.0, 10.0, 0.0, -10.0 }
    end

    for _, z in ipairs(probeHeights) do
        z = tonumber(z) or 0.0

        if type(GetWaterHeightNoWaves) == 'function' then
            local height = parseWaterHeightResult(pcall(GetWaterHeightNoWaves, x, y, z))
            if height then return height end
        end

        if type(GetWaterHeight) == 'function' then
            local height = parseWaterHeightResult(pcall(GetWaterHeight, x, y, z))
            if height then return height end
        end
    end

    return nil
end

local function shouldAutoRestoreHeight(zone)
    if getSettings().autoRestoreHeight == false then return false end
    return true
end

local function getFirstSampledRestoreHeight(zoneKey)
    local samples = sampledRestoreHeights[zoneKey]
    if type(samples) ~= 'table' then return nil end

    for _, sampled in pairs(samples) do
        if type(sampled) == 'number' then return sampled end
    end

    return nil
end

local function getFallbackRestoreHeight(zone)
    local height = tonumber(zone.restoreHeight)
    if height and (height ~= 0.0 or getSettings().zeroRestoreHeightMeansAuto == false) then
        return height
    end

    return nil
end

local function getRestoreHeight(zone, zoneKey, pointIndex)
    if shouldAutoRestoreHeight(zone) then
        local samples = sampledRestoreHeights[zoneKey]
        local sampled = samples and samples[pointIndex]
        if type(sampled) == 'number' then return sampled end
        return getFallbackRestoreHeight(zone)
    end

    return tonumber(zone.restoreHeight)
end

function protectedWater.GetProtectedWaterZoneAt(x, y, includePadding)
    x = tonumber(x)
    y = tonumber(y)
    if not x or not y then return nil end

    for _, zone in ipairs(getZones()) do
        if isZoneEnabled(zone) then
            if pointInZone(zone, x, y, includePadding) then return zone end
        end
    end

    return nil
end

function protectedWater.IsPointInProtectedWater(x, y, includePadding)
    return protectedWater.GetProtectedWaterZoneAt(x, y, includePadding) ~= nil
end

function protectedWater.GetDistanceToProtectedWaterZone(x, y, includePadding)
    x = tonumber(x)
    y = tonumber(y)
    if not x or not y then return math.huge, nil end

    local bestDistance = math.huge
    local bestZone = nil

    for _, zone in ipairs(getZones()) do
        if isZoneEnabled(zone) then
            local distance = distanceToZone(zone, x, y, includePadding)

            if distance < bestDistance then
                bestDistance = distance
                bestZone = zone
            end
        end
    end

    return bestDistance, bestZone
end

function protectedWater.DoesRadiusOverlapProtectedWater(x, y, radius, includePadding)
    radius = tonumber(radius) or 0.0
    if radius <= 0.0 then return false, nil, math.huge end

    local distance, zone = protectedWater.GetDistanceToProtectedWaterZone(x, y, includePadding)
    return distance <= radius, zone, distance
end

function protectedWater.ShouldSkipWaterModification(x, y, radius)
    local pointZone = protectedWater.GetProtectedWaterZoneAt(x, y, true)
    if pointZone then
        return true, ('point inside %s'):format(pointZone.name or 'protected water'), pointZone, 0.0
    end

    local overlaps, zone, distance = protectedWater.DoesRadiusOverlapProtectedWater(x, y, radius, true)
    if overlaps then
        return true, ('radius overlaps %s'):format(zone and zone.name or 'protected water'), zone, distance
    end

    return false, nil, zone, distance
end

function protectedWater.ClampModifyWaterRadiusNearProtectedZones(x, y, radius)
    radius = tonumber(radius) or 0.0
    if radius <= 0.0 then return 0.0, nil end

    local distance, zone = protectedWater.GetDistanceToProtectedWaterZone(x, y, true)
    if distance <= 0.0 then return 0.0, zone end
    if distance < radius then return math.max(0.0, distance), zone end
    return radius, zone
end

function protectedWater.SetWaterDebugEnabled(enabled)
    debugModifyWater = enabled == true
end

function protectedWater.IsWaterDebugEnabled()
    return debugModifyWater == true or getSettings().debugModifyWater == true
end

local function isRestoreReason(reason)
    return type(reason) == 'string' and string.find(string.lower(reason), 'restore', 1, true) ~= nil
end

local function logModifyWater(x, y, height, radius, finalRadius, skipped, reason, pointZone, overlapZone, distance)
    if not protectedWater.IsWaterDebugEnabled() then return end

    print(('[FloodDebug] ModifyWater x=%.1f y=%.1f height=%.3f radius=%.1f finalRadius=%.1f skipped=%s reason=%s pointProtected=%s overlapProtected=%s distance=%.1f finalHeightMode=absolute'):format(
        x,
        y,
        height,
        radius,
        finalRadius or radius,
        tostring(skipped == true),
        reason or 'none',
        pointZone and (pointZone.name or 'protected water') or 'none',
        overlapZone and (overlapZone.name or 'protected water') or 'none',
        distance or -1.0
    ))
end

function protectedWater.SafeModifyWater(x, y, height, radius, reason)
    x = tonumber(x)
    y = tonumber(y)
    height = tonumber(height)
    radius = tonumber(radius)

    if type(ModifyWater) ~= 'function' then return false, 'ModifyWater unavailable' end
    if not x or not y or not height or not radius or radius <= 0.0 then
        logModifyWater(x or 0.0, y or 0.0, height or 0.0, radius or 0.0, radius or 0.0, true, 'invalid args')
        return false, 'invalid args'
    end

    local pointZone = protectedWater.GetProtectedWaterZoneAt(x, y, true)
    local overlaps, overlapZone, distance = protectedWater.DoesRadiusOverlapProtectedWater(x, y, radius, true)
    local allowRestore = isRestoreReason(reason)
    local skipped = false
    local skipReason = nil
    local finalRadius = radius

    if (pointZone or overlaps) and not allowRestore then
        skipped = true
        skipReason = pointZone and ('point inside ' .. (pointZone.name or 'protected water'))
            or ('radius overlaps ' .. (overlapZone and overlapZone.name or 'protected water'))
    elseif overlaps and not pointZone and getSettings().clampModifyWaterRadius == true then
        finalRadius = math.max(0.0, (distance or 0.0) - 1.0)
        if finalRadius <= 0.0 then
            skipped = true
            skipReason = 'clamped radius <= 0'
        end
    end

    logModifyWater(x, y, height, radius, finalRadius, skipped, skipReason or reason, pointZone, overlapZone, distance)
    if skipped then return false, skipReason end

    local order = getSettings().modifyWaterOrder or 'height_radius'
    local ok
    if order == 'radius_height' then
        ok = pcall(ModifyWater, x, y, finalRadius, height)
    else
        ok = pcall(ModifyWater, x, y, height, finalRadius)
    end

    return ok == true, ok == true and nil or 'ModifyWater failed'
end

function protectedWater.isQuadProtected(bounds)
    if type(bounds) ~= 'table' then return false, nil, nil end

    local centerX = (bounds.minX + bounds.maxX) * 0.5
    local centerY = (bounds.minY + bounds.maxY) * 0.5
    local centerZone = protectedWater.GetProtectedWaterZoneAt(centerX, centerY, true)
    if centerZone then return true, centerZone, 'center' end

    local area = math.abs((bounds.maxX - bounds.minX) * (bounds.maxY - bounds.minY))
    local defaultMaxArea = tonumber(getSettings().maxProtectedQuadSkipArea) or 6000000.0

    for _, zone in ipairs(getZones()) do
        if isZoneEnabled(zone) then
            local maxArea = tonumber(zone.maxProtectedQuadSkipArea) or defaultMaxArea
            local zoneBounds = getZoneBounds(zone, true)
            if area <= maxArea and zoneBounds and boxesOverlap(bounds, zoneBounds) then
                return true, zone, 'overlap'
            end
        end
    end

    return false, nil, nil
end

function protectedWater.CaptureProtectedRestoreHeights()
    sampledRestoreHeights = {}

    if getSettings().enabled == false or getSettings().autoRestoreHeight == false then
        return 0, 0
    end

    local sampled = 0
    local missed = 0

    for zoneIndex, zone in ipairs(getZones()) do
        if isZoneEnabled(zone) and shouldAutoRestoreHeight(zone) then
            local zoneKey = getZoneKey(zone, zoneIndex)
            sampledRestoreHeights[zoneKey] = {}

            for pointIndex, point in ipairs(getRestorePoints(zone)) do
                local x, y = getPointXY(point)
                local height = x and y and sampleWaterHeightAt(x, y) or nil

                if type(height) == 'number' then
                    sampledRestoreHeights[zoneKey][pointIndex] = height
                    sampled = sampled + 1
                else
                    missed = missed + 1
                end
            end
        end
    end

    if getSettings().debugRestoreSampling == true then
        print(('[weather] Protected water restore height samples=%d missed=%d'):format(sampled, missed))
    end

    return sampled, missed
end

function protectedWater.GetProtectedRestoreHeight(zone, zoneIndex, pointIndex)
    if type(zone) ~= 'table' then return nil end

    local zoneKey = getZoneKey(zone, zoneIndex)
    if shouldAutoRestoreHeight(zone) then
        local samples = sampledRestoreHeights[zoneKey]
        local sampled = samples and samples[pointIndex or 1]
        if type(sampled) == 'number' then return sampled end
        local firstSample = getFirstSampledRestoreHeight(zoneKey)
        if type(firstSample) == 'number' then return firstSample end
        return getFallbackRestoreHeight(zone)
    end

    return tonumber(zone.restoreHeight)
end

function protectedWater.RestoreProtectedWaterBodies()
    if type(ModifyWater) ~= 'function' then return 0, 0 end

    local settings = getSettings()
    if settings.restoreAfterApply == false then return 0, 0 end

    local restored = 0
    local failed = 0

    for zoneIndex, zone in ipairs(getZones()) do
        if isZoneEnabled(zone) then
            local radius = tonumber(zone.restoreRadius)
            local restorePoints = getRestorePoints(zone)
            local zoneKey = getZoneKey(zone, zoneIndex)

            if radius and radius > 0.0 then
                for pointIndex, point in ipairs(restorePoints) do
                    local x, y = getPointXY(point)
                    local height = getRestoreHeight(zone, zoneKey, pointIndex)
                    if x and y and height then
                        local ok = protectedWater.SafeModifyWater(x, y, height, radius, ('restore protected %s'):format(zone.name or zoneKey))

                        if ok then
                            restored = restored + 1
                        else
                            failed = failed + 1
                        end
                    elseif shouldAutoRestoreHeight(zone) then
                        if protectedWater.IsWaterDebugEnabled() then
                            print(('[FloodDebug] Protected restore skipped zone=%s reason=missing restoreHeight; not using 0.0 fallback'):format(zone.name or zoneKey))
                        end
                        failed = failed + 1
                    end
                end
            end
        end
    end

    return restored, failed
end

function protectedWater.DebugDrawProtectedWaterBodies(z)
    if type(DrawLine) ~= 'function' then return end

    local settings = getSettings()
    local color = settings.debugColor or {}
    local r = tonumber(color.r) or 0
    local g = tonumber(color.g) or 180
    local b = tonumber(color.b) or 255
    local a = tonumber(color.a) or 220
    z = tonumber(z) or tonumber(settings.debugDrawZ) or 40.0

    for _, zone in ipairs(getZones()) do
        if isZoneEnabled(zone) and zone.type ~= 'polygon' then
            local box = getBox(zone, false)
            DrawLine(box.minX, box.minY, z, box.maxX, box.minY, z, r, g, b, a)
            DrawLine(box.maxX, box.minY, z, box.maxX, box.maxY, z, r, g, b, a)
            DrawLine(box.maxX, box.maxY, z, box.minX, box.maxY, z, r, g, b, a)
            DrawLine(box.minX, box.maxY, z, box.minX, box.minY, z, r, g, b, a)
        elseif isZoneEnabled(zone) and type(zone.points) == 'table' then
            local j = #zone.points
            for i = 1, #zone.points do
                local ax, ay = getPointXY(zone.points[j])
                local bx, by = getPointXY(zone.points[i])
                if ax and ay and bx and by then
                    DrawLine(ax, ay, z, bx, by, z, r, g, b, a)
                end
                j = i
            end
        end
    end
end

function protectedWater.setZones(zones)
    runtimeZones = type(zones) == 'table' and zones or {}
    sampledRestoreHeights = {}
end

function protectedWater.getActiveZones()
    return getZones()
end

protectedWater.getZones = getZones
protectedWater.isPointInProtectedWater = protectedWater.IsPointInProtectedWater
protectedWater.getProtectedWaterZoneAt = protectedWater.GetProtectedWaterZoneAt
protectedWater.getDistanceToProtectedWaterZone = protectedWater.GetDistanceToProtectedWaterZone
protectedWater.doesRadiusOverlapProtectedWater = protectedWater.DoesRadiusOverlapProtectedWater
protectedWater.shouldSkipWaterModification = protectedWater.ShouldSkipWaterModification
protectedWater.clampModifyWaterRadiusNearProtectedZones = protectedWater.ClampModifyWaterRadiusNearProtectedZones
protectedWater.safeModifyWater = protectedWater.SafeModifyWater
protectedWater.setWaterDebugEnabled = protectedWater.SetWaterDebugEnabled
protectedWater.isWaterDebugEnabled = protectedWater.IsWaterDebugEnabled
protectedWater.restoreProtectedWaterBodies = protectedWater.RestoreProtectedWaterBodies
protectedWater.captureProtectedRestoreHeights = protectedWater.CaptureProtectedRestoreHeights
protectedWater.getProtectedRestoreHeight = protectedWater.GetProtectedRestoreHeight
protectedWater.debugDrawProtectedWaterBodies = protectedWater.DebugDrawProtectedWaterBodies

return protectedWater
