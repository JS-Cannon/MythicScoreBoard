-- Per-mob enemy forces % for M+ nameplates and tooltips.
--
-- GetUnitCriteriaProgressValues returns Secret Values (WoW 12.0+): they can't
-- be compared or used in Lua string ops. Pass them straight to C widget calls
-- (SetFormattedText, AddDoubleLine); wrap in pcall to swallow nil on bosses.

local MS = _G["MythicScoreboard"]

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function IsInMythicPlus()
    return select(3, GetInstanceInfo()) == 8
end

local function IsTooltipEnabled()
    local s = MythicScoreboardDB and MythicScoreboardDB.settings
    return s and s.showMobForces ~= false
end

local function IsNameplateEnabled()
    local s = MythicScoreboardDB and MythicScoreboardDB.settings
    return s and s.showMobForcesNameplates ~= false
end

-- ── Tooltip ───────────────────────────────────────────────────────────────────

local function AddForcesToTooltip(tooltip, tooltipData)
    if not IsTooltipEnabled() then return end
    if not IsInMythicPlus() then return end
    if not (C_ScenarioInfo and C_ScenarioInfo.GetUnitCriteriaProgressValues) then return end

    -- tooltip:GetUnit() is tainted in M+ (C_DamageMeter side-effect).
    -- Use "mouseover" — a literal string, always clean.
    if not UnitExists("mouseover") then return end
    if not UnitCanAttack("player", "mouseover") then return end

    -- Call API with the literal "mouseover" token — no taint
    local count, countPercent, countPercentString =
        C_ScenarioInfo.GetUnitCriteriaProgressValues("mouseover")

    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("Enemy Forces", " ", 0.67, 0.67, 0.67, 0.00, 0.78, 1.00)

    local n = tooltip:NumLines()
    local rightFS = _G["GameTooltipTextRight" .. n]
    if rightFS then
        local ok = pcall(rightFS.SetFormattedText, rightFS, "%s%%", countPercentString)
        if ok then
            rightFS:SetTextColor(0.00, 0.78, 1.00, 1)
            tooltip:Show()
        end
    end
end

local function HookTooltip()
    -- OnTooltipSetUnit was removed in Midnight; AddTooltipPostCall is the replacement.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(
            Enum.TooltipDataType.Unit, AddForcesToTooltip)
    end
end

-- ── Nameplates ────────────────────────────────────────────────────────────────

local nameplateLabels = {}
local FONT_PATH = "Fonts\\FRIZQT__.TTF"

local function GetOrCreateLabel(unit)
    if nameplateLabels[unit] then return nameplateLabels[unit] end
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then return nil end
    local lbl = nameplate:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(FONT_PATH, 14, "OUTLINE")
    lbl:SetTextColor(1.00, 1.00, 1.00, 1)
    lbl:SetPoint("BOTTOM", nameplate, "TOP", 0, 2)
    lbl:SetJustifyH("CENTER")
    lbl:SetText("")
    nameplateLabels[unit] = lbl
    return lbl
end

local function UpdateNameplateLabel(unit)
    if not unit or not UnitExists(unit) then return end

    local lbl = GetOrCreateLabel(unit)
    if not lbl then return end

    if not IsNameplateEnabled() or not IsInMythicPlus()
            or not UnitCanAttack("player", unit) then
        lbl:SetText("")
        return
    end

    if not (C_ScenarioInfo and C_ScenarioInfo.GetUnitCriteriaProgressValues) then
        lbl:SetText("")
        return
    end

    -- Secret Value — pass straight to C; no Lua ops on it.
    local count, countPercent, countPercentString =
        C_ScenarioInfo.GetUnitCriteriaProgressValues(unit)

    -- SetFormattedText is a C call — safe to pass Secret Values
    -- pcall catches nil countPercentString (boss / no forces)
    local ok = pcall(lbl.SetFormattedText, lbl, "%s%%", countPercentString)
    if not ok then
        lbl:SetText("")
    end
end

local function ClearNameplateLabel(unit)
    local lbl = nameplateLabels[unit]
    if lbl then lbl:SetText("") end
    nameplateLabels[unit] = nil
end

local function RefreshAllNameplates()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            UpdateNameplateLabel(unit)
        end
    end
end

-- ── Event frame ───────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")

frame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        UpdateNameplateLabel(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        ClearNameplateLabel(unit)
    elseif event == "SCENARIO_CRITERIA_UPDATE" then
        if IsNameplateEnabled() and IsInMythicPlus() then
            RefreshAllNameplates()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if MythicScoreboardDB and MythicScoreboardDB.settings then
            if MythicScoreboardDB.settings.showMobForces == nil then
                MythicScoreboardDB.settings.showMobForces = true
            end
            if MythicScoreboardDB.settings.showMobForcesNameplates == nil then
                MythicScoreboardDB.settings.showMobForcesNameplates = true
            end
        end
        -- Nameplate unit tokens are reused across zone transitions; wipe stale refs.
        for unit, lbl in pairs(nameplateLabels) do
            if lbl then lbl:SetText("") end
        end
        wipe(nameplateLabels)
        RefreshAllNameplates()
    end
end)

HookTooltip()

-- ── Public toggle helpers ─────────────────────────────────────────────────────

function MS:GetMobForcesTooltip()
    return MythicScoreboardDB and MythicScoreboardDB.settings
        and MythicScoreboardDB.settings.showMobForces ~= false
end

function MS:SetMobForcesTooltip(v)
    if MythicScoreboardDB and MythicScoreboardDB.settings then
        MythicScoreboardDB.settings.showMobForces = v and true or false
    end
end

function MS:GetMobForcesNameplate()
    return MythicScoreboardDB and MythicScoreboardDB.settings
        and MythicScoreboardDB.settings.showMobForcesNameplates ~= false
end

function MS:SetMobForcesNameplate(v)
    if MythicScoreboardDB and MythicScoreboardDB.settings then
        MythicScoreboardDB.settings.showMobForcesNameplates = v and true or false
        if v then
            RefreshAllNameplates()
        else
            for _, lbl in pairs(nameplateLabels) do
                lbl:SetText("")
            end
        end
    end
end
