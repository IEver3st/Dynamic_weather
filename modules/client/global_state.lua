local resourceName = GetCurrentResourceName()

local SetArtificialLightsState = SetArtificialLightsState
local SetArtificialLightsStateAffectsVehicles = SetArtificialLightsStateAffectsVehicles

local function applyBlackoutState(on)
    on = on == true
    SetArtificialLightsState(on)
    if SetArtificialLightsStateAffectsVehicles then
        SetArtificialLightsStateAffectsVehicles(not on)
    end
end

local function syncBlackoutFromGlobal()
    local v = GlobalState.dynamic_weather_blackout
    applyBlackoutState(v == true)
end

RegisterNetEvent('dynamic_weather:clientForceWeather', function(weatherType)
    if type(weatherType) ~= 'string' then return end
    local engine = lib.require('modules.client.engine')
    if engine and engine.forceWeatherFast then
        engine.forceWeatherFast(weatherType)
    end
end)

RegisterNetEvent('dynamic_weather:clientClearForceWeather', function()
    local engine = lib.require('modules.client.engine')
    if engine and engine.clearForceWeatherFast then
        engine.clearForceWeatherFast()
    end
end)

RegisterNetEvent('dynamic_weather:applyBlackout', function(enabled)
    applyBlackoutState(enabled == true)
end)

AddEventHandler('onClientResourceStart', function(name)
    if name ~= resourceName then return end
    syncBlackoutFromGlobal()
end)

AddStateBagChangeHandler('dynamic_weather_blackout', nil, function(bagName, key, value)
    if bagName ~= 'global' or key ~= 'dynamic_weather_blackout' then return end
    applyBlackoutState(value == true)
end)
