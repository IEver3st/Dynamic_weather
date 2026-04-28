local mathModule = {}

function mathModule.pointInPolygon(x, y, points)
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

function mathModule.pointLineDistance(px, py, x1, y1, x2, y2)
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

function mathModule.distanceToZoneEdge(x, y, zone)
    local points = zone.points
    if not points or #points < 3 then return 0.0 end

    local minDist = math.huge
    local count = #points

    for i = 1, count do
        local j = i % count + 1
        local d = mathModule.pointLineDistance(x, y,
            points[i].x, points[i].y,
            points[j].x, points[j].y)
        if d < minDist then minDist = d end
    end

    return minDist
end

function mathModule.polygonCentroid(points)
    local cx, cy = 0.0, 0.0
    local count = #points
    if count == 0 then return 0.0, 0.0 end

    for i = 1, count do
        cx = cx + points[i].x
        cy = cy + points[i].y
    end

    return cx / count, cy / count
end

return mathModule
