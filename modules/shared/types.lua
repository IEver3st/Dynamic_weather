local ALL_WEATHER_TYPES = {
    'CLEAR',
    'EXTRASUNNY',
    'CLOUDS',
    'OVERCAST',
    'RAIN',
    'THUNDER',
    'CLEARING',
    'NEUTRAL',
    'SMOG',
    'FOGGY',
    'XMAS',
    'SNOWLIGHT',
    'SNOW',
    'BLIZZARD',
    'HALLOWEEN',
}

local WEATHER_COLORS = {
    CLEAR       = '#f59e0b',
    EXTRASUNNY  = '#fbbf24',
    CLOUDS      = '#94a3b8',
    OVERCAST    = '#64748b',
    RAIN        = '#3b82f6',
    THUNDER     = '#8b5cf6',
    CLEARING    = '#34d399',
    NEUTRAL     = '#9ca3af',
    SMOG        = '#a8a29e',
    FOGGY       = '#d6d3d1',
    XMAS        = '#ef4444',
    SNOWLIGHT   = '#e0f2fe',
    SNOW        = '#ffffff',
    BLIZZARD    = '#bae6fd',
    HALLOWEEN   = '#f97316',
}

local WEATHER_TRANSITION_DEFAULTS = {
    fromAnyToRain       = 10.0,
    fromAnyToThunder    = 8.0,
    fromRainToClear     = 15.0,
    fromThunderToClear  = 20.0,
    defaultTransition   = 10.0,
}
