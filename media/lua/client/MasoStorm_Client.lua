local MasoStorm = MasoStorm
local ZombRand = ZombRand
local ClientUtils = MasoStorm.ClientUtils

-- state
local StormState = {
    reset = function(self)
        self.hasTripped = false
    end,
    hasTripped = false
}

local StormUtils = {
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
        local scratchDefense, biteDefense, skinDefense = MasoStorm.Utils.getDefenses(character, partIndex)
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

        -- Let's make sure the player doesn't trip more than once.
        if StormState.hasTripped or character:isSitOnGround() then
            return
        end

        StormState.hasTripped = true

        character:setBumpType("stagger")
        character:setVariable("BumpDone", false)
        character:setVariable("BumpFall", true)
        character:setVariable("BumpFallType", "pushedFront")

        local stats = character:getStats()
        stats:setFatigue(stats:getFatigue() + 0.25)
    end
}

local function onEveryOneMinute()
    local isStormActive = MasoStorm.Utils.getIsStormActive()

    if (not isStormActive) then
        StormState:reset()
        return
    end

    local progress = MasoStorm.Utils.getStormProgress()

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

    if (progress >= 0.55) then
        StormUtils.trip()
    end
end

local function onGameStart()
    ClientUtils.request()
end

Events.EveryOneMinute.Add(onEveryOneMinute)
Events.OnGameStart.Add(onGameStart)

-- DEBUG ONLY --
------------------------------------------------------------------
------------------------------------------------------------------
------------------------------------------------------------------
------------------------------------------------------------------
------------------------------------------------------------------
------------------------------------------------------------------
------------------------------------------------------------------
local function onKeyPressed(key)
    -- if (not isAdmin()) then
    -- return
    -- end

    -- Key O to trigger event.
    if (key == 24) then
        local state = ClientUtils.get()
        state.hour = getGameTime():getWorldAgeHours()
        ModData.transmit(MasoStorm.ModDataNS)
        getPlayer():Say("Forcing storm" .. tostring(state.hour))
    end
end

Events.OnKeyPressed.Add(onKeyPressed)

local function onReceiveGlobalModData(key, modData)
    getPlayer():Say("received md: " .. key)
end

Events.OnReceiveGlobalModData.Add(onReceiveGlobalModData)
