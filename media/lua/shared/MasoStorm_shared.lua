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

local Settings = SandboxVars.MasoStorm

MasoStorm = {
    ModDataNS = "MasoStorm",
    Settings = Settings,
    Utils = {
        timeout = timeout,
        clamp = clamp,
        getFactor = getFactor,
        getFadeInAndOutFactor = getFadeInAndOutFactor
    }
}
