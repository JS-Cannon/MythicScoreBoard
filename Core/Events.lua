local _max  = math.max
local MS = _G["MythicScoreboard"]
local _issecret = issecretvalue

-- Add DataBroker & LibDBIcon references
local LDB = LibStub("LibDataBroker-1.1", true)
local icon = LibStub("LibDBIcon-1.0", true)

local DIFF_LABEL = {
    [1]="Normal",      [2]="Heroic",    [23]="Mythic",
    [8]="Mythic Keystone",
    [24]="Timewalking", [33]="Timewalking",
    [205]="Follower (N)", [207]="Follower (H)", [208]="Follower (M)",
}

MS.DIFF_GROUPS = {
    { key="mythicplus",  label="Mythic+",     ids={8}           },
    { key="mythic",      label="Mythic",      ids={23}          },
    { key="heroic",      label="Heroic",      ids={2}           },
    { key="normal",      label="Normal",      ids={1}           },
    { key="timewalking", label="Timewalking", ids={24,33}        },
    { key="follower",    label="Follower",    ids={205,207,208} },
}

local MYTHIC_PLUS = 8

-- Boss counts for completion detection. EJ is the fallback for unlisted dungeons.
local BOSS_COUNTS = {
    -- Season 2 (patch 12.1)
    ["Altar of Fangs"]         = 3,
    ["Murder Row"]             = 4,
    ["Den of Nalorakk"]        = 3,
    ["The Blinding Vale"]      = 4,
    ["Voidscar Arena"]         = 3,
    ["King's Rest"]            = 4,
    ["Temple of Sethraliss"]   = 3,
    ["Ruby Life Pools"]        = 3,
    -- Season 1 (kept for saved-run completion detection)
    ["Windrunner Spire"]       = 4,
    ["Maisara Caverns"]        = 3,
    ["Magisters' Terrace"]     = 4,
    ["Nexus-Point Xenas"]      = 3,
    ["Algeth'ar Academy"]      = 4,
    ["Seat of the Triumvirate"]= 4,
    ["Skyreach"]               = 4,
    ["Pit of Saron"]           = 3,
}

local function GetDifficultyID()  return select(3, GetInstanceInfo()) or 0 end

local function IsTracked(diff)
    local td = MythicScoreboardDB and MythicScoreboardDB.settings
                and MythicScoreboardDB.settings.trackedDifficulties
    for _, grp in ipairs(MS.DIFF_GROUPS) do
        for _, id in ipairs(grp.ids) do
            if id == diff then
                return (not td) or (td[grp.key] == true)
            end
        end
    end
    return false
end

local function GetDungeonName()
    local instanceName, itype = GetInstanceInfo()
    if instanceName and instanceName ~= "" and itype == "party" then
        return instanceName
    end
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local id = C_ChallengeMode.GetActiveChallengeMapID()
        if id and id > 0 then
            local info = C_ChallengeMode.GetMapInfo and C_ChallengeMode.GetMapInfo(id)
            if info and info.name then return info.name end
        end
    end
    return GetRealZoneText() or "Unknown"
end

local function GetKeystoneLevel()
    return (C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo
        and select(1, C_ChallengeMode.GetActiveKeystoneInfo())) or 0
end

local function AutoResetMeter()
    if not (MythicScoreboardDB and MythicScoreboardDB.settings
            and MythicScoreboardDB.settings.autoResetMeter) then return end
    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
        C_DamageMeter.ResetAllCombatSessions()
    end
end

local _deadUnits           = {}
local _scheduleCheckActive = false

-- Tracks enemy casts so we can identify stuns that actually stopped a cast.
--
-- Keyed by nameplate unit token. Enemy GUIDs are secret in Midnight M+, and
-- secret values cannot be used as Lua table keys.
-- We intentionally do not use COMBAT_LOG_EVENT_UNFILTERED because CLEU is
-- blocked in Midnight Mythic+.
local _trackedEnemyCasts = {}

local function IsSecret(value)
    return _issecret and value ~= nil and _issecret(value)
end

-- Cast-stopping crowd control, keyed by the harmful aura spell ID reported by
-- C_UnitAuras.  This intentionally includes stuns, incapacitations, fears and
-- horrifies: all can terminate an interruptible NPC cast.  Roots (for example
-- Mass Entanglement, Landslide, Binding Shot and Void Tendrils) are excluded
-- because rooted enemies can still cast.  Knockbacks without a visible harmful
-- aura cannot be attributed safely through this aura-based tracker.
local STUN_SPELLS = {
    -- Death Knight
    [221562] = true,  -- Asphyxiate
    [91800]  = true,  -- Gnaw (Ghoul)
    [91797]  = true,  -- Monstrous Blow (Ghoul)
    [207167] = true,  -- Blinding Sleet

    -- Demon Hunter
    [179057] = true,  -- Chaos Nova
    [207685] = true,  -- Sigil of Misery
    [217832] = true,  -- Imprison

    -- Druid
    [22570]  = true,  -- Maim
    [5211]   = true,  -- Mighty Bash
    [99]     = true,  -- Incapacitating Roar
    [2637]   = true,  -- Hibernate

    -- Evoker
    [368970] = true,  -- Tail Swipe (knockdown aura)
    [360806] = true,  -- Sleep Walk

    -- Hunter
    [19577]  = true,  -- Intimidation (trigger spell)
    [24394]  = true,  -- Intimidation (applied stun aura)
    [187650] = true,  -- Freezing Trap

    -- Mage
    [113724] = true,  -- Ring of Frost
    [118]    = true,  -- Polymorph
    [31661]  = true,  -- Dragon's Breath

    -- Monk
    [119381] = true,  -- Leg Sweep
    [115078] = true,  -- Paralysis

    -- Paladin
    [853]    = true,  -- Hammer of Justice
    [105593] = true,  -- Fist of Justice
    [20066]  = true,  -- Repentance
    [115750] = true,  -- Blinding Light

    -- Priest
    [8122]   = true,  -- Psychic Scream
    [64044]  = true,  -- Psychic Horror
    [88625]  = true,  -- Holy Word: Chastise
    [9484]   = true,  -- Shackle Undead

    -- Rogue
    [1833]   = true,  -- Cheap Shot
    [408]    = true,  -- Kidney Shot
    [2094]   = true,  -- Blind
    [315341] = true,  -- Between the Eyes
    [1776]   = true,  -- Gouge
    [6770]   = true,  -- Sap

    -- Shaman
    [118905] = true,  -- Capacitor Totem
    [305483] = true,  -- Lightning Lasso
    [51514]  = true,  -- Hex

    -- Warlock
    [30283]  = true,  -- Shadowfury
    [89766]  = true,  -- Axe Toss (Felguard)
    [6789]   = true,  -- Mortal Coil
    [5782]   = true,  -- Fear
    [710]    = true,  -- Banish

    -- Warrior
    [7922]   = true,  -- Charge stun
    [132168] = true,  -- Shockwave
    [107570] = true,  -- Storm Bolt (cast spell)
    [132169] = true,  -- Storm Bolt (applied stun aura)
    [5246]   = true,  -- Intimidating Shout
}

-- Some abilities apply a separate aura spell (for example Hunter
-- Intimidation's trigger is 19577 but its stun aura is 24394).  Fall back to
-- the localized spell name so those trigger/aura ID pairs remain trackable
-- without depending on English-only name strings or every internal aura ID.
local _stunAuraNames = nil
local function IsTrackedStunAura(spellID, spellName)
    if spellID and not IsSecret(spellID) and STUN_SPELLS[spellID] then
        return true
    end
    if not spellName or IsSecret(spellName) then return false end
    if not _stunAuraNames then
        _stunAuraNames = {}
        if C_Spell and C_Spell.GetSpellInfo then
            for id in pairs(STUN_SPELLS) do
                local info = C_Spell.GetSpellInfo(id)
                local name = info and info.name
                if name and not IsSecret(name) then _stunAuraNames[name] = true end
            end
        end
    end
    return _stunAuraNames[spellName] or false
end

local function IsDangerousEnemyCast(unit)
    if not unit or not UnitExists(unit) then return false end
    if UnitIsFriend("player", unit) then return false end

    local name, _, _, _, startMS, endMS, _, _, notInterruptible,
          spellID = UnitCastingInfo(unit)

    if not name or not startMS or not endMS then
        return false
    end

    -- A cast which Blizzard reports as non-interruptible is not something
    -- we should count as a stun interrupt.
    if notInterruptible then
        return false
    end

    return true, spellID, name, startMS / 1000, endMS / 1000
end

local function ResolveCCOwner(sourceUnit)
    if not sourceUnit or IsSecret(sourceUnit) then return nil end

    -- Direct player source.
    if UnitIsPlayer(sourceUnit) then
        local name = UnitName(sourceUnit)
        if name and not IsSecret(name) then
            return MS.ShortName(name)
        end
        return nil
    end

    -- Totems and guardians are not always exposed as party-pet units. Their
    -- creator is the most reliable owner source when the aura identifies the
    -- summoned unit (for example, Capacitor Totem).
    local creator = UnitCreator and UnitCreator(sourceUnit)
    if creator and not IsSecret(creator) then
        return MS.ShortName(creator)
    end

    -- Ordinary pet/guardian source.
    local guid = UnitGUID(sourceUnit)
    if not guid or IsSecret(guid) then return nil end
    return MS._petGUIDToOwner and MS._petGUIDToOwner[guid]
end

local function ScanEnemyCasts()
    if not MS.inDungeon or not MS.currentRun then
        wipe(_trackedEnemyCasts)
        return
    end

    local now = GetTime()
    local seen = {}

    for i = 1, 40 do
        local unit = "nameplate" .. i

        if UnitExists(unit) and not UnitIsFriend("player", unit) then
            local name, _, _, _, startMS, endMS, _, _, notInterruptible,
                  spellID = UnitCastingInfo(unit)

            if not IsSecret(name) and not IsSecret(startMS)
                    and not IsSecret(endMS) and not IsSecret(spellID)
                    and not IsSecret(notInterruptible)
                    and name and startMS and endMS and not notInterruptible then
                seen[unit] = true

                local existing = _trackedEnemyCasts[unit]

                -- New cast.
                if not existing
                        or existing.startMS ~= startMS
                        or existing.spellID ~= spellID then

                    _trackedEnemyCasts[unit] = {
                        unit      = unit,
                        spellID   = spellID,
                        spellName = name,
                        startMS   = startMS,
                        endMS     = endMS,
                        stopped   = false,
                        seenAt    = now,
                    }
                    if MS.debugInterruptLogging then
                        print("|cff00ccff[MythicScoreboard DEBUG]|r Watching "
                            .. unit .. " cast: " .. name)
                    end
                else
                    existing.endMS = endMS
                end
            end
        end
    end

    -- Remove casts whose nameplates disappeared.
    for unit, cast in pairs(_trackedEnemyCasts) do
        if not seen[unit] then
            if now < (cast.endMS / 1000) - 0.10 then
                -- UNIT_AURA can be delivered after the cast has disappeared.
                -- Keep the record until its original end time so that a stun
                -- aura arriving on the same frame can still be attributed.
                if cast.pendingStun then
                    cast.stopped = true
                else
                    cast.missingAt = cast.missingAt or now
                end
            else
                _trackedEnemyCasts[unit] = nil
            end
        elseif now > (cast.endMS / 1000) + 0.5 then
            _trackedEnemyCasts[unit] = nil
        end
    end
end

local function CreditStunInterrupt(cast)
    if not cast.pendingStun or cast.stunCredited then return end

    cast.stunCredited = true
    local owner = cast.pendingStun.owner
    local player = MS.currentRun and MS.currentRun.players
        and MS.currentRun.players[owner]
    if not player then return end

    player.stunInterrupts = (player.stunInterrupts or 0) + 1
    MS:DebugLogInterruptCounts()
    MS:SaveCurrentRun()
    if MS.sbFrameVisible and MS.sbFrameVisible() then MS:RefreshOverview() end
end

local function CheckStunInterrupts()
    if not MS.inDungeon or not MS.currentRun then return end

    local now = GetTime()

    for _, cast in pairs(_trackedEnemyCasts) do
        if cast.stopped then
            CreditStunInterrupt(cast)
        else
            local unit = cast.unit

            if UnitExists(unit) then
                local name, _, _, _, startMS, endMS, _, _, notInterruptible =
                    UnitCastingInfo(unit)

                -- The original cast is still running.
                if name and not IsSecret(name) and not IsSecret(startMS)
                        and not IsSecret(endMS) and startMS == cast.startMS then
                    cast.endMS = endMS or cast.endMS

                -- The cast disappeared before its expected end.
                elseif now < (cast.endMS / 1000) - 0.10 then
                    -- Wait for UNIT_AURA to identify the stopping effect.
                    -- The aura event can arrive just after this poll, so an
                    -- unattributed early end must remain eligible briefly.
                    if cast.pendingStun then
                        cast.stopped = true
                        CreditStunInterrupt(cast)
                    end
                end
            end
        end
    end
end

local function StartDungeonRun()
    if MS.inDungeon then return end
    local diff = GetDifficultyID()
    if not IsTracked(diff) then return end
    local name, level = GetDungeonName(), GetKeystoneLevel()
    MS.inDungeon = true
    MS:StartRun(name, level, diff, DIFF_LABEL[diff] or "Unknown")
    local display = level > 0 and (name .. " +" .. level)
                               or (name .. " [" .. (DIFF_LABEL[diff] or "?") .. "]")
    print("|cff00ccff[MythicScoreboard]|r Run started: " .. display)
end

local function EndDungeonRun(completed, inTime)
    if not MS.inDungeon then return end
    MS.inDungeon = false
    wipe(_deadUnits)
    MS:EndRun(completed, inTime or false)
end

local function HandleUnitDied()
    if not MS.inDungeon then return end
    local run = MS.currentRun
    if not run then return end
    local worldElapsed = GetWorldElapsedTime and select(2, GetWorldElapsedTime(1))
    local now = (worldElapsed and worldElapsed > 0)
        and worldElapsed
        or  _max(0, GetTime() - run.startTime)
    for _, unit in ipairs(MS:GroupUnits()) do
        -- Skip mind-controlled mobs temporarily showing as players in the roster.
        if UnitIsPlayer(unit) then
            local dead = UnitIsDeadOrGhost(unit)
            if dead and not _deadUnits[unit] then
                _deadUnits[unit] = true
                local uname = UnitName(unit)
                if uname and uname ~= "" then
                    local short = MS.ShortName(uname)
                    local p     = run.players[short]
                    if p and not MS:IsDupDeath(p, now) then
                        MS:RecordDeathEvent(short)
                    end
                end
            elseif not dead and _deadUnits[unit] then
                _deadUnits[unit] = nil
            end
        end
    end
end

local _reloading = false

local function HandleDamageMeterUpdated()
    if not MS.inDungeon then return end
    -- Skip while meter data is secret (Midnight M+ combat protection).
    if _issecret and C_DamageMeter and C_DamageMeter.GetCombatSessionFromType then
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, 0, 0)
        if ok and session then
            if (session.maxValue and _issecret(session.maxValue))
                    or (session.duration and _issecret(session.duration))
                    or (session.combatSources and session.combatSources[1]
                        and (_issecret(session.combatSources[1].totalAmount)
                             or (session.combatSources[1].name
                                 and _issecret(session.combatSources[1].name)))) then
                return
            end
        end
    end
    MS:SnapshotFromDamageMeter()
    if MS.sbFrameVisible and MS.sbFrameVisible() then MS:RefreshOverview() end
end

local function SyncRoster()
    if not MS.inDungeon or not MS.currentRun then return end
    if GetNumGroupMembers() == 0 then return end
    local VALID_CLASS = MS.ValidClass
    local current = {}
    for _, unit in ipairs(MS:GroupUnits()) do
        if UnitIsPlayer(unit) then
            local uname = UnitName(unit)
            local _, cls = UnitClass(unit)
            if uname and uname ~= "" then
                local short = MS.ShortName(uname)
                current[short] = true
                if not MS.currentRun.players[short] and MS.NewPlayerStats then
                    local safeClass = (cls and VALID_CLASS[cls:upper()]) and cls:upper() or "UNKNOWN"
                    MS.currentRun.players[short] =
                        MS.NewPlayerStats(short, safeClass, UnitGUID(unit))
                end
                if MS.currentRun.players[short] then
                    MS.currentRun.players[short].left = nil
                end
            end
        end
    end
    for name, p in pairs(MS.currentRun.players) do
        if not current[name] then p.left = true end
    end
end

local function GetQualityFromItemLink(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end

    local hex = itemLink:match("|c(%x%x%x%x%x%x%x%x)|Hitem:")
    if not hex then
        return nil
    end

    local r = tonumber(hex:sub(3, 4), 16) / 255
    local g = tonumber(hex:sub(5, 6), 16) / 255
    local b = tonumber(hex:sub(7, 8), 16) / 255

    for quality = 0, 7 do
        local qr, qg, qb = GetItemQualityColor(quality)

        if math.abs(r - qr) < 0.01
            and math.abs(g - qg) < 0.01
            and math.abs(b - qb) < 0.01
        then
            return quality
        end
    end

    return nil
end

local function IsEligibleLoot(itemLink)
    if not itemLink then
        return false
    end

    -- Only weapons and armor.
    local _, _, _, _, _, classID =
        C_Item.GetItemInfoInstant(itemLink)

    if classID ~= Enum.ItemClass.Weapon
        and classID ~= Enum.ItemClass.Armor
    then
        return false
    end

    -- Get item binding information.
    local _, _, _, _, _, _, _, _, _, _, _, _, bindType =
        C_Item.GetItemInfo(itemLink)

    -- 2 = Bind on Equip.
    if bindType == 2 then
        return false
    end

    -- Exclude Warbound / account-bound-until-equipped.
    if C_Item.IsItemBindToAccountUntilEquip
        and C_Item.IsItemBindToAccountUntilEquip(itemLink)
    then
        return false
    end

    return true
end

local frame = CreateFrame("Frame")

-- Bonus IDs (upgrade track, etc.) live in the item string's 13th segment.
local function LootLinkHasBonusIDs(link)
    if type(link) ~= "string" then return false end
    local itemString = link:match("item:([%d:]+)")
    if not itemString then return false end
    local parts = {strsplit(":", itemString)}
    local numBonus = tonumber(parts[13])
    return numBonus and numBonus > 0
end

local function ApplyLootToPlayer(targetRun, name, itemName, itemLink, itemTexture, isConfirmedLink, quality, qualityColor)
    local p = targetRun.players[name]
    if not p then return end

    -- A real hyperlink from the encounter/chat event is authoritative.
    -- Never let a name-only lookup overwrite it.
    if p.lootLinkConfirmed and not isConfirmedLink then
        return
    end

    local newItemID = itemLink and tonumber(itemLink:match("item:(%d+)"))

    -- Don't replace a full M+ link with a weaker link for the same item.
    if newItemID
        and p.lootItemID == newItemID
        and p.lootItemLink
        and LootLinkHasBonusIDs(p.lootItemLink)
        and not LootLinkHasBonusIDs(itemLink)
    then
        return
    end

    if itemName then
        p.lootItemName = itemName
    end

    if itemLink then
        p.lootItemLink = itemLink
        p.lootItemID = newItemID or p.lootItemID
        p.lootLinkConfirmed = isConfirmedLink and true or p.lootLinkConfirmed

        -- The itemLink itself is the authoritative loot data.
        p.lootQuality = GetQualityFromItemLink(itemLink)

        if C_Item.GetDetailedItemLevelInfo then
            p.lootItemLevel =
                C_Item.GetDetailedItemLevelInfo(itemLink)
                or p.lootItemLevel
        end
    end

    if itemTexture then
        p.lootIcon = itemTexture
    elseif newItemID and C_Item.GetItemIconByID then
        p.lootIcon = C_Item.GetItemIconByID(newItemID)
    end

    -- Only use the old quality fallback when we don't have
    -- a quality encoded in the authoritative link.
    if p.lootQuality == nil and quality ~= nil then
        p.lootQuality = quality

        local r, g, b = GetItemQualityColor(quality)
        p.lootQualityColor = { r, g, b }
    elseif p.lootQuality == nil and qualityColor then
        p.lootQualityColor = qualityColor
    elseif p.lootQuality ~= nil then
        local r, g, b = GetItemQualityColor(p.lootQuality)
        p.lootQualityColor = { r, g, b }
    end

    if MS._awaitingLootAutoShow
        and MythicScoreboardDB
        and MythicScoreboardDB.runs
        and targetRun == MythicScoreboardDB.runs[1]
    then
        MS._awaitingLootAutoShow = nil

        C_Timer.After(0.1, function()
            MS:ShowScoreboard()
        end)
    end

    targetRun._seq = (targetRun._seq or 0) + 1

    if MS.sbFrameVisible and MS.sbFrameVisible() then
        MS:RefreshOverview()
    end
end

-- Only equippable Weapon/Armor gear populates the Loot column; reagents,
-- currency-like stacks, keystones, consumables, and Warbound/BoE items
-- (not yet truly bound to the looter) are skipped. Retries briefly while
-- the client finishes loading item data.
local function TryResolveLoot(targetRun, name, itemQuery, itemNameFallback, isConfirmedLink, qualityColor, attempt)
    attempt = attempt or 1

    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemQuery)

    if classID ~= nil
        and classID ~= Enum.ItemClass.Weapon
        and classID ~= Enum.ItemClass.Armor
    then
        return
    end

    local iName, iLink, iQuality, _, _, _, _, _, iEquipLoc, iTexture =
        C_Item.GetItemInfo(itemQuery)

    if not iName or not iLink then
        if attempt < 8 then
            C_Timer.After(0.4, function()
                TryResolveLoot(
                    targetRun,
                    name,
                    itemQuery,
                    itemNameFallback,
                    isConfirmedLink,
                    qualityColor,
                    attempt + 1
                )
            end)
        end

        return
    end

    if not iEquipLoc or iEquipLoc == "" then
        return
    end

    if C_Item.IsItemBindToAccountUntilEquip
        and C_Item.IsItemBindToAccountUntilEquip(iLink or itemQuery)
    then
        return
    end

    -- IMPORTANT:
    -- If the original event supplied a real hyperlink, keep THAT EXACT LINK.
    -- Otherwise this is only a fallback resolution.
    local finalLink = isConfirmedLink and itemQuery or iLink

    ApplyLootToPlayer(
        targetRun,
        name,
        iName or itemNameFallback,
        finalLink,
        iTexture,
        isConfirmedLink,
        iQuality,
        qualityColor
    )
end

-- Loot can only be attributed to a just-finished run for a grace period after
-- FinalizeMythicPlusRun commits it (MS._lootGraceUntil). The reward chest is
-- opened manually and can land well after the boss dies -- especially on an
-- overtime/failed key, when the group often lingers instead of rushing out.
-- Requiring we still be inside a party instance stops unrelated loot picked
-- up well after leaving the dungeon from being misattributed.
local function GetLootTargetRun()
    local targetRun = MS.currentRun
    if not targetRun and MS._lootGraceUntil and GetTime() <= MS._lootGraceUntil
            and MythicScoreboardDB and MythicScoreboardDB.runs then
        local _, itype = GetInstanceInfo()
        if itype == "party" then
            local latest = MythicScoreboardDB.runs[1]
            if latest and latest.completed and (latest.keystoneLevel or 0) > 0 and latest.players then
                targetRun = latest
            end
        end
    end
    if targetRun and targetRun.players then return targetRun end
    return nil
end

MS.pendingLoot = MS.pendingLoot or {}

local function NormalizeLootName(name)
    if not name then return nil end

    name = name:gsub("|c%x%x%x%x%x%x%x%x", "")
    name = name:gsub("|r", "")
    name = name:gsub("^%s+", "")
    name = name:gsub("%s+$", "")

    return name
end

local function CleanupPendingLoot()
    if not MS.pendingLoot then return end

    local now = GetTime()

    for i = #MS.pendingLoot, 1, -1 do
        if now - MS.pendingLoot[i].time > 3 then
            table.remove(MS.pendingLoot, i)
        end
    end
end

local function AddPendingChatLoot(targetRun, playerName, itemName, itemLink, qualityColor)
    if not targetRun or not playerName or not itemName then
        return
    end

    CleanupPendingLoot()

    table.insert(MS.pendingLoot, {
        source = "CHAT",
        targetRun = targetRun,
        playerName = playerName,
        itemName = itemName,
        itemLink = itemLink,
        qualityColor = qualityColor,
        time = GetTime(),
    })
end

local function AddPendingEncounterLoot(targetRun, itemID, itemLink, itemName)
    if not targetRun or not itemID then
        return
    end

    CleanupPendingLoot()

    table.insert(MS.pendingLoot, {
        source = "ENCOUNTER",
        targetRun = targetRun,
        itemID = itemID,
        itemLink = itemLink,
        itemName = itemName,
        time = GetTime(),
    })
end

local function FindPendingChatLoot(targetRun, itemName, playerName)
    if not MS.pendingLoot or not itemName then
        return nil
    end

    CleanupPendingLoot()

    local wantedItem = NormalizeLootName(itemName)
    local wantedPlayer = playerName and MS.ShortName(playerName)

    for i = #MS.pendingLoot, 1, -1 do
        local pending = MS.pendingLoot[i]

        if pending.source == "CHAT"
            and pending.targetRun == targetRun
            and NormalizeLootName(pending.itemName) == wantedItem
        then
            if not wantedPlayer or pending.playerName == wantedPlayer then
                table.remove(MS.pendingLoot, i)
                return pending
            end
        end
    end

    return nil
end

local function FindPendingEncounterLoot(targetRun, itemName)
    if not MS.pendingLoot or not itemName then
        return nil
    end

    CleanupPendingLoot()

    local wantedItem = NormalizeLootName(itemName)

    for i = #MS.pendingLoot, 1, -1 do
        local pending = MS.pendingLoot[i]

        if pending.source == "ENCOUNTER"
            and pending.targetRun == targetRun
            and pending.itemName
            and NormalizeLootName(pending.itemName) == wantedItem
        then
            table.remove(MS.pendingLoot, i)
            return pending
        end
    end

    return nil
end

-- COMBAT_LOG_EVENT_UNFILTERED and DAMAGE_METER_COMBAT_SESSION_UPDATED are
-- blocked in Midnight instances; damage is polled via C_DamageMeter instead.
local _eventsToRegister = {
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEAVING_WORLD",
    "PLAYER_DIFFICULTY_CHANGED",
    "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
    "ENCOUNTER_START", "ENCOUNTER_END",
    "PLAYER_DEAD", "GROUP_ROSTER_UPDATE",
    "UNIT_PET",
    "UNIT_AURA", -- Aura changes stun tracker
    "SCENARIO_CRITERIA_UPDATE",
    "CHAT_MSG_LOOT", -- Fallback for non-encounter loot (chests, mob drops).
    "ENCOUNTER_LOOT_RECEIVED", -- Primary source: gives a real itemLink, unlike CHAT_MSG_LOOT.
}

local function RegisterAllEvents()
    for _, ev in ipairs(_eventsToRegister) do frame:RegisterEvent(ev) end
end

local function SetupMinimapIcon()
    if not LDB or not icon then return end

    -- 1. Create DataBroker Data Object
    local MS_LDB = LDB:NewDataObject("MythicScoreboard", {
        type = "data source",
        text = "MythicScoreboard",
        icon = "Interface\\Icons\\inv_relics_hourglass", -- Path to icon texture
        OnClick = function(_, button)
            if button ~= "LeftButton" then return end
            if not MS.ToggleUI then
                print("|cffff4444[MythicScoreboard]|r UI did not initialize. Enable Lua errors, then reload the UI.")
                return
            end
            local ok, err = pcall(MS.ToggleUI, MS)
            if not ok then
                print("|cffff4444[MythicScoreboard]|r Minimap UI error: " .. tostring(err))
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("|cff00ccffMythicScoreboard|r")
            tt:AddLine("Left-Click to toggle scoreboard", 1, 1, 1)
        end,
    })

    -- 2. Initialize database defaults for icon position/visibility
    MythicScoreboardDB.minimap = MythicScoreboardDB.minimap or { hide = false }

    -- 3. Register icon with LibDBIcon
    icon:Register("MythicScoreboard", MS_LDB, MythicScoreboardDB.minimap)
end

-- Defer registration if loaded mid-combat to avoid ADDON_ACTION_FORBIDDEN.
if InCombatLockdown() then
    local _deferFrame = CreateFrame("Frame")
    _deferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    _deferFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        self:SetScript("OnEvent", nil)
        RegisterAllEvents()
    end)
else
    RegisterAllEvents()
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... == "MythicScoreboard" then
            MythicScoreboardDB = MythicScoreboardDB or { runs = {} }
            MythicScoreboardDB.runs = MythicScoreboardDB.runs or {}
            MythicScoreboardDB.personalBests = MythicScoreboardDB.personalBests or {}

            -- Initialize Minimap Icon
            SetupMinimapIcon()

            local s = MythicScoreboardDB.settings
            if not s then
                MythicScoreboardDB.settings = {}
                s = MythicScoreboardDB.settings
            end
            if s.autoResetMeter           == nil then s.autoResetMeter           = true  end
            if s.autoOpenOnComplete       == nil then s.autoOpenOnComplete       = true  end
            if s.historyLimit             == nil then s.historyLimit             = 10    end
            if s.trackedDifficulties      == nil then
                s.trackedDifficulties = {
                    mythicplus  = true,
                    mythic      = false,
                    heroic      = false,
                    normal      = false,
                    timewalking = false,
                    follower    = false,
                }
            end
            if s.showMobForces            == nil then s.showMobForces            = true  end
            if s.showMobForcesNameplates  == nil then s.showMobForcesNameplates  = true  end
            MythicScoreboardDB.mobForces = MythicScoreboardDB.mobForces or {}
            if not (C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable) then
                print("|cffff4444[MythicScoreboard]|r C_DamageMeter unavailable — requires WoW 12.0+.")
            end
            MS:BuildUI()
            local _, itype = GetInstanceInfo()
            if itype == "party" and MythicScoreboardDB.activeRun then
                MS:RestoreCurrentRun()
                C_Timer.After(0.2, function() MS:RefreshOverview() end)
            end
            print("|cff00ccff[MythicScoreboard]|r v" .. MS.version .. "  /sb to open.")
        end

    elseif event == "PLAYER_LEAVING_WORLD" then
        _reloading = IsLoggedIn() and true or false
        if not _reloading and MS.inDungeon then
            EndDungeonRun(false, false)
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        local justReloaded = _reloading
        _reloading = false
        local _, itype, diff = GetInstanceInfo()
        if MS.inDungeon then
            if justReloaded then
                MS:RebuildPetGUIDCache()
                C_Timer.After(1.0, function() MS:RebuildPetGUIDCache() end)
                C_Timer.After(3.0, function() MS:RebuildPetGUIDCache() end)
                C_Timer.After(6.0, function() MS:RebuildPetGUIDCache() end)
            elseif not (itype == "party" and IsTracked(diff)) then
                -- Don't kill an active M+ run on a zone transition.
                if not (MS.currentRun and (MS.currentRun.keystoneLevel or 0) > 0) then
                    EndDungeonRun(false, false)
                end
            end
        elseif itype == "party" and IsTracked(diff) and diff ~= MYTHIC_PLUS then
            C_Timer.After(0.5, function()
                if not MS.inDungeon then
                    local _, itype2, diff2 = GetInstanceInfo()
                    if itype2 == "party" and IsTracked(diff2) and diff2 ~= MYTHIC_PLUS then
                        AutoResetMeter(); StartDungeonRun()
                        MS:RebuildPetGUIDCache()
                        C_Timer.After(1.0, function() MS:RebuildPetGUIDCache() end)
                        C_Timer.After(3.0, function() MS:RebuildPetGUIDCache() end)
                    end
                end
            end)
        end

    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_DIFFICULTY_CHANGED" then
        if not MS.inDungeon then
            if _scheduleCheckActive then return end
            _scheduleCheckActive = true
        end
        local attempt, maxAttempts = 0, 6
        local function scheduleCheck()
            attempt = attempt + 1
            C_Timer.After(attempt * 0.4, function()
                if MS.inDungeon then _scheduleCheckActive = false; return end
                local _, itype, diff = GetInstanceInfo()
                if itype == "party" and IsTracked(diff) and diff ~= MYTHIC_PLUS then
                    _scheduleCheckActive = false
                    AutoResetMeter(); StartDungeonRun()
                    MS:RebuildPetGUIDCache()
                    C_Timer.After(1.0, function() MS:RebuildPetGUIDCache() end)
                    C_Timer.After(3.0, function() MS:RebuildPetGUIDCache() end)
                elseif attempt < maxAttempts and itype == "party" then
                    scheduleCheck()
                else
                    _scheduleCheckActive = false
                end
            end)
        end
        if MS.inDungeon then
            C_Timer.After(0.3, function()
                local _, itype, diff = GetInstanceInfo()
                if not (itype == "party" and IsTracked(diff)) then
                    if MS.currentRun and (MS.currentRun.keystoneLevel or 0) > 0 then
                        local mapID = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID
                            and C_ChallengeMode.GetActiveChallengeMapID()
                        if mapID then
                            return
                        elseif itype == "party" then
                            EndDungeonRun(false, false)
                        else
                            return
                        end
                    else
                        EndDungeonRun(false, false)
                    end
                end
            end)
        else
            scheduleCheck()
        end

    elseif event == "CHALLENGE_MODE_START" then
        local mapID = C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetActiveChallengeMapID()
        if not mapID then return end

        local newName  = GetDungeonName()
        local newLevel = GetKeystoneLevel()

        -- Same dungeon+level, unfinished run → resume rather than restart.
        if MS.currentRun and (MS.currentRun.keystoneLevel or 0) > 0
                and not MS.currentRun.completed
                and MS.currentRun.dungeonName == newName
                and MS.currentRun.keystoneLevel == newLevel then
            MS.inDungeon = true
            MS:RebuildPetGUIDCache()
            C_Timer.After(1.0, function() MS:RebuildPetGUIDCache() end)
            C_Timer.After(3.0, function() MS:RebuildPetGUIDCache() end)
            return
        end

        -- Commit any in-progress run before starting fresh.
        if MS.currentRun and (MS.currentRun.keystoneLevel or 0) > 0
                and not MS.currentRun.completed then
            if MS.inDungeon then
                EndDungeonRun(false, false)
            else
                MS:EndRun(false, false)
            end
        elseif MS.inDungeon then
            -- Discard a non-M+ placeholder started before the key was inserted.
            MS.inDungeon = false
            wipe(_deadUnits)
            MS:DiscardCurrentRun()
        end

        AutoResetMeter(); StartDungeonRun()
        wipe(MS._petGUIDToOwner)
        if MS._petNameToOwner then wipe(MS._petNameToOwner) end
        MS:RebuildPetGUIDCache()
        C_Timer.After(1.0, function() MS:RebuildPetGUIDCache() end)
        C_Timer.After(3.0, function() MS:RebuildPetGUIDCache() end)

    elseif event == "CHALLENGE_MODE_COMPLETED" then
        if MS.inDungeon and MS.currentRun then
            MS.inDungeon = false
            wipe(_deadUnits)

            -- CHALLENGE_MODE_COMPLETED carries no payload; the real numbers
            -- come from GetChallengeCompletionInfo (GetCompletionInfo is
            -- deprecated/removed as of 12.0.0).
            local totalTimeMs, onTime
            if C_ChallengeMode and C_ChallengeMode.GetChallengeCompletionInfo then
                local info = C_ChallengeMode.GetChallengeCompletionInfo()
                -- info.time/onTime default to 0/false before Blizzard populates them;
                -- only trust onTime once we have a real (nonzero) completion time.
                if info and info.time and info.time > 0 then
                    totalTimeMs, onTime = info.time, info.onTime
                end
            end

            local worldElapsed
            if totalTimeMs and totalTimeMs > 0 then
                worldElapsed = totalTimeMs / 1000
            else
                worldElapsed = GetWorldElapsedTime and select(2, GetWorldElapsedTime(1))
            end

            if worldElapsed and worldElapsed > 0 then
                MS.currentRun.endTime = MS.currentRun.startTime + worldElapsed
            else
                MS.currentRun.endTime = GetTime()
                worldElapsed = MS.currentRun.endTime - MS.currentRun.startTime
            end

            local inTime
            if onTime ~= nil then
                inTime = onTime
            else
                local timeLimit = MS.currentRun.keystoneTimeLimit
                if timeLimit and timeLimit > 0 and worldElapsed and worldElapsed > 0 then
                    inTime = worldElapsed <= timeLimit
                else
                    inTime = false
                end
            end

            MS.currentRun.completed = true
            MS.currentRun.inTime    = inTime
            -- Wait for SCENARIO_CRITERIA_UPDATE to confirm all criteria complete.
            MS.currentRun._pendingFinalize = true
            MS:SaveCurrentRun()
            local safetyRun = MS.currentRun
            C_Timer.After(3, function()
                if MS.currentRun == safetyRun and safetyRun._pendingFinalize then
                    safetyRun._pendingFinalize = nil
                    safetyRun.currentPct = 100
                    MS:FinalizeMythicPlusRun()
                end
            end)
        end

    elseif event == "CHALLENGE_MODE_RESET" then
        if MS.inDungeon then
            EndDungeonRun(false, false)
        elseif MS.currentRun and not MS.currentRun.completed then
            wipe(_deadUnits)
            MS:EndRun(false, false)
        end

    elseif event == "ENCOUNTER_START" then
        -- encounterID here is the dungeonEncounterID from EJ_GetEncounterInfoByIndex,
        -- not the journal's own encounter ID — they're different namespaces.
        local encounterID, bossName = ...
        if MS.inDungeon then MS:BossPull(bossName or "Boss", encounterID) end

    elseif event == "ENCOUNTER_END" then
        local encounterID, bossName, _, _, success = ...
        if MS.inDungeon then
            if success == 0 then
                MS:BossWipe(bossName or "Boss", encounterID)
            elseif success == 1 then
                local killedBoss = MS:BossKill(bossName or "Boss", encounterID)
                MS:SnapshotBossProgress(killedBoss)
                if GetDifficultyID() ~= MYTHIC_PLUS then
                    C_Timer.After(1.5, function()
                        if not MS.inDungeon or InCombatLockdown() then return end
                        MS:SnapshotFromDamageMeter()
                        if not MS.currentRun then return end
                        local dungName    = MS.currentRun.dungeonName or ""
                        local totalBosses = BOSS_COUNTS[dungName]
                        if not totalBosses then
                            local ejInstance = EJ_GetInstanceForMap
                                and MS.currentRun.challengeMapID
                                and EJ_GetInstanceForMap(MS.currentRun.challengeMapID)
                            if ejInstance and ejInstance > 0 then
                                local ok = pcall(EJ_SelectInstance, ejInstance)
                                if ok then
                                    local idx = 1; totalBosses = 0
                                    while EJ_GetEncounterInfoByIndex(idx, ejInstance) do
                                        totalBosses = totalBosses + 1; idx = idx + 1
                                    end
                                    if totalBosses == 0 then totalBosses = nil end
                                end
                            end
                        end
                        if totalBosses then
                            local killed = 0
                            for _, b in ipairs(MS.currentRun.bosses) do
                                if b.killTime then killed = killed + 1 end
                            end
                            if killed >= totalBosses then
                                MS.currentRun.completed = true
                                C_Timer.After(0.5, function()
                                    if MS:GetAutoOpenOnComplete() then
                                        MS:ShowScoreboard()
                                    end
                                end)
                            end
                        end
                    end)
                end
            end
        end

    elseif event == "SCENARIO_CRITERIA_UPDATE" then
        MS:UpdateEnemyForcesProgress()
        if MS.currentRun and MS.currentRun._pendingFinalize then
            local allDone = false
            if C_Scenario and C_Scenario.GetStepInfo then
                local ok, _, _, numCriteria = pcall(C_Scenario.GetStepInfo)
                if ok and numCriteria and numCriteria > 0 then
                    local completedCount = 0
                    for i = 1, numCriteria do
                        local ok2, info = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
                        if ok2 and info and info.completed then completedCount = completedCount + 1 end
                    end
                    allDone = (completedCount >= numCriteria)
                end
            end
            if allDone then
                MS.currentRun._pendingFinalize = nil
                MS.currentRun.currentPct = 100
                MS:FinalizeMythicPlusRun()
            end
        end

    elseif event == "PLAYER_DEAD" then
        if MS.inDungeon then HandleUnitDied() end

    elseif event == "GROUP_ROSTER_UPDATE" then
        MS:InvalidateGroupUnits()
        SyncRoster(); MS:PopulateAll()
        MS:PopulateRolesAndScores()
        MS:RebuildPetGUIDCache()
        C_Timer.After(2.0, function() MS:RebuildPetGUIDCache() end)
        if MS.currentRun and (MS.currentRun.keystoneLevel or 0) > 0
                and not MS.currentRun.completed
                and GetNumGroupMembers() == 0 then
            if MS.inDungeon then
                EndDungeonRun(false, false)
            else
                MS:EndRun(false, false)
            end
            return
        end
        C_Timer.After(2.0, function()
            if MS.RefreshOverview and MS.sbFrameVisible and MS.sbFrameVisible() then
                MS:RefreshOverview()
            end
        end)

    elseif event == "UNIT_PET" then
        -- Read the pet GUID immediately — this is the window before any lockdown.
        local ownerUnit = ...
        if ownerUnit then
            local petUnit = ownerUnit .. "pet"
            if UnitExists(petUnit) then
                local ok, petGUID = pcall(UnitGUID, petUnit)
                if ok and petGUID and not (_issecret and _issecret(petGUID))
                        and type(petGUID) == "string"
                        and (petGUID:find("^Pet%-") or petGUID:find("^Creature%-")) then
                    local ownerName = UnitName(ownerUnit)
                    if ownerName and not (_issecret and _issecret(ownerName)) then
                        MS._petGUIDToOwner[petGUID] = MS.ShortName(ownerName)
                    end
                end
            end
        end
        MS:RebuildPetGUIDCache()
        C_Timer.After(0.5, function() MS:RebuildPetGUIDCache() end)
        C_Timer.After(1.5, function() MS:RebuildPetGUIDCache() end)

    elseif event == "ENCOUNTER_LOOT_RECEIVED" then
        local _, itemID, itemLink, _, playerName = ...

        if not itemID then
            return
        end

        local targetRun = GetLootTargetRun()
        if not targetRun then
            return
        end

        ----------------------------------------------------------------
        -- Resolve the item name only for correlation / display.
        -- The itemLink itself remains authoritative.
        ----------------------------------------------------------------

        local itemName

        if itemLink then
            itemName = C_Item.GetItemInfo(itemLink)
        end

        if not itemName then
            itemName = C_Item.GetItemInfo(itemID)
        end

        ----------------------------------------------------------------
        -- CASE 1:
        -- ENCOUNTER_LOOT_RECEIVED gives us a real player name.
        ----------------------------------------------------------------

        if playerName
            and playerName ~= ""
            and playerName ~= "Unknown"
        then
            local name = MS.ShortName(playerName)

            if targetRun.players[name] then

                if itemName then
                    FindPendingChatLoot(
                        targetRun,
                        itemName,
                        name
                    )
                end

                --------------------------------------------------------
                -- IMPORTANT:
                -- Store the authoritative encounter hyperlink directly.
                -- Do NOT send it through TryResolveLoot().
                --------------------------------------------------------

                if itemLink then
                    if not IsEligibleLoot(itemID, itemLink) then
                        return
                    end

                    ApplyLootToPlayer(
                        targetRun,
                        name,
                        itemName,
                        itemLink,
                        C_Item.GetItemIconByID
                            and C_Item.GetItemIconByID(itemID),
                        true,
                        nil,
                        nil
                    )
                end

                return
            end

            return
        end

        ----------------------------------------------------------------
        -- CASE 2:
        -- ENCOUNTER_LOOT_RECEIVED says "Unknown".
        --
        -- CHAT_MSG_LOOT knows who received the item, so correlate using
        -- the item name.
        ----------------------------------------------------------------

        if itemName then
            local pending =
                FindPendingChatLoot(
                    targetRun,
                    itemName
                )

            if pending then
                local name = pending.playerName

                if name and targetRun.players[name] then

                    ----------------------------------------------------
                    -- The encounter hyperlink wins.
                    ----------------------------------------------------

                    if itemLink then
                        ApplyLootToPlayer(
                            targetRun,
                            name,
                            itemName,
                            itemLink,
                            C_Item.GetItemIconByID
                                and C_Item.GetItemIconByID(itemID),
                            true,
                            nil,
                            pending.qualityColor
                        )
                    end

                    return
                end
            end
        end

        ----------------------------------------------------------------
        -- CASE 3:
        -- Encounter arrived before CHAT, or item name isn't cached yet.
        ----------------------------------------------------------------

        AddPendingEncounterLoot(
            targetRun,
            itemID,
            itemLink,
            itemName
        )

        ----------------------------------------------------------------
        -- If we have an itemLink but no item name yet, give the client
        -- a little time to populate it.
        ----------------------------------------------------------------

        if itemLink and not itemName then

            local function RetryEncounterName(attempt)
                local resolvedName =
                    C_Item.GetItemInfo(itemLink)

                if resolvedName then

                    local pending =
                        FindPendingChatLoot(
                            targetRun,
                            resolvedName
                        )

                    if pending then
                        local name = pending.playerName

                        if name and targetRun.players[name] then

                            FindPendingEncounterLoot(
                                targetRun,
                                resolvedName
                            )

                            ApplyLootToPlayer(
                                targetRun,
                                name,
                                resolvedName,
                                itemLink,
                                C_Item.GetItemIconByID
                                    and C_Item.GetItemIconByID(itemID),
                                true,
                                nil,
                                pending.qualityColor
                            )
                        end

                        return
                    end

                    ----------------------------------------------------
                    -- Update the pending encounter record with its name.
                    ----------------------------------------------------

                    for i = #MS.pendingLoot, 1, -1 do
                        local p = MS.pendingLoot[i]

                        if p.source == "ENCOUNTER"
                            and p.targetRun == targetRun
                            and p.itemID == itemID
                        then
                            p.itemName = resolvedName
                            break
                        end
                    end

                    return
                end

                if attempt < 8 then
                    C_Timer.After(0.4, function()
                        RetryEncounterName(attempt + 1)
                    end)
                end
            end

            RetryEncounterName(1)
        end

    elseif event == "CHAT_MSG_LOOT" then
        local message, playerName = ...

        if not message then
            return
        end

        local targetRun = GetLootTargetRun()
        if not targetRun then
            return
        end

        ----------------------------------------------------------------
        -- Extract hyperlink and/or item name.
        ----------------------------------------------------------------

        local itemLink = message:match(
            "(|c%x%x%x%x%x%x%x%x|Hitem:.-|h%[.-%]|h|r)"
        )

        local itemName =
            message:match("%[(.-)%]")

        if not itemLink and not itemName then
            return
        end

        ----------------------------------------------------------------
        -- Only a hyperlink literally contained in CHAT_MSG_LOOT is
        -- authoritative.
        ----------------------------------------------------------------

        local isConfirmedLink = itemLink ~= nil

        ----------------------------------------------------------------
        -- If CHAT only supplied the item name, resolve it as a fallback.
        -- This link remains UNCONFIRMED.
        ----------------------------------------------------------------

        if not itemLink and itemName then
            local _, resolvedLink =
                GetItemInfo(itemName)

            if resolvedLink then
                itemLink = resolvedLink
            end
        end

        ----------------------------------------------------------------
        -- Fallback chat color.
        ----------------------------------------------------------------

        local qualityColor

        if not itemLink then
            local hexColor =
                message:match("|c(%x%x%x%x%x%x%x%x)")

            if hexColor then
                local r =
                    tonumber(hexColor:sub(3, 4), 16) or 255

                local g =
                    tonumber(hexColor:sub(5, 6), 16) or 255

                local b =
                    tonumber(hexColor:sub(7, 8), 16) or 255

                qualityColor = {
                    r / 255,
                    g / 255,
                    b / 255
                }
            end
        end

        ----------------------------------------------------------------
        -- Determine recipient.
        ----------------------------------------------------------------

        local recipient =
            message:match("|Hplayer:([^:|]+)")
            or message:match("^([^%[]+) receives loot:")
            or message:match("^([^%[]+) receives item:")
            or message:match("^([^%[]+) won:")

        if recipient then
            recipient =
                recipient:gsub("^%s+", "")
                        :gsub("%s+$", "")
        end

        if not recipient
            and (
                message:find("^You receive ")
                or message:find("^You won:")
            )
        then
            recipient = UnitName("player")
        end

        if not recipient or recipient == "" then
            recipient =
                playerName
                and playerName ~= ""
                and playerName
                or UnitName("player")
        end

        local name = MS.ShortName(recipient)

        if not targetRun.players[name] then
            return
        end

        ----------------------------------------------------------------
        -- Record CHAT observation.
        ----------------------------------------------------------------

        AddPendingChatLoot(
            targetRun,
            name,
            itemName,
            itemLink,
            qualityColor
        )

        ----------------------------------------------------------------
        -- If ENCOUNTER arrived first, use its authoritative link now.
        ----------------------------------------------------------------

        if itemName then
            local pendingEncounter =
                FindPendingEncounterLoot(
                    targetRun,
                    itemName
                )

            if pendingEncounter then

                if pendingEncounter.itemLink then
                    TryResolveLoot(
                        targetRun,
                        name,
                        pendingEncounter.itemLink,
                        itemName,
                        true,
                        qualityColor
                    )

                    return

                elseif pendingEncounter.itemID then
                    TryResolveLoot(
                        targetRun,
                        name,
                        pendingEncounter.itemID,
                        itemName,
                        false,
                        qualityColor
                    )

                    return
                end
            end
        end

        ----------------------------------------------------------------
        -- No ENCOUNTER result yet.
        --
        -- Use CHAT as a fallback. If this is only a name-resolved link,
        -- it remains unconfirmed and can later be replaced by the
        -- authoritative ENCOUNTER link.
        ----------------------------------------------------------------

        if itemLink then
            TryResolveLoot(
                targetRun,
                name,
                itemLink,
                itemName,
                isConfirmedLink,
                qualityColor
            )
        else
            TryResolveLoot(
                targetRun,
                name,
                itemName,
                itemName,
                false,
                qualityColor
            )
        end

    -- elseif event == "UNIT_AURA" then
    --     if not MS.inDungeon or not MS.currentRun then return end

    --     local unit = ...
    --     if not unit or not UnitExists(unit) then return end

    --     -- We only care about enemy nameplates.
    --     if not unit:find("^nameplate") then return end
    --     if UnitIsFriend("player", unit) then return end

    --     -- Use the public nameplate token as the tracker key. Enemy GUIDs are
    --     -- secret in Midnight M+ and cannot be used to index addon tables.
    --     local cast = _trackedEnemyCasts[unit]
    --     if not cast or cast.stopped then return end

    --     local now = GetTime()

    --     -- If the cast has already naturally finished, don't associate a stun
    --     -- with it.
    --     if now >= (cast.endMS / 1000) - 0.10 then
    --         return
    --     end

    --     if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end

    --     -- We need to inspect all harmful auras because the stun may not be aura 1.
    --     local stunOwner, stunSpellID

    --     for auraIndex = 1, 40 do
    --         local aura = C_UnitAuras.GetAuraDataByIndex(unit, auraIndex, "HARMFUL")
    --         if not aura then break end

    --         local spellID = aura.spellId
    --         local spellName = aura.name
    --         if IsTrackedStunAura(spellID, spellName) then
    --             local sourceUnit = aura.sourceUnit
    --             local owner = ResolveCCOwner(sourceUnit)

    --             if MS.debugInterruptLogging then
    --                 local sourceLabel = (sourceUnit and not IsSecret(sourceUnit))
    --                     and sourceUnit or "unknown/secret"
    --                 print("|cff00ccff[MythicScoreboard DEBUG]|r Stun aura "
    --                     .. tostring(spellID) .. " on " .. unit
    --                     .. "; source: " .. sourceLabel
    --                     .. "; owner: " .. (owner or "unresolved"))
    --             end

    --             if owner then
    --                 stunOwner = owner
    --                 stunSpellID = spellID
    --                 break
    --             end
    --         end
    --     end

    --     if not stunOwner then return end

    --     -- We have seen a qualifying stun on an enemy that was actively casting.
    --     --
    --     -- Don't immediately count it: the cast has to actually disappear early.
    --     if not cast.pendingStun then
    --         cast.pendingStun = {
    --             owner = stunOwner,
    --             spellID = stunSpellID,
    --             time = now,
    --         }
    --     end
    end
end)

-- Poll C_DamageMeter every 2s (DAMAGE_METER_COMBAT_SESSION_UPDATED is blocked in M+).
C_Timer.NewTicker(2, function()
    local ok, err = pcall(HandleDamageMeterUpdated)
    if not ok then
        print("|cffff4444[MythicScoreboard]|r Meter poll error: " .. tostring(err))
    end
end)

-- Poll for stun tracking
C_Timer.NewTicker(0.1, function()
    if not MS.inDungeon then return end

    local ok, err = pcall(function()
        --ScanEnemyCasts()
        --CheckStunInterrupts()
    end)

    if not ok then
        print("|cffff4444[MythicScoreboard]|r Stun tracker error: " .. tostring(err))
    end
end)

-- Coalesce SaveCurrentRun writes to at most once per second.
C_Timer.NewTicker(1, function()
    if MS._saveDirty then MS:FlushSave() end
end)

-- Poll death state every 0.75s (UNIT_DIED via CLEU is blocked in M+).
C_Timer.NewTicker(0.75, function()
    if not MS.inDungeon then return end
    local ok, err = pcall(HandleUnitDied)
    if not ok then
        print("|cffff4444[MythicScoreboard]|r Death poll error: " .. tostring(err))
    end
end)





-- ============================================================
-- TEMPORARY LOOT DEBUG FRAME
-- Replace the previous temporary loot debug block with this.
-- Remove this entire block when debugging is finished.
-- ============================================================

local MS_LootDebugFrame =
    CreateFrame("Frame", "MS_LootDebugFrame", UIParent, "BackdropTemplate")

MS_LootDebugFrame:SetSize(450, 500)
MS_LootDebugFrame:SetPoint("CENTER")
MS_LootDebugFrame:SetMovable(true)
MS_LootDebugFrame:EnableMouse(true)
MS_LootDebugFrame:RegisterForDrag("LeftButton")

MS_LootDebugFrame:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)

MS_LootDebugFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)

MS_LootDebugFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 16,
    insets = {
        left = 4,
        right = 4,
        top = 4,
        bottom = 4,
    },
})

local title = MS_LootDebugFrame:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontNormal"
)

title:SetPoint("TOPLEFT", 12, -10)
title:SetText("MythicScoreboard Loot Debug")

-- ============================================================
-- Stored debug lines
-- ============================================================

local debugLines = {}

local function MS_LootDebugBuildText()
    return table.concat(debugLines, "\n")
end

local debugOutput

function MS_LootDebugPrint(...)
    local parts = {}

    for i = 1, select("#", ...) do
        local value = select(i, ...)

        if value == nil then
            value = "nil"
        end

        parts[#parts + 1] = tostring(value)
    end

    local line = table.concat(parts, " ")

    debugLines[#debugLines + 1] = line

    debugOutput:AddMessage(line)

    MS_LootDebugFrame:Show()
end

-- ============================================================
-- Close button
-- ============================================================

local close = CreateFrame(
    "Button",
    nil,
    MS_LootDebugFrame,
    "UIPanelCloseButton"
)

close:SetPoint("TOPRIGHT", 2, 2)

-- ============================================================
-- Clear button
-- ============================================================

local clearButton = CreateFrame(
    "Button",
    nil,
    MS_LootDebugFrame,
    "UIPanelButtonTemplate"
)

clearButton:SetSize(80, 24)
clearButton:SetPoint("TOPRIGHT", close, "TOPLEFT", -4, 0)
clearButton:SetText("Clear")

clearButton:SetScript("OnClick", function()
    debugLines = {}
    debugOutput:Clear()
end)

-- ============================================================
-- Copy button
-- ============================================================

local copyButton = CreateFrame(
    "Button",
    nil,
    MS_LootDebugFrame,
    "UIPanelButtonTemplate"
)

copyButton:SetSize(80, 24)
copyButton:SetPoint("TOPRIGHT", clearButton, "TOPLEFT", -4, 0)
copyButton:SetText("Copy All")

-- ============================================================
-- Scroll frame
-- ============================================================

local scrollFrame = CreateFrame(
    "ScrollFrame",
    nil,
    MS_LootDebugFrame,
    "UIPanelScrollFrameTemplate"
)

scrollFrame:SetPoint("TOPLEFT", 12, -40)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 12)

-- Actual text area inside the scroll frame
debugOutput = CreateFrame(
    "ScrollingMessageFrame",
    nil,
    scrollFrame
)

debugOutput:SetWidth(830)
debugOutput:SetHeight(430)

debugOutput:SetFontObject(GameFontHighlightSmall)
debugOutput:SetJustifyH("LEFT")
debugOutput:SetFading(false)
debugOutput:SetMaxLines(5000)
debugOutput:SetInsertMode("BOTTOM")
debugOutput:SetHyperlinksEnabled(true)

scrollFrame:SetScrollChild(debugOutput)

-- ============================================================
-- Mouse wheel scrolling
-- ============================================================

debugOutput:EnableMouse(true)
debugOutput:EnableMouseWheel(true)

debugOutput:SetScript("OnMouseWheel", function(self, delta)

    local current = scrollFrame:GetVerticalScroll()
    local range = scrollFrame:GetVerticalScrollRange()

    local step = 40

    if delta > 0 then
        scrollFrame:SetVerticalScroll(
            math.max(0, current - step)
        )
    else
        scrollFrame:SetVerticalScroll(
            math.min(range, current + step)
        )
    end
end)

-- Also allow the scroll frame itself to receive the wheel.
scrollFrame:EnableMouseWheel(true)

scrollFrame:SetScript("OnMouseWheel", function(self, delta)

    local current = self:GetVerticalScroll()
    local range = self:GetVerticalScrollRange()

    local step = 40

    if delta > 0 then
        self:SetVerticalScroll(
            math.max(0, current - step)
        )
    else
        self:SetVerticalScroll(
            math.min(range, current + step)
        )
    end
end)

-- ============================================================
-- Hyperlink clicking
-- ============================================================

debugOutput:SetScript("OnHyperlinkClick", function(
    self,
    link,
    text,
    button
)
    if ChatFrameUtil
        and ChatFrameUtil.HandleHyperlink
    then
        ChatFrameUtil.HandleHyperlink(
            self,
            link,
            text,
            button
        )
    end
end)

-- ============================================================
-- Copy window
-- ============================================================

local copyFrame =
    CreateFrame("Frame", "MS_LootDebugCopyFrame", UIParent, "BackdropTemplate")

copyFrame:SetSize(850, 500)
copyFrame:SetPoint("CENTER")
copyFrame:SetFrameStrata("DIALOG")

copyFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 16,
    insets = {
        left = 4,
        right = 4,
        top = 4,
        bottom = 4,
    },
})

copyFrame:Hide()

local copyTitle = copyFrame:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontNormal"
)

copyTitle:SetPoint("TOPLEFT", 12, -10)
copyTitle:SetText("MythicScoreboard Loot Debug — Copy")

local copyClose = CreateFrame(
    "Button",
    nil,
    copyFrame,
    "UIPanelCloseButton"
)

copyClose:SetPoint("TOPRIGHT", 2, 2)

local copyInstructions = copyFrame:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlightSmall"
)

copyInstructions:SetPoint("TOPLEFT", 12, -35)
copyInstructions:SetText(
    "Click inside the text, press Ctrl+A, then Ctrl+C."
)

local copyScroll =
    CreateFrame(
        "ScrollFrame",
        nil,
        copyFrame,
        "UIPanelScrollFrameTemplate"
    )

copyScroll:SetPoint("TOPLEFT", 12, -60)
copyScroll:SetPoint("BOTTOMRIGHT", -30, 12)

local copyEditBox = CreateFrame(
    "EditBox",
    nil,
    copyScroll
)

copyEditBox:SetMultiLine(true)
copyEditBox:SetAutoFocus(false)
copyEditBox:SetFontObject(ChatFontNormal)
copyEditBox:SetJustifyH("LEFT")
copyEditBox:SetJustifyV("TOP")
copyEditBox:SetWidth(790)
copyEditBox:SetTextColor(1, 1, 1, 1)

copyScroll:SetScrollChild(copyEditBox)

copyButton:SetScript("OnClick", function()

    copyEditBox:SetText(
        MS_LootDebugBuildText()
    )

    copyFrame:Show()

    copyEditBox:SetFocus()
    copyEditBox:HighlightText()
end)

-- ============================================================
-- Slash commands
-- ============================================================

SLASH_MSLOOTDEBUG1 = "/mslootdebug"

SlashCmdList.MSLOOTDEBUG = function()

    if MS_LootDebugFrame:IsShown() then
        MS_LootDebugFrame:Hide()
    else
        MS_LootDebugFrame:Show()
    end
end

SLASH_MSLOOTDEBUGCLEAR1 = "/mslootdebugclear"

SlashCmdList.MSLOOTDEBUGCLEAR = function()

    debugLines = {}
    debugOutput:Clear()
end

-- ============================================================
-- Event capture
-- ============================================================

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("CHAT_MSG_LOOT")
eventFrame:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")

eventFrame:SetScript("OnEvent", function(self, event, ...)

    if event == "CHAT_MSG_LOOT" then

        local message, playerName = ...

        local isItemLoot =
            message
            and (
                message:find("^You receive loot:")
                or message:find("^You won:")
                or message:find(" receives loot:")
                or message:find(" won:")
            )

        if not isItemLoot then
            return
        end

        local itemLink = message:match(
            "(|c%x%x%x%x%x%x%x%x|Hitem:.-|h%[.-%]|h|r)"
        )

        local itemName = message:match("%[(.-)%]")

        MS_LootDebugPrint(
            "|cffff9900========== CHAT_MSG_LOOT =========="
        )

        MS_LootDebugPrint(
            "Message:",
            message
        )

        MS_LootDebugPrint(
            "Player arg:",
            playerName or "nil"
        )

        MS_LootDebugPrint(
            "Extracted link:",
            itemLink or "nil"
        )

        MS_LootDebugPrint(
            "Extracted name:",
            itemName or "nil"
        )

        MS_LootDebugPrint(
            "Full event arguments:"
        )

        for i = 1, 10 do

            local value = select(i, ...)

            if value ~= nil then
                MS_LootDebugPrint(
                    "  arg" .. i .. ":",
                    value
                )
            end
        end

        MS_LootDebugPrint(
            "|cffff9900================================"
        )

    elseif event == "ENCOUNTER_LOOT_RECEIVED" then

        local encounterID,
              itemID,
              itemLink,
              quantity,
              playerName = ...

        MS_LootDebugPrint(
            "|cff00ff00====== ENCOUNTER_LOOT_RECEIVED ======"
        )

        MS_LootDebugPrint(
            "Encounter ID:",
            encounterID or "nil"
        )

        MS_LootDebugPrint(
            "Item ID:",
            itemID or "nil"
        )

        MS_LootDebugPrint(
            "Item Link:",
            itemLink or "nil"
        )

        MS_LootDebugPrint(
            "Quantity:",
            quantity or "nil"
        )

        MS_LootDebugPrint(
            "Player:",
            playerName or "nil"
        )

        MS_LootDebugPrint(
            "Full event arguments:"
        )

        for i = 1, 10 do

            local value = select(i, ...)

            if value ~= nil then
                MS_LootDebugPrint(
                    "  arg" .. i .. ":",
                    value
                )
            end
        end

        MS_LootDebugPrint(
            "|cff00ff00========================================"
        )
    end
end)

MS_LootDebugFrame:Hide()
copyFrame:Hide()