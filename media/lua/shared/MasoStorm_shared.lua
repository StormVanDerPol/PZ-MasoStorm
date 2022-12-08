local function timeout(func, delay)
    delay = delay or 1
    local ticks = 0
    local canceled = false

    local function onTick()
        if not canceled and ticks < delay then
            ticks = ticks + 1
            return
        end

        Events.OnTick.Remove(onTick)
        if not canceled then
            func()
        end
    end

    Events.OnTick.Add(onTick)
    return function()
        canceled = true
    end
end

local function clamp(value, min, max)
    if min > max then
        min, max = max, min
    end
    return math.min(math.max(value, min), max)
end

-- this is probably better solved with some actual math
local function getFadeInAndOutFactor(value, min, max, invertBreakpoint)
    local n = value - min
    local d = invertBreakpoint - min

    if (value > invertBreakpoint) then
        n = max - value
        d = max - invertBreakpoint
    end

    return clamp(n / d, 0, 1)
end

local function getFactor(value, min, max)
    local n = value - min
    local d = max - min

    return clamp(n / d, 0, 1)
end

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

local Settings = SandboxVars.MasoStorm
local ModDataNS = "MasoStorm"

local ServerUtils = {
    transmit = function(state)
        ModData.add(MasoStorm.ModDataNS, state)
        if isServer() then
            ModData.transmit(MasoStorm.ModDataNS)
        end
    end,
    get = function()
        if isServer() then
            return ModData.getOrCreate(MasoStorm.ModDataNS)
        end
    end,
    getTriggerTime = function()
        local hours = ZombRand(0, 24)
        local days = ZombRand(MasoStorm.Settings.minDays, MasoStorm.Settings.maxDays)
        local triggerTime = getGameTime():getWorldAgeHours() + (days * 24.0) - 24 + hours
        return triggerTime
    end
}

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

local function getIsStormActive()
    local state = nil
    if isServer() then
        state = ServerUtils.get()
    elseif isClient() then
        state = ClientUtils.get()
    end

    local currentHour = getGameTime():getWorldAgeHours()
    local isStormActive = ((currentHour > state.hour) and (currentHour < state.hour + MasoStorm.Settings.duration))
    return isStormActive
end

local function getStormProgress()
    local state = nil
    if isServer() then
        state = ServerUtils.get()
    elseif isClient() then
        state = ClientUtils.get()
    end

    local currentHour = getGameTime():getWorldAgeHours()
    local normalizedCurrentHour = currentHour - state.hour
    return MasoStorm.Utils.clamp(normalizedCurrentHour / MasoStorm.Settings.duration, 0, 1)
end

MasoStorm = {
    ModDataNS = ModDataNS,
    Settings = Settings,
    Utils = {
        timeout = timeout,
        clamp = clamp,
        getFactor = getFactor,
        getFadeInAndOutFactor = getFadeInAndOutFactor,
        getStormProgress = getStormProgress,
        getIsStormActive = getIsStormActive,
        getDefenses = getDefenses
    },
    ServerUtils = ServerUtils,
    ClientUtils = ClientUtils
}
