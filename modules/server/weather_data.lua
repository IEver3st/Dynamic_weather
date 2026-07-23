local weatherData = {}
local alerts = {}
local nextAlertId = 0
local cleanupActive = false

local function now()
    return os.time()
end

local function clampSeverity(value)
    local n = tonumber(value) or (Config.WeatherData and Config.WeatherData.defaultSeverity) or 1
    n = math.floor(n)
    if n < 1 then return 1 end
    if n > 5 then return 5 end
    return n
end

local function getStorage()
    return lib.require('modules.server.storage')
end

local function getMath()
    return lib.require('modules.shared.math')
end

local function normalizeWeather(weather)
    if type(weather) ~= 'string' or #weather == 0 then
        return Config.globalFallbackWeather or 'CLEAR'
    end
    return string.upper(weather)
end

local function resolveSeverity(zone, state)
    if state and state.severity ~= nil then return clampSeverity(state.severity) end
    if zone and zone.severity ~= nil then return clampSeverity(zone.severity) end

    local weather = normalizeWeather(state and state.currentWeather)
    if weather == 'THUNDER' then return 4 end
    if weather == 'RAIN' then return 2 end
    if weather == 'FOGGY' or weather == 'SMOG' then return 2 end
    return clampSeverity(nil)
end

local function resolveRoadCondition(weather, severity)
    weather = normalizeWeather(weather)
    severity = clampSeverity(severity)

    if weather == 'THUNDER' then
        return severity >= 4 and 'HAZARDOUS' or 'LOW_VISIBILITY'
    end

    if weather == 'RAIN' or weather == 'CLEARING' then
        return severity >= 3 and 'LOW_VISIBILITY' or 'WET'
    end

    if weather == 'FOGGY' or weather == 'SMOG' then
        return 'LOW_VISIBILITY'
    end

    return 'DRY'
end

local function roadAdvisory(condition)
    local messages = Config.RoadConditions or {}
    return messages[condition] or messages.DRY or 'Normal patrol conditions.'
end

local function zoneList()
    local storage = getStorage()
    local defs = storage.getZones()
    local list = {}
    for _, zone in pairs(defs or {}) do
        list[#list + 1] = zone
    end
    table.sort(list, function(a, b)
        return tostring(a.id) < tostring(b.id)
    end)
    return list
end

local function findZoneAtCoords(x, y)
    x = tonumber(x)
    y = tonumber(y)
    if not x or not y then return nil end

    local mathModule = getMath()
    for _, zone in ipairs(zoneList()) do
        if zone.enabled ~= false and zone.points and #zone.points >= 3 then
            if mathModule.pointInPolygon(x, y, zone.points) then
                return zone
            end
        end
    end
end

local function zoneState(zoneId)
    local states = getStorage().getZoneStates()
    return states and states[zoneId] or nil
end

local function buildZoneWeather(zone)
    if not zone then
        local weather = Config.globalFallbackWeather or 'CLEAR'
        local severity = clampSeverity(nil)
        local road = resolveRoadCondition(weather, severity)
        return {
            zoneId = nil,
            zoneLabel = nil,
            weather = weather,
            severity = severity,
            roadCondition = road,
            advisoryText = roadAdvisory(road),
        }
    end

    local state = zoneState(zone.id) or {}
    local weather = normalizeWeather(state.currentWeather or (zone.weatherPool and zone.weatherPool[1]))
    local severity = resolveSeverity(zone, state)
    local road = resolveRoadCondition(weather, severity)

    return {
        zoneId = zone.id,
        zoneLabel = zone.label,
        regionId = zone.id,
        regionLabel = zone.label,
        weather = weather,
        severity = severity,
        roadCondition = road,
        advisoryText = roadAdvisory(road),
        windSpeed = state.windSpeed,
        windDirection = state.windDirection,
        lastUpdated = state.lastUpdated,
        timeUntilAdvance = state.timeUntilAdvance,
    }
end

local function periodTime(base, period)
    local startTime = base + ((period.offsetMinutes or 0) * 60)
    local endTime = startTime + ((period.durationMinutes or 30) * 60)
    return startTime, endTime
end

local function forecastWeatherForPeriod(zone, index)
    local state = zoneState(zone.id) or {}
    if index == 1 then
        return normalizeWeather(state.currentWeather or (zone.weatherPool and zone.weatherPool[1]))
    end
    if index == 2 and state.nextWeather then
        return normalizeWeather(state.nextWeather)
    end

    local pool = zone.weatherPool or {}
    if #pool == 0 then return Config.globalFallbackWeather or 'CLEAR' end
    local offset = ((index - 1) % #pool) + 1
    return normalizeWeather(pool[offset])
end

local function buildForecastForZone(zone)
    if not zone then return {} end

    local base = now()
    local periods = (Config.WeatherData and Config.WeatherData.forecastPeriods) or {}
    local forecast = {}

    for i, period in ipairs(periods) do
        local startTime, endTime = periodTime(base, period)
        local weather = forecastWeatherForPeriod(zone, i)
        local severity = resolveSeverity(zone, zoneState(zone.id))
        local road = resolveRoadCondition(weather, severity)

        forecast[#forecast + 1] = {
            period = period.id or tostring(i),
            label = period.label or tostring(i),
            startTime = startTime,
            endTime = endTime,
            zoneId = zone.id,
            zoneLabel = zone.label,
            regionId = zone.id,
            regionLabel = zone.label,
            weather = weather,
            severity = severity,
            roadCondition = road,
            advisoryText = roadAdvisory(road),
        }
    end

    return forecast
end

local function findRegion(regionId)
    if type(regionId) ~= 'string' or #regionId == 0 then return nil end
    local needle = string.lower(regionId)
    for _, zone in ipairs(zoneList()) do
        if string.lower(zone.id or '') == needle or string.lower(zone.label or '') == needle then
            return zone
        end
    end
end

local function activeAlerts()
    local ts = now()
    local list = {}
    for id, alert in pairs(alerts) do
        if not alert.expiresAt or alert.expiresAt > ts then
            list[#list + 1] = alert
        else
            alerts[id] = nil
        end
    end
    table.sort(list, function(a, b)
        return tostring(a.id) < tostring(b.id)
    end)
    return list
end

local function broadcastAlertIssued(alert)
    TriggerClientEvent('weather:client:alertIssued', -1, alert)
    TriggerEvent('weather:server:alertIssued', alert)
end

local function broadcastAlertCleared(alertId, alert)
    TriggerClientEvent('weather:client:alertCleared', -1, alertId, alert)
    TriggerEvent('weather:server:alertCleared', alertId, alert)
end

function weatherData.start()
    if cleanupActive then return end
    cleanupActive = true
    CreateThread(function()
        while cleanupActive do
            Wait(((Config.WeatherData or {}).alerts or {}).cleanupInterval or 60000)
            if cleanupActive then
                local ts = now()
                for id, alert in pairs(alerts) do
                    if alert.expiresAt and alert.expiresAt <= ts then
                        alerts[id] = nil
                        broadcastAlertCleared(id, alert)
                    end
                end
            end
        end
    end)
end

function weatherData.stop()
    cleanupActive = false
end

function weatherData.getCurrentWeather()
    return buildZoneWeather(zoneList()[1])
end

function weatherData.getActiveWeatherZones()
    local list = {}
    for _, zone in ipairs(zoneList()) do
        if zone.enabled ~= false then
            local item = buildZoneWeather(zone)
            item.points = zone.points
            item.mapColor = zone.mapColor
            list[#list + 1] = item
        end
    end
    return list
end

function weatherData.getWeatherAtCoords(x, y)
    return buildZoneWeather(findZoneAtCoords(x, y))
end

function weatherData.getForecast()
    local result = {}
    for _, zone in ipairs(zoneList()) do
        if zone.enabled ~= false then
            result[zone.id] = buildForecastForZone(zone)
        end
    end
    return result
end

function weatherData.getForecastForRegion(regionId)
    return buildForecastForZone(findRegion(regionId))
end

function weatherData.getActiveAlerts()
    return activeAlerts()
end

function weatherData.getRoadConditionAtCoords(x, y)
    local weather = weatherData.getWeatherAtCoords(x, y)
    return {
        zoneId = weather.zoneId,
        zoneLabel = weather.zoneLabel,
        weather = weather.weather,
        severity = weather.severity,
        roadCondition = weather.roadCondition,
        advisoryText = weather.advisoryText,
    }
end

function weatherData.createWeatherAlert(data)
    if type(data) ~= 'table' then return nil, 'invalid alert' end

    nextAlertId = nextAlertId + 1
    local issued = now()
    local defaultDuration = (((Config.WeatherData or {}).alerts or {}).defaultDurationMinutes or 30) * 60
    local zone = data.zoneId and findRegion(data.zoneId) or nil
    local severity = clampSeverity(data.severity)

    local alert = {
        id = data.id or ('weather_alert_%d'):format(nextAlertId),
        type = data.type or 'WEATHER_ADVISORY',
        title = data.title or 'Weather Advisory',
        zoneId = data.zoneId or data.regionId or (zone and zone.id),
        zoneLabel = data.zoneLabel or data.regionLabel or (zone and zone.label),
        regionId = data.regionId or data.zoneId or (zone and zone.id),
        regionLabel = data.regionLabel or data.zoneLabel or (zone and zone.label),
        severity = severity,
        issuedAt = data.issuedAt or issued,
        expiresAt = data.expiresAt or data.expiryTime or (issued + defaultDuration),
        message = data.message or '',
        recommendedActions = data.recommendedActions or data.actions or {},
    }

    alerts[alert.id] = alert
    broadcastAlertIssued(alert)
    return alert
end

function weatherData.clearWeatherAlert(alertId)
    if type(alertId) ~= 'string' or #alertId == 0 then return false, 'invalid alert id' end
    local alert = alerts[alertId]
    if not alert then return false, 'alert not found' end
    alerts[alertId] = nil
    broadcastAlertCleared(alertId, alert)
    return true
end

function weatherData.createDispatchIncident(data)
    if type(data) ~= 'table' then return nil, 'invalid incident' end
    local weather = data.coords and weatherData.getWeatherAtCoords(data.coords.x, data.coords.y) or {}
    local incident = {
        type = data.type or 'WEATHER_INCIDENT',
        title = data.title or 'Weather Incident',
        message = data.message or '',
        coords = data.coords,
        zoneId = data.zoneId or weather.zoneId,
        zoneLabel = data.zoneLabel or weather.zoneLabel,
        regionId = data.regionId or weather.regionId,
        regionLabel = data.regionLabel or weather.regionLabel,
        severity = clampSeverity(data.severity or weather.severity),
        weather = data.weather or weather.weather,
        roadCondition = data.roadCondition or weather.roadCondition,
        jobs = data.jobs or (((Config.WeatherData or {}).dispatch or {}).defaultJobs) or {},
        createdAt = now(),
    }

    local dispatch = (Config.WeatherData or {}).dispatch or {}
    if dispatch.enabled ~= false then
        TriggerEvent(dispatch.eventName or 'weather:server:incidentCreated', incident)
    end
    return incident
end

local function isWetHudWeather(name)
    local w = string.upper(tostring(name or ''))
    return w == 'RAIN' or w == 'THUNDER' or w == 'CLEARING'
end

---@param zoneId string|nil
---@param x number|nil
---@param y number|nil
---@return table snapshot ok, forecast, wet ETA for HUD integrations
function weatherData.getHudSnapshot(zoneId, x, y)
    local zone = nil
    if type(zoneId) == 'string' and #zoneId > 0 then
        local zones = getStorage().getZones()
        local z = zones[zoneId]
        if z and z.enabled ~= false then
            zone = z
        end
    end
    if not zone and tonumber(x) and tonumber(y) then
        zone = findZoneAtCoords(x, y)
    end

    local t = now()

    if not zone then
        local w = buildZoneWeather(nil)
        local weather = w.weather
        local flood = lib.require('modules.server.flood_event')
        return {
            ok = true,
            inZone = false,
            zoneId = nil,
            zoneLabel = nil,
            serverCurrent = weather,
            serverNext = weather,
            timeUntilAdvance = nil,
            intervalMinutes = 15,
            forecast = {},
            wetEtaSeconds = isWetHudWeather(weather) and 0 or nil,
            floodEventActive = flood.isActive(),
            floodPhase = flood.getPhase(),
        }
    end

    local state = zoneState(zone.id) or {}
    local sequences = getStorage().getSequences()
    local seq = zone.sequence and sequences[zone.sequence] or nil
    local intervalMinutes = (seq and seq.intervalMinutes) or 15

    local forecast = buildForecastForZone(zone)
    local simpleForecast = {}
    for i = 1, #forecast do
        local p = forecast[i]
        simpleForecast[#simpleForecast + 1] = {
            period = p.period,
            label = p.label,
            weather = p.weather,
            startsInSeconds = math.max(0, (p.startTime or t) - t),
            endsInSeconds = math.max(0, (p.endTime or t) - t),
        }
    end

    local cur = normalizeWeather(state.currentWeather or (zone.weatherPool and zone.weatherPool[1]))
    local nxt = normalizeWeather(state.nextWeather or cur)
    local wetEta = nil
    if isWetHudWeather(cur) then
        wetEta = 0
    elseif isWetHudWeather(nxt) and state.timeUntilAdvance ~= nil then
        wetEta = tonumber(state.timeUntilAdvance)
    else
        for j = 1, #simpleForecast do
            if isWetHudWeather(simpleForecast[j].weather) then
                wetEta = simpleForecast[j].startsInSeconds
                break
            end
        end
    end

    local flood = lib.require('modules.server.flood_event')
    return {
        ok = true,
        inZone = true,
        zoneId = zone.id,
        zoneLabel = zone.label,
        serverCurrent = cur,
        serverNext = nxt,
        timeUntilAdvance = state.timeUntilAdvance,
        intervalMinutes = intervalMinutes,
        forecast = simpleForecast,
        wetEtaSeconds = wetEta,
        floodEventActive = flood.isActive(),
        floodPhase = flood.getPhase(),
    }
end

function weatherData.notifyStateUpdated(zoneId, state)
    local zone = zoneId and getStorage().getZones()[zoneId] or nil
    local payload = {
        zoneId = zoneId,
        state = state,
        weather = zone and buildZoneWeather(zone) or nil,
        updatedAt = now(),
    }
    TriggerClientEvent('weather:client:stateUpdated', -1, payload)
    TriggerEvent('weather:server:stateUpdated', payload)
end

return weatherData
