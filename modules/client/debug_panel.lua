local PANEL_ID = 'dynamic_weather_debug'
local UPDATE_MS = 500

local active = false

local function dbgExportsOk()
    return type(exports.es_lib) == 'table'
        and type(exports.es_lib.showDebugPanel) == 'function'
end

local function dbgShow(payload)
    exports.es_lib:showDebugPanel(payload)
end

local function dbgUpdate(payload)
    exports.es_lib:updateDebugPanel(payload)
end

local function dbgHide()
    exports.es_lib:hideDebugPanel()
end

local function dbgIsOpen()
    return exports.es_lib:isDebugPanelOpen()
end

local function formatDuration(seconds)
    if not seconds or seconds < 0 then
        return '—'
    end
    local s = math.floor(seconds + 0.5)
    local m = math.floor(s / 60)
    local r = s % 60
    if m > 0 then
        return ('%dm %02ds'):format(m, r)
    end
    return ('%ds'):format(r)
end

local function stopPanel()
    active = false
    if dbgExportsOk() and dbgIsOpen() then
        dbgHide()
    end
end

local function buildLines(zone, engineState, snap, edgeDist, edgeId, edgeLabel)
    local lines = {}

    if zone then
        lines[#lines + 1] = { label = 'Zone', value = zone.label or zone.id }
        lines[#lines + 1] = { label = 'Zone ID', value = zone.id }
    else
        lines[#lines + 1] = { label = 'Zone', value = '(none — global fallback)' }
    end

    lines[#lines + 1] = {
        label = 'Display weather',
        value = engineState.weather or '—',
    }
    lines[#lines + 1] = {
        label = 'Transition target',
        value = engineState.target or '—',
    }

    if zone and snap and snap.denied then
        lines[#lines + 1] = {
            label = 'Server sequence',
            value = 'No permission (weather.debug / world)',
        }
    elseif zone and snap and snap.ok then
        lines[#lines + 1] = {
            label = 'Server current',
            value = snap.currentWeather or '—',
        }
        lines[#lines + 1] = {
            label = 'Server next',
            value = snap.nextWeather or '—',
        }
        lines[#lines + 1] = {
            label = 'Sequence advance in',
            value = formatDuration(snap.timeUntilAdvance),
        }
        lines[#lines + 1] = {
            label = 'Roll interval',
            value = ('%d min'):format(snap.intervalMinutes or 15),
        }
    elseif zone then
        lines[#lines + 1] = {
            label = 'Server sequence',
            value = 'No data (sync?)',
        }
    else
        lines[#lines + 1] = {
            label = 'Nearest zone edge',
            value = edgeDist and ('%.1f m'):format(edgeDist) or '—',
        }
        if edgeId then
            lines[#lines + 1] = {
                label = 'Nearest zone',
                value = ('%s (%s)'):format(edgeLabel or edgeId, edgeId),
            }
        end
    end

    return lines
end

local function tickPanel()
    local engine = lib.require('modules.client.engine')
    if not engine then return end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local x, y = coords.x, coords.y

    local zone = engine.findPlayerZone(x, y)
    local engineState = engine.getState() or {}

    local snap = nil
    if zone and lib.callback and lib.callback.await then
        snap = lib.callback.await('dynamic_weather:getZoneSequenceDebug', false, zone.id)
    end

    local edgeDist, edgeId, edgeLabel = engine.nearestZoneEdgeDistance(x, y)

    local lines = buildLines(zone, engineState, snap, edgeDist, edgeId, edgeLabel)

    local payload = {
        id = PANEL_ID,
        title = 'Dynamic Weather',
        subtitle = zone and 'Inside zone' or 'Outside zones',
        position = 'top-right',
        accentColor = '#38bdf8',
        lines = lines,
    }

    if dbgExportsOk() and dbgIsOpen() then
        dbgUpdate(payload)
    else
        dbgShow(payload)
    end
end

RegisterCommand('weatherdebug', function()
    if not dbgExportsOk() then
        print('^1[weather] es_lib debug panel exports missing (start es_lib)^0')
        return
    end

    if active then
        stopPanel()
        return
    end

    active = true
    tickPanel()
    CreateThread(function()
        while active do
            Wait(UPDATE_MS)
            if active then
                tickPanel()
            end
        end
    end)
end, false)
