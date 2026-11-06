-- HoA Alerts options window and slash commands.
local A = HoAAlerts

local panel = CreateFrame("Frame", "HoAAlertsOptions", UIParent)
panel:SetWidth(340)
panel:SetHeight(466)
panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
panel:SetFrameStrata("DIALOG")
panel:SetMovable(true)
panel:EnableMouse(true)
panel:SetClampedToScreen(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", function() this:StartMoving() end)
panel:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
panel:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
panel:Hide()
table.insert(UISpecialFrames, "HoAAlertsOptions")   -- Escape closes it

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", panel, "TOP", 0, -18)
title:SetText("HoA Alerts")

local close = CreateFrame("Button", "HoAAlertsOptionsClose", panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)

local function Header(text, y)
    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, y)
    header:SetText(text)
end

local checks = {}
local function Check(name, label, x, y, get, set, icon)
    local check = CreateFrame("CheckButton", "HoAAlertsOptions" .. name, panel, "UICheckButtonTemplate")
    check:SetWidth(24)
    check:SetHeight(24)
    check:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    local text = getglobal(check:GetName() .. "Text")
    text:SetText(label)
    if icon then
        local tex = check:CreateTexture(nil, "ARTWORK")
        tex:SetWidth(18)
        tex:SetHeight(18)
        tex:SetPoint("LEFT", check, "RIGHT", 2, 1)
        tex:SetTexture("Interface\\Icons\\" .. icon)
        tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        text:ClearAllPoints()
        text:SetPoint("LEFT", tex, "RIGHT", 4, 0)
    end
    check:SetScript("OnClick", function()
        set(this:GetChecked() and true or false)
        PlaySound(this:GetChecked() and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
    end)
    check.get = get
    table.insert(checks, check)
    return check
end

local function SmallButton(name, label, width, point, x, y, onClick)
    local button = CreateFrame("Button", "HoAAlertsOptions" .. name, panel, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(22)
    button:SetPoint(point, panel, point, x, y)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    return button
end

-- Spawn types, each with a little "test" button
Header("Warn me about", -48)
local y = -68
for _, t in ipairs(A.TYPES) do
    local key = t.key
    Check("Type" .. key, t.name, 24, y,
        function() return HoAAlertsDB.types[key] end,
        function(on) HoAAlertsDB.types[key] = on; A.RefreshTracker() end,
        t.icon)
    SmallButton("Test" .. key, "Test", 50, "TOPRIGHT", -24, y - 1, function() A.Test(key) end)
    y = y - 26
end

-- How to warn
y = y - 8
Header("How", y)
y = y - 20
local hows = {   -- key, label, column, row
    { "warning", "Big warning text", 0, 0 },
    { "sound",   "Sound",            1, 0 },
    { "flash",   "Screen edge flash", 0, 1 },
    { "chat",    "Chat message",     1, 1 },
    { "tracker", "Tracker list (distance + direction)", 0, 2 },
    { "groundFlash", "Red flash when a ground effect hits me", 0, 3 },
}
for _, how in ipairs(hows) do
    local key = how[1]
    Check("How" .. key, how[2], 24 + how[3] * 150, y - how[4] * 26,
        function() return HoAAlertsDB[key] end,
        function(on) HoAAlertsDB[key] = on; A.RefreshTracker() end)
end
SmallButton("Testground", "Test", 50, "TOPRIGHT", -24, y - 3 * 26 - 1, function() A.Test("ground") end)
y = y - 4 * 26

-- Range slider
y = y - 28
local slider = CreateFrame("Slider", "HoAAlertsOptionsRange", panel, "OptionsSliderTemplate")
slider:SetWidth(280)
slider:SetHeight(16)
slider:SetPoint("TOPLEFT", panel, "TOPLEFT", 30, y)
slider:SetMinMaxValues(0, 600)
slider:SetValueStep(25)
getglobal("HoAAlertsOptionsRangeLow"):SetText("any")
getglobal("HoAAlertsOptionsRangeHigh"):SetText("600 yd")
local function RangeLabel(value)
    getglobal("HoAAlertsOptionsRangeText"):SetText(value > 0 and ("Only warn within " .. value .. " yards") or "Warn at any distance")
end
slider:SetScript("OnValueChanged", function()
    local value = math.floor(this:GetValue() / 25 + 0.5) * 25
    if HoAAlertsDB then
        HoAAlertsDB.range = value
    end
    RangeLabel(value)
end)

-- Bottom buttons
local lockButton
lockButton = SmallButton("Lock", "Unlock frames", 120, "BOTTOMLEFT", 22, 18, function()
    A.SetUnlocked(not A.IsUnlocked())
    lockButton:SetText(A.IsUnlocked() and "Lock frames" or "Unlock frames")
end)
SmallButton("TestAll", "Test all", 90, "BOTTOM", 34, 18, function() A.Test() end)
SmallButton("Reset", "Reset", 70, "BOTTOMRIGHT", -22, 18, function()
    A.ResetPositions()
    A.Print("Frame positions reset.")
end)

panel:SetScript("OnShow", function()
    for _, check in ipairs(checks) do
        check:SetChecked(check.get() and 1 or nil)
    end
    slider:SetValue(HoAAlertsDB.range or 0)
    RangeLabel(HoAAlertsDB.range or 0)
    lockButton:SetText(A.IsUnlocked() and "Lock frames" or "Unlock frames")
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function OnOff(value)
    return value and "|cff00ff00on|r" or "|cffff4040off|r"
end

local function Help()
    A.Print("v" .. A.VERSION .. " commands:")
    local lines = {
        "/hoaa - open the options window",
        "/hoaa test [type] - show test warnings (type 'ground' for the hit flash)",
        "/hoaa unlock | lock - move the warning text and tracker",
        "/hoaa range <yards> - only warn within that distance (0 = any)",
        "/hoaa <type> - toggle a spawn type: leyline, greed, altar, elite, moonwell, valor",
        "/hoaa warning | sound | flash | chat | tracker - toggle an output",
        "/hoaa ground - toggle the red flash when a ground effect hits you",
        "/hoaa reset - reset frame positions",
    }
    for _, line in ipairs(lines) do
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00" .. line .. "|r")
    end
end

local OUTPUTS = { warning = true, sound = true, flash = true, chat = true, tracker = true }

SLASH_HOAALERTS1 = "/hoaa"
SLASH_HOAALERTS2 = "/hoaalerts"
SlashCmdList["HOAALERTS"] = function(msg)
    msg = string.lower(msg or "")
    local _, _, command, rest = string.find(msg, "^%s*(%S*)%s*(.-)%s*$")
    command = command or ""
    if command == "" or command == "config" or command == "options" then
        if panel:IsShown() then
            panel:Hide()
        else
            panel:Show()
        end
    elseif command == "help" then
        Help()
    elseif command == "test" then
        if rest ~= "" and rest ~= "ground" and not A.TYPE_BY_KEY[rest] then
            A.Print("Unknown type '" .. rest .. "'.")
            return
        end
        A.Test(rest ~= "" and rest or nil)
    elseif command == "unlock" then
        A.SetUnlocked(true)
    elseif command == "lock" then
        A.SetUnlocked(false)
    elseif command == "reset" then
        A.ResetPositions()
        A.Print("Frame positions reset.")
    elseif command == "range" then
        local yards = tonumber(rest)
        if not yards or yards < 0 then
            A.Print("Usage: /hoaa range <yards>  (0 = any distance)")
            return
        end
        HoAAlertsDB.range = math.floor(yards)
        A.Print(yards > 0 and ("Only warning within " .. HoAAlertsDB.range .. " yards.") or "Warning at any distance.")
    elseif A.TYPE_BY_KEY[command] then
        local t = A.TYPE_BY_KEY[command]
        HoAAlertsDB.types[command] = not HoAAlertsDB.types[command]
        A.Print(t.name .. " alerts " .. OnOff(HoAAlertsDB.types[command]))
        A.RefreshTracker()
    elseif command == "ground" then
        HoAAlertsDB.groundFlash = not HoAAlertsDB.groundFlash
        A.Print("Ground-effect hit flash " .. OnOff(HoAAlertsDB.groundFlash))
    elseif OUTPUTS[command] then
        HoAAlertsDB[command] = not HoAAlertsDB[command]
        A.Print(command .. " " .. OnOff(HoAAlertsDB[command]))
        A.RefreshTracker()
    else
        Help()
    end
end
