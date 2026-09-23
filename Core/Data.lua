local _abs   = math.abs
local _fmt   = string.format
local _floor = math.floor
local _min   = math.min
local _max   = math.max
local _ins   = table.insert
local _rem   = table.remove

local MS = _G["MythicScoreboard"]

MS._petGUIDToOwner = MS._petGUIDToOwner or {}
MS._petNameToOwner = MS._petNameToOwner or {}

local _issecret = issecretvalue  -- nil on pre-12.0 clients

-- Uses GetWorldElapsedTime for active M+ (starts at 0 post-countdown).
-- Falls back to GetTime() delta for non-M+.
local function GetCurrentElapsed(run)
    if not run then return 0 end
    if run.endTime and run.endTime > 0 then
        local dur = run.endTime - (run.startTime or 0)
        if dur > 0 and dur < 7200 then return dur end
        -- Derive from latest boss kill if end timestamp looks wrong.
        if run.bosses and #run.bosses > 0 then
            local latest = 0
            for _, b in ipairs(run.bosses) do
                if (b.killTime or 0) > latest then latest = b.killTime end
            end
            if latest > 0 then return latest + 30 end
        end
        return 0
    end
    if (run.keystoneLevel or 0) > 0 then
        if GetWorldElapsedTime then
            local worldElapsed = select(2, GetWorldElapsedTime(1))
            if worldElapsed and worldElapsed > 0 then return worldElapsed end
        end
        return 0
    end
    return _max(0, GetTime() - run.startTime)
end

-- M+ time limits, used when C_ChallengeMode.GetDeadlineExpiration() is unavailable.
MS.DUNGEON_TIMERS = {
    -- Season 2 (patch 12.1)
    ["Altar of Fangs"]         = 30 * 60,
    ["Murder Row"]             = 34 * 60,
    ["Den of Nalorakk"]        = 32 * 60,
    ["The Blinding Vale"]      = 31 * 60,
    ["Voidscar Arena"]         = 30 * 60,
    ["King's Rest"]            = 33 * 60,
    ["Temple of Sethraliss"]   = 33 * 60,
    ["Ruby Life Pools"]        = 28 * 60,
    -- Season 1 (kept for saved-run display)
    ["Magisters' Terrace"]     = 34 * 60,
    ["Maisara Caverns"]        = 33 * 60,
    ["Nexus-Point Xenas"]      = 30 * 60,
    ["Windrunner Spire"]       = 33 * 60,
    ["Algeth'ar Academy"]      = 31 * 60,
    ["Pit of Saron"]           = 30 * 60,
    ["Seat of the Triumvirate"]= 34 * 60,
    ["Skyreach"]               = 28 * 60,
}

local MYTHIC_PLUS = 8

local function ShortName(name) return name:match("^([^%-]+)") or name end
MS.ShortName = ShortName

local _groupUnits      = {}
local _groupUnitsDirty = true

function MS:RebuildGroupUnitsCache()
    wipe(_groupUnits)
    _groupUnits[1] = "player"
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, GetNumGroupMembers() do _groupUnits[#_groupUnits + 1] = prefix .. i end
    _groupUnitsDirty = false
end

function MS:GroupUnits()
    if _groupUnitsDirty then self:RebuildGroupUnitsCache() end
    return _groupUnits
end

function MS:InvalidateGroupUnits()
    _groupUnitsDirty = true
end

local DUPLICATE_DEATH_WINDOW = 2

function MS:IsDupDeath(p, now)
    return _abs((p._lastDeathTime or -999) - now) < DUPLICATE_DEATH_WINDOW
end

local function NewRunData()
    return {
        dungeonName          = "",
        keystoneLevel        = 0,
        difficultyID         = 0,
        difficultyLabel      = "",
        startTime            = 0,
        endTime              = 0,
        completed            = false,
        inTime               = false,
        affixes              = {},
        players              = {},
        bosses               = {},
        activeBoss           = nil,
        deathPenaltySeconds  = 0,
        currentPct           = nil,
        _wallClockStart      = nil,
        challengeMapID       = nil,  -- UiMapID for EJ icon resolution
    }
end

local function NewPlayerStats(name, classToken, guid)
    return {
        name                 = name,
        class                = classToken or "UNKNOWN",
        guid                 = guid,
        role                 = "",
        damageDone           = 0,
        healingDone          = 0,
        damageTaken          = 0,
        avoidableDamageTaken = 0,
        dps                  = 0,
        hps                  = 0,
        interrupts           = 0,
        interruptEvents      = {},
        stunInterrupts       = 0,
        dispels              = 0,
        deaths               = 0,
        deathEvents          = {},
        mythicScore          = 0,
        itemLevel            = 0,
        deathRecapID         = 0,
        specID               = nil,
    }
end

MS.currentRun      = nil
MS.inDungeon       = false
MS.scoreCache      = {}
MS.NewPlayerStats  = NewPlayerStats
MS.debugInterruptLogging = false -- Temporary stun-tracker diagnostic.

local VALID_CLASS = {
    WARRIOR=true, PALADIN=true,  HUNTER=true,  ROGUE=true,   PRIEST=true,
    DEATHKNIGHT=true, SHAMAN=true, MAGE=true,  WARLOCK=true, MONK=true,
    DRUID=true, DEMONHUNTER=true, EVOKER=true,
}
MS.ValidClass = VALID_CLASS

-- Prints only when a player's tracked interrupt totals change, so this remains
-- useful during a run without spamming chat on every damage-meter poll.
function MS:DebugLogInterruptCounts()
    if not self.debugInterruptLogging or not self.currentRun then return end
    self._debugInterruptCounts = self._debugInterruptCounts or {}
    for name, p in pairs(self.currentRun.players) do
        local interrupts = p.interrupts or 0
        local stuns      = p.stunInterrupts or 0
        local previous   = self._debugInterruptCounts[name]
        if not previous or previous.interrupts ~= interrupts or previous.stuns ~= stuns then
            self._debugInterruptCounts[name] = { interrupts = interrupts, stuns = stuns }
            print(_fmt("|cff00ccff[MythicScoreboard DEBUG]|r %s -- Interrupts: %d, Stun interrupts: %d",
                name, interrupts, stuns))
        end
    end
end

local SYNTH_INTERRUPT_MIN_WINDOW = 2

-- Fills in synthetic interruptEvent timestamps from the C_DamageMeter count.
-- Distributes events evenly across the current boss window with per-player
-- jitter to avoid stacking timeline markers.
function MS:_BackfillSyntheticInterrupts(run)
    run = run or self.currentRun
    if not run then return end
    local now = GetCurrentElapsed(run)

    local bossAnchor = 0
    if run.bosses then
        for _, boss in ipairs(run.bosses) do
            local pt = boss.pullTime or 0
            if pt <= now and pt > bossAnchor then bossAnchor = pt end
        end
    end

    local function playerJitter(name)
        local h = 0
        for i = 1, #name do h = h + name:byte(i) end
        return ((h % 31) / 30 - 0.5) * 6.0
    end

    for _, p in pairs(run.players) do
        p.interruptEvents = p.interruptEvents or {}
        local recorded = #p.interruptEvents
        local total    = p.interrupts or 0
        local delta    = total - recorded
        if delta > 0 then
            local tStart = bossAnchor
            if recorded > 0 then
                tStart = _max(tStart, p.interruptEvents[recorded].time)
            end
            local window = now - tStart
            if window < SYNTH_INTERRUPT_MIN_WINDOW then
                tStart = _max(0, now - SYNTH_INTERRUPT_MIN_WINDOW)
                window = now - tStart
            end
            local step   = window / (delta + 1)
            local jitter = playerJitter(p.name or "")
            for i = 1, delta do
                local t = tStart + step * i + jitter
                _ins(p.interruptEvents, { time = _max(tStart, _min(now, t)), spell = "Unknown" })
            end
        end
    end
end

-- Inserts at index 1 so the newest run is always first.
function MS:_CommitRunToHistory(run)
    if not (MythicScoreboardDB and MythicScoreboardDB.runs) then return end
    local cap = MythicScoreboardDB.settings and MythicScoreboardDB.settings.historyLimit or 10
    cap = _max(1, _min(30, cap))
    local serialized = self:SerializeRun(run)

    -- A Mythic (23) placeholder can be committed during the short period
    -- before CHALLENGE_MODE_START supplies the keystone data.  Once its M+
    -- run completes, discard that short abandoned placeholder even when its
    -- start is more than the normal two-minute duplicate window away.
    if serialized.completed and serialized.difficultyID == MYTHIC_PLUS
            and (serialized.keystoneLevel or 0) > 0 then
        for i = _min(6, #MythicScoreboardDB.runs), 1, -1 do
            local existing = MythicScoreboardDB.runs[i]
            local isPlaceholder = existing and existing.difficultyID == 23
                and (existing.keystoneLevel or 0) == 0 and not existing.completed
            local duration = existing and (existing.endTime or 0) - (existing.startTime or 0)
            if isPlaceholder and existing.dungeonName == serialized.dungeonName
                    and duration >= 0 and duration <= 5 * 60
                    and (existing.endTime or 0) <= (serialized.endTime or 0) then
                _rem(MythicScoreboardDB.runs, i)
            end
        end
    end

    local function IsSameRun(a, b)
        if not (a and b) then return false end
        if (a.dungeonName or "") ~= (b.dungeonName or "") then return false end

        local startClose = _abs((a.startTime or 0) - (b.startTime or 0)) <= 120
        local endClose   = _abs((a.endTime or 0) - (b.endTime or 0)) <= 120
        local wallEqual  = (a._wallClockStart and b._wallClockStart
                            and a._wallClockStart == b._wallClockStart)

        local sameKey = (a.keystoneLevel or 0) == (b.keystoneLevel or 0)
                     and (a.difficultyID or 0) == (b.difficultyID or 0)
        if sameKey then
            return startClose or endClose or wallEqual
        end

        -- Handle pre-key Mythic placeholder (difficulty 23, keystone 0)
        -- that can race with the actual Mythic+ run commit.
        local aIsPlaceholder = (a.difficultyID == 23 and (a.keystoneLevel or 0) == 0 and not a.completed)
        local bIsPlaceholder = (b.difficultyID == 23 and (b.keystoneLevel or 0) == 0 and not b.completed)
        local aIsMPlus       = (a.difficultyID == 8 and (a.keystoneLevel or 0) > 0)
        local bIsMPlus       = (b.difficultyID == 8 and (b.keystoneLevel or 0) > 0)

        if (aIsPlaceholder and bIsMPlus) or (bIsPlaceholder and aIsMPlus) then
            return startClose or wallEqual
        end

        return false
    end

    -- Guard against double-commit races (abandon fallback + completion finalize)
    -- by merging with any recent matching run, not only the head entry.
    for i = 1, _min(6, #MythicScoreboardDB.runs) do
        local existing = MythicScoreboardDB.runs[i]
        if IsSameRun(existing, serialized) then
            if serialized.completed and not existing.completed then
                MythicScoreboardDB.runs[i] = serialized
            elseif existing.completed and not serialized.completed then
                -- Keep the completed version.
            else
                -- Same completion state: keep the one with the latest end time.
                if (serialized.endTime or 0) >= (existing.endTime or 0) then
                    MythicScoreboardDB.runs[i] = serialized
                end
            end
            return
        end
    end

    _ins(MythicScoreboardDB.runs, 1, serialized)
    while #MythicScoreboardDB.runs > cap do _rem(MythicScoreboardDB.runs) end
end

-- Drops the current run without saving. Used to discard the Mythic (diff=23)
-- placeholder that's created while waiting for a keystone to be inserted.
function MS:DiscardCurrentRun()
    self.currentRun = nil
    self.inDungeon  = false
    if MythicScoreboardDB then MythicScoreboardDB.activeRun = nil end
end

-- Announces a PB or first clear. Must be called after _CommitRunToHistory.
function MS:_AnnouncePB(run)
    if not (run.completed and run.inTime and (run.keystoneLevel or 0) > 0) then return end
    if not MythicScoreboardDB then return end
    local thisDur = self:GetRunDuration(run)
    local key = (run.dungeonName or "") .. ":" .. run.keystoneLevel

    MythicScoreboardDB.personalBests = MythicScoreboardDB.personalBests or {}
    local prevBest = MythicScoreboardDB.personalBests[key]
    if not prevBest and MythicScoreboardDB.runs then
        for i = 2, #MythicScoreboardDB.runs do
            local r = MythicScoreboardDB.runs[i]
            if r.completed and r.inTime
                    and r.dungeonName == run.dungeonName
                    and (r.keystoneLevel or 0) == run.keystoneLevel then
                local dur = (r.endTime or 0) - (r.startTime or 0)
                if dur > 0 and (not prevBest or dur < prevBest) then prevBest = dur end
            end
        end
    end

    local timeStr = self:FormatTime(thisDur)
    if not prevBest or thisDur < prevBest then
        MythicScoreboardDB.personalBests[key] = thisDur
        if not prevBest then
            print(_fmt("|cff00ccff[MythicScoreboard]|r |cffffcc00** First recorded clear!|r %s +%d -- %s",
                run.dungeonName, run.keystoneLevel, timeStr))
        else
            print(_fmt("|cff00ccff[MythicScoreboard]|r |cffffcc00** New personal best!|r %s +%d -- %s |cff888888(-%s)|r",
                run.dungeonName, run.keystoneLevel, timeStr,
                self:FormatTime(prevBest - thisDur)))
        end
    end
end

function MS:SnapshotFromDamageMeter()
    if not self.currentRun then return end
    if not (C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable()
            and C_DamageMeter.GetCombatSessionFromType) then return end

    -- Don't store secret values — that taints addon tables and breaks Blizzard UI.
    if _issecret then
        local ok, probe = pcall(C_DamageMeter.GetCombatSessionFromType, 0, 0)
        if ok and probe then
            if (probe.maxValue and _issecret(probe.maxValue))
                    or (probe.duration and _issecret(probe.duration))
                    or (probe.combatSources and probe.combatSources[1]
                        and (_issecret(probe.combatSources[1].totalAmount)
                             or (probe.combatSources[1].name
                                 and _issecret(probe.combatSources[1].name)))) then
                return
            end
        end
    end

    local OVERALL = (Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Overall) or 0
    local sessionDuration = 0

    local function getSources(t)
        local ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, OVERALL, t)
        if not (ok and s) then return nil end
        if t == 0 and s.duration and s.duration > 0
                and not (_issecret and _issecret(s.duration)) then
            sessionDuration = s.duration
        end
        return s.combatSources or nil
    end

    local function resolve(src)
        local cls = src.classFilename and src.classFilename:upper() or ""
        if cls == "" or not VALID_CLASS[cls] then return nil end
        local rawGUID = src.sourceGUID
        if type(rawGUID) == "string"
                and not (_issecret and _issecret(rawGUID))
                and (rawGUID:find("^Pet%-") or rawGUID:find("^Creature%-")) then
            return nil
        end
        local name
        if src.isLocalPlayer then
            name = UnitName("player")
        else
            if _issecret and _issecret(src.name) then return nil end
            name = type(src.name) == "string" and (src.name .. "") or nil
        end
        if not name or name == "" then return nil end
        local p = self.currentRun.players[ShortName(name)]
        if not p then return nil end
        p.class = cls
        if src.isLocalPlayer then
            p.guid = UnitGUID("player")
        elseif not (_issecret and _issecret(src.sourceGUID)) then
            local g = src.sourceGUID
            if g and type(g) == "string" and g:find("^Player%-") then p.guid = g end
        end
        return p
    end

    local dmg = getSources(0)
    if not dmg then return end
    for _, src in ipairs(dmg) do
        local p = resolve(src)
        if p then
            local amt = src.totalAmount
            if _issecret and amt ~= nil and _issecret(amt) then amt = nil end
            p.damageDone = amt or 0
            local rawAps = src.amountPerSecond
            local aps = (_issecret and rawAps ~= nil and _issecret(rawAps))
                        and 0 or (tonumber(rawAps) or 0)
            p.dps = (aps > 0) and aps
                 or (sessionDuration > 0 and p.damageDone / sessionDuration or 0)
        end
    end

    local heal = getSources(2)
    if heal then
        for _, src in ipairs(heal) do
            local p = resolve(src)
            if p then
                local amt = src.totalAmount
                if _issecret and amt ~= nil and _issecret(amt) then amt = nil end
                p.healingDone = amt or 0
                local rawAps = src.amountPerSecond
                local aps = (_issecret and rawAps ~= nil and _issecret(rawAps))
                            and 0 or (tonumber(rawAps) or 0)
                p.hps = (aps > 0) and aps
                     or (sessionDuration > 0 and p.healingDone / sessionDuration or 0)
            end
        end
    end

    local function applyField(srcType, field)
        local sources = getSources(srcType)
        if not sources then return end
        local resolved = {}
        for _, src in ipairs(sources) do
            local p = resolve(src)
            resolved[src] = p
            if p then
                local amt = src.totalAmount
                if _issecret and amt ~= nil and _issecret(amt) then amt = nil end
                p[field] = amt or 0
            end
        end
        for _, src in ipairs(sources) do
            if not resolved[src] then
                if not (_issecret and _issecret(src.sourceGUID)) then
                    local petGUID = src.sourceGUID
                    if petGUID and type(petGUID) == "string" then
                        local ownerName = nil

                        -- Live unit scan first, then GUID cache.
                        local prefix = IsInRaid() and "raid" or "party"
                        local memberCount = _max(GetNumGroupMembers(), 4)
                        for i = 0, memberCount do
                            local ownerUnit = i == 0 and "player" or (prefix .. i)
                            local petUnit   = i == 0 and "pet"    or (prefix .. i .. "pet")
                            if UnitExists(petUnit) then
                                local ok2, pguid = pcall(UnitGUID, petUnit)
                                if ok2 and pguid
                                        and not (_issecret and _issecret(pguid))
                                        and pguid == petGUID then
                                    ownerName = UnitName(ownerUnit)
                                    if ownerName then
                                        self._petGUIDToOwner[petGUID] = ShortName(ownerName)
                                    end
                                    break
                                end
                            end
                        end

                        if not ownerName then
                            if not self._petGUIDToOwner[petGUID] then
                                self:RebuildPetGUIDCache()
                            end
                            ownerName = self._petGUIDToOwner[petGUID]
                        end

                        -- Tooltip scan as last resort when unit GUIDs are secret.
                        if not ownerName and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
                            local ok3, td = pcall(C_TooltipInfo.GetHyperlink, "unit:" .. petGUID)
                            if ok3 and td and td.lines and td.lines[2] then
                                local line2 = td.lines[2]
                                if line2.guid and type(line2.guid) == "string"
                                        and not (_issecret and _issecret(line2.guid))
                                        and line2.guid:find("^Player") then
                                    local ownerGUID2 = line2.guid
                                    local prefix2 = IsInRaid() and "raid" or "party"
                                    for i = 0, _max(GetNumGroupMembers(), 4) do
                                        local u = i == 0 and "player" or (prefix2 .. i)
                                        local ok4, ug = pcall(UnitGUID, u)
                                        if ok4 and ug == ownerGUID2 then
                                            ownerName = UnitName(u)
                                            break
                                        end
                                    end
                                end
                                if not ownerName and line2.leftText then
                                    local realmName = GetRealmName and GetRealmName() or ""
                                    local titleGlobals = {
                                        UNITNAME_TITLE_PET, UNITNAME_TITLE_COMPANION,
                                        UNITNAME_TITLE_GUARDIAN, UNITNAME_TITLE_MINION,
                                        UNITNAME_TITLE_CHARM, UNITNAME_TITLE_CREATION,
                                    }
                                    if UNITNAME_TITLE_PET and PET_TYPE_DEMON then
                                        titleGlobals[#titleGlobals+1] =
                                            UNITNAME_TITLE_PET:gsub(PET_TYPE_PET or "Pet", PET_TYPE_DEMON)
                                    end
                                    for _, p in pairs(self.currentRun.players) do
                                        local short = ShortName(p.name or "")
                                        for _, fmt in ipairs(titleGlobals) do
                                            if fmt then
                                                local s1 = fmt:format(short)
                                                local s2 = fmt:format(short .. "-" .. realmName)
                                                local ok5, match = pcall(function()
                                                    return line2.leftText == s1 or line2.leftText == s2
                                                end)
                                                if ok5 and match then
                                                    ownerName = short
                                                    break
                                                end
                                            end
                                        end
                                        if ownerName then break end
                                    end
                                end
                                if ownerName then
                                    self._petGUIDToOwner[petGUID] = ShortName(ownerName)
                                end
                            end
                        end
                        if not ownerName then
                            local prefix3  = IsInRaid() and "raid" or "party"
                            local petOwners = {}
                            for i = 1, _max(GetNumGroupMembers(), 4) do
                                local petUnit3   = prefix3 .. i .. "pet"
                                local ownerUnit3 = prefix3 .. i
                                if UnitExists(petUnit3) then
                                    local oname3 = UnitName(ownerUnit3)
                                    if oname3 and not (_issecret and _issecret(oname3)) then
                                        petOwners[#petOwners + 1] = ShortName(oname3)
                                    end
                                end
                            end
                            if #petOwners == 1 then
                                ownerName = petOwners[1]
                                self._petGUIDToOwner[petGUID] = ownerName
                            end
                        end
                        if not ownerName and src.name
                                and not (_issecret and _issecret(src.name)) then
                            self._petNameToOwner = self._petNameToOwner or {}
                            local mapped = self._petNameToOwner[src.name]
                            if mapped then
                                ownerName = mapped
                                if ownerName then
                                    self._petGUIDToOwner[petGUID] = ShortName(ownerName)
                                end
                            end
                        end
                        if ownerName then
                            local op = self.currentRun.players[ShortName(ownerName)]
                            if op then
                                local petAmt = src.totalAmount
                                if not (_issecret and petAmt ~= nil and _issecret(petAmt)) then
                                    op[field] = (op[field] or 0) + (petAmt or 0)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    applyField(7, "damageTaken"); applyField(8, "avoidableDamageTaken")

    for _, p in pairs(self.currentRun.players) do
        p.interrupts = 0
        p.dispels    = 0
    end
    applyField(5, "interrupts"); applyField(6, "dispels")

    self:_BackfillSyntheticInterrupts()
    self:DebugLogInterruptCounts()

    local deathSrc = getSources(9)
    if deathSrc then
        for _, src in ipairs(deathSrc) do
            local rawDeaths = src.totalAmount
            if _issecret and rawDeaths ~= nil and _issecret(rawDeaths) then
                rawDeaths = nil
            end
            local meterDeaths = rawDeaths or 0
            if meterDeaths > 0 then
                local name
                if src.isLocalPlayer then
                    name = UnitName("player")
                elseif not (_issecret and _issecret(src.name)) then
                    name = type(src.name) == "string" and (src.name .. "") or nil
                end
                if name and name ~= "" then
                    local short = ShortName(name)
                    if not self.currentRun.players[short] then
                        local cls  = (src.classFilename and src.classFilename:upper()) or "UNKNOWN"
                        local guid = (src.sourceGUID
                                      and not (_issecret and _issecret(src.sourceGUID)))
                                     and src.sourceGUID or nil
                        if not (_issecret and _issecret(name)) then
                            self.currentRun.players[short] = NewPlayerStats(short, cls, guid)
                        end
                    end
                    local p = self.currentRun.players[short]
                    if p and meterDeaths > p.deaths then
                        local delta2 = meterDeaths - p.deaths
                        local now2   = GetCurrentElapsed(self.currentRun)
                        for _ = 1, delta2 do
                            if not self:IsDupDeath(p, now2) then
                                _ins(p.deathEvents, { time = now2 })
                                p.deaths = p.deaths + 1
                            end
                        end
                    end
                    if src.isLocalPlayer then
                        local ok2, id = pcall(rawget, src, "deathRecapID")
                        if ok2 and id and id ~= 0 then p.deathRecapID = id end
                    end
                end
            end
        end
    end

    self:PopulateAll()
    self:SaveCurrentRun()
end

-- Inspect queue for item levels.
-- Frame is created lazily — CreateFrame can't be called at file scope.
local inspectQueue   = {}
local inspectPending = nil
local INSPECT_DELAY  = 0.5
local inspectFrame   = nil

local function EnsureInspectFrame()
    if inspectFrame then return end
    inspectFrame = CreateFrame("Frame")
    inspectFrame:RegisterEvent("INSPECT_READY")
    inspectFrame:SetScript("OnEvent", function(_, event, guid)
        if event ~= "INSPECT_READY" or not inspectPending then return end
        local targetUnit
        for _, unit in ipairs(MS:GroupUnits()) do
            if UnitGUID(unit) == guid then targetUnit = unit; break end
        end
        local name = inspectPending
        inspectPending = nil
        if targetUnit and C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
            local il = C_PaperDollInfo.GetInspectItemLevel(targetUnit)
            if il and il > 0 then
                il = _floor(il)
                MS.itemLevelCache = MS.itemLevelCache or {}
                MS.itemLevelCache[name] = il
                if MS.currentRun and MS.currentRun.players[name] then
                    MS.currentRun.players[name].itemLevel = il
                end
            end
        end
        if targetUnit and GetInspectSpecialization then
            local specID = GetInspectSpecialization(targetUnit)
            if specID and specID > 0 then
                MS.specCache = MS.specCache or {}
                MS.specCache[name] = specID
                if MS.currentRun and MS.currentRun.players[name] then
                    MS.currentRun.players[name].specID = specID
                end
            end
        end
        if MS.RefreshOverview and MS.sbFrameVisible and MS.sbFrameVisible() then
            MS:RefreshOverview()
        end
        ClearInspectPlayer()
        if #inspectQueue > 0 then
            C_Timer.After(INSPECT_DELAY, function() MS:_ProcessInspectQueue() end)
        end
    end)
end

function MS:_ProcessInspectQueue()
    if inspectPending or #inspectQueue == 0 then return end
    if InCombatLockdown() then
        C_Timer.After(5.0, function() self:_ProcessInspectQueue() end); return
    end
    EnsureInspectFrame()
    local entry = _rem(inspectQueue, 1)
    local unit
    for _, u in ipairs(self:GroupUnits()) do
        local uname = UnitName(u)
        if uname and ShortName(uname) == entry.name then unit = u; break end
    end
    if unit and CanInspect(unit) then
        inspectPending = entry.name
        NotifyInspect(unit)
        local pendingAtCall = entry.name
        C_Timer.After(5.0, function()
            if inspectPending == pendingAtCall then
                inspectPending = nil
                ClearInspectPlayer()
                if #inspectQueue > 0 then
                    C_Timer.After(INSPECT_DELAY, function() self:_ProcessInspectQueue() end)
                end
            end
        end)
    elseif #inspectQueue > 0 then
        C_Timer.After(INSPECT_DELAY, function() self:_ProcessInspectQueue() end)
    end
end

-- Roles and scores are stable mid-run; only call on GROUP_ROSTER_UPDATE.
function MS:PopulateRolesAndScores()
    if not self.currentRun then return end
    for _, unit in ipairs(self:GroupUnits()) do
        local uname = UnitName(unit)
        if uname then
            local short = ShortName(uname)
            local p     = self.currentRun.players[short]
            if p then
                local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
                if role and role ~= "" and role ~= "NONE" then p.role = role end
                if unit == "player" and GetSpecialization and GetSpecializationInfo then
                    local specIndex = GetSpecialization()
                    if specIndex then
                        local specID = GetSpecializationInfo(specIndex)
                        if specID then
                            p.specID = specID
                            self.specCache = self.specCache or {}
                            self.specCache[short] = specID
                        end
                    end
                end
                local sc = C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary
                    and C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
                if sc and sc.currentSeasonScore and sc.currentSeasonScore > 0 then
                    p.mythicScore = sc.currentSeasonScore
                    if self.scoreCache then self.scoreCache[short] = sc.currentSeasonScore end
                elseif self.scoreCache and self.scoreCache[short] then
                    p.mythicScore = self.scoreCache[short]
                end
                -- First read of the run becomes the baseline used to show the run's rating gain.
                if p.mythicScore and p.mythicScore > 0 then
                    if not p._preRunScore then
                        p._preRunScore = p.mythicScore
                    elseif p.mythicScore > p._preRunScore then
                        p.mythicScoreGain = p.mythicScore - p._preRunScore
                    end
                end
            end
        end
    end
end

function MS:PopulateAll()
    if not self.currentRun then return end
    self.itemLevelCache = self.itemLevelCache or {}
    self.specCache = self.specCache or {}
    local needsInspect = false
    for _, unit in ipairs(self:GroupUnits()) do
        local uname = UnitName(unit)
        if uname then
            local short = ShortName(uname)
            local p     = self.currentRun.players[short]
            if p then
                local cachedSpec = self.specCache[short]
                if cachedSpec and not p.specID then p.specID = cachedSpec end

                local cached = self.itemLevelCache[short]
                if cached and cached > 0 then
                    p.itemLevel = cached
                end

                if unit ~= "player" and ((not cached or cached == 0) or not p.specID)
                        and not inspectPending then
                    local already = false
                    for _, e in ipairs(inspectQueue) do
                        if e.name == short then already = true; break end
                    end
                    if not already then
                        _ins(inspectQueue, { name = short })
                        needsInspect = true
                    end
                end
            end
        end
    end
    if needsInspect then
        C_Timer.After(INSPECT_DELAY, function() self:_ProcessInspectQueue() end)
    end
end

function MS:StartRun(dungeonName, keystoneLevel, difficultyID, difficultyLabel)
    self.itemLevelCache = {}
    self._debugInterruptCounts = {}
    self.displayRun     = nil
    self._lootGraceUntil = nil
    self.currentRun = NewRunData()
    self.currentRun.dungeonName     = dungeonName or "Unknown Dungeon"
    self.currentRun.keystoneLevel   = keystoneLevel or 0
    self.currentRun.difficultyID    = difficultyID or 0
    self.currentRun.difficultyLabel = difficultyLabel or ""
    self.currentRun.startTime       = GetTime()
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        self.currentRun.challengeMapID = C_ChallengeMode.GetActiveChallengeMapID()
    end
    -- Prefer keystone API (plain integer array), fall back to C_MythicPlus.
    local affixesRaw
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local _, keystoneAffixes = C_ChallengeMode.GetActiveKeystoneInfo()
        if keystoneAffixes and #keystoneAffixes > 0 then
            affixesRaw = keystoneAffixes
        end
    end
    if not affixesRaw and C_MythicPlus and C_MythicPlus.GetCurrentAffixes then
        local afs = C_MythicPlus.GetCurrentAffixes()
        if afs and #afs > 0 then
            affixesRaw = {}
            for _, af in ipairs(afs) do
                local id = af.affixID or af.id
                if id then _ins(affixesRaw, id) end
            end
        end
    end
    if affixesRaw then
        for _, id in ipairs(affixesRaw) do
            _ins(self.currentRun.affixes, { id = id })
        end
    end
    self.inDungeon = true

    if difficultyID == MYTHIC_PLUS then
        local knownLimit = MS.DUNGEON_TIMERS and MS.DUNGEON_TIMERS[dungeonName or ""]
        if knownLimit then
            -- Used as an immediate placeholder for UI only; the live API value
            -- (fetched below) always overrides it since hardcoded timers can
            -- go stale across season/hotfix changes and cause false "Overtime".
            self.currentRun.keystoneTimeLimit = knownLimit
        end

        if C_ChallengeMode then
            local function TryFetchTimeLimit()
                if not self.currentRun then return end
                if C_ChallengeMode.GetActiveKeystoneInfo then
                    local _, _, tl = C_ChallengeMode.GetActiveKeystoneInfo()
                    local tlNum = tonumber(tl)
                    if tlNum and tlNum > 10 and tlNum < 7200 then
                        self.currentRun.keystoneTimeLimit = tlNum
                        self:SaveCurrentRun()
                        if self.RefreshOverview then self:RefreshOverview() end
                    end
                end
            end
            TryFetchTimeLimit()
            C_Timer.After(1.0, TryFetchTimeLimit)
            C_Timer.After(4.0, TryFetchTimeLimit)
        end

        self.currentRun.currentPct = 0
    end

    local function SeedPlayers()
        if not self.currentRun then return end
        for _, unit in ipairs(self:GroupUnits()) do
            local uname = UnitName(unit)
            local _, cls = UnitClass(unit)
            if uname and uname ~= "" then
                local short = ShortName(uname)
                if not self.currentRun.players[short] then
                    self.currentRun.players[short] =
                        NewPlayerStats(short, cls or "UNKNOWN", UnitGUID(unit))
                end
            end
        end
    end

    SeedPlayers()
    -- Deferred seed for solo/late-join cases.
    if GetNumGroupMembers() == 0 then
        C_Timer.After(2.0, function()
            SeedPlayers()
            self:PopulateAll()
            self:PopulateRolesAndScores()
            if self.RefreshOverview then self:RefreshOverview() end
        end)
    end
    self:PopulateAll()
    self:PopulateRolesAndScores()
    self.currentRun._wallClockStart = time()
    self:SaveCurrentRun()
    if self.RefreshOverview then self:RefreshOverview() end
    -- Short delay lets roster seeding settle before first snapshot.
    C_Timer.After(0.5, function()
        if self.currentRun and not InCombatLockdown() then
            self:SnapshotFromDamageMeter()
            self:SaveCurrentRun()
            if self.RefreshOverview then self:RefreshOverview() end
        end
    end)
end

function MS:EndRun(completed, inTime)
    if not self.currentRun then return end
    self.currentRun.endTime = GetTime()
    -- Don't overwrite completed=true already set by boss-count check.
    if not self.currentRun.completed then
        self.currentRun.completed = completed
    end
    self.currentRun.inTime = inTime
    self.inDungeon = false
    -- M+ skips snapshot here: C_DamageMeter is still protected at
    -- CHALLENGE_MODE_COMPLETED. Deferred to FinalizeMythicPlusRun().
    if (self.currentRun.keystoneLevel or 0) == 0 then
        self:SnapshotFromDamageMeter()
    end
    self:PopulateAll()
    self:FlushSave()
    self:_CommitRunToHistory(self.currentRun)
    self:_AnnouncePB(self.currentRun)
    if MythicScoreboardDB then MythicScoreboardDB.activeRun = nil end
    -- Window for the reward chest's loot to still land after the run object clears
    -- (players often linger, especially after an overtime/failed key).
    self._lootGraceUntil = GetTime() + 90
    self.currentRun = nil
    self.displayRun = nil
    if self.RefreshOverview then self:RefreshOverview() end
end

-- Finds the history entry just committed for a run, identified by its wall-clock start.
local function FindHistoryEntry(dungeonName, keystoneLevel, wallClockStart)
    if not (MythicScoreboardDB and MythicScoreboardDB.runs) then return nil end
    for _, r in ipairs(MythicScoreboardDB.runs) do
        if r.dungeonName == dungeonName and (r.keystoneLevel or 0) == keystoneLevel
                and r._wallClockStart == wallClockStart then
            return r
        end
    end
    return nil
end

-- The client doesn't apply the completed key's rating to
-- GetPlayerMythicPlusRatingSummary right away, so poll briefly afterward and
-- backfill the saved history entry once Blizzard updates each member's score.
function MS:_PollScoreGainUpdates(dungeonName, keystoneLevel, wallClockStart, attempt)
    attempt = attempt or 1
    local entry = FindHistoryEntry(dungeonName, keystoneLevel, wallClockStart)
    if not entry or not entry.players then return end

    local changed = false
    for _, unit in ipairs(self:GroupUnits()) do
        local uname = UnitName(unit)
        if uname then
            local short = ShortName(uname)
            local p = entry.players[short]
            if p and p._preRunScore then
                local sc = C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary
                    and C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
                if sc and sc.currentSeasonScore and sc.currentSeasonScore > p._preRunScore
                        and sc.currentSeasonScore ~= p.mythicScore then
                    p.mythicScore     = sc.currentSeasonScore
                    p.mythicScoreGain = sc.currentSeasonScore - p._preRunScore
                    if self.scoreCache then self.scoreCache[short] = sc.currentSeasonScore end
                    changed = true
                end
            end
        end
    end

    if changed and self.RefreshOverview and self.sbFrameVisible and self.sbFrameVisible() then
        self:RefreshOverview()
    end
    if attempt < 8 then
        C_Timer.After(2, function()
            self:_PollScoreGainUpdates(dungeonName, keystoneLevel, wallClockStart, attempt + 1)
        end)
    end
end

-- C_DamageMeter values are protected immediately when a key completes.
-- Poll until protection clears, then snapshot and open the scoreboard.
function MS:FinalizeMythicPlusRun()
    if not self.currentRun then return end
    local capturedRun = self.currentRun

    local function IsMeterProtected()
        if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then return false end
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, 0, 0)
        if not (ok and session) then return false end
        if _issecret and session.maxValue and _issecret(session.maxValue) then return true end
        local sources = session.combatSources
        if sources and sources[1] and _issecret and _issecret(sources[1].totalAmount) then
            return true
        end
        return false
    end

    local attempts    = 0
    local maxAttempts = 60

    local function TryFinalize()
        if self.currentRun ~= capturedRun then return end
        attempts = attempts + 1
        if IsMeterProtected() and attempts < maxAttempts then
            C_Timer.After(0.1, TryFinalize)
            return
        end
        self:SnapshotFromDamageMeter()
        if not self.currentRun.currentPct or self.currentRun.currentPct < 100 then
            self.currentRun.currentPct = 100
        end
        self:PopulateAll()
        self:_CommitRunToHistory(self.currentRun)
        self:_AnnouncePB(self.currentRun)
        self:_PollScoreGainUpdates(self.currentRun.dungeonName, self.currentRun.keystoneLevel or 0,
            self.currentRun._wallClockStart)
        self._awaitingLootAutoShow = {
            dungeonName   = self.currentRun.dungeonName,
            keystoneLevel = self.currentRun.keystoneLevel or 0,
            endTime       = self.currentRun.endTime or GetTime(),
            expiresAt     = GetTime() + 30,
        }
        MythicScoreboardDB.activeRun = nil
        -- Window for the reward chest's loot to still land after the run object clears
        -- (players often linger, especially after an overtime/failed key).
        self._lootGraceUntil = GetTime() + 90
        self.currentRun = nil
        self.displayRun = nil
        C_Timer.After(12, function()
            if self._awaitingLootAutoShow then
                self._awaitingLootAutoShow = nil
                self:ShowScoreboard()
            end
        end)
    end

    C_Timer.After(2, TryFinalize)
end

function MS:SaveCurrentRun()
    if not MythicScoreboardDB then return end
    if not self.currentRun then MythicScoreboardDB.activeRun = nil; return end
    -- Mark dirty; the 1-second coalesce ticker does the actual write.
    -- Call FlushSave() directly when an immediate write is required.
    self._saveDirty = true
end

function MS:FlushSave()
    if not self._saveDirty then return end
    if not MythicScoreboardDB then return end
    if not self.currentRun then MythicScoreboardDB.activeRun = nil; self._saveDirty = false; return end
    self.currentRun._seq = (self.currentRun._seq or 0) + 1
    local ok, err = pcall(function()
        local saved = self:SerializeRun(self.currentRun)
        saved._active         = true
        saved._wallClockStart = self.currentRun._wallClockStart or time()
        MythicScoreboardDB.activeRun = saved
        MythicScoreboardDB.petGUIDCache = {}
        for guid, owner in pairs(self._petGUIDToOwner) do
            MythicScoreboardDB.petGUIDCache[guid] = owner
        end
    end)
    self._saveDirty = false
    if not ok then
        if not self._saveErrLogged then
            self._saveErrLogged = true
            print("|cffff4444[MythicScoreboard]|r SaveCurrentRun error: " .. tostring(err))
        end
    else
        self._saveErrLogged = nil
    end
end

function MS:RestoreCurrentRun()
    if not MythicScoreboardDB or not MythicScoreboardDB.activeRun then return end
    local saved = MythicScoreboardDB.activeRun
    if not saved._active then return end
    local elapsed = time() - (saved._wallClockStart or time())
    self.currentRun = NewRunData()
    self.currentRun.dungeonName       = saved.dungeonName or "Unknown"
    self.currentRun.keystoneLevel     = saved.keystoneLevel or 0
    self.currentRun.difficultyID      = saved.difficultyID or 0
    self.currentRun.difficultyLabel   = saved.difficultyLabel or ""
    self.currentRun.keystoneTimeLimit = saved.keystoneTimeLimit
    self.currentRun.challengeMapID    = saved.challengeMapID
    self.currentRun.startTime         = GetTime() - elapsed
    self.currentRun._wallClockStart   = saved._wallClockStart
    self.currentRun.bosses            = saved.bosses or {}
    self.currentRun.currentPct        = saved.currentPct
    for name, p in pairs(saved.players or {}) do
        self.currentRun.players[name] = p
    end
    if MythicScoreboardDB.petGUIDCache then
        for guid, owner in pairs(MythicScoreboardDB.petGUIDCache) do
            self._petGUIDToOwner[guid] = owner
        end
    end
    self.inDungeon      = true
    self.itemLevelCache = {}
    print("|cff00ccff[MythicScoreboard]|r Run restored after UI reload.")
end

-- Finds the isWeightedProgress scenario criterion and returns completion %.
local function GetEnemyForcesPercent()
    if not (C_Scenario and C_Scenario.GetStepInfo) then return nil end
    local ok1, _, _, numCriteria = pcall(C_Scenario.GetStepInfo)
    if not ok1 or not numCriteria or numCriteria <= 0 then return nil end

    for i = 1, numCriteria do
        local ok2, info = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
        if ok2 and info and info.isWeightedProgress then
            if info.completed then return 100 end
            local curValue = info.quantity    or 0
            local maxValue = info.totalQuantity or 0
            if maxValue <= 0 then return nil end
            -- quantityString may be "42%" — strip the suffix for the raw count.
            if info.quantityString and info.quantityString ~= "" then
                local stripped = tonumber(info.quantityString:sub(1, -2))
                if stripped then curValue = stripped end
            end
            local pct = (curValue / maxValue) * 100
            pct = _floor(pct * 100 + 0.5) / 100
            return _min(100, pct)
        end
    end
    return nil
end

function MS:SnapshotBossProgress(boss, atPull)
    if not boss then return end
    local pct = (self.currentRun and self.currentRun.currentPct) or GetEnemyForcesPercent()
    if not pct then return end
    if atPull then boss.pullProgressPct = pct
    else            boss.progressPct    = pct end
end

function MS:UpdateEnemyForcesProgress()
    if not self.currentRun then return end
    local pct = GetEnemyForcesPercent()
    if pct ~= nil then
        self.currentRun.currentPct = pct
    elseif (self.currentRun.keystoneLevel or 0) > 0
            and self.currentRun.currentPct == nil then
        self.currentRun.currentPct = 0
    end
end

function MS:BossPull(bossName, dungeonEncounterId)
    if not self.currentRun then return end
    local now = GetCurrentElapsed(self.currentRun)
    -- Re-use existing entry on double-fire; stamp as wipe if > 10s have passed.
    for i = #self.currentRun.bosses, 1, -1 do
        local b = self.currentRun.bosses[i]
        if b.name == bossName and not b.killTime and not b.wipeTime then
            local elapsed = now - (b.pullTime or 0)
            if elapsed < 10 then
                self.currentRun.activeBoss = b
                if dungeonEncounterId and not b.dungeonEncounterId then
                    b.dungeonEncounterId = dungeonEncounterId
                end
                return
            else
                b.wipeTime = now
            end
            break
        elseif b.name == bossName and b.wipeTime and not b.killTime then
            break
        end
    end
    local boss = { name = bossName, pullTime = now, dungeonEncounterId = dungeonEncounterId }
    _ins(self.currentRun.bosses, boss)
    self.currentRun.activeBoss = boss
    self:SnapshotBossProgress(boss, true)
    self:SaveCurrentRun()
end

function MS:BossKill(bossName, dungeonEncounterId)
    if not self.currentRun then return nil end
    local t = GetCurrentElapsed(self.currentRun)
    if self.currentRun.activeBoss and self.currentRun.activeBoss.name == bossName then
        local boss = self.currentRun.activeBoss
        boss.killTime = t
        if dungeonEncounterId and not boss.dungeonEncounterId then
            boss.dungeonEncounterId = dungeonEncounterId
        end
        self.currentRun.activeBoss = nil
        self:SaveCurrentRun()
        return boss
    end
    for i = #self.currentRun.bosses, 1, -1 do
        local b = self.currentRun.bosses[i]
        if b.name == bossName and not b.killTime and not b.wipeTime then
            b.killTime = t
            if dungeonEncounterId and not b.dungeonEncounterId then
                b.dungeonEncounterId = dungeonEncounterId
            end
            self:FlushSave(); return b
        end
    end
    return nil
end

function MS:BossWipe(bossName, dungeonEncounterId)
    if not self.currentRun then return end
    local t = GetCurrentElapsed(self.currentRun)
    local boss = self.currentRun.activeBoss
    if boss and boss.name ~= bossName then boss = nil end
    if not boss then
        for i = #self.currentRun.bosses, 1, -1 do
            local b = self.currentRun.bosses[i]
            if b.name == bossName and not b.killTime and not b.wipeTime then
                boss = b; break
            end
        end
    end
    if boss then
        boss.wipeTime = t
        if dungeonEncounterId and not boss.dungeonEncounterId then
            boss.dungeonEncounterId = dungeonEncounterId
        end
        self.currentRun.activeBoss = nil
        self:SaveCurrentRun()
    end
end

function MS:RecordDeathEvent(unitName)
    if not self.currentRun or not unitName then return end
    local p = self.currentRun.players[ShortName(unitName)]
    if not p then return end
    local t = GetCurrentElapsed(self.currentRun)
    p.deaths = p.deaths + 1
    p._lastDeathTime = t
    _ins(p.deathEvents, { time = t })
    -- 15s penalty at +12, 5s at +4–11, 0 below +4.
    local level = self.currentRun.keystoneLevel or 0
    if level >= 12 then
        self.currentRun.deathPenaltySeconds = (self.currentRun.deathPenaltySeconds or 0) + 15
    elseif level >= 4 then
        self.currentRun.deathPenaltySeconds = (self.currentRun.deathPenaltySeconds or 0) + 5
    end
    self:SaveCurrentRun()
end

-- Scans all party/raid pet units and populates _petGUIDToOwner.
-- Called on UNIT_PET, GROUP_ROSTER_UPDATE, and CHALLENGE_MODE_START.
-- Additive — never removes entries. Wiped only at CHALLENGE_MODE_START.
function MS:RebuildPetGUIDCache()
    local prefix = IsInRaid() and "raid" or "party"
    local memberCount = _max(GetNumGroupMembers(), 4)
    for i = 0, memberCount do
        local ownerUnit = i == 0 and "player" or (prefix .. i)
        local petUnit   = i == 0 and "pet"    or (prefix .. i .. "pet")
        if UnitExists(petUnit) then
            local ok, guid = pcall(UnitGUID, petUnit)
            if ok and guid
                    and not (_issecret and _issecret(guid))
                    and type(guid) == "string"
                    and (guid:find("^Pet%-") or guid:find("^Creature%-")) then
                local oname = UnitName(ownerUnit)
                if oname and not (_issecret and _issecret(oname)) then
                    self._petGUIDToOwner[guid] = ShortName(oname)
                end
            end
            local petName = UnitName(petUnit)
            local oname   = UnitName(ownerUnit)
            if petName and oname
                    and not (_issecret and _issecret(petName))
                    and not (_issecret and _issecret(oname)) then
                self._petNameToOwner = self._petNameToOwner or {}
                self._petNameToOwner[petName] = ShortName(oname)
            end
        end
    end
end

function MS:GetAutoResetMeter()
    return MythicScoreboardDB and MythicScoreboardDB.settings
        and MythicScoreboardDB.settings.autoResetMeter
end

function MS:SetAutoResetMeter(value)
    if MythicScoreboardDB and MythicScoreboardDB.settings then
        MythicScoreboardDB.settings.autoResetMeter = value and true or false
    end
end

function MS:GetAutoOpenOnComplete()
    if not (MythicScoreboardDB and MythicScoreboardDB.settings) then return true end
    local v = MythicScoreboardDB.settings.autoOpenOnComplete
    return v == nil or v
end

function MS:SetAutoOpenOnComplete(value)
    if MythicScoreboardDB and MythicScoreboardDB.settings then
        MythicScoreboardDB.settings.autoOpenOnComplete = value and true or false
    end
end

function MS:GetHistoryLimit()
    local v = MythicScoreboardDB and MythicScoreboardDB.settings
        and MythicScoreboardDB.settings.historyLimit
    return _max(1, _min(30, v or 10))
end

function MS:SetHistoryLimit(value)
    value = _max(1, _min(30, _floor(tonumber(value) or 10)))
    if MythicScoreboardDB and MythicScoreboardDB.settings then
        MythicScoreboardDB.settings.historyLimit = value
        if MythicScoreboardDB.runs then
            while #MythicScoreboardDB.runs > value do _rem(MythicScoreboardDB.runs) end
        end
    end
end

function MS:SetSBFrameVisibleCallback(fn) MS.sbFrameVisible = fn end

function MS:SerializeRun(run)
    local function copy(t)
        if type(t) ~= "table" then return t end
        local out = {}
        for k, v in pairs(t) do out[k] = copy(v) end
        return out
    end
    return copy(run)
end

function MS:GetRunDuration(run)
    run = run or self.currentRun
    if not run then return 0 end
    return GetCurrentElapsed(run)
end

function MS:FormatTime(seconds)
    seconds = seconds or 0
    return _fmt("%d:%02d", _floor(seconds / 60), _floor(seconds % 60))
end
