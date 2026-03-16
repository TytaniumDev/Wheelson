---@class Wheelson
local WHLSN = _G.Wheelson

local Group = WHLSN.Group

---------------------------------------------------------------------------
-- Group Formation Algorithm
-- Direct port of packages/shared/src/parallelGroupCreator.ts
---------------------------------------------------------------------------

local lastGroups = {}

--- Clear stored last-groups history.
function WHLSN:ClearLastGroups()
    wipe(lastGroups)
end

--- Store groups for the next run's duplicate-avoidance.
---@param groups WHLSNGroup[]
---@param guildId? string
function WHLSN:SetLastGroups(groups, guildId)
    lastGroups[guildId or "default"] = groups
end

--- Get stored last groups for a guild.
---@param guildId? string
---@return WHLSNGroup[]
function WHLSN:GetLastGroups(guildId)
    return lastGroups[guildId or "default"] or {}
end

--- Fisher-Yates shuffle (in-place).
---@param arr any[]
---@return any[]
local function shuffle(arr)
    for i = #arr, 2, -1 do
        local j = random(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
    return arr
end

--- Remove a player by name from a list (in-place).
local function removeFromList(list, player)
    for i, p in ipairs(list) do
        if p:Equals(player) then
            table.remove(list, i)
            return
        end
    end
end

--- Check if a player is in a list.
local function isInList(list, player)
    for _, p in ipairs(list) do
        if p:Equals(player) then return true end
    end
    return false
end

--- Copy a table shallowly.
local function copyList(src)
    local dst = {}
    for i, v in ipairs(src) do dst[i] = v end
    return dst
end

---------------------------------------------------------------------------
-- Context-based pipeline helpers
---------------------------------------------------------------------------

--- Build the teammate lookup map from previous groups.
local function BuildLastGroupsDict(previousGroups)
    local dict = {}
    for _, group in ipairs(previousGroups) do
        local members = group:GetPlayers()
        for _, member in ipairs(members) do
            if not dict[member.name] then
                dict[member.name] = {}
            end
            for _, m in ipairs(members) do
                if not m:Equals(member) then
                    dict[member.name][m.name] = true
                end
            end
        end
    end
    return dict
end

--- Categorize players into role pools and shuffle them.
local function BuildRolePools(ctx)
    for _, p in ipairs(ctx.players) do
        if p:IsTankMain() then ctx.mainTanks[#ctx.mainTanks + 1] = p end
        if p:IsOfftank() and not p:IsTankMain() then
            if p:IsHealerMain() or p:IsOffhealer() then
                ctx.offTanksWithHeal[#ctx.offTanksWithHeal + 1] = p
            else
                ctx.offTanks[#ctx.offTanks + 1] = p
            end
        end
        if p:IsHealerMain() then ctx.mainHealers[#ctx.mainHealers + 1] = p end
        if p:IsOffhealer() and not p:IsHealerMain() then ctx.offHealers[#ctx.offHealers + 1] = p end
        if p:IsDpsMain() then ctx.mainDps[#ctx.mainDps + 1] = p end
        if p:IsOffdps() and not p:IsDpsMain() then ctx.offDps[#ctx.offDps + 1] = p end
        if p:HasBrez() then ctx.brezPlayers[#ctx.brezPlayers + 1] = p end
        if p:HasLust() then ctx.lustPlayers[#ctx.lustPlayers + 1] = p end
    end

    shuffle(ctx.mainTanks)
    shuffle(ctx.offTanks)
    shuffle(ctx.offTanksWithHeal)
    shuffle(ctx.mainHealers)
    shuffle(ctx.offHealers)
    shuffle(ctx.mainDps)
    shuffle(ctx.offDps)
    shuffle(ctx.brezPlayers)
    shuffle(ctx.lustPlayers)
end

--- Build merged available lists and compute maxGroups.
local function BuildAvailableLists(ctx)
    for _, p in ipairs(ctx.mainTanks) do ctx.availableTanks[#ctx.availableTanks + 1] = p end
    for _, p in ipairs(ctx.offTanks) do ctx.availableTanks[#ctx.availableTanks + 1] = p end
    for _, p in ipairs(ctx.offTanksWithHeal) do ctx.availableTanks[#ctx.availableTanks + 1] = p end

    for _, p in ipairs(ctx.mainHealers) do ctx.availableHealers[#ctx.availableHealers + 1] = p end
    for _, p in ipairs(ctx.offHealers) do ctx.availableHealers[#ctx.availableHealers + 1] = p end

    for _, p in ipairs(ctx.mainDps) do ctx.availableDps[#ctx.availableDps + 1] = p end
    for _, p in ipairs(ctx.offDps) do ctx.availableDps[#ctx.availableDps + 1] = p end

    ctx.maxGroups = math.floor(#ctx.players / 5)
    ctx.offhealersToGrab = math.max(0, ctx.maxGroups - #ctx.mainHealers)
end

--- Remove a player from all applicable pools.
local function removePlayer(ctx, player)
    if player == nil then return end
    ctx.usedPlayers[player.name] = true

    if player:IsTankMain() then
        removeFromList(ctx.mainTanks, player)
        removeFromList(ctx.availableTanks, player)
    elseif player:IsOfftank() then
        removeFromList(ctx.offTanks, player)
        removeFromList(ctx.offTanksWithHeal, player)
        removeFromList(ctx.availableTanks, player)
    end

    if player:IsHealerMain() then
        removeFromList(ctx.mainHealers, player)
        removeFromList(ctx.availableHealers, player)
    elseif player:IsOffhealer() then
        removeFromList(ctx.offHealers, player)
        removeFromList(ctx.availableHealers, player)
    end

    if player:IsDpsMain() then
        removeFromList(ctx.mainDps, player)
        removeFromList(ctx.availableDps, player)
    elseif player:IsOffdps() then
        removeFromList(ctx.offDps, player)
        removeFromList(ctx.availableDps, player)
    end

    if player:HasBrez() then removeFromList(ctx.brezPlayers, player) end
    if player:HasLust() then removeFromList(ctx.lustPlayers, player) end
end

--- Grab the next available player from a pool, preferring non-duplicates.
local function grabNextAvailablePlayer(ctx, availablePlayers, group)
    local teammates = group:GetPlayers()

    local ineligible = {}
    for _, teammate in ipairs(teammates) do
        local prev = ctx.lastGroupsDict[teammate.name]
        if prev then
            for name in pairs(prev) do
                ineligible[name] = true
            end
        end
    end

    for _, p in ipairs(availablePlayers) do
        if not ineligible[p.name] and not ctx.usedPlayers[p.name] then
            removePlayer(ctx, p)
            return p
        end
    end

    for _, p in ipairs(availablePlayers) do
        if not ctx.usedPlayers[p.name] then
            removePlayer(ctx, p)
            return p
        end
    end

    return nil
end

---------------------------------------------------------------------------
-- Assignment phase functions
---------------------------------------------------------------------------

local function AssignTanks(ctx)
    for _, currentGroup in ipairs(ctx.groups) do
        currentGroup.tank = grabNextAvailablePlayer(ctx, ctx.availableTanks, currentGroup)
    end
end

local function AssignLust(ctx)
    for _, currentGroup in ipairs(ctx.groups) do
        if not currentGroup:HasLust() then
            local filtered = {}
            for _, p in ipairs(ctx.lustPlayers) do
                if not isInList(ctx.availableTanks, p) then
                    filtered[#filtered + 1] = p
                end
            end
            local lustPlayer = grabNextAvailablePlayer(ctx, filtered, currentGroup)
            if lustPlayer then
                if lustPlayer:IsHealerMain() or (ctx.offhealersToGrab > 0 and lustPlayer:IsOffhealer()) then
                    currentGroup.healer = lustPlayer
                    if lustPlayer:IsOffhealer() then ctx.offhealersToGrab = ctx.offhealersToGrab - 1 end
                elseif lustPlayer:IsDpsMain() then
                    currentGroup.dps[#currentGroup.dps + 1] = lustPlayer
                end
            end
        end
    end
end

local function AssignBrez(ctx)
    for _, currentGroup in ipairs(ctx.groups) do
        if not currentGroup:HasBrez() then
            local brezPlayer
            if currentGroup.healer then
                local filtered = {}
                for _, p in ipairs(ctx.brezPlayers) do
                    if not isInList(ctx.availableTanks, p) and not isInList(ctx.availableHealers, p) then
                        filtered[#filtered + 1] = p
                    end
                end
                brezPlayer = grabNextAvailablePlayer(ctx, filtered, currentGroup)
            else
                local filtered = {}
                for _, p in ipairs(ctx.brezPlayers) do
                    if not isInList(ctx.availableTanks, p) then
                        filtered[#filtered + 1] = p
                    end
                end
                brezPlayer = grabNextAvailablePlayer(ctx, filtered, currentGroup)
            end

            if brezPlayer then
                if brezPlayer:IsHealerMain() or (ctx.offhealersToGrab > 0 and brezPlayer:IsOffhealer()) then
                    currentGroup.healer = brezPlayer
                    if brezPlayer:IsOffhealer() then ctx.offhealersToGrab = ctx.offhealersToGrab - 1 end
                elseif brezPlayer:IsDpsMain() then
                    currentGroup.dps[#currentGroup.dps + 1] = brezPlayer
                end
            end
        end
    end
end

local function AssignHealers(ctx)
    for _, currentGroup in ipairs(ctx.groups) do
        if not currentGroup.healer then
            local mainHealer = grabNextAvailablePlayer(ctx, ctx.mainHealers, currentGroup)
            if mainHealer then
                currentGroup.healer = mainHealer
            else
                local offHealer = grabNextAvailablePlayer(ctx, ctx.availableHealers, currentGroup)
                if offHealer then
                    currentGroup.healer = offHealer
                end
            end
        end
    end
end

local function AssignRangedDps(ctx)
    for _, currentGroup in ipairs(ctx.groups) do
        if not currentGroup:HasRanged() then
            local filtered = {}
            for _, p in ipairs(ctx.availableDps) do
                if p:IsRanged() then filtered[#filtered + 1] = p end
            end
            local rangedDps = grabNextAvailablePlayer(ctx, filtered, currentGroup)
            if rangedDps then
                currentGroup.dps[#currentGroup.dps + 1] = rangedDps
            end
        end
    end
end

local function FillRemainingDps(ctx)
    for _, currentGroup in ipairs(ctx.groups) do
        while #currentGroup.dps < 3 do
            local dpsPlayer = grabNextAvailablePlayer(ctx, ctx.availableDps, currentGroup)
            if not dpsPlayer then break end
            currentGroup.dps[#currentGroup.dps + 1] = dpsPlayer
        end
    end
end

local function HandleRemainderPlayers(ctx)
    local totalUsed = 0
    for _ in pairs(ctx.usedPlayers) do totalUsed = totalUsed + 1 end

    while totalUsed < #ctx.players do
        local remainderGroup = Group:New()
        local added = false
        while totalUsed < #ctx.players do
            local remaining = {}
            for _, p in ipairs(ctx.players) do
                if not ctx.usedPlayers[p.name] then
                    remaining[#remaining + 1] = p
                end
            end
            local player = grabNextAvailablePlayer(ctx, remaining, remainderGroup)
            if player then
                added = true
                totalUsed = totalUsed + 1
                local placed = false

                if player:IsTankMain() and not remainderGroup.tank then
                    remainderGroup.tank = player
                    placed = true
                elseif player:IsHealerMain() and not remainderGroup.healer then
                    remainderGroup.healer = player
                    placed = true
                elseif player:IsDpsMain() and #remainderGroup.dps < 3 then
                    remainderGroup.dps[#remainderGroup.dps + 1] = player
                    placed = true
                elseif player:IsOfftank() and not remainderGroup.tank then
                    remainderGroup.tank = player
                    placed = true
                elseif player:IsOffhealer() and not remainderGroup.healer then
                    remainderGroup.healer = player
                    placed = true
                elseif player:IsOffdps() and #remainderGroup.dps < 3 then
                    remainderGroup.dps[#remainderGroup.dps + 1] = player
                    placed = true
                end

                if not placed then
                    ctx.usedPlayers[player.name] = nil
                    totalUsed = totalUsed - 1
                    break
                end
            else
                break
            end
        end
        if added then
            ctx.groups[#ctx.groups + 1] = remainderGroup
        else
            break
        end
    end
end

---------------------------------------------------------------------------
-- Main entry point — clean pipeline
---------------------------------------------------------------------------

--- Create balanced Mythic+ groups from a player list.
--- Port of createMythicPlusGroups() from parallelGroupCreator.ts.
---@param players WHLSNPlayer[]
---@param guildId? string
---@return WHLSNGroup[]
function WHLSN:CreateMythicPlusGroups(players, guildId)
    guildId = guildId or "default"

    local ctx = {
        players         = copyList(players),
        usedPlayers     = {},
        groups          = {},
        lastGroupsDict  = BuildLastGroupsDict(lastGroups[guildId] or {}),
        mainTanks       = {},
        offTanks        = {},
        offTanksWithHeal = {},
        mainHealers     = {},
        offHealers      = {},
        mainDps         = {},
        offDps          = {},
        brezPlayers     = {},
        lustPlayers     = {},
        availableTanks  = {},
        availableHealers = {},
        availableDps    = {},
        maxGroups       = 0,
        offhealersToGrab = 0,
    }

    BuildRolePools(ctx)
    BuildAvailableLists(ctx)

    for _ = 1, ctx.maxGroups do
        ctx.groups[#ctx.groups + 1] = Group:New()
    end

    AssignTanks(ctx)
    AssignLust(ctx)
    AssignBrez(ctx)
    AssignHealers(ctx)
    AssignRangedDps(ctx)
    FillRemainingDps(ctx)
    HandleRemainderPlayers(ctx)

    lastGroups[guildId] = ctx.groups
    return ctx.groups
end
