local MAJOR, MINOR = "LibMythicMetaUI-1.0", 3
local LibStub = _G.LibStub
if not LibStub then return end
local UI = LibStub:NewLibrary(MAJOR, MINOR)
if not UI then return end

UI.WHITE = "Interface\\Buttons\\WHITE8X8"
UI.colors = {
    accent = { 12 / 255, 210 / 255, 157 / 255 },
    panel = { 0.05, 0.04, 0.08, 0.96 },
    surface = { 1, 1, 1, 0.035 },
    surfaceActive = { 1, 1, 1, 0.075 },
    border = { 0.15, 0.15, 0.15, 0.80 },
    text = { 1, 1, 1, 1 },
    muted = { 0.65, 0.65, 0.68, 1 },
    chevron = { 0.58, 0.68, 0.65, 1 },
}

local function color(target, method, value)
    target[method](target, value[1], value[2], value[3], value[4] or 1)
end

function UI:ApplyFont(object, size, flags, fontSetter, textColor)
    if fontSetter then fontSetter(object, size, flags or "") end
    if textColor and object.SetTextColor then color(object, "SetTextColor", textColor) end
end

function UI:StylePanel(panel)
    if panel.SetBackdropColor then color(panel, "SetBackdropColor", self.colors.panel) end
    if panel.SetBackdropBorderColor then color(panel, "SetBackdropBorderColor", self.colors.border) end
    if not panel.mythicMetaAccent then
        local line = panel:CreateTexture(nil, "BORDER")
        line:SetPoint("TOPLEFT", 1, -1); line:SetPoint("TOPRIGHT", -1, -1); line:SetHeight(2)
        color(line, "SetColorTexture", self.colors.accent)
        panel.mythicMetaAccent = line
    end
end

function UI:StyleTab(tab, active, fontSetter, size)
    self:ApplyFont(tab.text, size or 10, "", fontSetter, active and self.colors.accent or self.colors.text)
    if tab.bg then color(tab.bg, "SetColorTexture", active and self.colors.surfaceActive or { 1, 1, 1, 0.025 }) end
    if tab.line then
        color(tab.line, "SetColorTexture", self.colors.accent)
        tab.line:SetShown(active)
    end
end

function UI:StyleSectionHeader(text, fontSetter, size)
    self:ApplyFont(text, size or 10, "", fontSetter, self.colors.accent)
end

function UI:StylePanelTitle(text, fontSetter, size)
    self:ApplyFont(text, size or 11, "", fontSetter, self.colors.text)
end

function UI:StyleButton(button)
    if button.SetBackdropColor then color(button, "SetBackdropColor", self.colors.surface) end
    if button.SetBackdropBorderColor then color(button, "SetBackdropBorderColor", self.colors.border) end
end

function UI:SetButtonHovered(button, hovered)
    if button.SetBackdropColor then button:SetBackdropColor(1, 1, 1, hovered and 0.09 or 0.035) end
    if button.SetBackdropBorderColor then color(button, "SetBackdropBorderColor", hovered and self.colors.accent or self.colors.border) end
    if button.bg then button.bg:SetColorTexture(1, 1, 1, hovered and 0.09 or 0.035) end
end

function UI:StyleSurface(texture, alpha)
    if texture then texture:SetColorTexture(1, 1, 1, alpha or 0.035) end
end

function UI:StyleMenu(menu)
    if menu.SetBackdropColor then menu:SetBackdropColor(0.035, 0.03, 0.055, 0.99) end
    if menu.SetBackdropBorderColor then color(menu, "SetBackdropBorderColor", { self.colors.accent[1], self.colors.accent[2], self.colors.accent[3], 0.65 }) end
end

function UI:StyleDivider(texture, alpha)
    if texture then texture:SetColorTexture(self.colors.accent[1], self.colors.accent[2], self.colors.accent[3], alpha or 0.28) end
end

function UI:StyleLock(lock, unlocked)
    if not lock or not lock.body or not lock.left or not lock.top or not lock.right then return end
    local tint = unlocked and self.colors.accent or { 0.66, 0.66, 0.69, 1 }
    for _, region in ipairs({ lock.body, lock.left, lock.top, lock.right }) do color(region, "SetColorTexture", tint) end
    lock.left:ClearAllPoints(); lock.top:ClearAllPoints(); lock.right:ClearAllPoints()
    lock.left:SetPoint("BOTTOM", lock.body, "TOP", -3, 0)
    lock.top:SetPoint("BOTTOM", lock.body, "TOP", 0, 4)
    lock.right:SetPoint("BOTTOM", lock.body, "TOP", 3, unlocked and 2 or 0)
    if lock.keyhole then lock.keyhole:SetColorTexture(self.colors.panel[1], self.colors.panel[2], self.colors.panel[3], 0.95) end
end

function UI:StyleSelect(button)
    self:StyleButton(button)
    if button.text then
        button.text:ClearAllPoints(); button.text:SetPoint("LEFT", 9, 0); button.text:SetPoint("RIGHT", -27, 0); button.text:SetJustifyH("LEFT")
    end
    button.chevron = button.chevron or {}
    if #button.chevron == 0 then
        local left = button:CreateTexture(nil, "OVERLAY"); left:SetTexture(self.WHITE); left:SetSize(6, 1); left:SetPoint("RIGHT", -12, 1); left:SetRotation(-math.pi / 4)
        local right = button:CreateTexture(nil, "OVERLAY"); right:SetTexture(self.WHITE); right:SetSize(6, 1); right:SetPoint("RIGHT", -8, 1); right:SetRotation(math.pi / 4)
        button.chevron[1], button.chevron[2] = left, right
    end
    for _, line in ipairs(button.chevron) do color(line, "SetVertexColor", self.colors.chevron) end
end

function UI:StyleMenuOption(button)
    if not button.text then return end
    button.text:ClearAllPoints(); button.text:SetPoint("LEFT", 8, 0); button.text:SetPoint("RIGHT", -8, 0); button.text:SetJustifyH("LEFT")
end

function UI:StyleValueToggle(button, label)
    label:SetParent(button); label:ClearAllPoints(); label:SetPoint("LEFT", 10, 0); label:SetWidth(button:GetWidth() - 70); label:SetJustifyH("LEFT")
    button.text:ClearAllPoints(); button.text:SetPoint("RIGHT", -10, 0); button.text:SetWidth(62); button.text:SetJustifyH("RIGHT")
    self:StyleButton(button)
end

function UI:StyleCheckbox(check, checked)
    if check.box then check.box:SetColorTexture(1, 1, 1, 0.10) end
    if check.mark then
        color(check.mark, "SetColorTexture", self.colors.accent)
        check.mark:SetShown(not not checked)
    end
end

function UI:StyleInput(input)
    if input.SetBackdropColor then input:SetBackdropColor(1, 1, 1, 0.035) end
    if input.SetBackdropBorderColor then color(input, "SetBackdropBorderColor", self.colors.border) end
end

function UI:SetInputFocused(input, focused)
    if input and input.SetBackdropBorderColor then color(input, "SetBackdropBorderColor", focused and self.colors.accent or self.colors.border) end
end

function UI:StyleOptionsButton(button)
    if not button.icon then
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(14, 14); button.icon:SetPoint("CENTER")
        button.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    end
    button.icon:SetDesaturated(true); button.icon:SetVertexColor(0.68, 0.68, 0.72)
end

function UI:StyleCloseButton(button)
    if button.text then color(button.text, "SetTextColor", self.colors.muted) end
end
