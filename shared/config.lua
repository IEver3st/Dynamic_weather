Config = {}

-- Engine
Config.tickRate = 500
Config.defaultTransitionDuration = 15
Config.globalFallbackWeather = 'CLEAR'
Config.excludedWeatherTypes = {}

-- GlobalState keys: dynamic_weather_season, dynamic_weather_blackout (replicated)
Config.defaultSeason = 'summer'
Config.validSeasons = {
    spring = true,
    summer = true,
    autumn = true,
    fall = true, -- alias of autumn
    winter = true,
}

-- Sequence Engine
Config.sequenceInterval = 60000
Config.sequenceRandomWeight = 0.3

-- Sync safety heartbeat. Joins, saves, reloads, and weather changes sync immediately.
Config.syncBroadcastInterval = 60000
Config.syncOnJoinImmediate = true

-- Editor
Config.editorAllowMultipleUsers = false
-- NUI heartbeat: if no ping for `editorStaleAfterPingMs` (after at least one ping), or no first ping within `editorStaleBeforeFirstPingMs`, client force-closes editor.
Config.editorStaleAfterPingMs = 20000
Config.editorStaleBeforeFirstPingMs = 60000

-- ACE permissions aligned with es_admin-style action permissions.
Config.Permissions = {
    all = 'es_admin.all',
    weather = 'es_admin.world',
}

Config.ActionPermissions = {
    ['weather.editor'] = 'es_admin.world.weather.editor',
    ['weather.reload'] = 'es_admin.world.weather.reload',
    ['weather.force'] = 'es_admin.world.weather.force',
    ['weather.debug'] = 'es_admin.world.weather.debug',
    ['weather.sealevel'] = 'es_admin.world.weather.sealevel',
}

-- Debug
Config.debugPolygons = false
Config.debugLog = false

Config.SeaLevel = {
    enabled = true,
    minSeaLevel = -10.0,
    maxSeaLevel = 400.0,
    -- Runtime safety clamp. Extreme mountain-height water exposes GTA water LOD/tile seams.
    maxSafeSeaLevel = 80.0,
    defaultSmoothSeconds = 60,
    adminOnly = true,
    smoothTickMs = 1000,
    floodHeight = 2.0,
    floodMode = 'offset',
    floodTickMs = 2000,
    floodIncreaseRate = 0.02,
    braveFloodHeight = 2.0,
    braveFloodIncreaseRate = 0.02,
}

-- MDT / dispatch data support
Config.WeatherData = {
    defaultSeverity = 1,
    forecastPeriods = {
        { id = 'current', label = 'Current', offsetMinutes = 0, durationMinutes = 30 },
        { id = 'next', label = 'Next', offsetMinutes = 30, durationMinutes = 30 },
        { id = 'later', label = 'Later', offsetMinutes = 60, durationMinutes = 60 },
    },
    alerts = {
        cleanupInterval = 60000,
        defaultDurationMinutes = 30,
    },
    dispatch = {
        enabled = true,
        eventName = 'weather:server:incidentCreated',
        defaultJobs = { 'police', 'sheriff', 'ambulance' },
    },
}

Config.RoadConditions = {
    DRY = 'Normal patrol conditions.',
    WET = 'Use caution during high-speed driving.',
    LOW_VISIBILITY = 'Avoid unnecessary high-speed pursuits.',
    HAZARDOUS = 'Supervisor review recommended for pursuits.',
    EXTREME = 'Avoid area unless assigned to emergency response.',
}

Config.BlacklistedWindProps = {
    prop_tree_cedar_03 = true,
    prop_tree_cedar_04 = true,
    prop_tree_cedar_02 = true,
    prop_rus_olive = true,
    prop_tree_birch_03b = true,
    prop_palm_fan_03_b = true,
    prop_palm_huge_01a = true,
    prop_tree_pine_02 = true,
    prop_w_r_cedar_01 = true,
    prop_palm_fan_02_b = true,
    prop_palm_fan_04_d = true,
    prop_palm_med_01a = true,
    prop_palm_med_01b = true,
    prop_palm_med_01d = true,
    prop_palm_sm_01a = true,
    prop_palm_sm_01f = true,
    prop_tree_lficus_05 = true,
    prop_tree_jacada_02 = true,
    prop_palm_sm_01d = true,
    prop_tree_lficus_06 = true,
    prop_fan_palm_01a = true,
    prop_palm_fan_03_a = true,
    prop_tree_lficus_03 = true,
    prop_palm_sm_01e = true,
    prop_palm_huge_01b = true,
    prop_tree_lficus_02 = true,
}

Config.WindDebris = {
    enabled = true,
    minStormIntensity = 45,

    weatherTypes = {
        RAIN = 45,
        THUNDER = 70,
    },

    scanExistingObjects = true,
    scanInterval = 6500,
    scanRadius = 45.0,
    maxWorldObjectsAddedPerScan = 3,

    spawnClientDebris = true,
    spawnInterval = 4000,
    spawnRadiusMin = 18.0,
    spawnRadiusMax = 42.0,

    deleteRadius = 95.0,
    maxLifetime = 90000,

    maxTrackedWorldObjects = 6,
    maxManagedObjects = 10,
    maxTotalDebris = 7,
    maxLightDebris = 5,
    maxMediumDebris = 2,
    maxHeavyDebris = 1,
    minWorldObjectsBeforeSpawn = 4,
    spawnEvenWithWorldObjects = false,

    gustMinInterval = 3500,
    gustMaxInterval = 8500,
    mediumGustMinInterval = 7500,
    mediumGustMaxInterval = 15000,
    gustTickInterval = 500,
    idleGustTickInterval = 1500,
    minBurstWindowMs = 900,
    maxBurstEvents = 1,
    maxBurstEventsStorm = 1,
    maxHeavyBurstEvents = 1,
    gustBurstDeferMin = 700,
    gustBurstDeferMax = 1600,
    heavyBurstDeferMin = 1800,
    heavyBurstDeferMax = 3500,
    cartBurstDeferMin = 2500,
    cartBurstDeferMax = 6000,
    lightMinEventSpacing = 1800,
    mediumMinEventSpacing = 3500,
    heavyMinEventSpacing = 9000,
    cartMinEventSpacing = 18000,
    maxLightEntitySpeed = 8.0,
    maxMediumEntitySpeed = 5.5,
    maxHeavyEntitySpeed = 3.5,
    maxCartEntitySpeed = 2.0,

    lightForceMin = 1.8,
    lightForceMax = 4.6,
    mediumForceMin = 2.8,
    mediumForceMax = 6.5,
    heavyForceMin = 4.0,
    heavyForceMax = 8.5,

    windDirection = 240.0,
    windDirectionSway = 15,

    enableHeavyPropWind = true,
    heavyPropMinStormIntensity = 90,
    heavyPropMoveChance = 8,
    heavyPropCooldown = 30000,
    maxHeavyRollSpeed = 3.0,
    heavyCheckMinInterval = 9000,
    heavyCheckMaxInterval = 18000,
    debugHeavySearchRadius = 20.0,

    enableShoppingCartWind = true,
    cartMinStormIntensity = 85,
    cartMoveChance = 4,
    cartCooldown = 30000,
    maxCartRollSpeed = 1.25,
    cartGustMinInterval = 14000,
    cartGustMaxInterval = 32000,

    lightModels = {
        `prop_cs_paper_cup`,
        `p_amb_coffeecup_01`,
        `prop_food_bs_coffee`,
        `prop_ld_can_01`,
        `prop_ld_flow_bottle`,
        `prop_paper_bag_01`,
        `prop_paper_bag_small`,
        `prop_rub_litter_01`,
        `prop_rub_litter_02`,
        `prop_rub_litter_03`,
        `prop_rub_litter_04`,
        `prop_newspaper_01`,
        `prop_newspaper_02`,
        `prop_paper_ball`,
    },
    mediumModels = {
        `prop_cs_cardbox_01`,
        `prop_cs_rub_box_01`,
        `prop_paper_box_01`,
        `prop_boxpile_01a`,
        `prop_boxpile_02b`,
        `prop_boxpile_03a`,
        `hei_prop_heist_box`,
        `prop_rub_binbag_01`,
        `prop_rub_binbag_01b`,
        `prop_rub_bag_01`,
        `prop_roadcone01a`,
        `prop_roadcone02a`,
        `prop_bucket_01a`,
    },
    heavyModels = {
        `prop_bin_01a`,
        `prop_bin_02a`,
        `prop_bin_07a`,
        `prop_recyclebin_01a`,
        `prop_recyclebin_02a`,
        `prop_recyclebin_02b`,
    },
    shoppingCartModels = {
        `prop_rub_trolley01a`,
        `prop_rub_trolley02a`,
        `prop_rub_trolley03a`,
    },
    debug = false,
}

-- Backward compatibility: old module name now reads WindDebris first.
Config.StormProps = Config.StormProps or Config.WindDebris

Config.LightningPoleStrike = {
    enabled = true,
    weatherTypes = {
        THUNDER = true,
    },
    minSeverity = 4,
    chance = 6,
    minInterval = 20000,
    maxInterval = 60000,
    cooldown = 180000,
    searchRadius = 160.0,
    syncRadius = 400.0,
    blackoutRadius = 175.0,
    blackoutMin = 3500,
    blackoutMax = 8500,
    flickerBursts = 3,
    restoreFlickerBursts = 2,
    flickerOnMin = 80,
    flickerOnMax = 180,
    flickerOffMin = 80,
    flickerOffMax = 240,
    impactDelayMin = 120,
    impactDelayMax = 350,
    impactExplosionType = 2,
    impactExplosionScale = 0.0,
    cameraShake = 0.35,
    cameraShakeRadius = 140.0,
    fireChance = 5,
    fireDurationMin = 1400,
    fireDurationMax = 3200,
    vehicleAlarmRadius = 45.0,
    poolScanLimit = 220,
    debug = false,
    powerPoleModels = {
        'prop_telegraph_01a',
        'prop_telegraph_01b',
        'prop_telegraph_01c',
        'prop_telegraph_02a',
        'prop_telegraph_02b',
        'prop_utilitypole_01',
        'prop_utilitypole_02',
        'prop_utilitypole_03',
    },
    defaultStrikeOffset = vector3(0.0, 0.0, 11.0),
    modelStrikeOffsets = {
        prop_utilitypole_01 = vector3(0.0, 0.0, 11.5),
        prop_utilitypole_02 = vector3(0.0, 0.0, 12.5),
        prop_utilitypole_03 = vector3(0.0, 0.0, 13.0),
    },
}
