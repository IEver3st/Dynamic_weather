local zones = {}
local sequences = {}
local zoneStates = {}
local zoneDefsCopy = {}
local GetResourcePath = GetResourcePath
local resourcePath = GetResourcePath(GetCurrentResourceName())
local MAX_ZONE_COUNT = 256
local MAX_POINTS_PER_SHAPE = 128
local MAX_WEATHER_POOL = 32
local MAX_COORD_ABS = 20000.0

local function isFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isBoundedString(value, maximumLength)
    return type(value) == 'string' and #value > 0 and #value <= maximumLength
end

local function validateArray(value, maximumLength, label)
    if type(value) ~= 'table' then
        return false, ('%s must be an array'):format(label)
    end

    local length = #value
    if length > maximumLength then
        return false, ('%s exceeds %d entries'):format(label, maximumLength)
    end

    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 or key > length then
            return false, ('%s must contain sequential numeric keys'):format(label)
        end
        count = count + 1
    end

    if count ~= length then
        return false, ('%s contains sparse entries'):format(label)
    end

    return true
end

local function validatePoint(point)
    if type(point) ~= 'table' or not isFiniteNumber(point.x) or not isFiniteNumber(point.y) then
        return false
    end
    return math.abs(point.x) <= MAX_COORD_ABS and math.abs(point.y) <= MAX_COORD_ABS
end

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
    local temporaryPath = path .. '.tmp'
    local backupPath = path .. '.bak'
    local ok, encoded = pcall(json.encode, data)
    if not ok or type(encoded) ~= 'string' then
        print(('^1[weather] Cannot encode %s: %s^0'):format(path, tostring(encoded)))
        return false
    end

    local file = io.open(temporaryPath, 'w')
    if not file then
        print(('^1[weather] Cannot write %s^0'):format(temporaryPath))
        return false
    end

    file:write(encoded)
    file:close()

    local verifyFile = io.open(temporaryPath, 'r')
    local verifyContent = verifyFile and verifyFile:read('*a') or nil
    if verifyFile then verifyFile:close() end
    local decodedOk = type(verifyContent) == 'string' and pcall(json.decode, verifyContent)
    if not decodedOk then
        os.remove(temporaryPath)
        print(('^1[weather] Refusing invalid temporary JSON for %s^0'):format(path))
        return false
    end

    os.remove(backupPath)
    local existing = io.open(path, 'r')
    if existing then
        existing:close()
        if not os.rename(path, backupPath) then
            os.remove(temporaryPath)
            print(('^1[weather] Cannot create backup for %s^0'):format(path))
            return false
        end
    end

    if not os.rename(temporaryPath, path) then
        os.rename(backupPath, path)
        os.remove(temporaryPath)
        print(('^1[weather] Cannot replace %s^0'):format(path))
        return false
    end

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
    if not isBoundedString(zone.id, 64) or not zone.id:match('^[%w_%-]+$') then return false, 'invalid id' end
    if not isBoundedString(zone.label, 96) then return false, 'invalid label' end
    local pointsOk, pointsError = validateArray(zone.points, MAX_POINTS_PER_SHAPE, 'points')
    if not pointsOk then return false, pointsError end
    if #zone.points < 3 then return false, 'need 3+ points' end
    for i, pt in ipairs(zone.points) do
        if not validatePoint(pt) then
            return false, ('point %d invalid'):format(i)
        end
    end
    local poolOk, poolError = validateArray(zone.weatherPool, MAX_WEATHER_POOL, 'weatherPool')
    if not poolOk then return false, poolError end
    if #zone.weatherPool == 0 then
        return false, 'need weatherPool'
    end
    for i, weather in ipairs(zone.weatherPool) do
        if not isBoundedString(weather, 32) or not weather:match('^[%w_%-]+$') then
            return false, ('weatherPool entry %d invalid'):format(i)
        end
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
    local arrayOk, arrayError = validateArray(newZones, MAX_ZONE_COUNT, 'zones')
    if not arrayOk then return false, arrayError end
    local seenIds = {}
    for i, zone in ipairs(newZones) do
        local ok, err = validateZone(zone)
        if not ok then
            return false, ('Zone %d: %s'):format(i, err)
        end
        if seenIds[zone.id] then return false, ('Zone %d: duplicate id'):format(i) end
        seenIds[zone.id] = true
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
