Config = {}

-- Engine
Config.tickRate = 500
Config.defaultTransitionDuration = 15
Config.globalFallbackWeather = 'CLEAR'

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

-- Sync safety heartbeat. Joins, saves, reloads, and weather changes sync immediately.
Config.syncBroadcastInterval = 60000
Config.syncOnJoinImmediate = true

-- Editor
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
    ['weather.hurricane'] = 'es_admin.world.weather.hurricane',
}

-- Debug
Config.debugLog = false

Config.FloodRecessionDefaultDuration = 120
Config.FloodRecessionMinDuration = 10
Config.FloodRecessionMaxDuration = 900
Config.FloodRecessionUpdateInterval = 1000

-- Protected vanilla water bodies are loaded from shared/data/protected_water.json.
-- Flood applies skip matching water quads and restores sampled water heights after each pass.
Config.ProtectedWater = {
    enabled = true,
    defaultPadding = 150.0,
    defaultRestoreRadius = 250.0,
    maxProtectedQuadSkipArea = 6000000.0,
    autoRestoreHeight = true,
    autoRestoreGrid = false,
    maxAutoRestorePointsPerZone = 8,
    autoRestorePointSpacingScale = 1.25,
    restoreAfterApply = true,
    clampModifyWaterRadius = true,
    zeroRestoreHeightMeansAuto = true,
    modifyWaterOrder = 'height_radius',
    debugModifyWater = false,
    debugRestoreSampling = false,
    debugDrawZ = 40.0,
    debugColor = { r = 0, g = 180, b = 255, a = 220 },
}

-- Random scripted flood: sequence ticks can spawn a natural flood during thunder, then force thunder in all zones and raise sea level.
Config.FloodEvent = {
    enabled = true,
    chance = 0.08,
    chanceMin = 0.08,
    chanceMax = 0.08,
    maxOffset = 2.0,
    recommendedMaxOffset = 2.0,
    requireThunder = true,
    thunderWeather = 'THUNDER',
    thunderCondition = 'any_zone',
    stormLeadSeconds = 45,
    autoDispatch = true,
    dispatchType = 'WEATHER_FLOOD',
    dispatchTitle = 'Coastal flooding emergency',
    dispatchMessage = 'Severe coastal flooding in progress. Avoid low-lying areas and storm surge zones.',
    dispatchSeverity = 5,
    dispatchCoords = nil,
    serverEventOnStart = nil,
    serverEventOnEnd = nil,
}

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
    flashFloodWaterFile = 'flood_calm.xml',
    hurricaneFloodWaterFile = 'flood.xml',
    defaultFloodWaterProfile = 'flash',
    floodWaveQuadIds = { 0 },
    flashFloodWaveAmplitude = 0.0,
    hurricaneFloodWaveAmplitude = 1.0,
    floodTickMs = 2000,
    floodIncreaseRate = 0.02,
    floodIgnoreApplyThreshold = 0.02,
    floodIgnoreMaxApplyIntervalMs = 10000,
    floodIgnoreSmoothingStep = 0.05,
    floodIgnoreMaxQuadArea = 2500000.0,
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

Config.Hurricane = {
    enabled = true,
    defaultIntensity = 4,
    weatherType = 'THUNDER',
    severityByIntensity = {
        [1] = 3,
        [2] = 4,
        [3] = 4,
        [4] = 5,
        [5] = 5,
    },
    windSpeedByIntensity = {
        [1] = 12.0,
        [2] = 18.0,
        [3] = 25.0,
        [4] = 32.0,
        [5] = 40.0,
    },
    floodTargetByIntensity = {
        [1] = 0.5,
        [2] = 1.0,
        [3] = 1.5,
        [4] = 2.0,
        [5] = 2.5,
    },
    lightningMultiplierByIntensity = {
        [1] = 1.0,
        [2] = 1.4,
        [3] = 1.8,
        [4] = 2.4,
        [5] = 3.0,
    },
    floodLeadSeconds = 20,
    endFloodOnStop = true,
    floodRecessionSeconds = 120,
}

-- Hurricane debris: client-local flying litter/objects during /hurricane.
Config.HurricaneDebris = {
    -- Master switch for hurricane debris spawning.
    enabled = true,
    -- Keep debris local to each client; false makes CreateObject networked.
    localOnly = true,
    -- Explicit networked create override; leave false for client-only debris.
    createNetworked = false,
    -- CreateObject script host flag; usually false for local visual debris.
    createScriptHostObject = false,
    -- CreateObject door flag; keep false because debris props are not doors.
    createDoorFlag = false,
    -- Lowest hurricane intensity accepted by debris logic.
    minIntensity = 1,
    -- Highest hurricane intensity accepted by debris logic.
    maxIntensity = 5,

    -- Max live debris by hurricane intensity.
    maxDebrisByIntensity = {
        [1] = 8, -- Category 1 live object cap.
        [2] = 12, -- Category 2 live object cap.
        [3] = 16, -- Category 3 live object cap.
        [4] = 21, -- Category 4 live object cap.
        [5] = 26, -- Category 5 live object cap.
    },

    -- Spawn delay by hurricane intensity; lower means more debris.
    spawnIntervalByIntensityMs = {
        [1] = 450, -- Category 1 spawn delay.
        [2] = 350, -- Category 2 spawn delay.
        [3] = 250, -- Category 3 spawn delay.
        [4] = 212, -- Category 4 spawn delay.
        [5] = 175, -- Category 5 spawn delay.
    },

    -- Lifetime before debris auto-deletes.
    lifetimeMinMs = 5000,
    -- Longest lifetime before debris auto-deletes.
    lifetimeMaxMs = 12500,
    -- Spawn debris behind player heading so it crosses player line of sight.
    spawnBehindPlayer = true,
    -- Backward-compatible off switch for older camera fly-by config.
    spawnBehindCamera = true,
    -- Closest player-behind spawn distance.
    playerSpawnBackMinDistance = 6.0,
    -- Farthest player-behind spawn distance.
    playerSpawnBackMaxDistance = 12.0,
    -- Random left/right spread behind player.
    playerSpawnSideJitter = 10.0,
    -- Lowest player-spawn height above player.
    playerSpawnHeightMin = 2.0,
    -- Highest player-spawn height above player.
    playerSpawnHeightMax = 8.0,
    -- Shortest target distance ahead of player where debris should land.
    flyPastDistanceMin = 32.0,
    -- Longest target distance ahead of player where debris should land.
    flyPastDistanceMax = 52.0,
    -- Random target left/right spread beyond player.
    flyPastTargetSideJitter = 5.0,
    -- Lowest target height above ground ahead of player.
    flyPastTargetLiftMin = 0.15,
    -- Highest target height above ground ahead of player.
    flyPastTargetLiftMax = 0.75,
    -- Side force scale for later fly-by gusts; low keeps debris in sight line.
    flyPastGustSideForceScale = 0.12,
    -- Delete after debris lands/passes this far beyond player along fly-by path.
    flyPastDespawnDistance = 34.0,
    -- Minimum lifetime for fly-by debris before timer cleanup.
    flyPastMinLifetimeMs = 4200,
    -- Minimum age before pass-ahead cleanup can delete fly-by debris.
    flyPastDespawnAfterMs = 3000,
    -- Closest spawn distance from player.
    spawnMinDistance = 8.0,
    -- Farthest spawn distance from player.
    spawnMaxDistance = 30.0,
    -- Side spread multiplier from wind line.
    spawnSideOffsetScale = 0.55,
    -- Percent chance to spawn upwind so debris blows toward player.
    upwindSpawnChance = 72,
    -- Height above player used for ground probe.
    groundProbeHeight = 60.0,
    -- Lowest random lift above ground before placement.
    spawnGroundOffsetMin = 0.2,
    -- Highest random lift above ground before placement.
    spawnGroundOffsetMax = 1.2,
    -- Move object onto ground after spawn; prevents below-map starts.
    placeOnGroundOnSpawn = true,
    -- Optional wait after ground placement before velocity.
    groundSettleWaitMs = 500,
    -- Delete debris beyond this player distance.
    deleteDistance = 120.0,
    -- Delete debris if it drops below this world Z.
    deleteBelowZ = -50.0,
    -- Delete debris when it enters water.
    deleteWhenInWater = true,

    -- Gust processing loop interval while hurricane active.
    physicsTickMs = 200,
    -- Ambient wind native refresh interval.
    windApplyTickMs = 1000,
    -- Lightning roll interval while hurricane active.
    lightningTickMs = 3500,
    -- Base lightning chance per lightning tick.
    lightningChancePerTick = 10,
    -- Max lightning chance after hurricane multiplier.
    lightningChanceMax = 90,
    -- Server hurricane state request delay after client start.
    stateRequestDelayMs = 1000,
    -- Idle wait for wind loop when hurricane inactive.
    inactiveWindWaitMs = 1500,
    -- Idle wait for spawn loop when hurricane inactive.
    inactiveSpawnWaitMs = 1500,
    -- Idle wait for physics loop when hurricane inactive.
    inactivePhysicsWaitMs = 1000,
    -- Idle wait for lightning loop when hurricane inactive.
    inactiveLightningWaitMs = 2000,
    -- Cleanup loop interval.
    cleanupTickMs = 1000,
    -- Debug draw idle wait when overlay disabled.
    debugIdleWaitMs = 500,

    -- Initial horizontal speed after spawn.
    initialVelocityMin = 30.0,
    -- Max initial horizontal speed after spawn.
    initialVelocityMax = 54.0,
    -- Side drift as percent of initial speed.
    initialSideVelocityScale = 0.35,
    -- Random angle variation in degrees for debris direction (adds chaos).
    directionVariationDegrees = 35.0,
    -- Minimum gust force applied later.
    gustForceMin = 3.0,
    -- Maximum gust force applied later.
    gustForceMax = 8.0,
    -- Base gust chance per physics tick.
    gustChance = 75,
    -- Extra gust chance per intensity above 1.
    gustChancePerIntensity = 5,
    -- Max gust chance after intensity bonus.
    gustChanceMax = 95,
    -- Minimum time after gust skip/apply.
    gustCooldownMinMs = 350,
    -- Maximum time after gust skip/apply.
    gustCooldownMaxMs = 1100,
    -- First gust earliest delay after spawn.
    firstGustMinMs = 250,
    -- First gust latest delay after spawn.
    firstGustMaxMs = 900,
    -- Side force as percent of gust force.
    gustSideForceScale = 0.35,
    -- ApplyForceToEntity force type.
    applyForceType = 1,
    -- ApplyForceToEntity bone index.
    applyForceBoneIndex = 0,
    -- Apply force relative to entity axes.
    applyForceRelative = false,
    -- Apply force as high-force impulse.
    applyForceHighForce = true,
    -- Scale force by entity mass.
    applyForceScaleByMass = true,
    -- Play force audio impact.
    applyForcePlayAudio = false,
    -- Scale force by time warp.
    applyForceScaleByTimeWarp = true,
    -- Chance each velocity/gust gets upward lift.
    verticalLiftChance = 0.65,
    -- Minimum upward lift.
    verticalLiftMin = 2.0,
    -- Maximum upward lift.
    verticalLiftMax = 7.0,
    -- Chance fly-by spawn velocity gets extra upward lift.
    flyPastVerticalLiftChance = 0.25,
    -- Minimum fly-by spawn lift.
    flyPastVerticalLiftMin = 0.0,
    -- Maximum fly-by spawn lift.
    flyPastVerticalLiftMax = 1.0,
    -- Minimum fly-by gust lift.
    flyPastGustLiftMin = 0.0,
    -- Maximum fly-by gust lift.
    flyPastGustLiftMax = 0.7,
    -- Minimum angular spin.
    angularVelocityMin = 1.5,
    -- Maximum angular spin.
    angularVelocityMax = 8.0,

    -- Enable collision. Keep true so debris cannot fall through ground.
    enableCollision = true,
    -- Legacy override. If true, disables collision even when enableCollision is true.
    disableCollision = false,
    -- Keep physics active when changing collision state.
    keepPhysicsOnCollisionChange = true,
    -- Mark debris as mission entity for reliable cleanup.
    setMissionEntity = true,
    -- Grab mission ownership for cleanup.
    grabMissionEntity = true,
    -- Make entity dynamic for physics.
    setDynamic = true,
    -- Let debris fall/roll naturally.
    enableGravity = true,
    -- Freeze debris after spawn; usually false.
    freezeOnSpawn = false,
    -- Block debris inside interiors.
    noSpawnInInterior = true,
    -- Block debris if player or spawn point is underwater.
    noSpawnUnderwater = true,
    -- Block debris while player is in a vehicle.
    noSpawnInVehicle = false,
    -- Skip new spawns below this FPS; 0 disables.
    skipWhenFpsBelow = 45,
    -- Max wait for model load.
    modelLoadTimeoutMs = 1500,
    -- Require model to pass IsModelAnObject when native exists.
    requireObjectModel = true,
    -- Height above spawn point to check water.
    waterProbeHeight = 1.5,
    -- Water must be this close to spawn Z to block spawn.
    waterSpawnBuffer = 0.2,

    -- Fallback category weights if an intensity row is missing.
    defaultCategoryWeights = { common = 95, uncommon = 4, rare = 1 },
    -- Category weights by intensity; higher rare = heavier/larger props more often.
    categoryWeightsByIntensity = {
        [1] = { common = 99, uncommon = 1, rare = 0 }, -- Category 1 mix.
        [2] = { common = 98, uncommon = 2, rare = 0 }, -- Category 2 mix.
        [3] = { common = 97, uncommon = 2, rare = 1 }, -- Category 3 mix.
        [4] = { common = 96, uncommon = 3, rare = 1 }, -- Category 4 mix.
        [5] = { common = 95, uncommon = 4, rare = 1 }, -- Category 5 mix.
    },

    -- Debug overlay text styling.
    debugTextFont = 0,
    -- Debug overlay text size.
    debugTextScale = 0.28,
    -- Debug overlay text color.
    debugTextColor = { r = 230, g = 240, b = 255, a = 220 },
    -- Debug overlay left position.
    debugTextX = 0.015,
    -- Debug overlay top position.
    debugTextY = 0.68,
    -- Debug overlay row spacing.
    debugLineHeight = 0.022,

    -- Model categories used by weighted picker and disabled filtering.
    categories = {
        common = { -- Light debris picked most often.
            "ng_proc_sodacup_03a",
            "ng_proc_cigpak01c",
            "ng_proc_sodacup_02b001",
            "ng_proc_sodacup_02c",
            "ng_proc_food_chips01b",
            "v_res_tt_cancrsh01",
            "ng_proc_coffee_02a",
            "ng_proc_food_burg02a",
            "ng_proc_ciglight01a",
            "ng_proc_sodacup_03c",
            "ng_proc_food_chips01a",
            "ng_proc_paper_news_meteor",
            "ng_proc_paper_03a",
            "ng_proc_sodacan_02d",
            "ng_proc_paper_02a",
            "ng_proc_spraycan01a",
            "ng_proc_leaves03",
            "ng_proc_food_aple1a",
            "ng_proc_sodacan_02a",
            "ng_proc_sodacan_02b",
            "ng_proc_sodacan_02c",
            "ng_proc_leaves05",
            "ng_proc_paper_burger01a",
            "ng_proc_coffee_03b",
            "ng_proc_food_aple2a",
            "ng_proc_paper_news_rag",
            "ng_proc_leaves08",
            "ng_proc_litter_plasbot2",
            "ng_proc_litter_plasbot3",
        },
        uncommon = { -- Medium debris picked sometimes.
            "prop_ld_can_01",
            "prop_orang_can_01",
            "prop_ld_flow_bottle",
            "prop_ld_snack_01",
        },
        rare = { -- Larger debris picked mostly in high intensity.
            "prop_ld_scrap",
            "prop_ld_hat_01",
            "prop_ld_tshirt_01",
            "prop_ld_shoe_01",
        },
        disabled = { -- Valid names here never spawn.
            "prop_palm_fan_02_a",
            "prop_palm_fan_02_b",
            "prop_palm_fan_03_a",
            "prop_palm_fan_03_b",
            "prop_palm_fan_04_a",
            "prop_palm_fan_04_b",
        },
    },

    -- Master allowlist. Add/remove props here to control what can spawn.
    props = {
        -- Common
        "ng_proc_sodacup_03a",
        "ng_proc_cigpak01c",
        "ng_proc_sodacup_02b001",
        "ng_proc_sodacup_02c",
        "ng_proc_food_chips01b",
        "v_res_tt_cancrsh01",
        "ng_proc_coffee_02a",
        "ng_proc_food_burg02a",
        "ng_proc_ciglight01a",
        "ng_proc_sodacup_03c",
        "ng_proc_food_chips01a",
        "ng_proc_paper_news_meteor",
        "ng_proc_paper_03a",
        "ng_proc_sodacan_02d",
        "ng_proc_paper_02a",
        "ng_proc_spraycan01a",
        "ng_proc_leaves03",
        "ng_proc_food_aple1a",
        "ng_proc_sodacan_02a",
        "ng_proc_sodacan_02b",
        "ng_proc_sodacan_02c",
        "ng_proc_leaves05",
        "ng_proc_paper_burger01a",
        "ng_proc_coffee_03b",
        "ng_proc_food_aple2a",
        "ng_proc_paper_news_rag",
        "ng_proc_leaves08",
        "ng_proc_litter_plasbot2",
        "ng_proc_litter_plasbot3",
        -- Uncommon
        "prop_ld_can_01",
        "prop_orang_can_01",
        "prop_ld_flow_bottle",
        "prop_ld_snack_01",
        -- Rare
        "prop_ld_scrap",
        "prop_ld_hat_01",
        "prop_ld_tshirt_01",
        "prop_ld_shoe_01",
    },
}

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
    powerPoleModelHashes = {
        [`prop_telegraph_01a`] = true,
        [`prop_telegraph_01b`] = true,
        [`prop_telegraph_01c`] = true,
        [`prop_telegraph_01d`] = true,
        [`prop_telegraph_01e`] = true,
        [`prop_telegraph_01f`] = true,
        [`prop_telegraph_01g`] = true,
        [`prop_telegraph_02a`] = true,
        [`prop_telegraph_02b`] = true,
        [`prop_telegraph_03`] = true,
        [`prop_telegraph_04a`] = true,
        [`prop_telegraph_04b`] = true,
        [`prop_telegraph_05a`] = true,
        [`prop_telegraph_05b`] = true,
        [`prop_telegraph_05c`] = true,
        [`prop_telegraph_06a`] = true,
        [`prop_telegraph_06b`] = true,
        [`prop_telegraph_06c`] = true,
        [`prop_utilitypole_01`] = true,
        [`prop_utilitypole_02`] = true,
        [`prop_utilitypole_03`] = true,
    },
    powerPoleModels = {
        'prop_telegraph_01a',
        'prop_telegraph_01b',
        'prop_telegraph_01c',
        'prop_telegraph_01d',
        'prop_telegraph_01e',
        'prop_telegraph_01f',
        'prop_telegraph_01g',
        'prop_telegraph_02a',
        'prop_telegraph_02b',
        'prop_telegraph_03',
        'prop_telegraph_04a',
        'prop_telegraph_04b',
        'prop_telegraph_05a',
        'prop_telegraph_05b',
        'prop_telegraph_05c',
        'prop_telegraph_06a',
        'prop_telegraph_06b',
        'prop_telegraph_06c',
        'prop_utilitypole_01',
        'prop_utilitypole_02',
        'prop_utilitypole_03',
    },
    defaultStrikeOffset = vector3(0.0, 0.0, 11.0),
    strikeTopZOffset = 0.8,
    fallbackPoleModel = `prop_telegraph_01a`,
    fallbackPowerPoleCoords = {},
    modelStrikeOffsets = {
        [`prop_utilitypole_01`] = vector3(0.0, 0.0, 11.5),
        [`prop_utilitypole_02`] = vector3(0.0, 0.0, 12.5),
        [`prop_utilitypole_03`] = vector3(0.0, 0.0, 13.0),
    },
}
