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
        climateManager:triggerCustomWeatherStage(WeatherPeriod.STAGE_TROPICAL_STORM, MasoStorm.Settings.duration - 2)

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
        StormState.redSkyClimateColorInfo:setInterior(1, 0, 0, 0.7)
        -- The one we'll render
        globalLight:getModdedValue():setTo(globalLight:getInternalValue())
        globalLight:setModdedInterpolate(1)
        globalLight:setEnableModded(true)
    end,
    updateFakeSnowStorm = function(progress)
        local globalLight = getClimateManager():getClimateColor(ClimateManager.COLOR_GLOBAL_LIGHT)

        local factor = MasoStorm.Utils.getFadeInAndOutFactor(progress, 0, 1, 0.5)

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

        -- Stop storm, since it would turn into rain which looks a little awkward
        climateManager:stopWeatherAndThunder()
    end,
    applyPanic = function()
        local character = getPlayer()
        local stats = character:getStats()
        local panic = stats:getPanic()
        local increment = 14

        -- Less panic indoors
        if (not character:isOutside() or character:getVehicle()) then
            increment = 4
        end

        stats:setPanic(panic + increment)
    end,
    applyDamage = function()
        local character = getPlayer()

        if character:isDead() or (not character:isOutside() or character:getVehicle()) then
            -- Don't apply damage to dead or safe players.
            return
        end

        local rng = ZombRand(10)
        local randomPart = character:getBodyDamage():getBodyPart(BodyPartType.getRandom())

        -- TODO: add gear to prevent damage.

        if (MasoStorm.Settings.canBurn and rng == 0) then
            randomPart:setBurned()
        elseif rng < 8 then
            randomPart:AddDamage(ZombRand(10, 25) * MasoStorm.Settings.damageMultiplier)
        end
    end,
    applyBlindess = function(factor)
        -- TODO: add gear that lessens the blindness effects

        local character = getPlayer()
        local mode = getSearchMode():getSearchModeForPlayer(character:getPlayerNum())
        getSearchMode():setEnabled(character:getPlayerNum(), true)
        mode:getBlur():setTargets(factor, factor)
        mode:getDesat():setTargets(factor, factor)
        mode:getRadius():setTargets(5 / factor, 5 / factor)
        mode:getDarkness():setTargets(factor / 1.2, factor / 1.2)

        if (factor == 0) then
            getSearchMode():setEnabled(character:getPlayerNum(), false)
        end
    end,
    trip = function()
        -- TODO: add gear to prevent tripping & fatigue gain

        local character = getPlayer()
        local modData = character:getModData()

        -- Let's make sure the player doesn't trip more than once.
        if modData.hasTripped then
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
            StormUtils.cleanupFakeSnowStorm()
            StormState:reset()
        end
        -- Quit
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

    StormUtils.updateFakeSnowStorm(progress)

    if (progress > 0.25 and progress < 0.45) then
        StormUtils.playRandomThunder(false, 10)
        StormUtils.applyPanic()
    end

    if (progress > 0.35 and progress < 0.5) then
        StormUtils.applyDamage()
    end

    if (progress > 0.35 and progress < 0.6) then
        local factor = MasoStorm.Utils.getFadeInAndOutFactor(progress, 0.35, 0.6, 0.5)
        StormUtils.applyBlindess(factor)
    end

    if (progress > 0.49 and progress < 0.51) then
        StormUtils.playRandomThunder(true, 100)
        StormUtils.trip()
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
