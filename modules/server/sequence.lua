local sequenceModule = {}
local sequenceActive = false

local function tableLength(t)
    local count = 0
    for _ in pairs(t or {}) do
        count = count + 1
    end
    return count
end

local function getHour(time)
    return math.floor((time % 86400) / 3600)
end

local function pickWeather(sequence, hour, weatherPool)
    weatherPool = weatherPool or {}
    if #weatherPool == 0 then
        return 'CLEAR'
    end

    if not sequence or not sequence.timeline then
        return weatherPool[1] or 'CLEAR'
    end

    local timeline = sequence.timeline
    local bestSlot = nil

    for _, slot in ipairs(timeline) do
        if slot.hour <= hour then
            if not bestSlot or slot.hour > bestSlot.hour then
                bestSlot = slot
            end
        end
    end

    if not bestSlot then
        bestSlot = timeline[#timeline]
    end

    if math.random() < bestSlot.chance then
        local poolWeather = bestSlot.weather
        for _, w in ipairs(weatherPool) do
            if w == poolWeather then
                return poolWeather
            end
        end
        return weatherPool[math.random(#weatherPool)]
    end

    return weatherPool[math.random(#weatherPool)]
end

local function tickSequence()
    local storage = lib.require('modules.server.storage')
    local zones = storage.getZones()
    local sequences = storage.getSequences()
    local states = storage.getZoneStates()

    if not zones or tableLength(zones) == 0 then return end

    local currentTime = os.time()
    local hour = getHour(currentTime)
    local changedZones = {}

    for id, zone in pairs(zones) do
        if zone.enabled ~= false then
            local state = states[id]
            if state then
                state.timeUntilAdvance = (state.timeUntilAdvance or 60) - (Config.sequenceInterval / 1000)

                if state.timeUntilAdvance <= 0 then
                    local seq = sequences[zone.sequence]
                    local sequence = seq
                    local newWeather = pickWeather(sequence, hour, zone.weatherPool)

                    if newWeather ~= state.currentWeather then
                        state.currentWeather = newWeather
                        state.nextWeather = newWeather
                        state.lastUpdated = currentTime
                        changedZones[id] = {
                            currentWeather = newWeather,
                            nextWeather = newWeather,
                            windSpeed = state.windSpeed,
                            windDirection = state.windDirection,
                            severity = state.severity,
                            lastUpdated = currentTime,
                        }
                    end

                    local intervalMinutes = seq and seq.intervalMinutes or 15
                    state.timeUntilAdvance = intervalMinutes * 60
                end

                storage.updateZoneState(id, state)
            end
        end
    end

    if tableLength(changedZones) > 0 then
        for id, state in pairs(changedZones) do
            TriggerClientEvent('dynamic_weather:zoneUpdate', -1, id, state)
            local weatherData = lib.require('modules.server.weather_data')
            weatherData.notifyStateUpdated(id, state)
        end

        if Config.debugLog then
            print(('^3[weather] Sequence advanced %d zones (hour %.0f)^0'):format(
                tableLength(changedZones), hour))
        end
    end
end

function sequenceModule.start()
    if sequenceActive then return end

    local interval = Config.sequenceInterval or 60000
    sequenceActive = true
    CreateThread(function()
        while sequenceActive do
            Wait(interval)
            if sequenceActive then
                tickSequence()
            end
        end
    end)

    if Config.debugLog then
        print(('^2[weather] Sequence engine started (interval: %dms)^0'):format(interval))
    end
end

function sequenceModule.stop()
    sequenceActive = false
end

function sequenceModule.forceAdvance(zoneId)
    local storage = lib.require('modules.server.storage')
    local zones = storage.getZones()
    local sequences = storage.getSequences()
    local states = storage.getZoneStates()

    local zone = zones[zoneId]
    if not zone then return false end

    local hour = getHour(os.time())
    local seq = sequences[zone.sequence]
    local newWeather = pickWeather(seq, hour, zone.weatherPool)
    local state = states[zoneId] or {}

    state.currentWeather = newWeather
    state.nextWeather = newWeather
    state.lastUpdated = os.time()
    state.timeUntilAdvance = (seq and seq.intervalMinutes or 15) * 60

    storage.updateZoneState(zoneId, state)
    TriggerClientEvent('dynamic_weather:zoneUpdate', -1, zoneId, state)
    local weatherData = lib.require('modules.server.weather_data')
    weatherData.notifyStateUpdated(zoneId, state)

    return true, newWeather
end

return sequenceModule
