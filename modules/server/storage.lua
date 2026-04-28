local zones = {}
local sequences = {}
local zoneStates = {}
local zoneDefsCopy = {}

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

function storageModule.updateZoneState(zoneId, state)
    zoneStates[zoneId] = state
end

return storageModule
