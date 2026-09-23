local _abs = math.abs
local _ceil = math.ceil
local _floor = math.floor
local _huge = math.huge
local _max = math.max
local _min = math.min
local _fmt = string.format
local _ins = table.insert
local _rem = table.remove
local _sort = table.sort

local _slower = string.lower
local _smatch = string.match

local MS = _G["MythicScoreboard"]

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local CLASS_COLORS = {
    WARRIOR = {r = 0.78, g = 0.61, b = 0.43},
    PALADIN = {r = 0.96, g = 0.55, b = 0.73},
    HUNTER = {r = 0.67, g = 0.83, b = 0.45},
    ROGUE = {r = 1.00, g = 0.96, b = 0.41},
    PRIEST = {r = 1.00, g = 1.00, b = 1.00},
    DEATHKNIGHT = {r = 0.77, g = 0.12, b = 0.23},
    SHAMAN = {r = 0.00, g = 0.44, b = 0.87},
    MAGE = {r = 0.41, g = 0.80, b = 0.94},
    WARLOCK = {r = 0.58, g = 0.51, b = 0.79},
    MONK = {r = 0.00, g = 1.00, b = 0.59},
    DRUID = {r = 1.00, g = 0.49, b = 0.04},
    DEMONHUNTER = {r = 0.64, g = 0.19, b = 0.79},
    EVOKER = {r = 0.20, g = 0.58, b = 0.50},
    UNKNOWN = {r = 0.70, g = 0.70, b = 0.70}
}

local ITEM_QUALITY_COLORS = {
    [0] = {r = 0.62, g = 0.62, b = 0.62}, -- Poor (Junk)
    [1] = {r = 1.00, g = 1.00, b = 1.00}, -- Common (White)
    [2] = {r = 0.12, g = 1.00, b = 0.00}, -- Uncommon (Green)
    [3] = {r = 0.00, g = 0.44, b = 0.87}, -- Rare (Blue)
    [4] = {r = 0.64, g = 0.21, b = 0.93}, -- Epic (Purple)
    [5] = {r = 1.00, g = 0.50, b = 0.00}, -- Legendary (Orange)
    [6] = {r = 0.90, g = 0.80, b = 0.50}, -- Artifact (Gold)
    [7] = {r = 0.00, g = 0.80, b = 1.00} -- Heirloom (Light Blue)
}

-- ---------------------------------------------------------------------------
-- Shared utilities
-- ---------------------------------------------------------------------------

local function ClassColor(class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    local fb = CLASS_COLORS[class] or CLASS_COLORS["UNKNOWN"]
    return fb.r, fb.g, fb.b
end

local CLASS_ICON_COORDS = {
    WARRIOR = {0.00, 0.25, 0.00, 0.25},
    MAGE = {0.25, 0.50, 0.00, 0.25},
    ROGUE = {0.50, 0.75, 0.00, 0.25},
    DRUID = {0.75, 1.00, 0.00, 0.25},
    HUNTER = {0.00, 0.25, 0.25, 0.50},
    SHAMAN = {0.25, 0.50, 0.25, 0.50},
    PRIEST = {0.50, 0.75, 0.25, 0.50},
    WARLOCK = {0.75, 1.00, 0.25, 0.50},
    PALADIN = {0.00, 0.25, 0.50, 0.75},
    DEATHKNIGHT = {0.25, 0.50, 0.50, 0.75},
    MONK = {0.50, 0.75, 0.50, 0.75},
    DEMONHUNTER = {0.75, 1.00, 0.50, 0.75},
    EVOKER = {0.00, 0.25, 0.75, 1.00},
    UNKNOWN = {0.75, 1.00, 0.75, 1.00}
}

local ROLE_ICON_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_ICON_COORDS = {
    TANK = {0 / 64, 19 / 64, 22 / 64, 41 / 64},
    HEALER = {20 / 64, 39 / 64, 1 / 64, 20 / 64},
    DAMAGER = {20 / 64, 39 / 64, 22 / 64, 41 / 64}
}

local function GetRole(p)
    if p.role and p.role ~= "" then return p.role end
    if (p.healingDone or 0) > (p.damageDone or 0) then return "HEALER" end
    return "DAMAGER"
end

local FRAME_W = 1130
local ROW_H = 50
local HDR_H = 95
local COL_HDR_H = 28
local BOTTOM_H = 195
local ICON_SIZE = 32

local COLS = {
    {key = "player", label = "Player", w = 230},
    {key = "score", label = "M+ Rating", w = 94},
    {key = "loot", label = "Loot", w = 72},
    {key = "deaths", label = "Deaths", w = 67},
    {key = "dmgTaken", label = "Dmg Taken", w = 115},
    {key = "avoidable", label = "Avoidable", w = 138},
    {key = "dps", label = "DPS", w = 87}, {key = "hps", label = "HPS", w = 87},
    {key = "interrupts", label = "Interrupts", w = 117},
    {key = "dispels", label = "Dispels", w = 80}
}

local C = {
    bg = {0.047, 0.059, 0.082},
    rowOdd = {0.040, 0.052, 0.074},
    rowEven = {0.072, 0.088, 0.124},
    rowHeal = {0.036, 0.072, 0.092},
    border = {0.122, 0.150, 0.228},
    colHdr = {0.68, 0.75, 0.92},
    titleGold = {1.000, 0.816, 0.000},
    white = {1.000, 1.000, 1.000},
    stat = {0.62, 0.68, 0.82},
    orange = {1.000, 0.60, 0.18},
    cyan = {0.22, 0.84, 1.00},
    dispel = {0.32, 1.00, 0.72},
    red = {1.000, 0.25, 0.25},
    pbGreen = {0.35, 1.000, 0.50},
    bossTime = {0.54, 0.62, 0.78}
}

local function Abbrev(n)
    n = n or 0
    if n >= 1e9 then
        return _fmt("%.1fB", n / 1e9)
    elseif n >= 1e6 then
        return _fmt("%.1fM", n / 1e6)
    elseif n >= 1e3 then
        return _fmt("%.1fK", n / 1e3)
    else
        return tostring(_floor(n))
    end
end

local SCORE_TIERS = {
    {3000, 1.00, 0.50, 0.00}, {2500, 0.64, 0.21, 0.93},
    {2000, 0.00, 0.71, 1.00}, {1500, 0.00, 0.78, 0.44},
    {1000, 1.00, 0.85, 0.00}, {600, 0.80, 0.80, 0.80}, {0, 0.74, 0.49, 0.22}
}

local function ScoreColor(score)
    score = score or 0
    if C_ChallengeMode and
        C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor then
        local col = C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor(
                        score)
        if col then return col.r, col.g, col.b end
    end
    for _, t in ipairs(SCORE_TIERS) do
        if score >= t[1] then return t[2], t[3], t[4] end
    end
    return 0.74, 0.49, 0.22
end

local CYRILLIC_MAP = {
    ["А"] = "A",
    ["а"] = "a",
    ["Б"] = "B",
    ["б"] = "b",
    ["В"] = "V",
    ["в"] = "v",
    ["Г"] = "G",
    ["г"] = "g",
    ["Д"] = "D",
    ["д"] = "d",
    ["Е"] = "E",
    ["е"] = "e",
    ["Ё"] = "Yo",
    ["ё"] = "yo",
    ["Ж"] = "Zh",
    ["ж"] = "zh",
    ["З"] = "Z",
    ["з"] = "z",
    ["И"] = "I",
    ["и"] = "i",
    ["Й"] = "Y",
    ["й"] = "y",
    ["К"] = "K",
    ["к"] = "k",
    ["Л"] = "L",
    ["л"] = "l",
    ["М"] = "M",
    ["м"] = "m",
    ["Н"] = "N",
    ["н"] = "n",
    ["О"] = "O",
    ["о"] = "o",
    ["П"] = "P",
    ["п"] = "p",
    ["Р"] = "R",
    ["р"] = "r",
    ["С"] = "S",
    ["с"] = "s",
    ["Т"] = "T",
    ["т"] = "t",
    ["У"] = "U",
    ["у"] = "u",
    ["Ф"] = "F",
    ["ф"] = "f",
    ["Х"] = "Kh",
    ["х"] = "kh",
    ["Ц"] = "Ts",
    ["ц"] = "ts",
    ["Ч"] = "Ch",
    ["ч"] = "ch",
    ["Ш"] = "Sh",
    ["ш"] = "sh",
    ["Щ"] = "Shch",
    ["щ"] = "shch",
    ["Ъ"] = "",
    ["ъ"] = "",
    ["Ы"] = "Y",
    ["ы"] = "y",
    ["Ь"] = "",
    ["ь"] = "",
    ["Э"] = "E",
    ["э"] = "e",
    ["Ю"] = "Yu",
    ["ю"] = "yu",
    ["Я"] = "Ya",
    ["я"] = "ya"
}

local function TransliterateName(name)
    if not name then return "" end
    local isCyrillic = false
    local newName = name:gsub("[%z\1-\127\194-\244][\128-\191]*", function(char)
        if CYRILLIC_MAP[char] then
            isCyrillic = true
            return CYRILLIC_MAP[char]
        end
        return char
    end)

    return isCyrillic and ("!" .. newName) or name
end

-- Cache the default font path once; avoids repeated GetFont() calls during row builds.
local _FONT_PATH = GameFontNormal:GetFont()

local function SetBG(frame, r, g, b, a)
    if not frame then return end
    local t = frame._bg
    if not t then
        t = frame:CreateTexture(nil, "BACKGROUND")
        t:SetAllPoints()
        frame._bg = t
    end
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

local function HLine(parent, yOff)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOff)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOff)
    t:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    return t
end

local function MakeScrollFrame(parent, x1, y1, x2, y2)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetPoint("TOPLEFT", parent, "TOPLEFT", x1, y1)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", x2, y2)
    sf:EnableMouseWheel(true)

    local sb = CreateFrame("Slider", nil, sf)
    sb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, 0)
    sb:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, 0)
    sb:SetWidth(6)
    sb:SetOrientation("VERTICAL")
    sb:SetValueStep(1)
    sb:SetObeyStepOnDrag(true)
    sb:SetMinMaxValues(0, 0)
    sb:SetValue(0)
    if sb.SetBackdrop then sb:SetBackdrop(nil) end
    local sbBg = sb:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints();
    sbBg:SetColorTexture(0, 0, 0, 0)
    local thumb = sb:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(4, 36)
    thumb:SetColorTexture(0.40, 0.45, 0.55, 0.8)
    sb:SetThumbTexture(thumb)
    sb:Hide()
    sb:SetScript("OnEnter", function() end)
    sb:SetScript("OnLeave", function() end)

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(FRAME_W - 12)
    content:SetHeight(1)
    sf:SetScrollChild(content)

    sf:SetScript("OnMouseWheel", function(_, delta)
        local cur = sb:GetValue()
        local mn, mx = sb:GetMinMaxValues()
        sb:SetValue(_max(mn, _min(mx, cur - delta * ROW_H * 2)))
    end)
    sb:SetScript("OnValueChanged",
                 function(_, val) sf:SetVerticalScroll(val) end)
    local function UpdateRange()
        local maxS = _max(0, content:GetHeight() - sf:GetHeight())
        sb:SetMinMaxValues(0, maxS)
        if sb:GetValue() > maxS then sb:SetValue(maxS) end
        sb:SetShown(maxS > 0)
    end
    content:SetScript("OnSizeChanged", UpdateRange)

    sf.scrollContent = content
    sf.scrollBar = sb
    sf.UpdateRange = UpdateRange
    return sf
end

-- ---------------------------------------------------------------------------
-- History dropdown
-- ---------------------------------------------------------------------------

local histDropdown = nil
local histDropRows = {}

local function CloseHistDropdown()
    if histDropdown then
        histDropdown:SetScript("OnHide", nil)
        histDropdown:Hide()
        histDropdown:SetParent(nil)
        histDropdown = nil
    end
    wipe(histDropRows)
    if sbFrame then sbFrame:EnableMouse(true) end
end

local function DoClearHistory()
    if MythicScoreboardDB then MythicScoreboardDB.runs = {} end
    if not MS.inDungeon then MS.currentRun = nil end
    MS.displayRun = nil
    MS:RefreshOverview()
    if sbFrame and sbFrame.RefreshHistBtn then sbFrame.RefreshHistBtn() end
    print("|cff00ccff[MythicScoreboard]|r History cleared.")
end

local function BuildHistDropdownRows(drop, runs, anchorBtn)
    for _, r in ipairs(histDropRows) do
        if r.Hide then r:Hide() end
        if r.SetParent then r:SetParent(nil) end
    end
    wipe(histDropRows)

    local rowH = 26
    local maxVisible = 12
    local visRows = _min(#runs, maxVisible)
    local colW = {24, 140, 36, 50, 80}
    local DEL_W = 22
    local dropW = 8 + colW[1] + colW[2] + colW[3] + colW[4] + colW[5] + DEL_W +
                      8

    drop:SetSize(dropW, visRows * rowH + rowH + 3) -- +rowH for the Clear All row

    local fp = _FONT_PATH

    local yOff = 0
    for idx, run in ipairs(runs) do
        local row = CreateFrame("Button", nil, drop)
        row:SetSize(dropW - 2, rowH)
        row:SetPoint("TOPLEFT", drop, "TOPLEFT", 1, -1 + yOff)
        row:EnableMouse(true)

        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        if idx % 2 == 0 then
            rbg:SetColorTexture(C.rowEven[1], C.rowEven[2], C.rowEven[3], 1)
        else
            rbg:SetColorTexture(C.rowOdd[1], C.rowOdd[2], C.rowOdd[3], 1)
        end

        local hov = row:CreateTexture(nil, "ARTWORK")
        hov:SetAllPoints()
        hov:SetColorTexture(0.20, 0.35, 0.55, 0.55)
        hov:Hide()
        row:SetScript("OnEnter", function() hov:Show() end)
        row:SetScript("OnLeave", function() hov:Hide() end)

        local isMPlus = (run.keystoneLevel or 0) > 0
        local dur = MS:GetRunDuration(run)
        local result, rr, rg, rb2
        if run.completed then
            if isMPlus then
                if run.inTime then
                    result, rr, rg, rb2 = "In Time", 0.27, 1.0, 0.27
                else
                    result, rr, rg, rb2 = "Overtime", 1.0, 0.55, 0.15
                end
            else
                result, rr, rg, rb2 = "Cleared", 0.27, 1.0, 0.27
            end
        else
            result, rr, rg, rb2 = "Abandoned", 0.50, 0.50, 0.50
        end

        local diffText, diffR, diffG, diffB
        if isMPlus then
            diffText = "+" .. run.keystoneLevel
            diffR, diffG, diffB = C.titleGold[1], C.titleGold[2], C.titleGold[3]
        else
            local label = run.difficultyLabel or ""
            if label:find("Follower") then
                diffText = "F"
            elseif label == "Timewalking" then
                diffText = "TW"
            else
                diffText = label ~= "" and label or "?"
            end
            diffR, diffG, diffB = C.stat[1], C.stat[2], C.stat[3]
        end

        local rowCols = {
            {
                text = tostring(idx),
                r = C.bossTime[1],
                g = C.bossTime[2],
                b = C.bossTime[3],
                j = "CENTER"
            }, {
                text = run.dungeonName or "?",
                r = C.white[1],
                g = C.white[2],
                b = C.white[3],
                j = "LEFT"
            }, {text = diffText, r = diffR, g = diffG, b = diffB, j = "CENTER"},
            {
                text = MS:FormatTime(dur),
                r = C.stat[1],
                g = C.stat[2],
                b = C.stat[3],
                j = "CENTER"
            }, {text = result, r = rr, g = rg, b = rb2, j = "LEFT"}
        }
        local rx = 8
        for ci, rc in ipairs(rowCols) do
            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("LEFT", row, "LEFT", rx, 0)
            lbl:SetSize(colW[ci], rowH)
            lbl:SetJustifyH(rc.j)
            lbl:SetText(rc.text)
            lbl:SetTextColor(rc.r, rc.g, rc.b)
            lbl:SetFont(fp, 12, "")
            rx = rx + colW[ci]
        end

        local delBtn = CreateFrame("Button", nil, row)
        delBtn:SetSize(DEL_W, rowH)
        delBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        delBtn:EnableMouse(true)
        delBtn:SetFrameLevel(row:GetFrameLevel() + 2)

        local delBg = delBtn:CreateTexture(nil, "BACKGROUND")
        delBg:SetAllPoints()
        delBg:SetColorTexture(0.50, 0.06, 0.06, 0) -- starts transparent

        local delTxt = delBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        delTxt:SetAllPoints()
        delTxt:SetJustifyH("CENTER")
        delTxt:SetText("×")
        delTxt:SetTextColor(0.55, 0.18, 0.18)
        delTxt:SetFont(fp, 13, "")

        delBtn:SetScript("OnEnter", function()
            delBg:SetColorTexture(0.60, 0.08, 0.08, 0.85)
            delTxt:SetTextColor(1.00, 0.35, 0.35)
            hov:Hide()
            GameTooltip:SetOwner(delBtn, "ANCHOR_RIGHT")
            GameTooltip:SetText("Delete run", 1, 0.4, 0.4)
            GameTooltip:AddLine("Removes this run from history.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        delBtn:SetScript("OnLeave", function()
            delBg:SetColorTexture(0.50, 0.06, 0.06, 0)
            delTxt:SetTextColor(0.55, 0.18, 0.18)
            GameTooltip:Hide()
        end)

        local capturedIdx = idx
        local function DeleteRun()
            GameTooltip:Hide()
            if MythicScoreboardDB and MythicScoreboardDB.runs then
                _rem(MythicScoreboardDB.runs, capturedIdx)
                if MS.currentRun == run then MS.currentRun = nil end
                -- If the deleted run was being displayed, clear the selection
                -- so the scoreboard falls back to runs[1].
                if MS.displayRun == run then MS.displayRun = nil end
                runs = MythicScoreboardDB.runs
            end
            if #runs == 0 then
                CloseHistDropdown()
            else
                BuildHistDropdownRows(drop, runs, anchorBtn)
            end
            MS:RefreshOverview()
        end

        delBtn:SetScript("OnClick", DeleteRun)

        local sep = row:CreateTexture(nil, "OVERLAY")
        sep:SetHeight(1)
        sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        sep:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.5)

        local capturedRun = run
        row:SetScript("OnClick", function()
            MS.displayRun = capturedRun
            CloseHistDropdown()
            MS:RefreshOverview()
        end)

        yOff = yOff - rowH
        _ins(histDropRows, row)
    end

    -- ── Clear All History row ─────────────────────────────────────────────
    local clearAllArmed = false
    local clearAllTimer = nil

    local clearRow = CreateFrame("Button", nil, drop)
    clearRow:SetSize(dropW - 2, rowH)
    clearRow:SetPoint("TOPLEFT", drop, "TOPLEFT", 1, -1 + yOff)
    clearRow:EnableMouse(true)
    clearRow:SetFrameLevel(drop:GetFrameLevel() + 2)

    local sepLine = clearRow:CreateTexture(nil, "OVERLAY")
    sepLine:SetHeight(1)
    sepLine:SetPoint("TOPLEFT", clearRow, "TOPLEFT", 0, 0)
    sepLine:SetPoint("TOPRIGHT", clearRow, "TOPRIGHT", 0, 0)
    sepLine:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.7)

    local caBg = clearRow:CreateTexture(nil, "BACKGROUND")
    caBg:SetAllPoints()
    caBg:SetColorTexture(0.12, 0.04, 0.04, 1)

    local caHov = clearRow:CreateTexture(nil, "ARTWORK")
    caHov:SetAllPoints()
    caHov:SetColorTexture(0.50, 0.06, 0.06, 0)

    local caTxt = clearRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    caTxt:SetAllPoints()
    caTxt:SetJustifyH("CENTER")
    caTxt:SetText("Clear All History")
    caTxt:SetTextColor(0.75, 0.22, 0.22)
    caTxt:SetFont(fp, 12, "")

    local function DisarmClearAll()
        clearAllArmed = false
        if clearAllTimer then
            clearAllTimer:Cancel();
            clearAllTimer = nil
        end
        caTxt:SetText("Clear All History")
        caTxt:SetTextColor(0.75, 0.22, 0.22)
        caHov:SetColorTexture(0.50, 0.06, 0.06, 0)
    end

    clearRow:SetScript("OnEnter", function()
        if clearAllArmed then
            caHov:SetColorTexture(0.65, 0.08, 0.08, 0.90)
            caTxt:SetTextColor(1.0, 0.30, 0.30)
            GameTooltip:SetOwner(clearRow, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Confirm clear?", 1, 0.3, 0.3)
            GameTooltip:AddLine("Click again to delete all runs.", 1, 0.6, 0.6)
        else
            caHov:SetColorTexture(0.40, 0.06, 0.06, 0.70)
            caTxt:SetTextColor(1.0, 0.40, 0.40)
            GameTooltip:SetOwner(clearRow, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Clear All History", 1, 0.4, 0.4)
            GameTooltip:AddLine("Removes all saved runs.", 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    clearRow:SetScript("OnLeave", function()
        if not clearAllArmed then
            caHov:SetColorTexture(0.50, 0.06, 0.06, 0)
            caTxt:SetTextColor(0.75, 0.22, 0.22)
        end
        GameTooltip:Hide()
    end)
    clearRow:SetScript("OnClick", function()
        if clearAllArmed then
            DisarmClearAll()
            CloseHistDropdown()
            DoClearHistory()
        else
            clearAllArmed = true
            caTxt:SetText("Confirm — click to clear")
            caTxt:SetTextColor(1.0, 0.30, 0.30)
            caHov:SetColorTexture(0.50, 0.06, 0.06, 0.55)
            GameTooltip:Hide()
            clearAllTimer = C_Timer.NewTimer(3, DisarmClearAll)
        end
    end)

    _ins(histDropRows, clearRow)
end

local function OpenHistDropdown(anchorBtn)
    if histDropdown then
        CloseHistDropdown();
        return
    end

    local runs = (MythicScoreboardDB and MythicScoreboardDB.runs) or {}
    if #runs == 0 then
        print("|cff00ccff[MythicScoreboard]|r No history yet.")
        return
    end

    local drop = CreateFrame("Frame", nil, UIParent)
    drop:SetFrameStrata("TOOLTIP")
    drop:EnableMouse(true)
    drop:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)

    if sbFrame then sbFrame:EnableMouse(false) end

    drop:SetScript("OnEnter", function() end)
    drop:SetScript("OnLeave", function() end)
    drop:SetScript("OnHide", function()
        -- cleanup handled by CloseHistDropdown; this fires if hidden externally (e.g. ESC)
        if histDropdown then CloseHistDropdown() end
    end)

    local dborder = drop:CreateTexture(nil, "BACKGROUND")
    dborder:SetAllPoints()
    dborder:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    local dbg = drop:CreateTexture(nil, "BACKGROUND")
    dbg:SetPoint("TOPLEFT", drop, "TOPLEFT", 1, -1)
    dbg:SetPoint("BOTTOMRIGHT", drop, "BOTTOMRIGHT", -1, 1)
    dbg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.97)

    BuildHistDropdownRows(drop, runs, anchorBtn)

    histDropdown = drop
end

-- Canonical timeline duration for a run.  Used by both the rebuild path
-- (full computation) and the live-update path (fast call on every refresh).
-- Returns the number of seconds the timeline axis should span:
--   • endTime-based for completed runs
--   • keystoneTimeLimit (or live C_ChallengeMode query) for in-progress M+
--   • GetRunDuration fallback for non-M+ or unknown state
-- Boss kill times past the computed window are accommodated (+30 s buffer).
-- A 60 s pad past the key timer ensures the completion marker is never clipped.
-- ---------------------------------------------------------------------------
-- Timeline
-- ---------------------------------------------------------------------------

local function GetTimelineDuration(r)
    if not r then return 1 end
    local dur = 0
    if r.endTime and r.endTime > 0 then
        local d = r.endTime - (r.startTime or 0)
        -- A dungeon run cannot exceed 2 hours; guard against corrupt startTime.
        if d > 0 and d < 7200 then dur = d end
    elseif tonumber(r.keystoneTimeLimit) and r.keystoneTimeLimit > 0 then
        dur = r.keystoneTimeLimit
    elseif MS.DUNGEON_TIMERS and r.dungeonName and
        MS.DUNGEON_TIMERS[r.dungeonName] then
        -- Known dungeon — use the hardcoded limit immediately so the timeline
        -- is correct even before the API-based limit is populated.
        dur = MS.DUNGEON_TIMERS[r.dungeonName]
    elseif (r.keystoneLevel or 0) > 0 then
        -- Try GetDeadlineExpiration first
        if C_ChallengeMode and C_ChallengeMode.GetDeadlineExpiration then
            local expTime = C_ChallengeMode.GetDeadlineExpiration()
            if expTime and expTime > 0 then
                local limit = expTime - r.startTime
                if limit > 10 and limit < 7200 then dur = limit end
            end
        end
        if dur <= 0 and C_ChallengeMode and
            C_ChallengeMode.GetActiveKeystoneInfo then
            local _, _, timeLimit = C_ChallengeMode.GetActiveKeystoneInfo()
            local tl = tonumber(timeLimit)
            if tl and tl > 10 and tl < 7200 then dur = tl end
        end
    end
    if dur <= 0 then dur = _max(1, MS:GetRunDuration(r)) end
    -- For a live M+ run whose time limit we still can't determine, use a
    -- sensible minimum window rather than elapsed + a fixed pad, so the
    -- right-side label doesn't show a misleading near-future time.
    if (r.keystoneLevel or 0) > 0 and not r.completed then
        local elapsed = MS:GetRunDuration(r)
        if elapsed >= dur - 15 then
            -- At least 30 min total, or 5 min of runway ahead — whichever is larger.
            dur = _max(elapsed + 5 * 60, 30 * 60)
        end
    end
    if r.bosses then
        for _, b in ipairs(r.bosses) do
            if b.killTime and b.killTime > dur then
                dur = b.killTime + 30
            end
        end
    end
    if tonumber(r.keystoneTimeLimit) and r.keystoneTimeLimit > 0 then
        dur = _max(dur, r.keystoneTimeLimit)
    end
    -- For completed M+ runs, extend the axis to the full dungeon timer so the
    -- green "time saved" region after completion is clearly visible.
    if (r.keystoneLevel or 0) > 0 and r.completed then
        if MS.DUNGEON_TIMERS and r.dungeonName and
            MS.DUNGEON_TIMERS[r.dungeonName] then
            dur = _max(dur, MS.DUNGEON_TIMERS[r.dungeonName])
        end
    end
    return dur
end

local tlView = {
    height = BOTTOM_H -- resizable via drag handle
}

local TL_HEIGHT_MIN = 130
local TL_HEIGHT_MAX = 251
local TL_MARGIN = 6

local function FracToX(frac, trackW)
    if frac < 0 or frac >= 1 then return nil end
    return TL_MARGIN + frac * trackW
end

-- Like FracToX but clamps frac to [0, 1] rather than returning nil at the
-- right edge.  Used for elements (completion marker, last-boss chip) that
-- must always render even when the run finishes exactly at the time limit.
local function FracToXClamped(frac, trackW)
    frac = _max(0.0, _min(1.0, frac))
    return TL_MARGIN + frac * trackW
end

local function BuildTimeline(strip, run, totalDur, rebuildFn)

    -- Purge all child frames and regions (textures, font strings) from the
    -- previous build before creating new ones.  We cannot destroy WoW frames,
    -- so children are detached (re-parented to UIParent) and hidden; regions
    -- on the strip itself are also hidden.  This is an iterative BFS to avoid
    -- stack overflows when many frames accumulate across repeated rebuilds.
    strip._rebuildPending = false
    local function PurgeFrameTree(root)
        -- Iterative BFS instead of recursion to avoid stack overflows when many
        -- frames accumulate across repeated zoom cycles.  Re-parent each child
        -- BEFORE enqueuing it so its subtree is detached immediately, preventing
        -- double-visits of frames that were orphaned by a previous rebuild.
        local queue = {root}
        local i = 1
        while i <= #queue do
            local f = queue[i]
            i = i + 1
            for _, child in ipairs({f:GetChildren()}) do
                child:SetParent(UIParent) -- detach before enqueue
                queue[#queue + 1] = child
            end
            -- Hide and detach all regions (textures, fontstrings) on this frame
            for _, region in ipairs({f:GetRegions()}) do
                region:Hide()
                pcall(region.ClearAllPoints, region)
            end
            if f ~= root then
                f:Hide()
                pcall(f.ClearAllPoints, f)
                pcall(f.SetScript, f, "OnUpdate", nil)
                pcall(f.SetScript, f, "OnEnter", nil)
                pcall(f.SetScript, f, "OnLeave", nil)
                pcall(f.SetScript, f, "OnClick", nil)
                pcall(f.SetScript, f, "OnMouseDown", nil)
                pcall(f.SetScript, f, "OnMouseUp", nil)
                pcall(f.EnableMouse, f, false)
            end
        end
    end
    PurgeFrameTree(strip)
    for _, region in ipairs({strip:GetRegions()}) do region:Hide() end

    -- For completed runs, synthesise any missing interruptEvents / dispelEvents
    -- so timeline markers appear even for runs recorded before these fields existed.
    if run and run.completed and run.players then
        MS:_BackfillSyntheticInterrupts(run)
    end

    strip:ClearAllPoints()
    strip:SetPoint("BOTTOMLEFT", strip:GetParent(), "BOTTOMLEFT", 1, 1)
    strip:SetPoint("BOTTOMRIGHT", strip:GetParent(), "BOTTOMRIGHT", -1, 1)
    strip:SetHeight(tlView.height)
    strip:Show()
    SetBG(strip, C.bg[1], C.bg[2], C.bg[3], 1)
    HLine(strip, 0)

    local topEdge = strip:CreateTexture(nil, "OVERLAY")
    topEdge:SetHeight(2)
    topEdge:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
    topEdge:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)
    topEdge:SetColorTexture(0.38, 0.50, 0.80, 0.45)
    local botFade1 = strip:CreateTexture(nil, "BORDER")
    botFade1:SetHeight(14)
    botFade1:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
    botFade1:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)
    botFade1:SetColorTexture(0.01, 0.01, 0.03, 0.45)
    local botFade2 = strip:CreateTexture(nil, "BORDER")
    botFade2:SetHeight(6)
    botFade2:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
    botFade2:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)
    botFade2:SetColorTexture(0.00, 0.00, 0.02, 0.65)

    local BAR_Y = 48
    local TICK_H = 22
    local BAR_H = 16
    local bt1, bt2, bt3 = C.bossTime[1], C.bossTime[2], C.bossTime[3]

    -- Dynamic label-row layout state.  Safe defaults cover the no-boss path;
    -- the pre-computation block inside the boss section overwrites these before
    -- the completion-marker and skull-marker blocks consume them.
    local TS_ROW_H = 16 -- pull-timestamp row height in px (11 pt font + gap)
    local BN_ROW_H = 18 -- boss-name row height in px (13 pt font + gap)
    local TS_BASE_Y = BAR_Y + BAR_H + TICK_H + 4
    local BN_BASE_Y = TS_BASE_Y
    local LBL_TOP_Y = BN_BASE_Y + BN_ROW_H + 6
    local bossPullTsY = {} -- [bossIdx] → Y for that boss's pull timestamp label
    local bossNameY = {} -- [bossIdx] → Y for that boss's name label

    -- trackW must be read lazily because strip:GetWidth() returns 0 on the
    -- very first build (frame not yet laid out by the UI engine).  Re-query
    -- at draw time so the green "time saved" tail renders correctly without
    -- requiring a zoom cycle to force a re-layout.
    local function GetTrackW()
        local w = strip:GetWidth()
        if not w or w <= 0 then w = FRAME_W end
        return w - TL_MARGIN * 2
    end
    local trackW = GetTrackW()

    local barTrack = strip:CreateTexture(nil, "BACKGROUND")
    barTrack:SetHeight(BAR_H)
    barTrack:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", TL_MARGIN, BAR_Y - 1)
    barTrack:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -TL_MARGIN, BAR_Y - 1)
    barTrack:SetColorTexture(0.03, 0.04, 0.07, 1)
    local barShadTop = strip:CreateTexture(nil, "BORDER")
    barShadTop:SetHeight(2)
    barShadTop:SetPoint("TOPLEFT", barTrack, "TOPLEFT", 0, 0)
    barShadTop:SetPoint("TOPRIGHT", barTrack, "TOPRIGHT", 0, 0)
    barShadTop:SetColorTexture(0, 0, 0, 0.55)
    -- Faint bottom-rim glow
    local barGlowBot = strip:CreateTexture(nil, "BORDER")
    barGlowBot:SetHeight(1)
    barGlowBot:SetPoint("BOTTOMLEFT", barTrack, "BOTTOMLEFT", 0, 0)
    barGlowBot:SetPoint("BOTTOMRIGHT", barTrack, "BOTTOMRIGHT", 0, 0)
    barGlowBot:SetColorTexture(0.30, 0.40, 0.65, 0.18)

    local fontPath = _FONT_PATH

    if totalDur and totalDur > 0 then
        local viewStartSec = 0
        local viewEndSec = totalDur
        local stripPx = strip:GetWidth() or FRAME_W
        local labelW = 55
        local showBoth = stripPx >= (labelW * 2 + 40)

        local t0 = strip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t0:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", TL_MARGIN, 6)
        t0:SetWidth(labelW)
        t0:SetJustifyH("LEFT")
        t0:SetTextColor(bt1, bt2, bt3)
        t0:SetText(MS:FormatTime(viewStartSec))
        t0:SetFont(fontPath, 12, "")

        if showBoth then
            local tEnd =
                strip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            tEnd:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -TL_MARGIN, 6)
            tEnd:SetWidth(labelW)
            tEnd:SetJustifyH("RIGHT")
            tEnd:SetTextColor(bt1, bt2, bt3)
            tEnd:SetText(MS:FormatTime(viewEndSec))
            tEnd:SetFont(fontPath, 12, "")
        end
    end

    if totalDur and totalDur > 0 then
        local viewStart = 0
        local viewEnd = totalDur
        local viewSpan = viewEnd - viewStart
        local tickInterval
        if viewSpan <= 3 * 60 then
            tickInterval = 30
        elseif viewSpan <= 8 * 60 then
            tickInterval = 60
        elseif viewSpan <= 15 * 60 then
            tickInterval = 2 * 60
        else
            tickInterval = 5 * 60
        end

        local firstTick = _ceil(viewStart / tickInterval) * tickInterval
        local t = firstTick
        while t < viewEnd do
            local frac = t / totalDur
            local tx = FracToX(frac, trackW)
            if tx then
                local isMajor = (t % (tickInterval * 5) == 0) or tickInterval >=
                                    5 * 60
                local tickH = isMajor and 7 or 3
                local tickA = isMajor and 0.50 or 0.18

                local tickLine = strip:CreateTexture(nil, "ARTWORK")
                tickLine:SetSize(1, tickH)
                tickLine:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", tx, BAR_Y - 1)
                tickLine:SetColorTexture(1, 1, 1, tickA)

                if isMajor and tx > 55 and (trackW + TL_MARGIN - tx) > 55 then
                    local tickLbl = strip:CreateFontString(nil, "OVERLAY",
                                                           "GameFontNormal")
                    tickLbl:SetPoint("BOTTOM", strip, "BOTTOMLEFT", tx, 6)
                    tickLbl:SetText(MS:FormatTime(t))
                    tickLbl:SetTextColor(0.55, 0.60, 0.70)
                    tickLbl:SetFont(fontPath, 10, "")
                    tickLbl:SetJustifyH("CENTER")
                    tickLbl:SetWidth(50)
                end
            end
            t = t + tickInterval
        end
    end

    local clipFrame = CreateFrame("Frame", nil, strip)
    clipFrame:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", TL_MARGIN, 0)
    clipFrame:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -TL_MARGIN, 0)
    clipFrame:SetClipsChildren(true)

    -- Visual completion point: max(endTime-startTime, lastBossKillTime).
    -- ENCOUNTER_END for the last boss can fire after CHALLENGE_MODE_COMPLETED,
    -- making killTime > endTime-startTime.  Both the trailing segment and the
    -- gold completion marker use this value so they always agree.
    local visualEndSec
    if run and run.completed and run.endTime and run.endTime > 0 then
        visualEndSec = run.endTime - (run.startTime or 0)
        if run.bosses then
            for _, b in ipairs(run.bosses) do
                if b.killTime and b.killTime > visualEndSec then
                    visualEndSec = b.killTime
                end
            end
        end
    end

    if run and run.bosses and totalDur and totalDur > 0 then
        -- Hues chosen to avoid all 13 class colors.
        -- Rose, fuchsia, cornflower sit in genuinely unoccupied hue regions.
        -- Violet and amber were already safe and are kept.
        local bossHues = {
            {fight = {0.90, 0.28, 0.38}, trash = {0.34, 0.10, 0.14}}, -- rose      (≠ DK crimson, ≠ Druid orange)
            {fight = {0.48, 0.36, 0.68}, trash = {0.18, 0.13, 0.28}}, -- violet    (kept from original)
            {fight = {0.88, 0.24, 0.72}, trash = {0.34, 0.09, 0.28}}, -- fuchsia   (≠ DH purple, ≠ Paladin pastel)
            {fight = {0.40, 0.60, 0.90}, trash = {0.15, 0.22, 0.34}}, -- cornflower(≠ Mage cyan, ≠ Shaman blue)
            {fight = {0.90, 0.62, 0.12}, trash = {0.34, 0.22, 0.04}} -- amber     (kept from original)
        }

        local prevFrac = 0
        local livePct = run.currentPct

        local function DrawSeg(frac1, frac2, r, g, b, noGap)
            -- Re-query width each call: on the first build strip:GetWidth()
            -- may have been 0 when trackW was captured, so segments (especially
            -- the green "time saved" tail) would render at the wrong size or
            -- not at all until a zoom cycle forced a rebuild with a real width.
            local tw = GetTrackW()
            if frac1 > 1.0 then return end
            local x1 = TL_MARGIN + _max(frac1, 0) * tw
            local x2 = TL_MARGIN + _min(frac2, 1.0) * tw
            -- 1px gap between adjacent segments so each phase reads as discrete
            local w = _max(1, x2 - x1 - (noGap and 0 or 1))
            local seg = clipFrame:CreateTexture(nil, "ARTWORK")
            seg:SetHeight(BAR_H)
            seg:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT", x1 - TL_MARGIN,
                         BAR_Y - 1)
            seg:SetWidth(w)
            seg:SetColorTexture(r, g, b, 1)
            if w >= 3 then
                local sh = clipFrame:CreateTexture(nil, "OVERLAY")
                sh:SetSize(w, 1)
                sh:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT",
                            x1 - TL_MARGIN, BAR_Y - 1)
                sh:SetColorTexture(0, 0, 0, 0.40)
            end
        end

        local function MakeLabel(x, y, text, r, g, b, w, justify)
            local lbl = clipFrame:CreateFontString(nil, "OVERLAY",
                                                   "GameFontNormal")
            lbl:SetPoint("BOTTOM", clipFrame, "BOTTOMLEFT", x - TL_MARGIN, y)
            lbl:SetText(text)
            lbl:SetTextColor(r, g, b)
            lbl:SetFont(fontPath, 11, "")
            lbl:SetJustifyH(justify or "CENTER")
            lbl:SetWidth(w)
        end

        -- Inside-bar label: smaller, white at low alpha so it doesn't compete
        -- with the boss name chip above.
        local function MakeBarLabel(x, text, w)
            local lbl = clipFrame:CreateFontString(nil, "OVERLAY",
                                                   "GameFontNormal")
            lbl:SetPoint("BOTTOM", clipFrame, "BOTTOMLEFT", x - TL_MARGIN, 25)
            lbl:SetText(text)
            lbl:SetTextColor(1, 1, 1, 0.90)
            lbl:SetFont(fontPath, 10, "OUTLINE")
            lbl:SetJustifyH("CENTER")
            lbl:SetWidth(w)
        end

        local function CountDeathsInWindow(t1, t2)
            local n = 0
            for _, p in pairs(run.players) do
                for _, de in ipairs(p.deathEvents or {}) do
                    if (de.time or 0) >= t1 and (de.time or 0) <= t2 then
                        n = n + 1
                    end
                end
            end
            return n
        end

        local function MakeSegBtn(x1, x2, ttTitle, tr, tg, tb, ttLines)
            local bx = _max(TL_MARGIN, x1)
            local bw = _max(1, x2 - x1)
            if bw < 4 then return end
            local segBtn = CreateFrame("Button", nil, strip)
            segBtn:SetSize(bw, BAR_H + TICK_H)
            segBtn:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", bx, BAR_Y - 1)
            segBtn:SetFrameLevel(strip:GetFrameLevel() + 4)
            segBtn:EnableMouse(true)
            local captTitle, captR, captG, captB, captLines = ttTitle, tr, tg,
                                                              tb, ttLines
            segBtn:SetScript("OnEnter", function(self2)
                GameTooltip:SetOwner(self2, "ANCHOR_TOP")
                GameTooltip:SetText(captTitle, captR, captG, captB)
                if captLines then
                    for _, line in ipairs(captLines) do
                        GameTooltip:AddLine(line, 1, 1, 1)
                    end
                end
                GameTooltip:Show()
            end)
            segBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        -- ── Dynamic label-row pre-computation ─────────────────────────────────
        -- Greedy bin-packing: sort all labels by left edge, assign each to the
        -- lowest available row where it doesn't overlap its left neighbour
        -- (with a LABEL_PAD px gap).  Results populate bossPullTsY / bossNameY
        -- for the loop below, and LBL_TOP_Y is raised so skull markers always
        -- sit clear of every label row.
        do
            local LABEL_PAD = 6
            local MAX_ROWS = 5

            local function PackRows(items)
                _sort(items, function(a, b) return a.x1 < b.x1 end)
                local rowRight = {}
                for r = 1, MAX_ROWS do rowRight[r] = -_huge end
                local rows, maxRow = {}, 0
                for _, it in ipairs(items) do
                    local row = MAX_ROWS
                    for r = 1, MAX_ROWS do
                        if it.x1 - rowRight[r] >= LABEL_PAD then
                            row = r;
                            break
                        end
                    end
                    rowRight[row] = it.x2
                    rows[it.idx] = row
                    if row > maxRow then maxRow = row end
                end
                return rows, _max(1, maxRow)
            end

            local tsItems, bnItems = {}, {}
            for bi, boss2 in ipairs(run.bosses) do
                local pf = _min(1.0, (boss2.pullTime or 0) / totalDur)
                local kf = _min(1.0, (boss2.killTime or boss2.wipeTime or
                                    boss2.pullTime or 0) / totalDur)
                local pX = FracToX(pf, trackW)
                local mX = FracToX((pf + kf) / 2, trackW) or (pX and pX + 20)
                if pX then
                    -- Pull timestamps are left-aligned within ~62 px
                    _ins(tsItems, {idx = bi, x1 = pX, x2 = pX + 62})
                end
                if mX then
                    -- Boss names are centred; approximate half-width at ~7 px/char
                    local hw = _max(28, _ceil(#(boss2.name or "Boss") * 7))
                    _ins(bnItems, {idx = bi, x1 = mX - hw, x2 = mX + hw})
                end
            end

            local tsRows, maxTsRow = PackRows(tsItems)
            local bnRows, maxBnRow = PackRows(bnItems)

            TS_BASE_Y = BAR_Y + BAR_H + TICK_H + 4
            BN_BASE_Y = TS_BASE_Y + maxTsRow * TS_ROW_H + 4
            LBL_TOP_Y = BN_BASE_Y + maxBnRow * BN_ROW_H + 6

            for bi = 1, #run.bosses do
                bossPullTsY[bi] = TS_BASE_Y + ((tsRows[bi] or 1) - 1) * TS_ROW_H
                bossNameY[bi] = BN_BASE_Y + ((bnRows[bi] or 1) - 1) * BN_ROW_H
            end
        end
        -- ── end pre-computation ────────────────────────────────────────────────

        for i, boss in ipairs(run.bosses) do
            local hue = bossHues[((i - 1) % #bossHues) + 1]
            local pullFrac = _min(1.0, (boss.pullTime or 0) / totalDur)
            -- Wipe entries have wipeTime instead of killTime.
            local isWipe = boss.wipeTime and not boss.killTime
            local endTime = boss.killTime or boss.wipeTime or boss.pullTime or 0
            local killFrac = _min(1.0, endTime / totalDur)

            DrawSeg(prevFrac, pullFrac, hue.trash[1], hue.trash[2], hue.trash[3])
            do
                local tx1 = FracToX(prevFrac, trackW) or TL_MARGIN
                local tx2 = FracToX(pullFrac, trackW) or (TL_MARGIN + trackW)
                local trashDurSec = (boss.pullTime or 0) - prevFrac * totalDur
                local trashDeaths = CountDeathsInWindow(prevFrac * totalDur,
                                                        boss.pullTime or 0)
                local trashLines = {
                    _fmt("|cffccccccDuration:|r  %s", MS:FormatTime(trashDurSec))
                }
                if boss.pullProgressPct then
                    _ins(trashLines, _fmt("|cffccccccProgress:|r  %d%%",
                                          boss.pullProgressPct))
                end
                if trashDeaths > 0 then
                    _ins(trashLines,
                         _fmt("|cffff4444Deaths:|r  %d", trashDeaths))
                end
                MakeSegBtn(tx1, tx2, "Trash", hue.trash[1] + 0.2,
                           hue.trash[2] + 0.2, hue.trash[3] + 0.2, trashLines)
            end

            -- Boss/wipe fight bar
            if isWipe then
                -- Render wipe bar in a desaturated dark red to distinguish from a kill.
                DrawSeg(pullFrac, killFrac, 0.45, 0.10, 0.10)
            else
                DrawSeg(pullFrac, killFrac, hue.fight[1], hue.fight[2],
                        hue.fight[3])
            end
            do
                local bx1 = FracToX(pullFrac, trackW) or TL_MARGIN
                local bx2 = FracToX(killFrac, trackW) or (TL_MARGIN + trackW)
                local fightDurSec = endTime - (boss.pullTime or 0)
                local bossDeaths = CountDeathsInWindow(boss.pullTime or 0,
                                                       endTime)
                local bossLines = {
                    _fmt("|cffccccccDuration:|r  %s", MS:FormatTime(fightDurSec))
                }
                if isWipe then
                    _ins(bossLines, "|cffff4444Wipe|r")
                end
                if bossDeaths > 0 then
                    _ins(bossLines, _fmt("|cffff4444Deaths:|r  %d", bossDeaths))
                end
                local segLabel = isWipe and (boss.name or "Boss") or
                                     (boss.name or "Boss")
                MakeSegBtn(bx1, bx2, segLabel, isWipe and 0.45 or hue.fight[1],
                           isWipe and 0.10 or hue.fight[2],
                           isWipe and 0.10 or hue.fight[3], bossLines)
            end

            local pullX = FracToX(pullFrac, trackW)
            if pullX then
                -- Soft hue-colored glow behind the pull marker
                local edgeGlow = clipFrame:CreateTexture(nil, "ARTWORK")
                edgeGlow:SetSize(5, BAR_H + 6)
                edgeGlow:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT",
                                  pullX - TL_MARGIN - 2, BAR_Y - 2)
                local gr, gg, gb = isWipe and 0.45 or hue.fight[1],
                                   isWipe and 0.10 or hue.fight[2],
                                   isWipe and 0.10 or hue.fight[3]
                edgeGlow:SetColorTexture(gr, gg, gb, 0.18)
                local edge = clipFrame:CreateTexture(nil, "OVERLAY")
                edge:SetSize(2, BAR_H + 4)
                edge:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT",
                              pullX - TL_MARGIN, BAR_Y - 2)
                edge:SetColorTexture(1, 1, 1, 0.65)

                local tick = clipFrame:CreateTexture(nil, "ARTWORK")
                tick:SetSize(1, TICK_H)
                tick:SetPoint("BOTTOM", clipFrame, "BOTTOMLEFT",
                              pullX - TL_MARGIN, BAR_Y + BAR_H - 1)
                tick:SetColorTexture(gr, gg, gb, 0.80)

                -- Keep text clear of the pull tick line.
                -- Normal: box starts 4px right of tick (text to the right).
                -- Near right edge: box ends 4px left of tick (text to the left).
                local tsLabelW = 60
                local nearRight = (pullX - TL_MARGIN) + tsLabelW > trackW - 8
                local tsX = nearRight and (pullX - 64) or (pullX + 4)
                MakeLabel(tsX, bossPullTsY[i],
                          MS:FormatTime(boss.pullTime or 0), gr, gg, gb,
                          tsLabelW, "LEFT")
            end

            local killX = FracToX(killFrac, trackW)
            -- Skip the white kill tick if this boss kill IS the completion point —
            -- the gold completion line renders there instead.
            -- Also skip the kill tick for wipes (there is no kill).
            local isCompletionBoss = visualEndSec and
                                         (boss.killTime == visualEndSec)
            if killX and not isCompletionBoss and not isWipe then
                -- Soft glow behind the kill marker
                local ktGlow = clipFrame:CreateTexture(nil, "ARTWORK")
                ktGlow:SetSize(5, TICK_H)
                ktGlow:SetPoint("BOTTOM", clipFrame, "BOTTOMLEFT",
                                killX - TL_MARGIN - 2, BAR_Y + BAR_H - 1)
                ktGlow:SetColorTexture(0.95, 0.95, 0.95, 0.12)
                local kt = clipFrame:CreateTexture(nil, "OVERLAY")
                kt:SetSize(2, TICK_H)
                kt:SetPoint("BOTTOM", clipFrame, "BOTTOMLEFT",
                            killX - TL_MARGIN, BAR_Y + BAR_H - 1)
                kt:SetColorTexture(0.95, 0.95, 0.95, 0.90)
            end

            local fightMidFrac = (pullFrac + killFrac) / 2
            -- Use the clamped variant as the final fallback so the boss name
            -- chip always renders for the last boss even when killFrac >= 1.0.
            local midX =
                FracToX(fightMidFrac, trackW) or (pullX and pullX + 20) or
                    (killX and killX - 20) or
                    FracToXClamped(fightMidFrac, trackW)
            if midX then
                local visW = _max(20, (_min(killFrac, 1.0) - pullFrac) * trackW)

                -- ── Boss name / Wipe chip ──────────────────────────────────
                -- Chip is parented to clipFrame so its X is in the same
                -- coordinate space as every other element (midX - TL_MARGIN).
                -- Note: avoid non-ASCII symbols (e.g. ✗) — WoW's Friz Quadrata
                -- font lacks many Unicode glyphs and renders them as "[]".
                local bossLabel = isWipe and
                                      ((boss.name or "Boss") .. " (Wipe)") or
                                      (boss.name or "Boss")
                local CHIP_H = 16
                local CHIP_PAD = 6
                -- 12pt GameFontNormal is ~9px/char; pad both sides
                local chipW = _max(60, _ceil(#bossLabel * 9) + CHIP_PAD * 2)
                local chipCX = midX - TL_MARGIN
                -- Clamp so the chip stays fully within the clipFrame.
                local chipLeft = _max(0,
                                      _min(chipCX - chipW / 2, trackW - chipW))

                local chip = CreateFrame("Frame", nil, clipFrame)
                chip:SetSize(chipW, CHIP_H)
                chip:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT", chipLeft,
                              bossNameY[i])
                chip:SetFrameLevel(clipFrame:GetFrameLevel() + 3)

                -- border: wipe = dark red, kill = normal hue
                local cbr, cbg, cbb = isWipe and 0.55 or hue.fight[1] * 0.70,
                                      isWipe and 0.12 or hue.fight[2] * 0.70,
                                      isWipe and 0.12 or hue.fight[3] * 0.70
                local chipBorder = chip:CreateTexture(nil, "BACKGROUND")
                chipBorder:SetAllPoints()
                chipBorder:SetColorTexture(cbr, cbg, cbb, 1.0)
                -- dark fill inset 1px
                local chipFill = chip:CreateTexture(nil, "BORDER")
                chipFill:SetPoint("TOPLEFT", chip, "TOPLEFT", 1, -1)
                chipFill:SetPoint("BOTTOMRIGHT", chip, "BOTTOMRIGHT", -1, 1)
                chipFill:SetColorTexture(0.06, 0.07, 0.12, 0.96)
                -- label: bright for kills, muted red for wipes
                local chipLbl = chip:CreateFontString(nil, "OVERLAY",
                                                      "GameFontNormal")
                chipLbl:SetPoint("LEFT", chip, "LEFT", CHIP_PAD, 0)
                chipLbl:SetPoint("RIGHT", chip, "RIGHT", -CHIP_PAD, 0)
                chipLbl:SetHeight(CHIP_H)
                chipLbl:SetJustifyH("CENTER")
                chipLbl:SetText(bossLabel)
                if isWipe then
                    chipLbl:SetTextColor(1.0, 0.35, 0.35)
                else
                    chipLbl:SetTextColor(_min(1, hue.fight[1] * 1.4 + 0.20),
                                         _min(1, hue.fight[2] * 1.4 + 0.20),
                                         _min(1, hue.fight[3] * 1.4 + 0.20))
                end
                chipLbl:SetFont(fontPath, 12, "OUTLINE")

                -- Tooltip: show fight summary on hover
                chip:EnableMouse(true)
                chip:SetFrameLevel(clipFrame:GetFrameLevel() + 6)
                local captBoss = boss
                local captRun = run
                local captHue = hue
                local captWipe = isWipe
                chip:SetScript("OnEnter", function(self2)
                    GameTooltip:SetOwner(self2, "ANCHOR_BOTTOM")
                    local ttTitle = (captBoss.name or "Boss") ..
                                        (captWipe and " |cffff4444(Wipe)|r" or
                                            "")
                    GameTooltip:SetText(ttTitle, captWipe and 1.0 or
                                            (captHue.fight[1] * 1.4 + 0.20),
                                        captWipe and 0.35 or
                                            (captHue.fight[2] * 1.4 + 0.20),
                                        captWipe and 0.35 or
                                            (captHue.fight[3] * 1.4 + 0.20))

                    -- Timing
                    local pullT = captBoss.pullTime or 0
                    local endT = captBoss.killTime or captBoss.wipeTime or pullT
                    local dur = endT - pullT
                    GameTooltip:AddLine(" ")
                    if captWipe then
                        GameTooltip:AddLine(
                            "|cffccccccPull:|r  " .. MS:FormatTime(pullT) ..
                                "   |cffff4444Wipe:|r  " .. MS:FormatTime(endT) ..
                                "   |cffccccccFight:|r  " .. MS:FormatTime(dur),
                            1, 1, 1)
                    elseif captBoss.killTime and captBoss.pullTime then
                        GameTooltip:AddLine(
                            "|cffccccccPull:|r  " .. MS:FormatTime(pullT) ..
                                "   |cffccccccKill:|r  " .. MS:FormatTime(endT) ..
                                "   |cffccccccFight:|r  " .. MS:FormatTime(dur),
                            1, 1, 1)
                    end

                    if captRun and captRun.players then
                        -- Deaths during this fight
                        local deathsInFight = {}
                        for _, p in pairs(captRun.players) do
                            for _, de in ipairs(p.deathEvents or {}) do
                                local t = de.time or 0
                                if t >= pullT and t <= endT then
                                    _ins(deathsInFight, {
                                        name = p.name,
                                        class = p.class,
                                        time = t,
                                        spell = de.spell or "Unknown"
                                    })
                                end
                            end
                        end
                        _sort(deathsInFight,
                              function(a, b)
                            return a.time < b.time
                        end)

                        GameTooltip:AddLine(" ")
                        if #deathsInFight == 0 then
                            GameTooltip:AddLine("|cff44ff44No deaths|r", 1, 1, 1)
                        else
                            GameTooltip:AddLine(
                                "|cffff4444Deaths:  " .. #deathsInFight .. "|r",
                                1, 1, 1)
                            for _, d in ipairs(deathsInFight) do
                                local dr, dg, db = ClassColor(d.class)
                                local hex =
                                    _fmt("%02x%02x%02x", _floor(dr * 255),
                                         _floor(dg * 255), _floor(db * 255))
                                local intoPull = d.time - pullT
                                local line =
                                    "  |cff" .. hex .. d.name .. "|r" ..
                                        "  |cffffffff" .. MS:FormatTime(d.time) ..
                                        "  (+" .. MS:FormatTime(intoPull) ..
                                        " into pull)|r"
                                if d.spell ~= "Unknown" then
                                    line =
                                        line .. "  |cffff9944" .. d.spell ..
                                            "|r"
                                end
                                GameTooltip:AddLine(line, 1, 1, 1)
                            end
                        end

                        -- Interrupts during this fight
                        local intByPlayer = {}
                        local intTotal = 0
                        for _, p in pairs(captRun.players) do
                            local cnt = 0
                            for _, ie in ipairs(p.interruptEvents or {}) do
                                local t = ie.time or 0
                                if t >= pullT and t <= endT then
                                    cnt = cnt + 1
                                end
                            end
                            if cnt > 0 then
                                _ins(intByPlayer, {
                                    name = p.name,
                                    class = p.class,
                                    count = cnt
                                })
                                intTotal = intTotal + cnt
                            end
                        end
                        if intTotal > 0 then
                            _sort(intByPlayer,
                                  function(a, b)
                                return a.count > b.count
                            end)
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine(
                                "|cff38d8ffInterrupts:  " .. intTotal .. "|r",
                                1, 1, 1)
                            for _, ip in ipairs(intByPlayer) do
                                local dr, dg, db = ClassColor(ip.class)
                                local hex =
                                    _fmt("%02x%02x%02x", _floor(dr * 255),
                                         _floor(dg * 255), _floor(db * 255))
                                GameTooltip:AddLine(
                                    "  |cff" .. hex .. ip.name .. "|r  " ..
                                        ip.count, 1, 1, 1)
                            end
                        end
                    end
                    GameTooltip:Show()
                end)
                chip:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)

                -- Fight duration text centred INSIDE the bar segment
                -- (skip for wipes without a wipeTime — zero-width bar)
                if (boss.killTime or boss.wipeTime) and boss.pullTime then
                    local fightDur = endTime - boss.pullTime
                    local visW2 = _max(60, (_min(killFrac, 1.0) - pullFrac) *
                                           trackW)
                    MakeBarLabel(midX, MS:FormatTime(fightDur),
                                 _max(visW2 + 20, 60))
                end
            end

            local trashMidFrac = (prevFrac + pullFrac) / 2
            local trashMidX = FracToX(trashMidFrac, trackW)
            local trashPixW = (pullFrac - prevFrac) * trackW
            local rightEdgeTr = TL_MARGIN + trackW
            if trashMidX and trashPixW >= 30 and trashMidX > 60 and
                (rightEdgeTr - trashMidX) > 70 then
                local trashDur = (boss.pullTime or 0) - prevFrac * totalDur
                local pctStr = boss.pullProgressPct and
                                   ("  " .. boss.pullProgressPct .. "%") or ""
                MakeBarLabel(trashMidX, MS:FormatTime(trashDur) .. pctStr,
                             _max(30, trashPixW - 4))
            end

            prevFrac = killFrac
        end

        if prevFrac < 1.0 then
            local isCompleted = run.completed and run.endTime and run.endTime >
                                    0

            if isCompleted then
                -- Completed run: draw trailing segment from last boss to run end.
                -- Use compSec (max of endTime and last killTime) so the segment
                -- always reaches the completion marker even when ENCOUNTER_END
                -- fires after CHALLENGE_MODE_COMPLETED.
                local runEndFrac = _min(1.0, visualEndSec / totalDur)
                if runEndFrac >= prevFrac then
                    if run.inTime then
                        DrawSeg(prevFrac, runEndFrac, 0.10, 0.55, 0.18) -- green
                        -- Fill entire remaining bar green after completion
                        DrawSeg(runEndFrac, 1.0, 0.10, 0.55, 0.18, true)
                    else
                        DrawSeg(prevFrac, runEndFrac, 0.55, 0.08, 0.08) -- red
                    end

                    -- Label the trailing segment: duration + final pct.
                    -- For in-time runs this segment ends at 100% enemy forces;
                    -- for overtime runs we omit the pct (unknown final value).
                    local trailMidFrac = (prevFrac + runEndFrac) / 2
                    local trailMidX = FracToX(trailMidFrac, trackW)
                    local trailPixW = (runEndFrac - prevFrac) * trackW
                    local rightEdge = TL_MARGIN + trackW
                    if trailMidX and trailPixW >= 30 and trailMidX > 60 and
                        (rightEdge - trailMidX) > 70 then
                        local trailDur = visualEndSec - prevFrac * totalDur
                        local lastBossPct = 0
                        if run.bosses and #run.bosses > 0 then
                            lastBossPct =
                                run.bosses[#run.bosses].progressPct or 0
                        end
                        local pctStr = (run.inTime and lastBossPct < 100) and
                                           "  100%" or ""
                        MakeBarLabel(trailMidX,
                                     MS:FormatTime(trailDur) .. pctStr,
                                     _max(30, trailPixW - 4))
                    end
                end
            else
                -- Live/in-progress: create a persistent texture repositioned by UpdateLive.
                local liveSeg = clipFrame:CreateTexture(nil, "ARTWORK")
                liveSeg:SetHeight(BAR_H)
                liveSeg:SetColorTexture(0.20, 0.22, 0.30, 1)
                liveSeg:Hide()
                strip._liveSeg = liveSeg
                strip._liveClipFrame = clipFrame
                strip._livePrevFrac = prevFrac
            end
        end
    end

    local liveCursor = strip:CreateTexture(nil, "OVERLAY")
    liveCursor:SetSize(2, BAR_H + 10)
    liveCursor:SetColorTexture(0.80, 0.85, 1.00, 0.70)
    liveCursor:Hide()
    strip._liveCursor = liveCursor

    local liveLabel = strip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    liveLabel:SetTextColor(0.75, 0.78, 0.85)
    liveLabel:SetFont(fontPath, 11, "")
    liveLabel:SetJustifyH("LEFT")
    liveLabel:SetWidth(80)
    liveLabel:Hide()
    strip._liveLabel = liveLabel

    strip.UpdateLive = function(lRun, lTotalDur)
        if not lRun or not lTotalDur or lTotalDur <= 0 then
            if strip._liveSeg then strip._liveSeg:Hide() end
            if strip._liveCursor then strip._liveCursor:Hide() end
            if strip._liveLabel then strip._liveLabel:Hide() end
            return
        end

        local lTrackW = GetTrackW()

        local nowFrac
        if lRun.endTime and lRun.endTime > 0 then
            nowFrac = 1.0
        else
            nowFrac = _min(1.0, MS:GetRunDuration(lRun) / lTotalDur)
        end

        local pFrac = strip._livePrevFrac or 0

        -- Live segment bar
        local seg = strip._liveSeg
        if seg and nowFrac > pFrac + 0.001 then
            local x1 = FracToX(pFrac, lTrackW) or TL_MARGIN
            local x2 = FracToX(nowFrac, lTrackW) or (TL_MARGIN + lTrackW)
            if pFrac > 1.0 then
                seg:Hide()
            else
                x1 = _max(TL_MARGIN, x1)
                x2 = _min(TL_MARGIN + lTrackW, x2)
                local w = _max(1, x2 - x1)
                seg:ClearAllPoints()
                seg:SetPoint("BOTTOMLEFT", strip._liveClipFrame, "BOTTOMLEFT",
                             x1 - TL_MARGIN, BAR_Y - 1)
                seg:SetWidth(w)
                seg:Show()
            end
        elseif seg then
            seg:Hide()
        end

        -- Cursor line at current position
        local cur = strip._liveCursor
        if cur then
            local cx = FracToX(nowFrac, lTrackW)
            if cx then
                cur:ClearAllPoints()
                cur:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", cx - 1,
                             BAR_Y - 1)
                cur:Show()
            else
                cur:Hide()
            end
        end

        -- Live label: elapsed time + enemy forces %
        local lbl = strip._liveLabel
        if lbl then
            local elapsed = nowFrac * lTotalDur
            local txt = MS:FormatTime(elapsed)
            -- Always show enemy forces % for M+ runs (even 0%)
            if (lRun.keystoneLevel or 0) > 0 then
                local pct = lRun.currentPct
                txt = txt .. "  " .. _floor(pct ~= nil and pct or 0) .. "%"
            end
            lbl:SetText(txt)
            local cx = FracToX(nowFrac, lTrackW)
            if cx and cx + 4 < TL_MARGIN + lTrackW - 40 then
                lbl:ClearAllPoints()
                lbl:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", cx + 4,
                             BAR_Y + BAR_H + 2)
                lbl:Show()
            else
                lbl:Hide()
            end
        end
    end

    local keyLimit = run and tonumber(run.keystoneTimeLimit)
    if keyLimit and keyLimit > 0 and totalDur and totalDur > 0 then
        local ktFrac = keyLimit / totalDur
        local ktX = FracToX(ktFrac, trackW)
        if ktX then
            local runDur = MS:GetRunDuration(run)
            -- For live (uncompleted) runs inTime hasn't been finalised yet;
            -- derive it from current elapsed vs the key limit.
            local inTime = run.inTime
            if not run.completed then inTime = runDur <= keyLimit end
            local kr, kg, kb = inTime and 0.20 or 1.0, inTime and 1.00 or 0.20,
                               inTime and 0.20 or 0.20

            local ktLine = clipFrame:CreateTexture(nil, "OVERLAY")
            ktLine:SetSize(2, BAR_H + TICK_H + 6)
            ktLine:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT",
                            ktX - TL_MARGIN - 1, BAR_Y - 2)
            ktLine:SetColorTexture(kr, kg, kb, inTime and 0 or 0.90) -- hidden for in-time, shown for overtime

            local ktBtn = CreateFrame("Button", nil, clipFrame)
            ktBtn:SetSize(14, BAR_H + TICK_H + 6)
            ktBtn:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT",
                           ktX - TL_MARGIN - 7, BAR_Y - 2)
            ktBtn:SetFrameLevel(clipFrame:GetFrameLevel() + 6)
            ktBtn:EnableMouse(true)
            ktBtn:SetScript("OnEnter", function(self2)
                GameTooltip:SetOwner(self2, "ANCHOR_TOP")
                GameTooltip:SetText("Key Timer", kr, kg, kb)
                GameTooltip:AddLine(MS:FormatTime(keyLimit), 1, 1, 1)
                -- Deaths apply a score penalty only, not a timer deduction.
                -- Show as a note rather than an effective limit.
                local penalty = run.deathPenaltySeconds or 0
                if penalty > 0 then
                    local deaths = 0
                    if run.players then
                        for _, p in pairs(run.players) do
                            deaths = deaths + (p.deaths or 0)
                        end
                    end
                    GameTooltip:AddLine(
                        "|cffff4444-" .. MS:FormatTime(penalty) ..
                            " score penalty (" .. deaths .. " death" ..
                            (deaths == 1 and "" or "s") .. ")|r", 1, 1, 1)
                end
                if runDur > 0 then
                    local diff = _abs(runDur - keyLimit)
                    if inTime then
                        GameTooltip:AddLine(
                            "|cff44ff44In time by " .. MS:FormatTime(diff) ..
                                "|r", 1, 1, 1)
                    else
                        GameTooltip:AddLine(
                            "|cffff4444Over by " .. MS:FormatTime(diff) .. "|r",
                            1, 1, 1)
                    end
                end
                GameTooltip:Show()
            end)
            ktBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end

    -- Overtime shading: dark red overlay on bar from keystone limit to actual run end.
    -- Only drawn when the run genuinely exceeded the time limit.
    -- NOTE: keyLimit is already in scope from the block above; do not re-declare it.
    if keyLimit and keyLimit > 0 and totalDur and totalDur > 0 then
        local actualRunDur = (run.endTime and run.endTime > 0) and
                                 (run.endTime - run.startTime) or
                                 MS:GetRunDuration(run)
        if actualRunDur > keyLimit then
            local ktFrac = keyLimit / totalDur
            local runEndFrac = _min(1.0, actualRunDur / totalDur)
            if ktFrac < 1.0 then
                local drawF1 = ktFrac
                local drawF2 = runEndFrac
                local ox1 = FracToX(drawF1, trackW) or TL_MARGIN
                local ox2 = FracToX(drawF2, trackW) or (TL_MARGIN + trackW)
                ox1 = _max(TL_MARGIN, ox1);
                ox2 = _min(TL_MARGIN + trackW, ox2)
                if ox2 > ox1 then
                    local ot = clipFrame:CreateTexture(nil, "OVERLAY")
                    ot:SetHeight(BAR_H + 2)
                    ot:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT",
                                ox1 - TL_MARGIN, BAR_Y - 1)
                    ot:SetWidth(ox2 - ox1)
                    ot:SetColorTexture(0.55, 0.04, 0.04, 0.72)
                end
            end
        end
    end

    -- Completion marker: vertical gold line showing when the run was actually finished.
    -- M+: endTime (last boss kill + 100% enemy forces tick)
    -- Follower Mythic: last boss killTime
    if run and run.completed and totalDur and totalDur > 0 then
        local isMPlus = (run.keystoneLevel or 0) > 0
        local isFollower = run.difficultyLabel and
                               run.difficultyLabel:find("Follower")
        local compSec = nil

        if isMPlus and run.endTime and run.endTime > 0 then
            -- Use the authoritative keystone elapsed time, matching the header.
            -- visualEndSec may exceed this if ENCOUNTER_END fired after
            -- CHALLENGE_MODE_COMPLETED, but the marker should agree with the
            -- displayed run time, not the boss kill timestamp.
            compSec = run.endTime - (run.startTime or 0)
        elseif isFollower and run.bosses then
            -- Last boss kill time
            local lastKill = 0
            for _, b in ipairs(run.bosses) do
                if b.killTime and b.killTime > lastKill then
                    lastKill = b.killTime
                end
            end
            if lastKill > 0 then compSec = lastKill end
        end

        if compSec and compSec > 0 then
            local compFrac = compSec / totalDur
            -- Use clamped variant so the marker always renders, even when the
            -- run finishes exactly at (or fractionally past) the time limit.
            local compX = FracToXClamped(compFrac, trackW)
            if compX then
                local lineH = BAR_H + TICK_H + 14
                -- Outer wide glow
                local compGlow3 = clipFrame:CreateTexture(nil, "ARTWORK")
                compGlow3:SetSize(13, lineH)
                compGlow3:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT",
                                   compX - TL_MARGIN - 6, BAR_Y - 2)
                compGlow3:SetColorTexture(1.0, 0.85, 0.0, 0.07)
                -- Mid glow
                local compGlow = clipFrame:CreateTexture(nil, "ARTWORK")
                compGlow:SetSize(7, lineH)
                compGlow:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT",
                                  compX - TL_MARGIN - 3, BAR_Y - 2)
                compGlow:SetColorTexture(1.0, 0.85, 0.0, 0.20)
                -- Sharp gold line
                local compLine = clipFrame:CreateTexture(nil, "OVERLAY")
                compLine:SetSize(2, lineH)
                compLine:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT",
                                  compX - TL_MARGIN - 1, BAR_Y - 2)
                compLine:SetColorTexture(1.0, 0.92, 0.25, 1.0)

                -- Time label anchored to the top-right of the completion line.
                -- Clamp so the label never overflows the right edge of the track.
                local compLblX = _min(compX - TL_MARGIN + 4, trackW - 55)
                local compLbl = clipFrame:CreateFontString(nil, "OVERLAY",
                                                           "GameFontNormal")
                compLbl:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT",
                                 compLblX, BAR_Y - 2 + lineH)
                compLbl:SetText(MS:FormatTime(compSec))
                compLbl:SetTextColor(1.0, 0.85, 0.0)
                compLbl:SetFont(fontPath, 11, "")
                compLbl:SetJustifyH("LEFT")
                compLbl:SetWidth(60)

                local compBtn = CreateFrame("Button", nil, clipFrame)
                compBtn:SetSize(20, BAR_H + TICK_H + 14)
                compBtn:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT",
                                 compX - TL_MARGIN - 10, BAR_Y - 2)
                compBtn:SetFrameLevel(clipFrame:GetFrameLevel() + 6)
                compBtn:EnableMouse(true)
                compBtn:SetScript("OnEnter", function(self2)
                    GameTooltip:SetOwner(self2, "ANCHOR_TOP")
                    GameTooltip:SetText("Run Completed", 1.0, 0.85, 0.0)
                    GameTooltip:AddLine(MS:FormatTime(compSec), 1, 1, 1)
                    if run.keystoneTimeLimit and tonumber(run.keystoneTimeLimit) and
                        run.keystoneTimeLimit > 0 then
                        local diff = run.keystoneTimeLimit - compSec
                        if diff > 0 then
                            GameTooltip:AddLine(
                                "|cff44ff44Under time by " ..
                                    MS:FormatTime(diff) .. "|r", 1, 1, 1)
                        end
                    end
                    GameTooltip:Show()
                end)
                compBtn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            end
        end
    end

    if run and run.players and totalDur and totalDur > 0 then

        -- Death skull markers
        -- Skulls sit just above the label block.  LBL_TOP_Y is the bottom
        -- anchor of the topmost label row, so skulls placed there clear all
        -- boss-name and pull-timestamp text.  We cap the Y so icons can't
        -- exceed the strip height and get clipped off the top of the panel.
        -- Death skulls: centred vertically inside the bar.
        -- No stacking — the bar is only 16px tall so there's no room.
        -- Closely-timed deaths will slightly overlap, which is fine.
        local SKULL_W = 13
        -- Centre of bar in strip-space
        local skullBarY = BAR_Y - 1 + _floor((BAR_H - SKULL_W) / 2)

        local function IsDuringBoss(t)
            if not run.bosses then return false end
            for _, boss in ipairs(run.bosses) do
                local pullT = boss.pullTime or 0
                local killT = boss.killTime or boss.wipeTime or pullT
                if t >= pullT and t <= killT then return true end
            end
            return false
        end

        local allDeaths = {}
        for _, p in pairs(run.players) do
            if p.deathEvents then
                for _, de in ipairs(p.deathEvents) do
                    _ins(allDeaths, {
                        playerName = p.name,
                        playerClass = p.class,
                        time = de.time or 0,
                        spell = de.spell or "Unknown",
                        killer = de.killer or "Unknown"
                    })
                end
            end
        end

        _sort(allDeaths, function(a, b) return a.time < b.time end)

        local placedX = {}

        for _, death in ipairs(allDeaths) do
            local frac = _min(1.0, death.time / totalDur)
            local markerX = FracToX(frac, trackW)
            if markerX then
                local finalX = markerX
                for _, px in ipairs(placedX) do
                    if _abs(finalX - px) < 5 then
                        finalX = px + 5
                    end
                end
                _ins(placedX, finalX)

                local dr, dg, db = ClassColor(death.playerClass)

                local btn = CreateFrame("Button", nil, strip)
                btn:SetSize(SKULL_W + 2, SKULL_W + 2)
                btn:SetPoint("BOTTOM", strip, "BOTTOMLEFT",
                             finalX - (SKULL_W + 2) / 2, skullBarY)
                btn:EnableMouse(true)
                btn:SetFrameLevel(strip:GetFrameLevel() + 5)

                local skull = btn:CreateTexture(nil, "OVERLAY");
                skull:SetAllPoints()
                skull:SetTexture(
                    "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
                skull:SetVertexColor(dr, dg, db, 1)
                local hov = btn:CreateTexture(nil, "HIGHLIGHT");
                hov:SetAllPoints()
                hov:SetColorTexture(1, 1, 1, 0.15)

                local d = death
                btn:SetScript("OnEnter", function(self2)
                    GameTooltip:SetOwner(self2, "ANCHOR_TOP")
                    local cr, cg, cb2 = ClassColor(d.playerClass)
                    GameTooltip:SetText(d.playerName .. " - Died", cr, cg, cb2)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cffccccccTime:|r  " ..
                                            MS:FormatTime(d.time), 1, 1, 1)

                    if run and run.bosses then
                        for _, boss in ipairs(run.bosses) do
                            local pullT = boss.pullTime or 0
                            local killT =
                                boss.killTime or boss.wipeTime or (d.time + 1)
                            if d.time >= pullT and d.time <= killT then
                                local segLabel =
                                    (boss.name or "Boss") ..
                                        (boss.wipeTime and not boss.killTime and
                                            " (Wipe)" or "")
                                GameTooltip:AddLine(
                                    "|cffccccccSegment:|r  |cffffcc00" ..
                                        segLabel .. "|r", 1, 1, 1)
                                break
                            end
                        end
                    end

                    local playerRec = run and run.players and
                                          run.players[d.playerName]
                    local recapID = playerRec and playerRec.deathRecapID or 0
                    if recapID ~= 0 and DeathRecap_GetEvents then
                        local ok, events = pcall(DeathRecap_GetEvents, recapID)
                        if ok and events and #events > 0 then
                            GameTooltip:AddLine(" ")
                            local killingEvent = nil
                            for i = #events, 1, -1 do
                                local ev = events[i]
                                if ev and ev.overkill and ev.overkill > 0 then
                                    killingEvent = ev;
                                    break
                                end
                            end
                            killingEvent = killingEvent or events[#events]
                            if killingEvent then
                                local spellName =
                                    killingEvent.spellName or "Unknown"
                                local caster = killingEvent.caster or ""
                                local line =
                                    "|cffaaaaaa* Killing blow:|r |cffff9944" ..
                                        spellName .. "|r"
                                if caster ~= "" then
                                    line =
                                        line .. " |cff888888by|r |cffffd700" ..
                                            caster .. "|r"
                                end
                                GameTooltip:AddLine(line, 1, 1, 1)
                            end
                            for i = _max(1, #events - 2), #events do
                                local ev = events[i]
                                if ev and ev.spellName then
                                    local hitLine =
                                        "|cff666666" .. ev.spellName .. "|r"
                                    if ev.amount and ev.amount ~= 0 then
                                        hitLine =
                                            hitLine .. "  |cffff6666" ..
                                                Abbrev(-(ev.amount)) .. "|r"
                                    end
                                    if ev.overkill and ev.overkill > 0 then
                                        hitLine = hitLine .. " |cffff0000(KB)|r"
                                    end
                                    GameTooltip:AddLine("  " .. hitLine, 1, 1, 1)
                                end
                            end
                        end
                    elseif d.killer ~= "Unknown" then
                        GameTooltip:AddLine(
                            "|cffccccccKilled by:|r  |cffff9944" .. d.killer ..
                                "|r", 1, 1, 1)
                        if d.spell ~= "Unknown" then
                            GameTooltip:AddLine(
                                "|cffccccccAbility:|r  |cffff4444" .. d.spell ..
                                    "|r", 1, 1, 1)
                        end
                    end
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            end
        end

        -- Interrupt tick markers
        -- Collect all interruptEvents across all players, then render a small
        -- coloured tick (using the interrupt icon) at the correct timeline position.
        local INT_W = 5 -- height of the interrupt tick
        local INT_Y_BASE = BAR_Y + BAR_H + 3 -- just above the top of the bar
        local INT_CLUSTER = 4 -- min px gap before stacking into a new row
        local INT_NUM_ROWS = 3

        local allInterrupts = {}
        for _, p in pairs(run.players) do
            if p.interruptEvents then
                for _, ie in ipairs(p.interruptEvents) do
                    _ins(allInterrupts, {
                        playerName = p.name,
                        playerClass = p.class,
                        time = ie.time or 0,
                        spell = ie.spell or "Unknown"
                    })
                end
            end
        end

        _sort(allInterrupts, function(a, b) return a.time < b.time end)

        local intRowLastX = {}
        for i = 1, INT_NUM_ROWS do intRowLastX[i] = -999 end

        for _, iv in ipairs(allInterrupts) do
            local frac = _min(1.0, iv.time / totalDur)
            local markerX = FracToX(frac, trackW)
            if markerX then
                -- Stack rows upward to avoid overlap, same logic as skull markers.
                local row = 1
                for r = 1, INT_NUM_ROWS do
                    if markerX - intRowLastX[r] >= INT_CLUSTER then
                        row = r;
                        break
                    end
                    if r == INT_NUM_ROWS then
                        row = INT_NUM_ROWS
                    end
                end
                intRowLastX[row] = markerX
                local INT_Y = INT_Y_BASE + (row - 1) * (INT_W + 2)

                local ir, ig, ib = ClassColor(iv.playerClass)

                -- Tick mark: a narrow filled rectangle in the player's class colour.
                local TICK_W = 2
                local tick = clipFrame:CreateTexture(nil, "OVERLAY")
                tick:SetSize(TICK_W, INT_W)
                tick:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT",
                              markerX - TL_MARGIN - 1, INT_Y)
                tick:SetColorTexture(ir, ig, ib, 1)

                -- Invisible wider button on top for tooltip hit-testing.
                local btn = CreateFrame("Button", nil, strip)
                btn:SetSize(TICK_W + 8, INT_W + 4)
                btn:SetPoint("BOTTOM", strip, "BOTTOMLEFT", markerX, INT_Y - 1)
                btn:EnableMouse(true)
                btn:SetFrameLevel(strip:GetFrameLevel() + 7)
                local hov = btn:CreateTexture(nil, "HIGHLIGHT");
                hov:SetAllPoints()
                hov:SetColorTexture(1, 1, 1, 0.12)

                local iv2 = iv
                btn:SetScript("OnEnter", function(self2)
                    GameTooltip:SetOwner(self2, "ANCHOR_TOP")
                    local cr, cg, cb2 = ClassColor(iv2.playerClass)
                    GameTooltip:SetText(iv2.playerName .. " — Interrupted",
                                        cr, cg, cb2)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cffccccccTime:|r  " ..
                                            MS:FormatTime(iv2.time), 1, 1, 1)
                    if iv2.spell and iv2.spell ~= "Unknown" then
                        GameTooltip:AddLine(
                            "|cffccccccSpell:|r  |cffff9944" .. iv2.spell ..
                                "|r", 1, 1, 1)
                    end
                    if run and run.bosses then
                        for _, boss in ipairs(run.bosses) do
                            local pullT = boss.pullTime or 0
                            local killT =
                                boss.killTime or boss.wipeTime or (iv2.time + 1)
                            if iv2.time >= pullT and iv2.time <= killT then
                                local segLabel =
                                    (boss.name or "Boss") ..
                                        (boss.wipeTime and not boss.killTime and
                                            " (Wipe)" or "")
                                GameTooltip:AddLine(
                                    "|cffccccccSegment:|r  |cffffcc00" ..
                                        segLabel .. "|r", 1, 1, 1)
                                break
                            end
                        end
                    end
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            end
        end

    end

    strip:SetScript("OnEnter", function() end)
    strip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Drive the live cursor at ~10 fps via OnUpdate so it moves smoothly
    -- across the timeline during an active run.  For completed runs we clear
    -- the script to avoid unnecessary per-frame calls.
    if run and not run.completed then
        local _lastLiveTick = 0
        strip:SetScript("OnUpdate", function()
            local t = GetTime()
            if t - _lastLiveTick >= 0.1 then
                _lastLiveTick = t
                strip.UpdateLive(run, totalDur)
            end
        end)
    else
        strip:SetScript("OnUpdate", nil)
    end

    return strip
end

-- ---------------------------------------------------------------------------
-- Scoreboard frame state
-- ---------------------------------------------------------------------------

local sbFrame = nil
local overviewSF = nil
local overviewRows = {} -- visible rows this refresh
local _rowPool = {} -- pre-allocated reusable row frames
local _playersBuf = {} -- reused sort buffer; wiped each refresh
local MAX_PLAYERS = 5

-- Column sort state: nil key = default role/dps order, dir 1 = descending, -1 = ascending
local sortState = {key = nil, dir = 1}
local colHdrLabels = {} -- { [key] = fontstring } for updating sort indicators

-- Numeric sort value per column key
local COL_SORT_VALUES = {
    player = function(p) return p.name or "" end,
    score = function(p) return p.mythicScore or 0 end,
    loot = function(p) return (p.lootItemLink or p.lootItemName) and 1 or 0 end,
    deaths = function(p) return p.deaths or 0 end,
    dmgTaken = function(p) return p.damageTaken or 0 end,
    avoidable = function(p) return p.avoidableDamageTaken or 0 end,
    dps = function(p)
        return (p.dps or 0) > 0 and p.dps or (p.damageDone or 0)
    end,
    hps = function(p)
        return (p.hps or 0) > 0 and p.hps or (p.healingDone or 0)
    end,
    interrupts = function(p) return p.interrupts or 0 end,
    stunInterrupts = function(p) return p.stunInterrupts or 0 end,
    dispels = function(p) return p.dispels or 0 end
}

function MS:BuildUI()
    if sbFrame then return end

    local totalH = HDR_H + COL_HDR_H + 1 + (ROW_H * 5) + BOTTOM_H + 2
    sbFrame = CreateFrame("Frame", "MythicScoreboardFrame", UIParent)
    sbFrame:SetSize(FRAME_W, totalH)
    sbFrame:SetFrameStrata("DIALOG")
    sbFrame:SetMovable(true);
    sbFrame:EnableMouse(true)
    sbFrame:RegisterForDrag("LeftButton")
    -- ── Frame setup ─────────────────────────────────────────────────────────
    sbFrame:SetScript("OnDragStart", sbFrame.StartMoving)
    sbFrame:SetScript("OnDragStop", sbFrame.StopMovingOrSizing)

    sbFrame:SetScript("OnMouseDown", function()
        CloseHistDropdown()
        if sbFrame.SettingsPopup then sbFrame.SettingsPopup:Hide() end
    end)
    sbFrame:SetScript("OnShow", function()
        -- Re-apply background colours on every show. Named global frames can
        -- have SetBackdrop called on them by WoW or other addons, which inserts
        -- a backdrop texture that washes out the background.  Clearing any
        -- backdrop and re-colouring the textures each time the frame opens
        -- keeps the appearance consistent.
        if sbFrame.SetBackdrop then sbFrame:SetBackdrop(nil) end
        if sbFrame._borderTex then
            sbFrame._borderTex:SetColorTexture(C.border[1], C.border[2],
                                               C.border[3], 1)
        end
        if sbFrame._bgTex then
            sbFrame._bgTex:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.97)
        end
    end)
    sbFrame:SetScript("OnHide", function()
        CloseHistDropdown()
        if sbFrame.SettingsPopup then sbFrame.SettingsPopup:Hide() end
    end)
    sbFrame:SetScript("OnEnter", function() end)
    sbFrame:SetScript("OnLeave", function() end)
    sbFrame:SetClampedToScreen(true)
    sbFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 60);
    sbFrame:Hide()

    tinsert(UISpecialFrames, "MythicScoreboardFrame")

    -- Use explicit sublayer indices so the stacking order is deterministic
    -- even if external code or WoW's frame recycling touches the draw layers.
    -- border sits at BACKGROUND:0, bg at BACKGROUND:1 (renders on top of border).
    local border = sbFrame:CreateTexture(nil, "BACKGROUND", nil, 0);
    border:SetAllPoints()
    border:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    local bg = sbFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", sbFrame, "TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", sbFrame, "BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.97)
    -- Store refs so a stray SetBackdrop call cannot displace them.
    sbFrame._borderTex = border
    sbFrame._bgTex = bg

    -- ── Header ──────────────────────────────────────────────────────────────
    local hdr = CreateFrame("Frame", nil, sbFrame)
    hdr:SetPoint("TOPLEFT", sbFrame, "TOPLEFT", 1, -1)
    hdr:SetPoint("TOPRIGHT", sbFrame, "TOPRIGHT", -1, -1)
    hdr:SetHeight(HDR_H)

    -- Creates a rounded-feel button with a visible bg + 1px border
    local function MakeHeaderBtn(parent, w, h)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(w, h)
        -- border
        local border = btn:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints();
        border:SetColorTexture(0.28, 0.30, 0.42, 1)
        btn._border = border
        -- fill (inset 1px)
        local bg = btn:CreateTexture(nil, "BORDER")
        bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        bg:SetColorTexture(0.10, 0.12, 0.20, 1)
        btn._bg = bg
        return btn
    end

    local function BtnHover(btn, on)
        if btn._border then
            btn._border:SetColorTexture(on and 0.50 or 0.28,
                                        on and 0.55 or 0.30,
                                        on and 0.80 or 0.42, 1)
        end
        if btn._bg then
            btn._bg:SetColorTexture(on and 0.18 or 0.10, on and 0.22 or 0.12,
                                    on and 0.36 or 0.20, 1)
        end
    end

    local histBtn = MakeHeaderBtn(hdr, 320, 26)
    histBtn:SetPoint("TOPLEFT", hdr, "TOPLEFT", 6, -6)

    -- Inner font strings for the inline run preview.
    -- Index anchored left, result/time/level anchored from the right,
    -- dungeon name fills the space between — no fixed-width gaps.
    local hbIndex = histBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hbIndex:SetPoint("LEFT", histBtn, "LEFT", 8, 0)
    hbIndex:SetSize(18, 26)
    hbIndex:SetJustifyH("CENTER")
    hbIndex:SetFont(_FONT_PATH, 11, "")

    local hbResult = histBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hbResult:SetPoint("RIGHT", histBtn, "RIGHT", -8, 0)
    hbResult:SetSize(72, 26)
    hbResult:SetJustifyH("RIGHT")
    hbResult:SetFont(_FONT_PATH, 11, "")

    local hbTime = histBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hbTime:SetPoint("RIGHT", hbResult, "LEFT", -6, 0)
    hbTime:SetSize(40, 26)
    hbTime:SetJustifyH("RIGHT")
    hbTime:SetFont(_FONT_PATH, 11, "")

    local hbLevel = histBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hbLevel:SetPoint("RIGHT", hbTime, "LEFT", -6, 0)
    hbLevel:SetSize(28, 26)
    hbLevel:SetJustifyH("RIGHT")
    hbLevel:SetFont(_FONT_PATH, 11, "")

    local hbDungeon = histBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hbDungeon:SetPoint("LEFT", hbIndex, "RIGHT", 6, 0)
    hbDungeon:SetPoint("RIGHT", hbLevel, "LEFT", -6, 0)
    hbDungeon:SetJustifyH("LEFT")
    hbDungeon:SetFont(_FONT_PATH, 11, "")

    -- Fallback "History" label shown when there are no runs
    local hbTxt = histBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hbTxt:SetAllPoints()
    hbTxt:SetJustifyH("CENTER")
    hbTxt:SetText("History")
    hbTxt:SetTextColor(1, 1, 1)
    hbTxt:SetFont(_FONT_PATH, 12, "OUTLINE")

    local function RefreshHistBtn()
        local runs = MythicScoreboardDB and MythicScoreboardDB.runs
        -- Show the currently selected run (displayRun) if one is chosen,
        -- otherwise fall back to the most recent run.
        local r = MS.displayRun
        local idx = 1
        if r and runs then
            for i, v in ipairs(runs) do
                if v == r then
                    idx = i;
                    break
                end
            end
        else
            r = runs and runs[1]
        end
        if r then
            hbTxt:Hide()
            local isMPlus = (r.keystoneLevel or 0) > 0
            hbIndex:SetText(tostring(idx))
            hbIndex:SetTextColor(C.bossTime[1], C.bossTime[2], C.bossTime[3])

            hbDungeon:SetText(r.dungeonName or "?")
            hbDungeon:SetTextColor(C.white[1], C.white[2], C.white[3])

            if isMPlus then
                hbLevel:SetText("+" .. r.keystoneLevel)
                hbLevel:SetTextColor(C.titleGold[1], C.titleGold[2],
                                     C.titleGold[3])
            else
                local label = r.difficultyLabel or ""
                local dt = label:find("Follower") and "F" or label ==
                               "Timewalking" and "TW" or label ~= "" and label or
                               "?"
                hbLevel:SetText(dt)
                hbLevel:SetTextColor(C.stat[1], C.stat[2], C.stat[3])
            end

            hbTime:SetText(MS:FormatTime(MS:GetRunDuration(r)))
            hbTime:SetTextColor(C.stat[1], C.stat[2], C.stat[3])

            local result, rr, rg, rb
            if r.completed then
                if isMPlus then
                    if r.inTime then
                        result, rr, rg, rb = "In Time", 0.27, 1.0, 0.27
                    else
                        result, rr, rg, rb = "Overtime", 1.0, 0.55, 0.15
                    end
                else
                    result, rr, rg, rb = "Cleared", 0.27, 1.0, 0.27
                end
            else
                result, rr, rg, rb = "Abandoned", 0.50, 0.50, 0.50
            end
            hbResult:SetText(result)
            hbResult:SetTextColor(rr, rg, rb)
        else
            hbTxt:Show()
            hbIndex:SetText("")
            hbDungeon:SetText("")
            hbLevel:SetText("")
            hbTime:SetText("")
            hbResult:SetText("")
        end
    end

    sbFrame.RefreshHistBtn = RefreshHistBtn
    RefreshHistBtn()

    histBtn:SetScript("OnEnter", function()
        BtnHover(histBtn, true)
        if hbTxt:IsShown() then
            hbTxt:SetTextColor(C.titleGold[1], C.titleGold[2], C.titleGold[3])
        end
        local runs = MythicScoreboardDB and MythicScoreboardDB.runs
        if runs and #runs > 0 then
            GameTooltip:SetOwner(histBtn, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Run History", 1, 1, 1)
            GameTooltip:AddLine(
                "Click to browse all " .. #runs .. " saved run" ..
                    (#runs == 1 and "" or "s") .. ".", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end
    end)
    histBtn:SetScript("OnLeave", function()
        BtnHover(histBtn, false)
        hbTxt:SetTextColor(1, 1, 1)
        GameTooltip:Hide()
    end)
    histBtn:SetScript("OnClick", function() OpenHistDropdown(histBtn) end)
    sbFrame.HistoryButton = histBtn

    -- ── Close button ─────────────────────────────────────────────────────────
    local cb = CreateFrame("Button", nil, hdr)
    cb:SetSize(26, 26)
    cb:SetPoint("TOPRIGHT", hdr, "TOPRIGHT", -6, -6)

    local cbX = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbX:SetAllPoints()
    cbX:SetText("×")
    cbX:SetTextColor(0.60, 0.22, 0.22)
    cbX:SetJustifyH("CENTER")
    cbX:SetJustifyV("MIDDLE")
    cbX:SetFont(_FONT_PATH, 18, "")

    cb:SetScript("OnEnter", function()
        cbX:SetTextColor(1, 0.35, 0.35)
        GameTooltip:SetOwner(cb, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Close", 1, 0.4, 0.4)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function()
        cbX:SetTextColor(0.60, 0.22, 0.22)
        GameTooltip:Hide()
    end)
    cb:SetScript("OnClick", function()
        CloseHistDropdown();
        sbFrame:Hide()
    end)
    sbFrame.CloseButton = cb

    -- ── Settings button ────────────────────────────────────────────────────
    local settBtn = CreateFrame("Button", nil, hdr)
    settBtn:SetSize(62, 26)
    settBtn:SetPoint("TOPRIGHT", hdr, "TOPRIGHT", -32, -6)

    local settTxt = settBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settTxt:SetAllPoints()
    settTxt:SetJustifyH("CENTER")
    settTxt:SetFont(_FONT_PATH, 12, "")
    settTxt:SetText("Settings")
    settTxt:SetTextColor(1, 1, 1)

    -- Subtle underline bar that appears on hover
    local settLine = settBtn:CreateTexture(nil, "OVERLAY")
    settLine:SetHeight(1)
    settLine:SetPoint("BOTTOMLEFT", settBtn, "BOTTOMLEFT", 4, 3)
    settLine:SetPoint("BOTTOMRIGHT", settBtn, "BOTTOMRIGHT", -4, 3)
    settLine:SetColorTexture(C.titleGold[1], C.titleGold[2], C.titleGold[3], 0)

    settBtn:SetScript("OnEnter", function()
        settTxt:SetTextColor(C.titleGold[1], C.titleGold[2], C.titleGold[3])
        settLine:SetColorTexture(C.titleGold[1], C.titleGold[2], C.titleGold[3],
                                 0.7)
    end)
    settBtn:SetScript("OnLeave", function()
        settTxt:SetTextColor(1, 1, 1)
        settLine:SetColorTexture(C.titleGold[1], C.titleGold[2], C.titleGold[3],
                                 0)
        if not sbFrame.SettingsPopup:IsShown() then end
    end)
    settBtn:SetScript("OnClick", function()
        CloseHistDropdown()
        local pop = sbFrame.SettingsPopup
        if pop:IsShown() then
            pop:Hide()
        else
            pop:Show()
        end
        GameTooltip:Hide()
    end)
    sbFrame.SettingsBtn = settBtn

    -- ── Settings popup panel ────────────────────────────────────────────────
    local SETT_W = 180
    local NUM_GROUPS = #MS.DIFF_GROUPS

    -- Sections: Auto Reset (1 row), Nameplate/Tooltip/AutoOpen (3 rows),
    --           History Limit stepper, separator + "Track Difficulties" header + diff rows
    local ROW_H = 24
    local SEP_H = 10
    local SETT_H = 10 + ROW_H -- Auto Reset
    + ROW_H -- Nameplate
    + ROW_H -- Tooltip
    + ROW_H -- Auto Open After Run
    + ROW_H -- History Limit
    + SEP_H -- separator
    + 18 -- "Track Difficulties" label
    + NUM_GROUPS * ROW_H -- diff rows
    + 10 -- bottom pad

    local settPop = CreateFrame("Frame", nil, sbFrame)
    settPop:SetSize(SETT_W, SETT_H)
    settPop:SetFrameStrata("TOOLTIP")
    settPop:SetFrameLevel(sbFrame:GetFrameLevel() + 30)
    settPop:EnableMouse(true)
    settPop:ClearAllPoints()
    settPop:SetPoint("TOPRIGHT", settBtn, "BOTTOMRIGHT", 0, -4)
    settPop:Hide()

    local spBorder = settPop:CreateTexture(nil, "BACKGROUND", nil, 0)
    spBorder:SetAllPoints()
    spBorder:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    local spBg = settPop:CreateTexture(nil, "BACKGROUND", nil, 1)
    spBg:SetPoint("TOPLEFT", settPop, "TOPLEFT", 1, -1)
    spBg:SetPoint("BOTTOMRIGHT", settPop, "BOTTOMRIGHT", -1, 1)
    spBg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.97)

    -- Helper: make a toggle row (checkbox + label)
    local function MakeToggleRow(parent, yOff, labelText, getFn, setFn,
                                 tooltipText)
        local chk = CreateFrame("Button", nil, parent)
        chk:SetSize(13, 13)
        chk:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOff)
        chk:EnableMouse(true)

        local chkBorder = chk:CreateTexture(nil, "BACKGROUND")
        chkBorder:SetAllPoints()
        chkBorder:SetColorTexture(0.35, 0.40, 0.55, 1)
        local chkFill = chk:CreateTexture(nil, "BORDER")
        chkFill:SetPoint("TOPLEFT", chk, "TOPLEFT", 1, -1)
        chkFill:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", -1, 1)
        chkFill:SetColorTexture(0.08, 0.10, 0.16, 1)
        local chkMark = chk:CreateTexture(nil, "OVERLAY")
        chkMark:SetPoint("TOPLEFT", chk, "TOPLEFT", -1, 1)
        chkMark:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", 1, -1)
        chkMark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")

        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", chk, "RIGHT", 6, 0)
        lbl:SetText(labelText)
        lbl:SetFont(_FONT_PATH, 12, "")

        local function Refresh()
            local on = getFn and getFn() or false
            chkMark:SetShown(on)
            if on then
                chkMark:SetVertexColor(0.20, 0.95, 0.30, 1)
                chkFill:SetColorTexture(0.08, 0.18, 0.10, 1)
            else
                chkFill:SetColorTexture(0.06, 0.08, 0.08, 1)
            end
            lbl:SetTextColor(on and 0.85 or 0.45, on and 0.90 or 0.45,
                             on and 0.85 or 0.50)
        end
        -- Do NOT call Refresh() here — settPop.Refresh() is called OnShow,
        -- by which point all MS functions are guaranteed to be defined.

        chk:SetScript("OnClick", function()
            setFn(not getFn())
            Refresh()
        end)
        chk:SetScript("OnEnter", function()
            chkBorder:SetColorTexture(0.55, 0.65, 0.90, 1)
            if tooltipText then
                GameTooltip:SetOwner(chk, "ANCHOR_LEFT")
                GameTooltip:SetText(labelText, 1, 1, 1)
                GameTooltip:AddLine(tooltipText, 0.75, 0.75, 0.75, true)
                GameTooltip:Show()
            end
        end)
        chk:SetScript("OnLeave", function()
            chkBorder:SetColorTexture(0.35, 0.40, 0.55, 1)
            if tooltipText then GameTooltip:Hide() end
        end)

        return {refresh = Refresh}
    end

    local yOff = -10

    -- Auto Reset row
    local arRow = MakeToggleRow(settPop, yOff, "Auto Reset Meter",
                                function() return MS:GetAutoResetMeter() end,
                                function(v) MS:SetAutoResetMeter(v) end,
                                "Resets the Blizzard damage meter on zone-in.\nRequired for accurate data.")
    yOff = yOff - ROW_H

    -- Nameplate row
    local npRow = MakeToggleRow(settPop, yOff, "Nameplate Forces %", function()
        return MS:GetMobForcesNameplate()
    end, function(v) MS:SetMobForcesNameplate(v) end,
                                "Shows enemy forces % above each mob's nameplate in Mythic+.")
    yOff = yOff - ROW_H

    -- Tooltip row
    local ttRow = MakeToggleRow(settPop, yOff, "Tooltip Forces %",
                                function() return MS:GetMobForcesTooltip() end,
                                function(v) MS:SetMobForcesTooltip(v) end,
                                "Shows enemy forces % in the unit tooltip when hovering a mob in Mythic+.")
    yOff = yOff - ROW_H

    -- Auto-open row
    local aoRow = MakeToggleRow(settPop, yOff, "Auto Open After Run",
                                function() return MS:GetAutoOpenOnComplete() end,
                                function(v) MS:SetAutoOpenOnComplete(v) end,
                                "Automatically opens the scoreboard when a Mythic+ dungeon is completed.")
    yOff = yOff - ROW_H

    -- History Limit stepper row
    local hlFrame = CreateFrame("Frame", nil, settPop)
    hlFrame:SetSize(SETT_W - 20, ROW_H)
    hlFrame:SetPoint("TOPLEFT", settPop, "TOPLEFT", 10, yOff)

    local hlLbl = settPop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hlLbl:SetPoint("LEFT", hlFrame, "LEFT", 0, 0)
    hlLbl:SetText("History Limit")
    hlLbl:SetFont(_FONT_PATH, 13, "")

    local hlMinus = CreateFrame("Button", nil, settPop)
    hlMinus:SetSize(16, 16)
    hlMinus:SetPoint("RIGHT", hlFrame, "RIGHT", 0, 0)
    local hlMinusTxt =
        hlMinus:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hlMinusTxt:SetAllPoints();
    hlMinusTxt:SetText("−")
    hlMinusTxt:SetFont(_FONT_PATH, 14, "");
    hlMinusTxt:SetJustifyH("CENTER")
    hlMinusTxt:SetTextColor(0.65, 0.68, 0.80)

    local hlVal = settPop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hlVal:SetPoint("RIGHT", hlMinus, "LEFT", -4, 0)
    hlVal:SetWidth(22);
    hlVal:SetJustifyH("CENTER")
    hlVal:SetFont(_FONT_PATH, 13, "")
    hlVal:SetTextColor(1, 1, 1)

    local hlPlus = CreateFrame("Button", nil, settPop)
    hlPlus:SetSize(16, 16)
    hlPlus:SetPoint("RIGHT", hlVal, "LEFT", -4, 0)
    local hlPlusTxt = hlPlus:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hlPlusTxt:SetAllPoints();
    hlPlusTxt:SetText("+")
    hlPlusTxt:SetFont(_FONT_PATH, 14, "");
    hlPlusTxt:SetJustifyH("CENTER")
    hlPlusTxt:SetTextColor(0.65, 0.68, 0.80)

    local function RefreshHL() hlVal:SetText(tostring(MS:GetHistoryLimit())) end
    local hlRow = {refresh = RefreshHL}

    hlMinus:SetScript("OnClick", function()
        MS:SetHistoryLimit(MS:GetHistoryLimit() - 1)
        RefreshHL()
    end)
    hlMinus:SetScript("OnEnter", function() hlMinusTxt:SetTextColor(1, 1, 1) end)
    hlMinus:SetScript("OnLeave",
                      function() hlMinusTxt:SetTextColor(0.65, 0.68, 0.80) end)

    hlPlus:SetScript("OnClick", function()
        MS:SetHistoryLimit(MS:GetHistoryLimit() + 1)
        RefreshHL()
    end)
    hlPlus:SetScript("OnEnter", function() hlPlusTxt:SetTextColor(1, 1, 1) end)
    hlPlus:SetScript("OnLeave",
                     function() hlPlusTxt:SetTextColor(0.65, 0.68, 0.80) end)

    yOff = yOff - ROW_H

    -- Section separator
    local spSep = settPop:CreateTexture(nil, "ARTWORK")
    spSep:SetHeight(1)
    spSep:SetPoint("TOPLEFT", settPop, "TOPLEFT", 4, yOff - 4)
    spSep:SetPoint("TOPRIGHT", settPop, "TOPRIGHT", -4, yOff - 4)
    spSep:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.6)
    yOff = yOff - SEP_H

    -- "Track Difficulties" section header
    local diffHdr = settPop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    diffHdr:SetPoint("TOPLEFT", settPop, "TOPLEFT", 8, yOff)
    diffHdr:SetText("Track Difficulties")
    diffHdr:SetTextColor(C.titleGold[1], C.titleGold[2], C.titleGold[3])
    diffHdr:SetFont(_FONT_PATH, 11, "")
    yOff = yOff - 18

    -- Difficulty rows
    local diffCheckRows = {}
    for gi, grp in ipairs(MS.DIFF_GROUPS) do
        local captGrp = grp
        local function IsOn()
            local td = MythicScoreboardDB and MythicScoreboardDB.settings and
                           MythicScoreboardDB.settings.trackedDifficulties
            return (not td) or (td[captGrp.key] == true)
        end
        local row = MakeToggleRow(settPop, yOff, grp.label, IsOn, function(v)
            local td = MythicScoreboardDB and MythicScoreboardDB.settings and
                           MythicScoreboardDB.settings.trackedDifficulties
            if td then td[captGrp.key] = v end
        end)
        diffCheckRows[gi] = row
        yOff = yOff - ROW_H
    end

    settPop.Refresh = function()
        arRow.refresh()
        npRow.refresh()
        ttRow.refresh()
        aoRow.refresh()
        hlRow.refresh()
        for _, row in ipairs(diffCheckRows) do row.refresh() end
    end

    settPop:SetScript("OnShow", function() settPop.Refresh() end)
    sbFrame.SettingsPopup = settPop
    -- ── end difficulty panel ────────────────────────────────────────────────

    -- ── Title labels ────────────────────────────────────────────────────────
    local dungName = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dungName:SetPoint("TOP", hdr, "TOP", 0, -5);
    dungName:SetJustifyH("CENTER")
    dungName:SetTextColor(C.titleGold[1], C.titleGold[2], C.titleGold[3])
    dungName:SetFont(_FONT_PATH, 16, "")
    sbFrame.DungeonName = dungName
    local subtitle = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOP", dungName, "BOTTOM", 0, -2);
    subtitle:SetJustifyH("CENTER")
    subtitle:SetTextColor(C.white[1], C.white[2], C.white[3]);
    sbFrame.Subtitle = subtitle
    local timer = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timer:SetPoint("TOP", subtitle, "BOTTOM", 0, -1);
    timer:SetJustifyH("CENTER")
    timer:SetTextColor(C.white[1], C.white[2], C.white[3]);
    sbFrame.Timer = timer

    local deathPenaltyLbl = hdr:CreateFontString(nil, "OVERLAY",
                                                 "GameFontNormalSmall")
    deathPenaltyLbl:SetPoint("TOP", timer, "BOTTOM", 0, -1)
    deathPenaltyLbl:SetJustifyH("CENTER")
    deathPenaltyLbl:SetTextColor(1, 0.27, 0.27)
    deathPenaltyLbl:Hide()
    sbFrame.DeathPenaltyLabel = deathPenaltyLbl

    local pbLabel = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pbLabel:SetPoint("TOP", deathPenaltyLbl, "BOTTOM", 0, -2)
    pbLabel:SetJustifyH("CENTER")
    pbLabel:SetTextColor(C.pbGreen[1], C.pbGreen[2], C.pbGreen[3])
    pbLabel:SetText("** Personal Best **")
    pbLabel:Hide()
    sbFrame.PBLabel = pbLabel

    -- ── Affix icons ────────────────────────────────────────────────────────
    -- Up to 4 icons shown below the PB label, centred in the header.
    -- ScenarioChallengeModeAffixMixin, which gives us SetUp(affixID) and OnEnter
    -- tooltip handling for free, and uses the "ChallengeMode-AffixRing-Sm" atlas
    -- border just like MPT does.
    local AFFIX_SIZE = 16 -- MPT uses 16
    local AFFIX_GAP = 5 -- MPT uses 5
    local affixIcons = {}
    for i = 1, 4 do
        local frame = CreateFrame("Frame", nil, hdr)
        frame:SetSize(AFFIX_SIZE, AFFIX_SIZE)
        frame:Hide()
        frame:EnableMouse(true)

        -- Ring border (OVERLAY layer) — matches MPT exactly
        local border = frame:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints()
        border:SetAtlas("ChallengeMode-AffixRing-Sm")
        frame.Border = border

        -- Portrait texture (ARTWORK layer) — SetUp() will populate this
        local portrait = frame:CreateTexture(nil, "ARTWORK")
        portrait:SetSize(AFFIX_SIZE, AFFIX_SIZE)
        portrait:SetPoint("CENTER", border)
        frame.Portrait = portrait

        -- Mix in Blizzard's affix mixin — provides SetUp(affixID) and OnEnter tooltip
        frame.SetUp = ScenarioChallengeModeAffixMixin.SetUp
        frame:SetScript("OnEnter", ScenarioChallengeModeAffixMixin.OnEnter)
        frame:SetScript("OnLeave", GameTooltip_Hide)

        affixIcons[i] = frame
    end

    -- Position all visible icons centred horizontally.
    -- MPT positions icon[1] relative to the right edge, then chains LEFT→RIGHT.
    local function LayoutAffixIcons(count)
        local totalW = count * AFFIX_SIZE + (count - 1) * AFFIX_GAP
        local startX = -totalW / 2 + AFFIX_SIZE / 2
        local anchorY = -4 -- relative to pbLabel bottom
        for i = 1, 4 do
            local frame = affixIcons[i]
            frame:ClearAllPoints()
            if i <= count then
                local xOff = startX + (i - 1) * (AFFIX_SIZE + AFFIX_GAP)
                frame:SetPoint("TOP", sbFrame.PBLabel, "BOTTOM", xOff, anchorY)
                frame:Show()
            else
                frame:Hide()
            end
        end
    end
    sbFrame.AffixIcons = affixIcons
    sbFrame.LayoutAffixIcons = LayoutAffixIcons

    -- ── Column header row ───────────────────────────────────────────────────
    local colHdr = CreateFrame("Frame", nil, sbFrame)
    colHdr:SetPoint("TOPLEFT", sbFrame, "TOPLEFT", 1, -(HDR_H + 1))
    colHdr:SetPoint("TOPRIGHT", sbFrame, "TOPRIGHT", -1, -(HDR_H + 1))
    colHdr:SetHeight(COL_HDR_H)
    local xOff = 8
    for _, col in ipairs(COLS) do
        local btn = CreateFrame("Frame", nil, colHdr)
        btn:SetPoint("LEFT", colHdr, "LEFT", xOff, 0)
        btn:SetSize(col.w, COL_HDR_H)
        btn:EnableMouse(true)

        local HEADLINE_KEYS = {dps = true, hps = true, interrupts = true}
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if col.key == "loot" then
            lbl:SetPoint("LEFT", btn, "LEFT", 0, 0)
            lbl:SetWidth(col.w)
            lbl:SetJustifyH("CENTER")
        else
            local lblX = col.key == "deaths" and 2 or 4
            lbl:SetPoint("LEFT", btn, "LEFT", lblX, 0)
            lbl:SetWidth(col.w - 4)
            lbl:SetJustifyH("LEFT")
        end
        lbl:SetText(col.label)
        lbl:SetTextColor(C.colHdr[1], C.colHdr[2], C.colHdr[3])
        local hdrFontSize = (col.key == "player") and 12 or
                                (HEADLINE_KEYS[col.key] and 14 or 13)
        lbl:SetFont(_FONT_PATH, hdrFontSize, "")
        colHdrLabels[col.key] = lbl

        local hov = btn:CreateTexture(nil, "HIGHLIGHT");
        hov:SetAllPoints()
        hov:SetColorTexture(1, 1, 1, 0.06)

        local colKey = col.key
        local colLabel = col.label
        btn:SetScript("OnMouseUp", function(_, mouseBtn)
            if mouseBtn ~= "LeftButton" then return end
            if sortState.key == colKey then
                if sortState.dir == 1 then
                    sortState.dir = -1
                else
                    sortState.key = nil
                    sortState.dir = 1
                end
            else
                sortState.key = colKey
                sortState.dir = 1
            end
            -- Update all header labels
            for k, fs in pairs(colHdrLabels) do
                local baseLbl
                for _, c in ipairs(COLS) do
                    if c.key == k then
                        baseLbl = c.label;
                        break
                    end
                end
                if k == sortState.key then
                    local arrow = sortState.dir == 1 and " v" or " ^"
                    fs:SetText(baseLbl .. arrow)
                    fs:SetTextColor(C.titleGold[1], C.titleGold[2],
                                    C.titleGold[3])
                else
                    fs:SetText(baseLbl)
                    fs:SetTextColor(C.colHdr[1], C.colHdr[2], C.colHdr[3])
                end
            end
            MS:RefreshOverview()
        end)

        xOff = xOff + col.w
    end
    HLine(colHdr, -COL_HDR_H + 1)

    -- ── Scroll frame ────────────────────────────────────────────────────────
    overviewSF = MakeScrollFrame(sbFrame, 1, -(HDR_H + COL_HDR_H + 2), -1,
                                 tlView.height + 1)
    sbFrame.overviewSF = overviewSF
    local tlc = CreateFrame("Frame", nil, sbFrame)
    tlc:SetPoint("BOTTOMLEFT", sbFrame, "BOTTOMLEFT", 1, 1)
    tlc:SetPoint("BOTTOMRIGHT", sbFrame, "BOTTOMRIGHT", -1, 1)
    tlc:SetHeight(tlView.height)
    tlc:Hide()
    sbFrame.timelineContainer = tlc

    MS:SetSBFrameVisibleCallback(function()
        return sbFrame and sbFrame:IsShown()
    end)

    -- ── Slash commands ──────────────────────────────────────────────────────
    SLASH_MYTHICSCOREBOARD1 = "/sb"
    SLASH_MYTHICSCOREBOARD2 = "/mscoreboard"
    SlashCmdList["MYTHICSCOREBOARD"] = function(msg)
        local cmd = _slower(_smatch(msg or "", "^%s*(.-)%s*$"))
        if cmd == "" then
            MS:ShowScoreboard()
        elseif cmd == "help" then
            print("|cff00ccff[MythicScoreboard]|r v" .. MS.version ..
                      "  Commands: /sb, /sb clear, /sb autoreset, /sb help")

        elseif cmd == "autoreset" then
            local newVal = not MS:GetAutoResetMeter()
            MS:SetAutoResetMeter(newVal)
            local state = newVal and "|cff00ff00ON|r" or "|cffff4444OFF|r"
            print(
                "|cff00ccff[MythicScoreboard]|r Auto-reset Blizzard damage meter on zone-in: " ..
                    state)
        elseif cmd == "clear" then
            DoClearHistory()
        else
            print(
                "|cff00ccff[MythicScoreboard]|r Unknown command. Type /sb help for a list.")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Row pool
-- ---------------------------------------------------------------------------

local function ClearRows(rows)
    for _, r in ipairs(rows) do r:Hide() end
    wipe(rows)
end

-- Return a row frame from the pool (creating it if needed).
-- Each pool row has pre-built children; callers update their content.
local function AcquireRow(parent)
    local row = _rem(_rowPool)
    if row then
        row:SetParent(parent)
        row:ClearAllPoints()
        row:Show()
        -- Defensive: create _cstrip if missing (shouldn't happen but guards
        -- against any edge case where it was never initialised).
        if not row._cstrip then
            local cstrip = CreateFrame("Frame", nil, row)
            cstrip:SetSize(3, ROW_H);
            cstrip:SetPoint("LEFT", row, "LEFT", 0, 0)
            row._cstrip = cstrip
        end
        return row
    end
    -- Build a new row with all child regions pre-allocated.
    row = CreateFrame("Frame", nil, parent)
    row:SetSize(FRAME_W - 12, ROW_H)

    local cstrip = CreateFrame("Frame", nil, row)
    cstrip:SetSize(3, ROW_H);
    cstrip:SetPoint("LEFT", row, "LEFT", 0, 0)
    row._cstrip = cstrip

    -- Self-glow textures (shown only for the local player's row)
    local selfBg = row:CreateTexture(nil, "BORDER")
    selfBg:SetAllPoints();
    selfBg:SetColorTexture(0.72, 0.62, 0.08, 0.13);
    selfBg:Hide()
    row._selfBg = selfBg

    local glowTop = row:CreateTexture(nil, "ARTWORK")
    glowTop:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    glowTop:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    glowTop:SetHeight(ROW_H)
    glowTop:SetGradient("VERTICAL", CreateColor(0.95, 0.82, 0.10, 0.22),
                        CreateColor(0.95, 0.82, 0.10, 0.00))
    glowTop:Hide();
    row._glowTop = glowTop

    local glowLine = row:CreateTexture(nil, "OVERLAY")
    glowLine:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    glowLine:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    glowLine:SetHeight(1);
    glowLine:SetColorTexture(1.0, 0.90, 0.25, 0.80)
    glowLine:Hide();
    row._glowLine = glowLine

    local glowLeft = row:CreateTexture(nil, "OVERLAY")
    glowLeft:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    glowLeft:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    glowLeft:SetWidth(2);
    glowLeft:SetColorTexture(1.0, 0.88, 0.20, 0.90)
    glowLeft:Hide();
    row._glowLeft = glowLeft

    -- Class icon
    local classIcon = row:CreateTexture(nil, "ARTWORK")
    classIcon:SetSize(ICON_SIZE, ICON_SIZE)
    classIcon:SetPoint("LEFT", row, "LEFT", 8, 0)
    classIcon:SetTexture(
        "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    row._classIcon = classIcon

    -- Role icon
    local roleIcon = row:CreateTexture(nil, "ARTWORK")
    roleIcon:SetSize(16, 16)
    roleIcon:SetPoint("BOTTOMLEFT", classIcon, "BOTTOMRIGHT", 2, 0)
    row._roleIcon = roleIcon

    -- Player name + sub-label (item level)
    local iconTotalW = ICON_SIZE + 2 + 16 + 4
    local nameX = 8 + iconTotalW
    local nameW = COLS[1].w - iconTotalW - 4

    local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameFs:SetPoint("LEFT", row, "LEFT", nameX, 5)
    nameFs:SetWidth(nameW);
    nameFs:SetJustifyH("LEFT")
    nameFs:SetFont(_FONT_PATH, 13, "")
    row._nameFs = nameFs

    local subFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subFs:SetPoint("LEFT", row, "LEFT", nameX, -8)
    subFs:SetWidth(nameW);
    subFs:SetJustifyH("LEFT")
    subFs:SetFont(_FONT_PATH, 11, "")
    row._subFs = subFs

    -- Loot icon/button
    local lootBtn = CreateFrame("Button", nil, row)
    lootBtn:SetSize(32, 32)
    lootBtn:SetFrameLevel(row:GetFrameLevel() + 10) -- ADD THIS LINE

    local lootX = 8 + COLS[1].w + COLS[2].w
    lootBtn:SetPoint("CENTER", row, "LEFT", lootX + COLS[3].w / 2, 0)

    lootBtn:EnableMouse(true)

    local lootBorder = lootBtn:CreateTexture(nil, "BACKGROUND")
    lootBorder:SetPoint("TOPLEFT", lootBtn, "TOPLEFT", -2, 2)
    lootBorder:SetPoint("BOTTOMRIGHT", lootBtn, "BOTTOMRIGHT", 2, -2)
    lootBorder:SetColorTexture(0, 0, 0, 1)
    lootBtn._border = lootBorder

    -- 2. Icon Texture (placed on ARTWORK layer directly over the button)
    local lootIcon = lootBtn:CreateTexture(nil, "ARTWORK")
    lootIcon:SetPoint("TOPLEFT", lootBtn, "TOPLEFT", 0, 0)
    lootIcon:SetPoint("BOTTOMRIGHT", lootBtn, "BOTTOMRIGHT", 0, 0)
    lootIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Crops baked-in border graphics
    lootBtn._icon = lootIcon

    lootBtn:Hide()

    row._lootBtn = lootBtn
    row._lootIcon = lootIcon

    local function HasBonusIDs(link)
        if type(link) ~= "string" then return false end
        local itemString = link:match("item:([%d:]+)")
        if not itemString then return false end

        local parts = {strsplit(":", itemString)}
        local numBonus = tonumber(parts[13])
        return numBonus and numBonus > 0
    end

    lootBtn:SetScript("OnEnter", function(self)
        local p = self:GetParent()._player
        if not p then return end

        local name = p.lootItemName
        if not name or name == "" then return end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

        -- 1. Display full Blizzard Tooltip if we have a hyperlink with scaling Bonus IDs
        if p.lootItemLink and HasBonusIDs(p.lootItemLink) then
            local ok = pcall(GameTooltip.SetHyperlink, GameTooltip,
                             p.lootItemLink)
            if ok and GameTooltip:NumLines() > 0 then
                GameTooltip:Show()
                return
            else
                GameTooltip:ClearLines()
            end
        end

        -- 2. Fallback Tooltip for historical runs / plain text drops
        local r, g, b = 1, 1, 1
        if p.lootQualityColor and type(p.lootQualityColor) == "table" and
            #p.lootQualityColor >= 3 then
            r = p.lootQualityColor[1]
            g = p.lootQualityColor[2]
            b = p.lootQualityColor[3]
        end

        GameTooltip:SetText(name, r, g, b)

        if p.lootItemLevel and p.lootItemLevel > 0 then
            GameTooltip:AddLine("Item Level: " .. tostring(p.lootItemLevel), 0.8,
                                0.8, 0.8)
        end

        GameTooltip:AddLine("Mythic+ Dungeon Drop", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    lootBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Stat FontStrings — headline stats (dps, hps, deaths, interrupts) at 14pt,
    -- secondary stats at 13pt.
    local HEADLINE = {dps = true, hps = true, interrupts = true}
    row._statFs = {}
    local xOff = 8
    for _, col in ipairs(COLS) do
        if col.key ~= "player" then
            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("LEFT", row, "LEFT", xOff + 4, 0)
            lbl:SetWidth(col.w - 4);
            lbl:SetJustifyH("LEFT")
            lbl:SetFont(_FONT_PATH, HEADLINE[col.key] and 14 or 13, "")
            row._statFs[col.key] = lbl
        end
        xOff = xOff + col.w
    end

    -- Hover highlight
    local hov = row:CreateTexture(nil, "HIGHLIGHT");
    hov:SetAllPoints()
    hov:SetColorTexture(1, 1, 1, 0.04)

    -- Separator (tracked so the last row can hide it)
    local sep = row:CreateTexture(nil, "ARTWORK");
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    row._sep = sep

    -- Scripts read row._player dynamically — no per-refresh closure allocation
    row:EnableMouse(true)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

local function ReleaseRow(row)
    if not row then return end
    -- FontStrings (e.g. _emptyLbl) are regions, not frames; skip them.
    if row.GetObjectType and row:GetObjectType() ~= "Frame" then return end
    if not row.SetParent then return end
    row:Hide()
    row:SetParent(UIParent)
    row:ClearAllPoints()
    _ins(_rowPool, row)
end

-- ---------------------------------------------------------------------------
-- Column rendering
-- ---------------------------------------------------------------------------

local COL_RENDERERS = {
    score = function(p)
        local sc = p.mythicScore or 0
        if sc <= 0 then return "—", C.stat[1], C.stat[2], C.stat[3] end
        local text = tostring(sc)
        if p.mythicScoreGain and p.mythicScoreGain > 0 then
            text = text .. _fmt(" |cff59ff7f(+%d)|r", p.mythicScoreGain)
        end
        return text, ScoreColor(sc)
    end,
    deaths = function(p)
        local d = p.deaths or 0
        if d > 0 then return tostring(d), C.red[1], C.red[2], C.red[3] end
        return "0", C.stat[1], C.stat[2], C.stat[3]
    end,
    dmgTaken = function(p)
        return Abbrev(p.damageTaken), C.stat[1], C.stat[2], C.stat[3]
    end,
    avoidable = function(p)
        local v = p.avoidableDamageTaken or 0
        if v > 0 then
            return Abbrev(v), C.orange[1], C.orange[2], C.orange[3]
        end
        return "0", C.stat[1], C.stat[2], C.stat[3]
    end,
    dps = function(p, dur)
        local v = (p.dps or 0) > 0 and p.dps or
                      ((dur > 0 and (p.damageDone or 0) > 0) and
                          (p.damageDone / dur) or 0)
        return Abbrev(v), 0.38, 0.68, 1.00
    end,
    hps = function(p, dur)
        local v = (p.hps or 0) > 0 and p.hps or
                      ((dur > 0 and (p.healingDone or 0) > 0) and
                          (p.healingDone / dur) or 0)
        return Abbrev(v), 0.28, 0.94, 0.65
    end,
    interrupts = function(p)
        local interrupts = p.interrupts or 0
        local stunInterrupts = p.stunInterrupts or 0

        local label = tostring(interrupts)
        if stunInterrupts > 0 then
            label = label .. " (" .. tostring(stunInterrupts) .. ")"
        end

        if interrupts > 0 or stunInterrupts > 0 then
            return label, C.cyan[1], C.cyan[2], C.cyan[3]
        end

        return "0", C.stat[1], C.stat[2], C.stat[3]
    end,
    dispels = function(p)
        local v = p.dispels or 0
        if v > 0 then
            return tostring(v), C.dispel[1], C.dispel[2], C.dispel[3]
        end
        return "0", C.stat[1], C.stat[2], C.stat[3]
    end
}

-- ---------------------------------------------------------------------------
-- Scoreboard public API
-- ---------------------------------------------------------------------------

function MS:ShowScoreboard()
    if not sbFrame then self:BuildUI() end
    sbFrame:Show();
    sbFrame:Raise()
    self._refreshPending = false
    local ok, err = pcall(self._DoRefreshOverview, self)
    if not ok then
        print("|cffff4444[MythicScoreboard]|r Scoreboard refresh error: " ..
                  tostring(err))
    end
end

function MS:RefreshOverview()
    if not sbFrame then return end
    if self._refreshPending then return end
    self._refreshPending = true
    C_Timer.After(0, function()
        self._refreshPending = false
        if not sbFrame then return end
        if self._refreshing then return end
        self._refreshing = true
        local ok, err = pcall(self._DoRefreshOverview, self)
        self._refreshing = false
        if not ok then
            print("|cffff4444[MythicScoreboard]|r Scoreboard refresh error: " ..
                      tostring(err))
        end
        if sbFrame and sbFrame.RefreshHistBtn then
            sbFrame.RefreshHistBtn()
        end
    end)
end

local ROLE_ORDER = {TANK = 1, HEALER = 2, DAMAGER = 3}

local function DefaultPlayerSort(a, b)
    local aLeft = a.left and 1 or 0
    local bLeft = b.left and 1 or 0
    if aLeft ~= bLeft then return aLeft < bLeft end
    local ra = ROLE_ORDER[GetRole(a)] or 3
    local rb = ROLE_ORDER[GetRole(b)] or 3
    if ra ~= rb then return ra < rb end
    return (a.damageDone or 0) > (b.damageDone or 0)
end

function MS:_DoRefreshOverview()
    if not sbFrame then return end
    if self.inDungeon and not InCombatLockdown() then
        self:SnapshotFromDamageMeter()
    end

    local run = self.currentRun
    if not run then
        if self.displayRun then
            run = self.displayRun
        elseif MythicScoreboardDB and MythicScoreboardDB.runs and
            #MythicScoreboardDB.runs > 0 then
            run = MythicScoreboardDB.runs[1]
        end
    end

    if run then
        local isMPlus = (run.keystoneLevel or 0) > 0
        sbFrame.DungeonName:SetText(isMPlus and
                                        ((run.dungeonName or "?") .. " +" ..
                                            run.keystoneLevel) or
                                        (run.dungeonName or "?"))
        sbFrame.Subtitle:SetText((run.difficultyLabel and run.difficultyLabel ~=
                                     "") and run.difficultyLabel or
                                     "Mythic Keystone")
        sbFrame.Timer:SetText(self:FormatTime(MS:GetRunDuration(run)))

        -- Death penalty shown below the elapsed timer
        local penalty = run.deathPenaltySeconds or 0
        if isMPlus and penalty > 0 then
            local deaths = 0
            for _, p in pairs(run.players) do
                deaths = deaths + (p.deaths or 0)
            end
            sbFrame.DeathPenaltyLabel:SetText(
                "-" .. MS:FormatTime(penalty) .. " (" .. deaths .. " death" ..
                    (deaths == 1 and "" or "s") .. ")")
            sbFrame.DeathPenaltyLabel:Show()
            sbFrame.PBLabel:ClearAllPoints()
            sbFrame.PBLabel:SetPoint("TOP", sbFrame.DeathPenaltyLabel, "BOTTOM",
                                     0, -2)
        else
            sbFrame.DeathPenaltyLabel:Hide()
            sbFrame.PBLabel:ClearAllPoints()
            sbFrame.PBLabel:SetPoint("TOP", sbFrame.Timer, "BOTTOM", 0, -2)
        end

        -- PB indicator: check personalBests first (survives history clears),
        -- then fall back to comparing against run history.
        local showPB = false
        if run.completed and run.inTime and isMPlus and MythicScoreboardDB then
            local thisDur = (run.endTime or 0) - (run.startTime or 0)
            if thisDur > 0 then
                local key = (run.dungeonName or "") .. ":" ..
                                (run.keystoneLevel or 0)
                local pb = MythicScoreboardDB.personalBests and
                               MythicScoreboardDB.personalBests[key]
                if pb then
                    showPB = (thisDur <= pb)
                elseif MythicScoreboardDB.runs then
                    local isPB = true
                    for _, r in ipairs(MythicScoreboardDB.runs) do
                        if r ~= run and r.completed and r.inTime and
                            r.dungeonName == run.dungeonName and
                            (r.keystoneLevel or 0) == (run.keystoneLevel or 0) then
                            local d = (r.endTime or 0) - (r.startTime or 0)
                            if d > 0 and d < thisDur then
                                isPB = false;
                                break
                            end
                        end
                    end
                    showPB = isPB
                end
            end
        end
        if showPB then
            sbFrame.PBLabel:Show()
        else
            sbFrame.PBLabel:Hide()
        end

        -- Affix icons:
        -- 1. Build a plain list of integer affix IDs from the stored run data.
        -- 2. Call C_ChallengeMode.GetAffixInfo(affixID) for name+description+filedataid.
        -- 3. Call frame:SetUp(affixID) — ScenarioChallengeModeAffixMixin handles
        --    portrait texture, border atlas, and tooltip wiring automatically.
        local affixIDs = {}
        if run.affixes and #run.affixes > 0 then
            for _, af in ipairs(run.affixes) do
                -- Stored as {id=N} by Data.lua; plain integers also accepted.
                _ins(affixIDs, af.id or af)
            end
        end
        -- Fall back to the live keystone info when the run has no stored affixes
        -- (e.g. scoreboard is viewing a historical run from before this fix).
        if #affixIDs == 0 and C_ChallengeMode and
            C_ChallengeMode.GetActiveKeystoneInfo then
            local _, keystoneAffixes = C_ChallengeMode.GetActiveKeystoneInfo()
            if keystoneAffixes then
                for _, id in ipairs(keystoneAffixes) do
                    _ins(affixIDs, id)
                end
            end
        end

        if isMPlus and #affixIDs > 0 then
            local count = _min(4, #affixIDs)
            for i = 1, count do
                local frame = sbFrame.AffixIcons[i]
                local affixID = affixIDs[i]

                -- Only call SetUp when the affix ID actually changed — same
                -- guard MPT uses (affix_icon_frame.affix_id ~= affix_id).
                if frame.affix_id ~= affixID then
                    frame:SetUp(affixID) -- ScenarioChallengeModeAffixMixin.SetUp
                    frame.affix_id = affixID
                end
                frame:Show()
            end
            -- Hide unused slots
            for i = count + 1, 4 do sbFrame.AffixIcons[i]:Hide() end
            sbFrame.LayoutAffixIcons(count)
        else
            -- No affixes — hide all icons
            for i = 1, 4 do sbFrame.AffixIcons[i]:Hide() end
        end
    else
        sbFrame.DungeonName:SetText("Mythic+ Scoreboard")
        sbFrame.Subtitle:SetText("No run data")
        sbFrame.Timer:SetText("")
        sbFrame.DeathPenaltyLabel:Hide()
        sbFrame.PBLabel:Hide()
        for i = 1, 4 do sbFrame.AffixIcons[i]:Hide() end
    end

    -- Boss signature: number of bosses + last kill time. Timeline only rebuilds
    -- when this changes, not on every RefreshOverview call.
    local function BossSig(r)
        if not r or not r.bosses then return "" end
        local last = 0
        for _, b in ipairs(r.bosses) do
            if (b.killTime or 0) > last then last = b.killTime end
        end
        return #r.bosses .. ":" .. last
    end

    sbFrame._tlRun = run

    if not sbFrame._rebuildTimeline then
        sbFrame._rebuildTimeline = function(forceRebuild)
            if sbFrame._tlRebuilding then return end

            local now = GetTime()
            local r = sbFrame._tlRun
            local sig = BossSig(r)
            local runChanged = r ~= sbFrame._tlLastBuiltRun
            local bossChanged = sig ~= (sbFrame._tlLastBossSig or "")
            if not forceRebuild and not runChanged and not bossChanged and
                sbFrame._tlLastBuild and (now - sbFrame._tlLastBuild) < 0.25 then
                return
            end
            sbFrame._tlLastBuild = now
            sbFrame._tlLastBuiltRun = r
            sbFrame._tlLastBossSig = sig
            sbFrame._tlRebuilding = true

            local tlc = sbFrame.timelineContainer
            local r = sbFrame._tlRun
            local newTotalH = HDR_H + COL_HDR_H + 1 + (ROW_H * 5) +
                                  tlView.height + 2
            sbFrame:SetHeight(newTotalH)
            overviewSF:ClearAllPoints()
            overviewSF:SetPoint("TOPLEFT", sbFrame, "TOPLEFT", 1,
                                -(HDR_H + COL_HDR_H + 2))
            overviewSF:SetPoint("BOTTOMRIGHT", sbFrame, "BOTTOMRIGHT", -1,
                                tlView.height + 1)
            if r then
                tlc:Show()
                local ok, err = pcall(BuildTimeline, tlc, r,
                                      GetTimelineDuration(r), function()
                    sbFrame._rebuildTimeline(true)
                end)
                if not ok then
                    print(
                        "|cffff4444[MythicScoreboard]|r Timeline build error: " ..
                            tostring(err))
                    sbFrame._tlLastBuild = GetTime() + 2.0 -- back off 2s to avoid spam
                    tlc:Hide()
                else
                    sbFrame._updateLive = tlc.UpdateLive
                end
            else
                tlc:Hide()
                sbFrame._updateLive = nil
            end

            sbFrame._tlRebuilding = false
        end
    end

    sbFrame._rebuildTimeline()

    if sbFrame._updateLive and sbFrame._tlRun then
        sbFrame._updateLive(sbFrame._tlRun, GetTimelineDuration(sbFrame._tlRun))
    end

    local sf = overviewSF
    local content = sf.scrollContent

    -- Skip the expensive row teardown/rebuild when nothing has changed.
    -- _seq is incremented by SaveCurrentRun on every data write, so this
    -- correctly fires on DPS updates, death events, etc., but not on the
    -- 2-second ticker ticks that produce no new data.
    local runSeq = run and (run._seq or 0) or -1
    local sortKey = sortState.key
    local sortDir = sortState.dir
    local rowsDirty = (run ~= sbFrame._lastRowsRun) or
                          (runSeq ~= (sbFrame._lastRowsSeq or -2)) or
                          (sortKey ~= sbFrame._lastRowsSortKey) or
                          (sortDir ~= sbFrame._lastRowsSortDir)
    if not rowsDirty then return end

    sbFrame._lastRowsRun = run
    sbFrame._lastRowsSeq = runSeq
    sbFrame._lastRowsSortKey = sortKey
    sbFrame._lastRowsSortDir = sortDir

    if not run then
        for _, r in ipairs(overviewRows) do ReleaseRow(r) end
        wipe(overviewRows)
        -- Re-use a persistent label rather than creating a new FontString
        if not sbFrame._emptyLbl then
            sbFrame._emptyLbl = content:CreateFontString(nil, "OVERLAY",
                                                         "GameFontNormalSmall")
            sbFrame._emptyLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -20)
            sbFrame._emptyLbl:SetTextColor(C.bossTime[1], C.bossTime[2],
                                           C.bossTime[3])
        end
        sbFrame._emptyLbl:SetText("No run data.")
        sbFrame._emptyLbl:Show()
        _ins(overviewRows, sbFrame._emptyLbl)
        content:SetHeight(60);
        sf.UpdateRange();
        return
    end

    local dur = self:GetRunDuration(run)
    wipe(_playersBuf)
    for _, p in pairs(run.players) do _ins(_playersBuf, p) end
    local players = _playersBuf

    -- ROLE_ORDER is a module-level constant defined above _DoRefreshOverview
    if sortState.key and COL_SORT_VALUES[sortState.key] then
        local getter = COL_SORT_VALUES[sortState.key]
        local dir = sortState.dir
        local isStr = sortState.key == "player"
        _sort(players, function(a, b)
            if not a or not b then return false end
            local av, bv = getter(a), getter(b)
            if isStr then
                if dir == 1 then
                    return av < bv
                else
                    return av > bv
                end
            else
                if av ~= bv then
                    if dir == 1 then
                        return av > bv
                    else
                        return av < bv
                    end
                end
                return (a.name or "") < (b.name or "")
            end
        end)
    else
        _sort(players, DefaultPlayerSort)
    end

    -- Release any previously active rows back to the pool
    for _, r in ipairs(overviewRows) do ReleaseRow(r) end
    wipe(overviewRows)

    local yOff = 0
    local localName = UnitName("player")
    for idx, p in ipairs(players) do
        local isEven = (idx % 2 == 0)
        local isHeal = (p.healingDone or 0) > (p.damageDone or 0)
        local hasLeft = p.left == true
        local isSelf = (p.name == localName)

        local row = AcquireRow(content)
        row:SetSize(FRAME_W - 12, ROW_H)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)

        -- Background
        local rb = isHeal and C.rowHeal or (isEven and C.rowEven or C.rowOdd)
        SetBG(row, rb[1], rb[2], rb[3], 1)

        -- Self-glow
        row._selfBg:SetShown(isSelf)
        row._glowTop:SetShown(isSelf)
        row._glowLine:SetShown(isSelf)
        row._glowLeft:SetShown(isSelf)

        -- Class color strip
        local cr, cg, cb_c = ClassColor(p.class)
        local dimFactor = hasLeft and 0.35 or 1.0
        if row._cstrip then
            SetBG(row._cstrip, cr * dimFactor, cg * dimFactor, cb_c * dimFactor,
                  0.85)
        end

        -- Last row hides its separator to avoid a double-border with the frame edge
        if row._sep then row._sep:SetShown(idx < #players) end

        -- Class icon
        local cc = CLASS_ICON_COORDS[p.class] or CLASS_ICON_COORDS["UNKNOWN"]
        row._classIcon:SetTexCoord(cc[1], cc[2], cc[3], cc[4])

        -- Role icon
        local role = GetRole(p)
        row._roleIcon:SetTexture(ROLE_ICON_TEX)
        row._roleIcon:Show()
        if GetTexCoordsForRoleSmallCircle then
            row._roleIcon:SetTexCoord(GetTexCoordsForRoleSmallCircle(role))
        else
            local rc = ROLE_ICON_COORDS[role] or ROLE_ICON_COORDS["DAMAGER"]
            row._roleIcon:SetTexCoord(rc[1], rc[2], rc[3], rc[4])
        end

        -- Player name
        -- row._nameFs:SetText(p.name or "?")
        row._nameFs:SetText(TransliterateName(p.name or "?"))
        if hasLeft then
            row._nameFs:SetTextColor(cr * 0.45, cg * 0.45, cb_c * 0.45)
        else
            row._nameFs:SetTextColor(cr, cg, cb_c)
        end

        -- Sub-label (item level)
        if (p.itemLevel or 0) > 0 then
            row._subFs:SetText(tostring(p.itemLevel))
        elseif hasLeft then
            row._subFs:SetText("|cffaaaaaa(left)|r")
        else
            row._subFs:SetText("")
        end
        row._subFs:SetTextColor(cr * 0.65, cg * 0.65, cb_c * 0.65)

        -- Update loot icon & quality border
        if p.lootIcon then
            row._lootIcon:SetTexture(p.lootIcon)

            -- Determine quality color with fallback
            local r, g, b
            if p.lootQualityColor and type(p.lootQualityColor) == "table" and
                #p.lootQualityColor >= 3 then
                r, g, b = p.lootQualityColor[1], p.lootQualityColor[2],
                          p.lootQualityColor[3]
            elseif p.lootItemLink then
                local quality = select(3, C_Item.GetItemInfo(p.lootItemLink))
                if quality then
                    r, g, b = C_Item.GetItemQualityColor(quality)
                end
            end

            -- Default fallback to Epic Purple
            r = r or 0.64
            g = g or 0.21
            b = b or 0.93

            -- Apply solid 2px border color
            row._lootBtn._border:SetColorTexture(r, g, b, 1)
            row._lootBtn:Show()
        else
            row._lootBtn:Hide()
        end

        -- Stat columns
        for _, col in ipairs(COLS) do
            if col.key ~= "player" then
                local lbl = row._statFs[col.key]
                if lbl then
                    local val, vr, vg, vb = "", C.stat[1], C.stat[2], C.stat[3]
                    local fn = COL_RENDERERS[col.key]
                    if fn then val, vr, vg, vb = fn(p, dur) end
                    lbl:SetText(val)
                    lbl:SetTextColor(vr, vg, vb)
                end
            end
        end

        -- Store player ref for tooltip — no per-refresh closure needed
        row._player = p
        row._run = run

        row:SetScript("OnEnter", function(self)
            local pCaptured = self._player
            if not pCaptured then return end
            GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            local mx, my = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            GameTooltip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
                                 mx / scale + 12, my / scale + 12)

            GameTooltip:SetText(pCaptured.name or "?", 1, 1, 1)

            local sc = pCaptured.mythicScore or 0
            if sc > 0 then
                local sr, sg, sb2 = ScoreColor(sc)
                GameTooltip:AddLine(_fmt("M+ Rating: |cff%02x%02x%02x%d|r",
                                         _floor(sr * 255), _floor(sg * 255),
                                         _floor(sb2 * 255), sc), 1, 1, 1)
            end

            if (pCaptured.itemLevel or 0) > 0 then
                GameTooltip:AddLine(_fmt("Item Level: |cffcccccc%d|r",
                                         pCaptured.itemLevel), 1, 1, 1)
            end

            local avoid = pCaptured.avoidableDamageTaken or 0
            if avoid > 0 then
                GameTooltip:AddLine("Avoidable damage: |cffff7700" ..
                                        Abbrev(avoid) .. "|r", 1, 1, 1)
            end

            local intCount = pCaptured.interrupts or 0
            do
                -- Compute highest/lowest across all eligible players first,
                -- before the intCount > 0 guard, so a player with 0 interrupts
                -- can still be tagged ** LOWEST **.
                -- Eligible for lowest: anyone who CAN interrupt.
                -- Excludes non-Shaman healers; all Shaman specs have Wind Shear
                -- so Restoration Shaman stays in the eligible pool.
                local isHoveredHealer = (pCaptured.role == "HEALER")
                local isHoveredShaman = (pCaptured.class == "SHAMAN")
                local hoveredCanInterrupt =
                    not isHoveredHealer or isHoveredShaman

                local badge = ""
                local runRef = self._run
                if runRef and runRef.players then
                    local hi = 0 -- global highest (all players)
                    local lo = _huge -- lowest among interrupt-eligible players
                    local playerCount = 0
                    local loCount = 0
                    for _, op in pairs(runRef.players) do
                        local v = op.interrupts or 0
                        playerCount = playerCount + 1
                        if v > hi then hi = v end
                        local opIsHealer = (op.role == "HEALER")
                        local opIsShaman = (op.class == "SHAMAN")
                        if not opIsHealer or opIsShaman then
                            loCount = loCount + 1
                            if v < lo then lo = v end
                        end
                    end
                    if playerCount > 1 then
                        if intCount > 0 and intCount == hi then
                            badge = " |cffffff00** HIGHEST **|r"
                        elseif loCount > 1 and hoveredCanInterrupt and intCount ==
                            lo then
                            badge = " |cffff4444** LOWEST **|r"
                        end
                    end
                end

                -- Show the line if the player has interrupts OR carries a badge.
                if intCount > 0 or badge ~= "" then
                    GameTooltip:AddLine("Interrupts: |cff00ccff" .. intCount ..
                                            "|r" .. badge, 1, 1, 1)
                end
            end

            local deathCount = pCaptured.deaths or 0
            if deathCount == 0 then
                GameTooltip:AddLine("Deaths: |cff44ff44None|r", 1, 1, 1)
            else
                GameTooltip:AddLine("Deaths: |cffff4444" .. deathCount .. "|r",
                                    1, 1, 1)
                if pCaptured.deathEvents and #pCaptured.deathEvents > 0 then
                    GameTooltip:AddLine(" ", 1, 1, 1)
                    for _, de in ipairs(pCaptured.deathEvents) do
                        local timeStr = MS:FormatTime(de.time or 0)
                        local segmentStr = ""
                        if run and run.bosses then
                            for _, boss in ipairs(run.bosses) do
                                local pullT = boss.pullTime or 0
                                local killT =
                                    boss.killTime or boss.wipeTime or
                                        (run.endTime and run.endTime -
                                            (run.startTime or 0)) or _huge
                                if (de.time or 0) >= pullT and (de.time or 0) <=
                                    killT then
                                    local segLabel =
                                        (boss.name or "?") ..
                                            (boss.wipeTime and not boss.killTime and
                                                " (Wipe)" or "")
                                    local intoPull = (de.time or 0) - pullT
                                    local intoStr = "|cffffffff+" ..
                                                        MS:FormatTime(intoPull) ..
                                                        " into pull|r"
                                    segmentStr =
                                        " |cffffffff[" .. segLabel .. ", " ..
                                            intoStr .. "]|r"
                                    break
                                end
                            end
                        end
                        GameTooltip:AddLine(
                            "|cffff9900" .. timeStr .. "|r" .. segmentStr, 1, 1,
                            1)
                        if de.events then
                            local events = de.events
                            local killingEvent
                            for i = #events, 1, -1 do
                                local ev = events[i]
                                if ev and (ev.overkill and ev.overkill > 0) then
                                    killingEvent = ev;
                                    break
                                end
                            end
                            killingEvent = killingEvent or events[#events]
                            if killingEvent then
                                local spellName =
                                    killingEvent.spellName or "Unknown"
                                local caster = killingEvent.caster or ""
                                local amt = killingEvent.amount or 0
                                local line = "|cffff9944" .. spellName .. "|r"
                                if caster ~= "" then
                                    line =
                                        line .. " |cff888888by|r |cffffd700" ..
                                            caster .. "|r"
                                end
                                if amt > 0 then
                                    line =
                                        line .. " |cffff4444(" .. Abbrev(-amt) ..
                                            ")|r"
                                end
                                GameTooltip:AddLine("  " .. line, 1, 1, 1)
                            end
                            for i = _max(1, #events - 2), #events do
                                local ev = events[i]
                                if ev and ev.spellName and ev.amount then
                                    local hitLine = _fmt(
                                                        "  |cff888888%s|r  |cffff6666%s|r",
                                                        ev.spellName, Abbrev(
                                                            -(ev.amount or 0)))
                                    if ev.overkill and ev.overkill > 0 then
                                        hitLine = hitLine ..
                                                      " |cffff0000(killing blow)|r"
                                    end
                                    GameTooltip:AddLine(hitLine, 1, 1, 1)
                                end
                            end
                        end
                    end
                end
            end

            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        yOff = yOff - ROW_H
        _ins(overviewRows, row)
    end

    content:SetHeight(_max(60, _abs(yOff) + 4))
    sf.UpdateRange()
end

-- Add this near the bottom of UI.lua
function MS:ToggleUI()
    if not sbFrame then MS:BuildUI() end
    if sbFrame:IsShown() then
        sbFrame:Hide()
    else
        MS:RefreshOverview()
        sbFrame:Show()
    end
end
