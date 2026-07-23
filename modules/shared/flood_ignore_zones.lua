local floodIgnoreZones = {}
local runtimeZones = nil

local function getZones()
    if runtimeZones then return runtimeZones end
    return floodIgnoreZones
end

local function isZoneEnabled(zone)
    return type(zone) == 'table' and zone.enabled ~= false
end

local function getPointXY(point)
    if type(point) ~= 'table' and type(point) ~= 'vector2' then return nil, nil end
    return tonumber(point.x or point[1]), tonumber(point.y or point[2])
end

local getCircleCenter

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

local function pointInBox(x, y, bounds)
    return x >= bounds.minX and x <= bounds.maxX and y >= bounds.minY and y <= bounds.maxY
end

local function boxesOverlap(a, b)
    return a.minX <= b.maxX and a.maxX >= b.minX and a.minY <= b.maxY and a.maxY >= b.minY
end

local function getPolygonBounds(points)
    local minX, maxX, minY, maxY
    for _, point in ipairs(points or {}) do
        local x, y = getPointXY(point)
        if x and y then
            minX = minX and math.min(minX, x) or x
            maxX = maxX and math.max(maxX, x) or x
            minY = minY and math.min(minY, y) or y
            maxY = maxY and math.max(maxY, y) or y
        end
    end

    if not minX then return nil end
    return { minX = minX, maxX = maxX, minY = minY, maxY = maxY }
end

local function getZoneBounds(zone)
    if type(zone) ~= 'table' then return nil end
    if zone.type == 'circle' or tonumber(zone.radius) then
        local cx, cy = getCircleCenter(zone)
        local radius = tonumber(zone.radius) or 0.0
        if not cx or not cy or radius <= 0.0 then return nil end

        return {
            minX = cx - radius,
            maxX = cx + radius,
            minY = cy - radius,
            maxY = cy + radius,
        }
    end

    if type(zone.points) == 'table' and #zone.points >= 3 then
        return getPolygonBounds(zone.points)
    end

    return nil
end

local function distanceToPolygon(x, y, points)
    if pointInPolygon(x, y, points) then return 0.0, true end

    local best = math.huge
    local j = #points
    for i = 1, #points do
        local ax, ay = getPointXY(points[j])
        local bx, by = getPointXY(points[i])
        if ax and ay and bx and by then
            best = math.min(best, distanceToSegment(x, y, ax, ay, bx, by))
        end
        j = i
    end

    return best, false
end

function getCircleCenter(zone)
    local center = zone.center or {}
    return tonumber(center.x) or tonumber(zone.centerX) or tonumber(zone.x),
        tonumber(center.y) or tonumber(zone.centerY) or tonumber(zone.y)
end

local function getZoneDistance(zone, x, y)
    if zone.type == 'circle' or tonumber(zone.radius) then
        local cx, cy = getCircleCenter(zone)
        local radius = tonumber(zone.radius) or 0.0
        if not cx or not cy or radius <= 0.0 then return math.huge, false end

        local dx = x - cx
        local dy = y - cy
        local distance = math.sqrt((dx * dx) + (dy * dy)) - radius
        return math.max(0.0, distance), distance <= 0.0
    end

    if type(zone.points) == 'table' and #zone.points >= 3 then
        return distanceToPolygon(x, y, zone.points)
    end

    return math.huge, false
end

local function getZoneMultiplier(zone, x, y)
    local distance, inside = getZoneDistance(zone, x, y)
    if inside then return 0.0, distance, true end

    local fadeDistance = tonumber(zone.fadeDistance) or 0.0
    if fadeDistance <= 0.0 or distance >= fadeDistance then
        return 1.0, distance, false
    end

    return math.max(0.0, math.min(1.0, distance / fadeDistance)), distance, false
end

local function getDefaultMaxIgnoredQuadArea()
    local cfg = Config and Config.SeaLevel or {}
    return tonumber(cfg.floodIgnoreMaxQuadArea) or 2500000.0
end

function floodIgnoreZones.CalculateMultiplier(zones, x, y)
    x = tonumber(x)
    y = tonumber(y)
    if not x or not y then
        return { multiplier = 1.0, zone = nil, zoneName = nil, inside = false, distance = math.huge }
    end

    local bestMultiplier = 1.0
    local bestZone = nil
    local bestDistance = math.huge
    local bestInside = false

    for _, zone in ipairs(zones or getZones()) do
        if isZoneEnabled(zone) then
            local multiplier, distance, inside = getZoneMultiplier(zone, x, y)
            if multiplier < bestMultiplier or (multiplier == bestMultiplier and distance < bestDistance) then
                bestMultiplier = multiplier
                bestZone = zone
                bestDistance = distance
                bestInside = inside
            end
        end
    end

    return {
        multiplier = bestMultiplier,
        zone = bestZone,
        zoneName = bestZone and (bestZone.name or bestZone.label or bestZone.id) or nil,
        inside = bestInside,
        distance = bestDistance,
    }
end

function floodIgnoreZones.IsQuadIgnored(zones, bounds)
    if type(bounds) ~= 'table' then
        bounds = zones
        zones = nil
    end

    if type(bounds) ~= 'table' then return false, nil, nil end
    local minX = tonumber(bounds.minX)
    local maxX = tonumber(bounds.maxX)
    local minY = tonumber(bounds.minY)
    local maxY = tonumber(bounds.maxY)
    if not minX or not maxX or not minY or not maxY then return false, nil, nil end

    local quadBounds = {
        minX = math.min(minX, maxX),
        maxX = math.max(minX, maxX),
        minY = math.min(minY, maxY),
        maxY = math.max(minY, maxY),
    }
    local centerX = (quadBounds.minX + quadBounds.maxX) * 0.5
    local centerY = (quadBounds.minY + quadBounds.maxY) * 0.5
    local area = math.abs((quadBounds.maxX - quadBounds.minX) * (quadBounds.maxY - quadBounds.minY))
    local defaultMaxArea = getDefaultMaxIgnoredQuadArea()

    for _, zone in ipairs(zones or getZones()) do
        if isZoneEnabled(zone) then
            local maxArea = tonumber(zone.maxIgnoredQuadArea) or defaultMaxArea
            if area <= maxArea then
                local _, inside = getZoneDistance(zone, centerX, centerY)
                if inside then return true, zone, 'center' end

                local zoneBounds = getZoneBounds(zone)
                if zoneBounds and boxesOverlap(quadBounds, zoneBounds) then
                    return true, zone, 'overlap'
                end

                if type(zone.points) == 'table' then
                    for _, point in ipairs(zone.points) do
                        local x, y = getPointXY(point)
                        if x and y and pointInBox(x, y, quadBounds) then
                            return true, zone, 'zone-point'
                        end
                    end
                end
            end
        end
    end

    return false, nil, nil
end

function floodIgnoreZones.DebugDrawFloodIgnoreZones(zones, z)
    if type(DrawLine) ~= 'function' then return end

    z = tonumber(z) or 40.0
    local r, g, b, a = 56, 189, 248, 220

    for _, zone in ipairs(zones or getZones()) do
        if isZoneEnabled(zone) and type(zone.points) == 'table' and #zone.points >= 2 then
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

function floodIgnoreZones.setZones(zones)
    runtimeZones = type(zones) == 'table' and zones or {}
end

function floodIgnoreZones.getZones()
    return getZones()
end

floodIgnoreZones.calculateMultiplier = floodIgnoreZones.CalculateMultiplier
floodIgnoreZones.isQuadIgnored = floodIgnoreZones.IsQuadIgnored
floodIgnoreZones.debugDrawFloodIgnoreZones = floodIgnoreZones.DebugDrawFloodIgnoreZones

return floodIgnoreZones
