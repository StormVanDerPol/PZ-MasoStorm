local MasoStorm = MasoStorm

local ServerUtils = {
    transmit = function(state)
        ModData.add(MasoStorm.ModDataNS, state)
        if isServer() then
            ModData.transmit(MasoStorm.ModDataNS)
        end
    end,
    get = function()
        return ModData.getOrCreate(MasoStorm.ModDataNS)
    end,
    getTriggerTime = function()
        local hours = ZombRand(0, 24)
        local days = ZombRand(MasoStorm.Settings.minDays, MasoStorm.Settings.maxDays)
        local triggerTime = getGameTime():getWorldAgeHours() + (days * 24.0) - 24 + hours
        return triggerTime
    end
}

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
    initFakeSnowStorm = function()
        local climateManager = getClimateManager()

        -- forced snow
        local isSnow = climateManager:getClimateBool(ClimateManager.BOOL_IS_SNOW)
        isSnow:setEnableModded(true)
        isSnow:setModdedValue(true)

        climateManager:stopWeatherAndThunder()
        climateManager:triggerCustomWeatherStage(WeatherPeriod.STAGE_STORM, MasoStorm.Settings.duration - 2)

        local globalLight = climateManager:getClimateColor(ClimateManager.COLOR_GLOBAL_LIGHT)

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
    end
}

local function onInitGlobalModData()
    ServerUtils.get()

    local state = {
        hour = ServerUtils.getTriggerTime()
    }

    ServerUtils.transmit(state)
end

-- Let's decide on a new time.
local function onEveryHours()
    local state = ServerUtils.get()
    local currentHour = getGameTime():getWorldAgeHours()

    if (currentHour > state.hour + MasoStorm.Settings.duration) then
        state.hour = ServerUtils.getTriggerTime()
        ServerUtils.transmit(state)
    end
end

-- Handle weather
local function onEveryOneMinute()
    local state = ServerUtils.get()

    local isStormActive = MasoStorm.Utils.getIsStormActive(state.hour)

    if (not isStormActive) then
        if (StormState.init) then
            StormState:reset()
        end
        return
    end

    -- Initialize
    if (not StormState.init) then
        -- Sync for good measure
        ServerUtils.transmit(state)
        StormState.init = true
        StormUtils.initFakeSnowStorm()
    end

    local progress = MasoStorm.Utils.getStormProgress(state.hour)
    local weatherFactor = MasoStorm.Utils.getFactor(progress, 0.25, 0.5)
    StormUtils.updateFakeSnowStorm(weatherFactor)

    if (weatherFactor == 1 and progress >= 0.55 and progress < 0.6) then
        StormUtils.cleanupFakeSnowStorm()
    end
end

-- Just for good measure
local function onConnected()
    local state = ServerUtils.get()
    ServerUtils.transmit(state)
end

-- EVENT BINDING
Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.EveryHours.Add(onEveryHours)
Events.EveryOneMinute.Add(onEveryOneMinute)
Events.OnConnected.Add(onConnected)

-- DEBUG ONLY --
------------------------------------------------------------------
------------------------------------------------------------------
------------------------------------------------------------------
------------------------------------------------------------------
------------------------------------------------------------------
------------------------------------------------------------------
------------------------------------------------------------------
------------------------------------------------------------------

local function onReceiveGlobalModData(key, modData)
    if (key ~= MasoStorm.ModDataNS) then
        return
    end

    local state = ServerUtils.get()
    state = modData
    StormState:reset()
    ServerUtils.transmit(state)
end

Events.OnReceiveGlobalModData.Add(onReceiveGlobalModData)
