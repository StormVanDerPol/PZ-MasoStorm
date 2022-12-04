local MasoStorm = MasoStorm
local ZombRand = ZombRand
local getGameTime = getGameTime

local ServerUtils = {
    transmit = function(state)
        ModData.add(MasoStorm.ModDataNS, state)
        if isServer() then
            ModData.transmit(MasoStorm.ModDataNS)
        end
    end,
    getModData = function()
        return ModData.getOrCreate(MasoStorm.ModDataNS)
    end,
    getTriggerTime = function()
        local hours = ZombRand(0, 24)
        local days = ZombRand(MasoStorm.Settings.minDays, MasoStorm.Settings.maxDays)
        local triggerTime = getGameTime():getWorldAgeHours() + (days * 24.0) - 24 + hours

        print("GENERATING NEW TRIGGER TIME", "trigger time: ", triggerTime, " | days: ", days, " | hours: ", hours)

        return triggerTime
    end
}

local function onInitGlobalModData()
    ServerUtils.getModData()

    local state = {
        hour = ServerUtils.getTriggerTime()
    }

    ServerUtils.transmit(state)
end

-- Let's decide on a new time.
local function onEveryHours()
    local state = ServerUtils.getModData()
    local currentHour = getGameTime():getWorldAgeHours()

    if (currentHour > state.hour + MasoStorm.Settings.duration) then
        state.hour = ServerUtils.getTriggerTime()
        ServerUtils.transmit(state)
    end
end

-- EVENT BINDING
Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.EveryHours.Add(onEveryHours)

-- DEBUG ONLY
local function onKeyPressed(key)
    -- Key O to trigger event.
    if (key == 24) then
        print("server key code: ", key)

        local state = ServerUtils.getModData()
        state.hour = getGameTime():getWorldAgeHours()

        ServerUtils.transmit(state)
    end
end

Events.OnKeyPressed.Add(onKeyPressed)
