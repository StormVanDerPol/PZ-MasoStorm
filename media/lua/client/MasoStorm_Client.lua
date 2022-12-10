local MasoStorm = MasoStorm
local ZombRand = ZombRand

local ClientUtils = {
    request = function()
        if isClient() then
            ModData.request(MasoStorm.ModDataNS)
        end
    end,
    get = function()
        return ModData.get(MasoStorm.ModDataNS)
    end,
    sync = function(key, modData)
        if isClient() and key == MasoStorm.ModDataNS then
            ModData.add(key, modData)
        end
    end
}

-- state
local StormState = {
    reset = function(self)
        self.hasTripped = false
    end,
    hasTripped = false
}

local StormUtils = {
    playRandomThunder = function(isSevere, chance)
        if (getPlayer():HasTrait("Deaf") or ZombRand(0, 100) > chance) then
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

        -- TODO: add (special) gear to prevent damage.
        -- TODO: factor in gear in burn chance.
        if (MasoStorm.Settings.canBurn and rng == 0) then
            randomPart:setBurned()
        else
            local defenseModifier = 1 - ((scratchDefense * 2 + biteDefense + skinDefense) / 4) / 100
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
        if StormState.hasTripped or not character:isOutside() or character:getVehicle() then
            return
        end

        StormState.hasTripped = true

        character:setBumpType("stagger")
        character:setVariable("BumpDone", false)
        character:setVariable("BumpFall", true)
        if (ZombRand(0, 10) < 5) then
            character:setVariable("BumpFallType", "pushedFront")
        else
            character:setVariable("BumpFallType", "pushedBehind")
        end

        local stats = character:getStats()
        stats:setFatigue(stats:getFatigue() + 0.25)
    end
}

local function onEveryOneMinute()
    local state = ClientUtils.get()
    local isStormActive = MasoStorm.Utils.getIsStormActive(state.hour)

    if (not isStormActive) then
        StormState:reset()
        return
    end

    local progress = MasoStorm.Utils.getStormProgress(state.hour)

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

    if (progress >= 0.55 and progress < 0.6) then
        StormUtils.trip()
    end
end

local function onGameStart()
    ClientUtils.request()
end

local function onReceiveGlobalModData(key, modData)
    ClientUtils.sync(key, modData)
end

Events.EveryOneMinute.Add(onEveryOneMinute)
Events.OnGameStart.Add(onGameStart)
Events.OnReceiveGlobalModData.Add(onReceiveGlobalModData)
