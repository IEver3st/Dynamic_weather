local zones = {}
local sequences = {}
local zoneStates = {}
local zoneDefsCopy = {}
local protectedWaterBodies = {}
local floodSettings = {}
local floodIgnoreZones = {}

local GetResourcePath = GetResourcePath
local resourcePath = GetResourcePath(GetCurrentResourceName())

local function tableLength(t)
    local count = 0
    for _ in pairs(t or {}) do
        count = count + 1
    end
    return count
end

local function readJsonFile(filename)
    local path = ('%s/shared/data/%s'):format(resourcePath, filename)
    local file = io.open(path, 'r')
    if not file then
        print(('^1[weather] Cannot read %s^0'):format(path))
        return nil
    end
    local content = file:read('*a')
    file:close()
    local ok, decoded = pcall(json.decode, content)
    if not ok then
        print(('^1[weather] Invalid JSON in %s: %s^0'):format(path, tostring(decoded)))
        return nil
    end
    return decoded
end

local function writeJsonFile(filename, data)
    local path = ('%s/shared/data/%s'):format(resourcePath, filename)
    local file = io.open(path, 'w')
    if not file then
        print(('^1[weather] Cannot write %s^0'):format(path))
        return false
    end
    local ok, encoded = pcall(json.encode, data)
    if not ok then
        file:close()
        print(('^1[weather] Cannot encode %s: %s^0'):format(path, tostring(encoded)))
        return false
    end
    file:write(encoded)
    file:close()
    print(('^2[weather] Written %s^0'):format(path))
    return true
end

local function mergeFloodSettings(overrides)
    Config.FloodEvent = Config.FloodEvent or {}
    local cfg = Config.FloodEvent
    local chance = tonumber(cfg.chance) or tonumber(cfg.chanceMin) or 0.08
    local maxOffset = tonumber(cfg.maxOffset) or tonumber((Config.SeaLevel or {}).floodHeight) or 2.0
    local recommendedMaxOffset = tonumber(cfg.recommendedMaxOffset) or 2.0

    local settings = {
        enabled = cfg.enabled ~= false,
        chance = chance,
        maxOffset = maxOffset,
        recommendedMaxOffset = recommendedMaxOffset,
        requireThunder = cfg.requireThunder ~= false,
        thunderCondition = cfg.thunderCondition or 'any_zone',
        stormLeadSeconds = tonumber(cfg.stormLeadSeconds) or 45,
    }

    if type(overrides) == 'table' then
        if overrides.enabled ~= nil then settings.enabled = overrides.enabled == true end
        if tonumber(overrides.chance) then settings.chance = tonumber(overrides.chance) end
        if tonumber(overrides.maxOffset) then settings.maxOffset = tonumber(overrides.maxOffset) end
        if overrides.requireThunder ~= nil then settings.requireThunder = overrides.requireThunder == true end
        if type(overrides.thunderCondition) == 'string' then settings.thunderCondition = overrides.thunderCondition end
        if tonumber(overrides.stormLeadSeconds) then settings.stormLeadSeconds = tonumber(overrides.stormLeadSeconds) end
    end

    settings.chance = math.max(0.0, math.min(1.0, settings.chance))
    settings.maxOffset = math.max(0.0, settings.maxOffset)
    settings.stormLeadSeconds = math.max(0.0, settings.stormLeadSeconds)
    if settings.thunderCondition ~= 'all_zones' then
        settings.thunderCondition = 'any_zone'
    end

    Config.FloodEvent.enabled = settings.enabled
    Config.FloodEvent.chance = settings.chance
    Config.FloodEvent.chanceMin = settings.chance
    Config.FloodEvent.chanceMax = settings.chance
    Config.FloodEvent.maxOffset = settings.maxOffset
    Config.FloodEvent.recommendedMaxOffset = settings.recommendedMaxOffset
    Config.FloodEvent.requireThunder = settings.requireThunder
    Config.FloodEvent.thunderCondition = settings.thunderCondition
    Config.FloodEvent.stormLeadSeconds = settings.stormLeadSeconds

    Config.SeaLevel = Config.SeaLevel or {}
    Config.SeaLevel.floodHeight = settings.maxOffset
    Config.SeaLevel.braveFloodHeight = settings.maxOffset
    Config.SeaLevel.floodMode = 'offset'

    return settings
end

local function validateMapColor(c)
    if c == nil then return true end
    if type(c) ~= 'string' then return false, 'mapColor must be string' end
    if c == '' then return true end
    if not c:match('^#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$') then
        return false, 'mapColor must be #RRGGBB hex'
    end
    return true
end

local function validateZone(zone, index)
    if type(zone) ~= 'table' then return false, 'not a table' end
    if type(zone.id) ~= 'string' or #zone.id == 0 then return false, 'missing id' end
    if type(zone.label) ~= 'string' then return false, 'missing label' end
    if type(zone.points) ~= 'table' or #zone.points < 3 then return false, 'need 3+ points' end
    for i, pt in ipairs(zone.points) do
        if type(pt.x) ~= 'number' or type(pt.y) ~= 'number' then
            return false, ('point %d invalid'):format(i)
        end
    end
    if type(zone.weatherPool) ~= 'table' or #zone.weatherPool == 0 then
        return false, 'need weatherPool'
    end
    local okc, errc = validateMapColor(zone.mapColor)
    if not okc then return false, errc end
    return true
end

local function validateProtectedWaterBody(body, index)
    if type(body) ~= 'table' then return false, 'not a table' end
    if type(body.id) ~= 'string' or #body.id == 0 then return false, 'missing id' end
    if type(body.name) ~= 'string' or #body.name == 0 then return false, 'missing name' end
    if type(body.points) ~= 'table' or #body.points < 3 then return false, 'need 3+ points' end
    for i, pt in ipairs(body.points) do
        if type(pt.x) ~= 'number' or type(pt.y) ~= 'number' then
            return false, ('point %d invalid'):format(i)
        end
    end
    if body.restorePoints ~= nil then
        if type(body.restorePoints) ~= 'table' then return false, 'restorePoints invalid' end
        for i, pt in ipairs(body.restorePoints) do
            if type(pt.x) ~= 'number' or type(pt.y) ~= 'number' then
                return false, ('restore point %d invalid'):format(i)
            end
        end
    end
    if body.restoreHeight ~= nil and type(body.restoreHeight) ~= 'number' then return false, 'restoreHeight invalid' end
    if body.restoreRadius ~= nil and type(body.restoreRadius) ~= 'number' then return false, 'restoreRadius invalid' end
    if body.padding ~= nil and type(body.padding) ~= 'number' then return false, 'padding invalid' end
    local okc, errc = validateMapColor(body.mapColor)
    if not okc then return false, errc end
    return true
end

local function validateFloodIgnoreZone(zone, index)
    if type(zone) ~= 'table' then return false, 'not a table' end
    if type(zone.id) ~= 'string' or #zone.id == 0 then return false, 'missing id' end
    if type(zone.name) ~= 'string' or #zone.name == 0 then return false, 'missing name' end

    local hasPolygon = type(zone.points) == 'table' and #zone.points >= 3
    local hasCircle = (type(zone.center) == 'table' or zone.centerX ~= nil or zone.x ~= nil) and tonumber(zone.radius) ~= nil
    if not hasPolygon and not hasCircle then
        return false, 'need polygon points or center/radius'
    end

    if hasPolygon then
        for i, pt in ipairs(zone.points) do
            if type(pt.x) ~= 'number' or type(pt.y) ~= 'number' then
                return false, ('point %d invalid'):format(i)
            end
        end
    end

    if hasCircle then
        local center = zone.center or {}
        local x = tonumber(center.x) or tonumber(zone.centerX) or tonumber(zone.x)
        local y = tonumber(center.y) or tonumber(zone.centerY) or tonumber(zone.y)
        local radius = tonumber(zone.radius)
        if not x or not y then return false, 'center invalid' end
        if not radius or radius <= 0.0 then return false, 'radius invalid' end
    end

    if zone.fadeDistance ~= nil and type(zone.fadeDistance) ~= 'number' then return false, 'fadeDistance invalid' end
    local okc, errc = validateMapColor(zone.mapColor)
    if not okc then return false, errc end
    return true
end

local function serializeZonesForClients()
    local list = {}

    for _, zone in ipairs(zones) do
        list[#list + 1] = {
            id = zone.id,
            label = zone.label,
            points = zone.points,
            enabled = zone.enabled ~= false,
            thickness = zone.thickness or 50.0,
            sequence = zone.sequence,
            weatherPool = zone.weatherPool,
            transitionDuration = zone.transitionDuration or 15,
            mapColor = zone.mapColor,
        }
    end

    return list
end

local storageModule = {}

function storageModule.loadZones()
    local data = readJsonFile('zones.json')
    if data and data.zones then
        zones = data.zones
        print(('^2[weather] Loaded %d zones from file^0'):format(#zones))
    else
        print('^1[weather] No zone data found, using empty set^0')
        zones = {}
    end

    local seqData = readJsonFile('sequences.json')
    if seqData and seqData.presets then
        sequences = seqData.presets
        print(('^2[weather] Loaded %d sequence presets^0'):format(tableLength(sequences)))
    else
        print('^1[weather] No sequence data found^0')
        sequences = {}
    end

    storageModule.loadProtectedWater()
    storageModule.loadFloodSettings()
    storageModule.loadFloodIgnoreZones()

    zoneDefsCopy = {}
    for i, zone in ipairs(zones) do
        zoneDefsCopy[zone.id] = {
            id = zone.id,
            label = zone.label,
            points = zone.points,
            enabled = zone.enabled,
            thickness = zone.thickness or 50.0,
            sequence = zone.sequence,
            weatherPool = zone.weatherPool,
            transitionDuration = zone.transitionDuration or 15,
            mapColor = zone.mapColor,
        }
    end

    storageModule.initializeStates()

    return zones
end

function storageModule.loadFloodIgnoreZones()
    local data = readJsonFile('flood_ignore_zones.json')
    if data and type(data.zones) == 'table' then
        floodIgnoreZones = data.zones
        print(('^2[weather] Loaded %d flood ignore zones from file^0'):format(#floodIgnoreZones))
    else
        floodIgnoreZones = {}
        print('^3[weather] No flood ignore zones found, using empty set^0')
    end

    return floodIgnoreZones
end

function storageModule.loadProtectedWater()
    local data = readJsonFile('protected_water.json')
    if data and type(data.bodies) == 'table' then
        protectedWaterBodies = data.bodies
        print(('^2[weather] Loaded %d protected water bodies from file^0'):format(#protectedWaterBodies))
    else
        protectedWaterBodies = {}
        print('^3[weather] No protected water data found, using empty set^0')
    end

    return protectedWaterBodies
end

function storageModule.loadFloodSettings()
    local data = readJsonFile('flood_settings.json')
    if data and type(data.settings) == 'table' then
        floodSettings = mergeFloodSettings(data.settings)
        print(('^2[weather] Loaded flood settings chance=%.3f maxOffset=%.2f thunderOnly=%s^0'):format(
            floodSettings.chance,
            floodSettings.maxOffset,
            tostring(floodSettings.requireThunder)
        ))
    else
        floodSettings = mergeFloodSettings()
        print('^3[weather] No flood settings data found, using config defaults^0')
    end

    return floodSettings
end

function storageModule.initializeStates()
    local nextStates = {}

    for id, zone in pairs(zoneDefsCopy) do
        local existing = zoneStates[id]
        if not existing then
            local weather = zone.weatherPool and zone.weatherPool[1] or 'CLEAR'
            existing = {
                currentWeather = weather,
                nextWeather = weather,
                timeUntilAdvance = 60,
                windSpeed = 5.0,
                windDirection = 0.0,
                lastUpdated = os.time(),
            }
        end

        nextStates[id] = existing
    end

    zoneStates = nextStates
end

function storageModule.saveZones(newZones)
    for i, zone in ipairs(newZones) do
        local ok, err = validateZone(zone)
        if not ok then
            return false, ('Zone %d: %s'):format(i, err)
        end
    end

    local data = { version = 1, zones = newZones }
    local ok = writeJsonFile('zones.json', data)
    if not ok then
        return false, 'Failed to write file'
    end

    zones = newZones
    zoneDefsCopy = {}
    for i, zone in ipairs(zones) do
        zoneDefsCopy[zone.id] = {
            id = zone.id,
            label = zone.label,
            points = zone.points,
            enabled = zone.enabled,
            thickness = zone.thickness or 50.0,
            sequence = zone.sequence,
            weatherPool = zone.weatherPool,
            transitionDuration = zone.transitionDuration or 15,
            mapColor = zone.mapColor,
        }
    end

    storageModule.initializeStates()

    return true
end

function storageModule.saveProtectedWater(newBodies)
    if type(newBodies) ~= 'table' then
        return false, 'protected bodies must be table'
    end

    for i, body in ipairs(newBodies) do
        local ok, err = validateProtectedWaterBody(body, i)
        if not ok then
            return false, ('Protected water %d: %s'):format(i, err)
        end
        body.type = body.type == 'box' and 'box' or 'polygon'
        body.enabled = body.enabled ~= false
        if body.restoreHeight ~= nil then
            body.restoreHeight = tonumber(body.restoreHeight)
        end
        body.restoreRadius = tonumber(body.restoreRadius) or 250.0
        body.padding = tonumber(body.padding) or 150.0
    end

    local data = { version = 1, bodies = newBodies }
    local ok = writeJsonFile('protected_water.json', data)
    if not ok then
        return false, 'Failed to write file'
    end

    protectedWaterBodies = newBodies
    return true
end

function storageModule.saveFloodSettings(newSettings)
    if type(newSettings) ~= 'table' then
        return false, 'flood settings must be table'
    end

    local settings = mergeFloodSettings(newSettings)
    local ok = writeJsonFile('flood_settings.json', { version = 1, settings = settings })
    if not ok then
        return false, 'Failed to write file'
    end

    floodSettings = settings
    return true, settings
end

function storageModule.saveFloodIgnoreZones(newZones)
    if type(newZones) ~= 'table' then
        return false, 'flood ignore zones must be table'
    end

    for i, zone in ipairs(newZones) do
        zone.zoneType = 'flood_ignore'
        zone.type = zone.type == 'circle' and 'circle' or 'polygon'
        zone.enabled = zone.enabled ~= false
        zone.fadeDistance = math.max(0.0, tonumber(zone.fadeDistance) or 0.0)
        zone.mapColor = zone.mapColor or '#38bdf8'

        if zone.type == 'circle' then
            local center = zone.center or {}
            zone.center = {
                x = tonumber(center.x) or tonumber(zone.centerX) or tonumber(zone.x) or 0.0,
                y = tonumber(center.y) or tonumber(zone.centerY) or tonumber(zone.y) or 0.0,
            }
            zone.radius = math.max(1.0, tonumber(zone.radius) or 1.0)
        end

        local ok, err = validateFloodIgnoreZone(zone, i)
        if not ok then
            return false, ('Flood ignore zone %d: %s'):format(i, err)
        end
    end

    local ok = writeJsonFile('flood_ignore_zones.json', { version = 1, zones = newZones })
    if not ok then
        return false, 'Failed to write file'
    end

    floodIgnoreZones = newZones
    return true
end

function storageModule.getZones()
    return zoneDefsCopy
end

function storageModule.getClientZones()
    return serializeZonesForClients()
end

function storageModule.getZoneStates()
    return zoneStates
end

function storageModule.getSequences()
    return sequences
end

function storageModule.getRawZones()
    return zones
end

function storageModule.getProtectedWaterBodies()
    return protectedWaterBodies
end

function storageModule.getFloodSettings()
    if not floodSettings or not next(floodSettings) then
        floodSettings = mergeFloodSettings()
    end
    return floodSettings
end

function storageModule.getFloodIgnoreZones()
    return floodIgnoreZones
end

function storageModule.updateZoneState(zoneId, state)
    zoneStates[zoneId] = state
end

return storageModule
