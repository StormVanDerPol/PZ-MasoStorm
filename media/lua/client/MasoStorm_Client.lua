local MasoStorm = MasoStorm
local print = print
local ZombRand = ZombRand

local ClientUtils = {
    request = function()
        if isClient() then
            ModData.request(MasoStorm.ModDataNS)
        end
    end,
    get = function()
        return ModData.get(MasoStorm.ModDataNS)
    end
}

-- I pray I dont need to use u much
local StormState = {
    reset = function(self)
        self.init = false
        self.preStormClimateColorInfo = nil
        self.redSkyClimateColorInfo = nil
    end,
    preStormClimateColorInfo = nil,
    redSkyClimateColorInfo = nil,
    init = false
}

local function getDefenses(player, holeIndex)
    local biteDefense = luautils.round(player:getBodyPartClothingDefense(holeIndex, true, false))
    local scratchDefense = luautils.round(player:getBodyPartClothingDefense(holeIndex, false, false))
    local skinDefense = 20

    if player:HasTrait("ThickSkinned") then
        skinDefense = 50
    end
    if player:HasTrait("ThinSkinned") then
        skinDefense = 0
    end

    biteDefense = math.floor(biteDefense)
    scratchDefense = math.floor(scratchDefense)
    return biteDefense, scratchDefense, skinDefense
end

local StormUtils = {
    getIsStormActive = function()
        local state = ClientUtils.get()
        local currentHour = getGameTime():getWorldAgeHours()

        local isStormActive = ((currentHour > state.hour) and (currentHour < state.hour + MasoStorm.Settings.duration))

        print("IS STORM ACTIVE: ", isStormActive, " | ", state.hour, " | ", currentHour)

        return isStormActive
    end,
    getStormProgress = function()
        local state = ClientUtils.get()
        local currentHour = getGameTime():getWorldAgeHours()

        local normalizedCurrentHour = currentHour - state.hour

        return MasoStorm.Utils.clamp(normalizedCurrentHour / MasoStorm.Settings.duration, 0, 1)
    end,
    playRandomThunder = function(isSevere, chance)
        if (ZombRand(0, 100) > chance) then
            return
        end

        local thunderSound = "rumbleThunder" .. tostring(ZombRand(2, 4))

        if isSevere then
            thunderSound = "thunder" .. tostring(ZombRand(1, 3))
        end

        getSoundManager():PlaySound(thunderSound, false, 0)
    end,
    initFakeSnowStorm = function()
        local climateManager = getClimateManager()

        -- forced snow
        local isSnow = climateManager:getClimateBool(ClimateManager.BOOL_IS_SNOW)
        isSnow:setEnableModded(true)
        isSnow:setModdedValue(true)

        climateManager:stopWeatherAndThunder()
        climateManager:triggerCustomWeatherStage(WeatherPeriod.STAGE_STORM, MasoStorm.Settings.duration - 2)

        -- TODO: remove fog from weather. Only adminValue seems to be a true override.
        -- Maybe we can make a new WeatherStage somehow?
        -- local fogIntensity = climateManager:getClimateFloat(ClimateManager.FLOAT_FOG_INTENSITY)
        -- fogIntensity:setEnableModded(true)
        -- fogIntensity:setModdedValue(0)
        -- fogIntensity:setModdedInterpolate(1)

        local globalLight = climateManager:getClimateColor(ClimateManager.COLOR_GLOBAL_LIGHT)
        -- We're going to interpolate from and back to this value.
        -- IDK how to get the value of whatever its GOING to be in the future.
        -- The moment you use modded climate, whatever the weather system is doing is lost
        -- This means that if the actual ClimateColorInfo is very different from what we stored things are going to be awkward
        -- A fix for this would be appreciated.
        StormState.preStormClimateColorInfo = ClimateColorInfo:new()
        StormState.preStormClimateColorInfo:setTo(globalLight:getInternalValue())
        -- Actual red sky CCI
        StormState.redSkyClimateColorInfo = ClimateColorInfo:new()
        StormState.redSkyClimateColorInfo:setExterior(1, 0, 0, 1)
        StormState.redSkyClimateColorInfo:setInterior(0.8, 0.1, 0.1, 0.7)
        -- The one we'll render
        globalLight:getModdedValue():setTo(globalLight:getInternalValue())
        globalLight:setModdedInterpolate(1)
        globalLight:setEnableModded(true)
    end,
    updateFakeSnowStorm = function(factor)
        local globalLight = getClimateManager():getClimateColor(ClimateManager.COLOR_GLOBAL_LIGHT)

        StormState.preStormClimateColorInfo:interp(
            StormState.redSkyClimateColorInfo,
            factor,
            globalLight:getModdedValue()
        )
    end,
    cleanupFakeSnowStorm = function()
        local climateManager = getClimateManager()

        -- Snow
        local isSnow = climateManager:getClimateBool(ClimateManager.BOOL_IS_SNOW)
        isSnow:setModdedValue(false)
        isSnow:setEnableModded(false)

        -- Back to vanilla colours
        local globalLight = climateManager:getClimateColor(ClimateManager.COLOR_GLOBAL_LIGHT)
        globalLight:setEnableModded(false)

        -- le fog (doensnt help)
        -- local fogIntensity = climateManager:getClimateFloat(ClimateManager.FLOAT_FOG_INTENSITY)
        -- fogIntensity:setEnableModded(false)

        -- climateManager:stopWeatherAndThunder()
    end,
    applyPanic = function()
        local character = getPlayer()
        local stats = character:getStats()
        local panic = stats:getPanic()
        local increment = 20

        -- Less panic indoors
        if (not character:isOutside() or character:getVehicle()) then
            increment = 10
        end

        if (character:isAsleep()) then
            character:forceAwake()
            increment = 40
        end

        stats:setPanic(math.min(panic + increment, 100))
    end,
    applyDamage = function()
        local character = getPlayer()

        if character:isDead() or (not character:isOutside() or character:getVehicle()) then
            -- Don't apply damage to dead or safe players.
            return
        end

        local rng = ZombRand(10)

        local partIndex = ZombRand(BodyPartType.MAX:index())
        local scratchDefense, biteDefense, skinDefense = getDefenses(character, partIndex)
        local randomPart = character:getBodyDamage():getBodyPart(BodyPartType.FromIndex(partIndex))

        character:Say("scratch: " .. tostring(scratchDefense) .. " bite: " .. tostring(biteDefense))

        -- TODO: add (special) gear to prevent damage.
        -- TODO: factor in gear in burn chance.
        if (MasoStorm.Settings.canBurn and rng == 0) then
            randomPart:setBurned()
        else
            local defenseModifier = 1 - ((scratchDefense * 2 + biteDefense + skinDefense) / 4) / 100
            -- character:Say("defensemod: " .. tostring(defenseModifier))
            randomPart:AddDamage(ZombRand(10, 25) * MasoStorm.Settings.damageMultiplier * defenseModifier)
        end
    end,
    applyBlindness = function(factor)
        -- TODO: add gear that lessens the blindness effects
        local character = getPlayer()

        if (factor == 0 or character:isDead()) then
            getSearchMode():setEnabled(character:getPlayerNum(), false)
            return
        end

        local mode = getSearchMode():getSearchModeForPlayer(character:getPlayerNum())
        getSearchMode():setEnabled(character:getPlayerNum(), true)
        mode:getBlur():setTargets(factor, factor)
        mode:getDesat():setTargets(factor, factor)
        mode:getRadius():setTargets(5 / factor, 5 / factor)
        mode:getDarkness():setTargets(factor / 1.2, factor / 1.2)
    end,
    trip = function()
        -- TODO: add gear to prevent tripping & fatigue gain

        local character = getPlayer()
        local modData = character:getModData()

        -- Let's make sure the player doesn't trip more than once.
        if modData.hasTripped or character:isSitOnGround() then
            return
        end

        character:setBumpType("stagger")
        character:setVariable("BumpDone", false)
        character:setVariable("BumpFall", true)
        character:setVariable("BumpFallType", "pushedFront")

        modData.hasTripped = true

        local stats = character:getStats()
        stats:setFatigue(stats:getFatigue() + 0.25)
    end,
    initOrCleanupTrip = function()
        local character = getPlayer()
        local modData = character:getModData()

        modData.hasTripped = false
    end
}

local function onEveryOneMinute()
    local isStormActive = StormUtils.getIsStormActive()

    if (not isStormActive) then
        if (StormState.init) then
            -- Unitialize
            StormState:reset()
        end

        return
    end

    -- Initialize
    if (not StormState.init) then
        StormState.init = true
        StormUtils.initFakeSnowStorm()
        StormUtils.initOrCleanupTrip()
    end

    local progress = StormUtils.getStormProgress()
    print("STORM PROGRESS", progress)

    -- local weatherFactor = MasoStorm.Utils.getFadeInAndOutFactor(progress, 0.25, 0.55, 0.5)
    local weatherFactor = MasoStorm.Utils.getFactor(progress, 0.25, 0.5)
    StormUtils.updateFakeSnowStorm(weatherFactor)

    if (weatherFactor == 1 and progress >= 0.55 and progress < 0.6) then
        StormUtils.trip()
        StormUtils.cleanupFakeSnowStorm()
        StormUtils.playRandomThunder(true, 100)
    end

    -- getPlayer():Say("weather factor: " .. tostring(weatherFactor))

    if (progress > 0.35 and progress < 0.55) then
        StormUtils.playRandomThunder(false, 35)
        StormUtils.applyPanic()
    end

    if (progress > 0.45 and progress < 0.55) then
        StormUtils.playRandomThunder(true, 75)
        StormUtils.applyDamage()
    end

    if (progress > 0.45 and progress < 0.6) then
        local factor = MasoStorm.Utils.getFadeInAndOutFactor(progress, 0.45, 0.6, 0.55)
        StormUtils.applyBlindness(factor)
    end
end

local function onGameStart()
    ClientUtils.request()
end

Events.EveryOneMinute.Add(onEveryOneMinute)
Events.OnGameStart.Add(onGameStart)

-- DEBUG ONLY
local function onKeyPressed(key)
    -- Key O to trigger event.
    if (key == 24) then
        print("client key code: ", key)
        StormState:reset()
    end

    if (key == 23) then
    end
end

Events.OnKeyPressed.Add(onKeyPressed)
