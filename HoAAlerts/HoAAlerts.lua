-- HoA Alerts: boss-mod style spawn warnings for Hordes of Azeroth.
--
-- The Hordes of Azeroth server talks to its client addon through system chat
-- lines that start with "BONK~". Every map pin is sent as
--   BONK~objective~<id>~<kind>~<x>~<y>~<mapId>~<label>~<seconds>~<icon>~<description>
-- and removed again with BONK~objectiveclear[~<id>]. Labels are localized, but
-- the kind and icon are fixed per spawn type, so those are what we match on.
--
-- Written for the 1.12 client (Lua 5.0): event handlers use the globals
-- this/event/arg1, and there is no # operator or string.gmatch.

HoAAlerts = {}
local A = HoAAlerts

A.VERSION = "1.0.0"

local PREFIX = "BONK~"
local ICON_PATH = "Interface\\Icons\\"
local QUIET_AFTER_START = 2      -- seconds: the server resends every pin after a reload
local WARNING_LINES = 3
local TRACKER_ROWS = 8
local TRACKER_INTERVAL = 0.2

-- Spawn types, in display order. "kind" and "icon" come from the server
-- (BonkRunShrines.cpp SHRINE_ICONS, BonkRun.cpp *_PIN_ICON).
A.TYPES = {
    { key = "leyline", kind = "shrine", icon = "Spell_Arcane_StarFire", name = "Ley Line",
      verb = "spawned", color = { 0.40, 0.65, 1.00 }, sound = "RaidWarning", default = true },
    { key = "greed", kind = "shrine", icon = "INV_Misc_Coin_02", name = "Greed Totem",
      verb = "spawned", color = { 1.00, 0.82, 0.00 }, sound = "LOOTWINDOWCOINSOUND", default = true },
    { key = "altar", kind = "shrine", icon = "Ability_Warrior_Challange", name = "Challenge Altar",
      verb = "spawned", color = { 1.00, 0.35, 0.25 }, sound = "ReadyCheck", default = true },
    { key = "elite", kind = "chest", icon = "INV_Box_04", name = "Elite Chest",
      verb = "dropped", color = { 0.25, 1.00, 0.35 }, sound = "QUESTCOMPLETED", default = true },
    { key = "moonwell", kind = "shrine", icon = "Spell_Arcane_TeleportMoonglade", name = "Moonwell",
      verb = "spawned", color = { 0.75, 0.55, 1.00 }, sound = "igQuestListComplete", default = false },
    { key = "valor", kind = "chest", icon = "INV_Box_02", name = "Valor Chest",
      verb = "spawned", color = { 0.85, 0.85, 0.85 }, sound = "MapPing", default = false },
}

local TYPE_BY_KEY, TYPE_BY_SIGNATURE = {}, {}
for _, t in ipairs(A.TYPES) do
    TYPE_BY_KEY[t.key] = t
    TYPE_BY_SIGNATURE[t.kind .. "|" .. t.icon] = t
end
A.TYPE_BY_KEY = TYPE_BY_KEY

local DEFAULTS = {
    warning = true,     -- big text in the middle of the screen
    sound = true,
    flash = true,       -- colored glow around the screen edges
    chat = true,
    tracker = true,     -- small list of active spawns with distance and direction
    groundFlash = true, -- red flash when a ground effect hits you
    range = 0,          -- only warn for spawns within this many yards (0 = any distance)
    holdTime = 4,       -- seconds a warning stays fully visible
    types = {},
}
for _, t in ipairs(A.TYPES) do
    DEFAULTS.types[t.key] = t.default
end

local function CopyDefaults(source, target)
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            CopyDefaults(v, target[k])
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

local function Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99HoA Alerts|r: " .. text)
end
A.Print = Print

local function Split(text, sep)
    local out, start = {}, 1
    while true do
        local i = string.find(text, sep, start, true)
        if not i then
            table.insert(out, string.sub(text, start))
            return out
        end
        table.insert(out, string.sub(text, start, i - 1))
        start = i + 1
    end
end

local function Hex(color)
    return string.format("|cff%02x%02x%02x", math.floor(color[1] * 255), math.floor(color[2] * 255), math.floor(color[3] * 255))
end

---------------------------------------------------------------------------
-- Geometry: distance and direction from the hero to a spawn.
-- Mirrors the base addon: UnitPosition returns (west, north, z, mapId) and a
-- pin's x/y are the server's north/west coordinates.
---------------------------------------------------------------------------

-- Some clients expose degree-based trig in the math table; detect and adapt.
local RADIANS = math.abs(math.sin(math.pi / 2) - 1) < 0.001
local function Sin(a)
    return RADIANS and math.sin(a) or math.sin(a * 180 / math.pi)
end

local function HeroPosition()
    if not UnitPosition then
        return nil
    end
    local west, north, _, mapId = UnitPosition("player")
    if not west then
        return nil
    end
    return north, west, mapId
end

local TAN_22_5 = 0.41421356
local function Compass(north, east)
    local an, ae = math.abs(north), math.abs(east)
    local ns = north >= 0 and "N" or "S"
    local ew = east >= 0 and "E" or "W"
    if ae <= an * TAN_22_5 then
        return ns
    elseif an <= ae * TAN_22_5 then
        return ew
    end
    return ns .. ew
end

-- Returns yards and a compass direction ("N", "NE", ...), or nil when unknown.
local function Where(spawn)
    local north, west, mapId = HeroPosition()
    if not north or (mapId and spawn.mapId and mapId ~= spawn.mapId) then
        return nil
    end
    local dn, dw = spawn.x - north, spawn.y - west
    local yards = math.sqrt(dn * dn + dw * dw)
    if yards < 3 then
        return yards, "here"
    end
    return yards, Compass(dn, -dw)
end
A.Where = Where

local function WhereText(spawn)
    local yards, direction = Where(spawn)
    if not yards then
        return nil
    end
    if direction == "here" then
        return "right here"
    end
    return math.floor(yards + 0.5) .. " yd, " .. direction
end

---------------------------------------------------------------------------
-- Big warning text (the "raid warning" part)
---------------------------------------------------------------------------

local warning = CreateFrame("Frame", "HoAAlertsWarningFrame", UIParent)
warning:SetWidth(640)
warning:SetHeight(WARNING_LINES * 40)
warning:SetPoint("TOP", UIParent, "TOP", 0, -160)
warning:SetFrameStrata("HIGH")
warning:SetMovable(true)
warning:SetClampedToScreen(true)
warning:RegisterForDrag("LeftButton")

warning.bg = warning:CreateTexture(nil, "BACKGROUND")
warning.bg:SetAllPoints(warning)
warning.bg:SetTexture(0, 0, 0, 0.4)
warning.bg:Hide()

warning.lines = {}
for i = 1, WARNING_LINES do
    local line = CreateFrame("Frame", nil, warning)
    line:SetWidth(640)
    line:SetHeight(38)
    line:SetPoint("TOP", warning, "TOP", 0, -(i - 1) * 40)
    line.text = line:CreateFontString(nil, "OVERLAY")
    line.text:SetFont("Fonts\\FRIZQT__.TTF", 24, "THICKOUTLINE")
    line.text:SetPoint("CENTER", line, "CENTER", 18, 0)
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetWidth(34)
    line.icon:SetHeight(34)
    line.icon:SetPoint("RIGHT", line.text, "LEFT", -8, 0)
    line.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    line:Hide()
    warning.lines[i] = line
end

local messages = {}   -- newest first: { text, icon, color, at }

local function RenderWarnings()
    for i = 1, WARNING_LINES do
        local line, message = warning.lines[i], messages[i]
        if message then
            line.text:SetText(message.text)
            line.text:SetTextColor(message.color[1], message.color[2], message.color[3])
            line.icon:SetTexture(message.icon)
            line:Show()
        else
            line:Hide()
        end
    end
end

warning:SetScript("OnUpdate", function()
    local now = GetTime()
    local hold = HoAAlertsDB and HoAAlertsDB.holdTime or DEFAULTS.holdTime
    local changed = false
    for i = table.getn(messages), 1, -1 do
        local age = now - messages[i].at
        if age > hold + 1 then
            table.remove(messages, i)
            changed = true
        end
    end
    if changed then
        RenderWarnings()
    end
    for i = 1, WARNING_LINES do
        local message = messages[i]
        if message then
            local age = now - message.at
            local line = warning.lines[i]
            line:SetAlpha(age > hold and math.max(0, 1 - (age - hold)) or 1)
            -- brief "pop" when a warning appears
            local pop = age < 0.25 and (1 + (0.25 - age) * 1.6) or 1
            line:SetScale(pop)
        end
    end
end)

local function ShowWarning(text, icon, color)
    table.insert(messages, 1, { text = text, icon = icon, color = color, at = GetTime() })
    while table.getn(messages) > WARNING_LINES do
        table.remove(messages)
    end
    RenderWarnings()
end

---------------------------------------------------------------------------
-- Screen-edge flash
---------------------------------------------------------------------------

local flash = CreateFrame("Frame", "HoAAlertsFlashFrame", UIParent)
flash:SetAllPoints(UIParent)
flash:SetFrameStrata("BACKGROUND")
flash:Hide()
flash.edges = {}
local EDGE = 140
local function Edge(p1, p2, horizontal)
    local tex = flash:CreateTexture(nil, "BACKGROUND")
    tex:SetTexture(1, 1, 1)
    tex:SetBlendMode("ADD")
    tex:SetPoint(p1, flash, p1)
    tex:SetPoint(p2, flash, p2)
    if horizontal then
        tex:SetHeight(EDGE)
    else
        tex:SetWidth(EDGE)
    end
    table.insert(flash.edges, tex)
    return tex
end
flash.top = Edge("TOPLEFT", "TOPRIGHT", true)
flash.bottom = Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
flash.left = Edge("TOPLEFT", "BOTTOMLEFT", false)
flash.right = Edge("TOPRIGHT", "BOTTOMRIGHT", false)

flash:SetScript("OnUpdate", function()
    local t = GetTime() - this.at
    if t >= this.duration then
        this:Hide()
        return
    end
    local pulse = this.duration / this.pulses
    local phase = math.mod(t, pulse) / pulse
    this:SetAlpha(Sin(phase * math.pi))
end)

-- color = {r, g, b}; spawn warnings pulse twice over 1.2 s, ground hits once.
local function Flash(color, duration, pulses, strength)
    local r, g, b, a = color[1], color[2], color[3], strength or 0.7
    flash.top:SetGradientAlpha("VERTICAL", r, g, b, 0, r, g, b, a)
    flash.bottom:SetGradientAlpha("VERTICAL", r, g, b, a, r, g, b, 0)
    flash.left:SetGradientAlpha("HORIZONTAL", r, g, b, a, r, g, b, 0)
    flash.right:SetGradientAlpha("HORIZONTAL", r, g, b, 0, r, g, b, a)
    flash.color = color
    flash.duration = duration or 1.2
    flash.pulses = pulses or 2
    flash.at = GetTime()
    flash:SetAlpha(0)
    flash:Show()
end
A.Flash = Flash

---------------------------------------------------------------------------
-- Ground-effect hits
--
-- In Hordes of Azeroth every telegraphed ground effect (circles, cones,
-- lines, rings, eruptions, bolt landing zones) hits you as a direct enemy
-- spell hit, which the 1.12 combat log reports as "X's Y hits you for N."
-- Enemy melee and damage-over-time use other messages, so a direct enemy
-- spell hit means you were standing in something.
---------------------------------------------------------------------------

local GROUND_RED = { 1, 0.08, 0.05 }
local GROUND_FLASH_TIME = 0.5
local GROUND_COOLDOWN = 0.35     -- don't strobe when several effects land at once
local lastGroundFlash = 0

local function LinePattern(text)
    if not text then
        return nil
    end
    text = string.gsub(text, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    text = string.gsub(text, "%%%%s", ".+")
    text = string.gsub(text, "%%%%d", "%%d+")
    return "^" .. text     -- no end anchor: absorbed/resisted notes may follow
end

local GROUND_PATTERNS = {}
for _, format in ipairs({ SPELLLOGOTHERSELF, SPELLLOGSCHOOLOTHERSELF, SPELLLOGCRITOTHERSELF, SPELLLOGCRITSCHOOLOTHERSELF }) do
    local pattern = LinePattern(format)
    if pattern then
        table.insert(GROUND_PATTERNS, pattern)
    end
end
if table.getn(GROUND_PATTERNS) == 0 then
    -- English fallback if the client lacks the global format strings
    GROUND_PATTERNS = { "^.+'s .+ hits you for %d+", "^.+'s .+ crits you for %d+" }
end

local function IsGroundHit(text)
    if not text then
        return false
    end
    for _, pattern in ipairs(GROUND_PATTERNS) do
        if string.find(text, pattern) then
            return true
        end
    end
    return false
end
A.IsGroundHit = IsGroundHit

local function GroundHit()
    local now = GetTime()
    if now - lastGroundFlash < GROUND_COOLDOWN then
        return
    end
    lastGroundFlash = now
    Flash(GROUND_RED, GROUND_FLASH_TIME, 1, 0.85)
end
A.GroundHit = GroundHit

-- The client files a hit under different events depending on who the source
-- is (a living enemy, or an invisible hazard left behind by a dead one).
local GROUND_EVENTS = {
    "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
    "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
    "CHAT_MSG_SPELL_PET_DAMAGE",
    "CHAT_MSG_SPELL_PARTY_DAMAGE",
    "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
}

---------------------------------------------------------------------------
-- Tracker: active spawns with live distance and direction.
-- Styled like the Hordes of Azeroth damage meter: flat dark panel with a
-- gold-brown border, gradient header, and 20 px rows with a framed icon and
-- a shaded bar. Here the bar shows closeness: full when you are on top of a
-- spawn, empty at TRACKER_BAR_RANGE yards or more.
---------------------------------------------------------------------------

local FLAT = "Interface\\Buttons\\WHITE8X8"
local TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local NUMBER_FONT = "Fonts\\ARIALN.TTF"
local TRACKER_WIDTH = 220
local HEADER = 24
local ROW = 20
local ROW_GAP = 2
local PAD = 5
local BAR_BRIGHTNESS = 0.8
local BAR_FADE = { 0.87, 0.72, 0.88 }   -- the meter's left-to-right bar shading
local BAR_SPEED = 8
local TRACKER_BAR_RANGE = 400

local function Text(parent, size, font)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(font or TEXT_FONT, size)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    return text
end

local function ShadeBar(fill, color, from, to)
    local function Channel(value, fade, position)
        return value * BAR_BRIGHTNESS * (fade + (1 - fade) * position)
    end
    fill:SetGradient("HORIZONTAL",
        Channel(color[1], BAR_FADE[1], from), Channel(color[2], BAR_FADE[2], from), Channel(color[3], BAR_FADE[3], from),
        Channel(color[1], BAR_FADE[1], to), Channel(color[2], BAR_FADE[2], to), Channel(color[3], BAR_FADE[3], to))
end

local tracker = CreateFrame("Frame", "HoAAlertsTracker", UIParent)
tracker:SetWidth(TRACKER_WIDTH)
tracker:SetHeight(HEADER + PAD * 2 + ROW)
tracker:SetPoint("RIGHT", UIParent, "RIGHT", -230, 120)
tracker:SetFrameStrata("LOW")
tracker:SetMovable(true)
tracker:SetClampedToScreen(true)
tracker:RegisterForDrag("LeftButton")
tracker:SetBackdrop({
    bgFile = FLAT, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = false, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
tracker:SetBackdropColor(0.04, 0.04, 0.05, 0.62)
tracker:SetBackdropBorderColor(0.55, 0.5, 0.42)
tracker:Hide()

tracker.header = tracker:CreateTexture(nil, "BORDER")
tracker.header:SetTexture(FLAT)
tracker.header:SetGradientAlpha("VERTICAL", 0.1, 0.08, 0.05, 0.9, 0.24, 0.19, 0.12, 0.9)
tracker.header:SetPoint("TOPLEFT", tracker, "TOPLEFT", 3, -3)
tracker.header:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -3, -3)
tracker.header:SetHeight(HEADER - 4)

tracker.rule = tracker:CreateTexture(nil, "ARTWORK")
tracker.rule:SetTexture(FLAT)
tracker.rule:SetVertexColor(0.55, 0.45, 0.25, 0.8)
tracker.rule:SetHeight(1)
tracker.rule:SetPoint("TOPLEFT", tracker.header, "BOTTOMLEFT", 0, 0)
tracker.rule:SetPoint("TOPRIGHT", tracker.header, "BOTTOMRIGHT", 0, 0)

tracker.title = Text(tracker, 13)
tracker.title:SetPoint("LEFT", tracker.header, "LEFT", 6, 0)
tracker.title:SetTextColor(1, 0.82, 0)
tracker.title:SetText("HoA Alerts")

tracker.count = Text(tracker, 12, NUMBER_FONT)
tracker.count:SetPoint("RIGHT", tracker.header, "RIGHT", -6, 0)
tracker.count:SetJustifyH("RIGHT")

tracker.empty = Text(tracker, 11)
tracker.empty:SetPoint("TOPLEFT", tracker, "TOPLEFT", PAD + 4, -(HEADER + PAD + 4))
tracker.empty:SetTextColor(0.63, 0.63, 0.63)
tracker.empty:SetText("Nothing up yet. Drag to move.")
tracker.empty:Hide()

tracker.rows = {}
for i = 1, TRACKER_ROWS do
    local row = CreateFrame("Frame", nil, tracker)
    local top = -(HEADER + PAD + (i - 1) * (ROW + ROW_GAP))
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", tracker, "TOPLEFT", PAD, top)
    row:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -PAD, top)

    row.frame = row:CreateTexture(nil, "BACKGROUND")
    row.frame:SetTexture(FLAT)
    row.frame:SetVertexColor(0, 0, 0, 0.9)
    row.frame:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.frame:SetWidth(ROW)
    row.frame:SetHeight(ROW)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", row.frame, "BOTTOMRIGHT", -1, 1)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.track = row:CreateTexture(nil, "BACKGROUND")
    row.track:SetTexture(FLAT)
    row.track:SetVertexColor(0, 0, 0, 0.55)
    row.track:SetPoint("TOPLEFT", row.frame, "TOPRIGHT", 2, 0)
    row.track:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

    row.fill = row:CreateTexture(nil, "BORDER")
    row.fill:SetTexture(FLAT)
    row.fill:SetHeight(ROW)
    row.fill:SetPoint("TOPLEFT", row.track, "TOPLEFT", 0, 0)
    row.fill:Hide()

    row.value = Text(row, 13, NUMBER_FONT)
    row.value:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    row.value:SetJustifyH("RIGHT")
    row.name = Text(row, 11)
    row.name:SetPoint("LEFT", row.track, "LEFT", 5, 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")

    row.barWidth = TRACKER_WIDTH - PAD * 2 - ROW - 2
    row.level, row.goal = 0, 0
    row:Hide()
    tracker.rows[i] = row
end

local function DrawBar(row)
    local width = row.barWidth * row.level
    if width < 0.5 then
        row.fill:Hide()
        return
    end
    ShadeBar(row.fill, row.color, 0, row.level)
    row.fill:SetWidth(width)
    row.fill:Show()
end

---------------------------------------------------------------------------
-- Spawn bookkeeping
---------------------------------------------------------------------------

local active = {}      -- objective id -> spawn
local seen = {}        -- spawn signature -> true, so resends never re-alert
local quietUntil = 0
local unlocked = false
A.active = active

local function SortedSpawns()
    local list = {}
    for _, spawn in pairs(active) do
        spawn.yards, spawn.direction = Where(spawn)
        table.insert(list, spawn)
    end
    table.sort(list, function(a, b)
        return (a.yards or 99999) < (b.yards or 99999)
    end)
    return list
end

local function Closeness(yards)
    if not yards then
        return 0
    end
    return math.max(0.03, math.min(1, 1 - yards / TRACKER_BAR_RANGE))
end

local function RefreshTracker()
    local db = HoAAlertsDB
    local list = (db and db.tracker) and SortedSpawns() or {}
    local shown = 0
    for _, spawn in ipairs(list) do
        if shown >= TRACKER_ROWS then
            break
        end
        if db.types[spawn.type.key] then
            shown = shown + 1
            local row = tracker.rows[shown]
            row.color = spawn.type.color
            row.goal = Closeness(spawn.yards)
            if row.key ~= spawn.id then
                row.key = spawn.id       -- a different spawn moved into this row: no slide
                row.level = row.goal
            end
            row.icon:SetTexture(ICON_PATH .. spawn.type.icon)
            row.name:SetText(spawn.type.name)
            if spawn.yards then
                local dir = spawn.direction == "here" and "here" or spawn.direction
                row.value:SetText(math.floor(spawn.yards + 0.5) .. "y |cffa0a0a0" .. dir .. "|r")
            else
                row.value:SetText("")
            end
            DrawBar(row)
            row:Show()
        end
    end
    for i = shown + 1, TRACKER_ROWS do
        tracker.rows[i].key = nil
        tracker.rows[i]:Hide()
    end
    tracker.count:SetText(shown > 0 and (shown .. " up") or "")
    if shown > 0 or unlocked then
        if shown == 0 then
            tracker.empty:Show()
        else
            tracker.empty:Hide()
        end
        tracker:SetHeight(HEADER + PAD * 2 + math.max(shown, 1) * (ROW + ROW_GAP) - ROW_GAP)
        tracker:Show()
    else
        tracker:Hide()
    end
end
A.RefreshTracker = RefreshTracker

local trackerElapsed = 0
tracker:SetScript("OnUpdate", function()
    -- bars glide toward their target like the meter's
    local step = math.min(1, arg1 * BAR_SPEED)
    for _, row in ipairs(this.rows) do
        if row:IsShown() and row.level ~= row.goal then
            local level = row.level + (row.goal - row.level) * step
            if math.abs(level - row.goal) < 0.002 then
                level = row.goal
            end
            row.level = level
            DrawBar(row)
        end
    end
    trackerElapsed = trackerElapsed + arg1
    if trackerElapsed >= TRACKER_INTERVAL then
        trackerElapsed = 0
        RefreshTracker()
    end
end)

local function Alert(spawn, test)
    local db = HoAAlertsDB
    local t = spawn.type
    if not test then
        if not db.types[t.key] then
            return
        end
        if db.range and db.range > 0 then
            local yards = Where(spawn)
            if yards and yards > db.range then
                return
            end
        end
    end
    local where = WhereText(spawn)
    local text = t.name .. " " .. t.verb .. "!"
    if db.warning then
        ShowWarning(text .. (where and ("  |cffffffff(" .. where .. ")|r") or ""), ICON_PATH .. t.icon, t.color)
    end
    if db.chat then
        Print(Hex(t.color) .. text .. "|r" .. (where and (" " .. where) or ""))
    end
    if db.sound then
        PlaySound(t.sound)
    end
    if db.flash then
        Flash(t.color)
    end
end
A.Alert = Alert

local function OnObjective(f)
    local id, kind, icon = f[2], f[3] or "", f[9] or ""
    local x, y, mapId = tonumber(f[4] or ""), tonumber(f[5] or ""), tonumber(f[6] or "")
    if not id or not x or not y then
        return
    end
    local t = TYPE_BY_SIGNATURE[kind .. "|" .. icon]
    if not t then
        return
    end
    -- Ids restart with every run, so include the type and exact spot.
    local signature = id .. "|" .. icon .. "|" .. f[4] .. "|" .. f[5]
    local spawn = active[id]
    if spawn and spawn.signature == signature then
        return
    end
    spawn = { id = id, type = t, x = x, y = y, mapId = mapId, label = f[7], signature = signature }
    active[id] = spawn
    if seen[signature] then
        return
    end
    seen[signature] = true
    if GetTime() >= quietUntil then
        Alert(spawn)
    end
    RefreshTracker()
end

local handlers = {}

-- BONK~objective~id~kind~x~y~mapId~label~seconds~icon~description
-- (fields are numbered from the word after "BONK~", so the icon is f[9])
handlers["objective"] = OnObjective

handlers["objectiveclear"] = function(f)
    if f[2] and f[2] ~= "" then
        active[f[2]] = nil
    else
        -- a full clear: run ended, stage changed, or a resend is coming
        for k in pairs(active) do
            active[k] = nil
        end
        for k in pairs(seen) do
            seen[k] = nil
        end
    end
    RefreshTracker()
end

-- "start" arrives at the beginning of a run and also before the server
-- replays the whole run state (e.g. after /reload). Pins replayed right
-- after it are already known, so record them without warning.
handlers["start"] = function()
    quietUntil = GetTime() + QUIET_AFTER_START
end

handlers["end"] = function()
    for k in pairs(active) do
        active[k] = nil
    end
    for k in pairs(seen) do
        seen[k] = nil
    end
    RefreshTracker()
end

A.handlers = handlers

local function HandleLine(text)
    if not text or string.sub(text, 1, 5) ~= PREFIX then
        return
    end
    local fields = Split(string.sub(text, 6), "~")
    local handler = handlers[fields[1]]
    if handler then
        handler(fields)
    end
end
A.HandleLine = HandleLine

---------------------------------------------------------------------------
-- Moving the frames
---------------------------------------------------------------------------

local function SavePosition(frame, key)
    local point, _, relativePoint, x, y = frame:GetPoint()
    HoAAlertsDB[key] = { point, relativePoint, x, y }
end

local function RestorePosition(frame, key)
    local p = HoAAlertsDB[key]
    if p then
        frame:ClearAllPoints()
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
end

for _, entry in ipairs({ { warning, "warningPos" }, { tracker, "trackerPos" } }) do
    local frame, key = entry[1], entry[2]
    frame:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        SavePosition(this, key)
    end)
end

function A.SetUnlocked(on)
    unlocked = on and true or false
    warning:EnableMouse(unlocked)
    tracker:EnableMouse(unlocked)
    if unlocked then
        warning.bg:Show()
        ShowWarning("HoA Alerts warnings appear here - drag to move", ICON_PATH .. "Spell_Arcane_StarFire", { 1, 1, 1 })
        Print("Frames unlocked. Drag the warning area and the tracker, then type |cffffff00/hoaa lock|r.")
    else
        warning.bg:Hide()
        Print("Frames locked.")
    end
    RefreshTracker()
end

function A.IsUnlocked()
    return unlocked
end

function A.ResetPositions()
    HoAAlertsDB.warningPos, HoAAlertsDB.trackerPos = nil, nil
    warning:ClearAllPoints()
    warning:SetPoint("TOP", UIParent, "TOP", 0, -160)
    tracker:ClearAllPoints()
    tracker:SetPoint("RIGHT", UIParent, "RIGHT", -230, 120)
end

-- Fire one warning of each enabled type (or the given type) a short way off.
function A.Test(key)
    if key == "ground" then
        lastGroundFlash = 0
        GroundHit()
        return
    end
    local north, west, mapId = HeroPosition()
    north, west = north or 0, west or 0
    local i = 0
    for _, t in ipairs(A.TYPES) do
        if (key and t.key == key) or (not key and HoAAlertsDB.types[t.key]) then
            i = i + 1
            local spawn = { id = "test" .. t.key, type = t, x = north + 40 + i * 25, y = west + (i - 2) * 60,
                mapId = mapId, test = true }
            Alert(spawn, true)
        end
    end
    if i == 0 then
        Print("All alert types are disabled.")
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("VARIABLES_LOADED")
events:RegisterEvent("CHAT_MSG_SYSTEM")
local IS_GROUND_EVENT = {}
for _, name in ipairs(GROUND_EVENTS) do
    events:RegisterEvent(name)
    IS_GROUND_EVENT[name] = true
end
events:SetScript("OnEvent", function()
    if event == "CHAT_MSG_SYSTEM" then
        if HoAAlertsDB then
            HandleLine(arg1)
        end
    elseif IS_GROUND_EVENT[event] then
        if HoAAlertsDB and HoAAlertsDB.groundFlash and IsGroundHit(arg1) then
            GroundHit()
        end
    elseif event == "VARIABLES_LOADED" then
        if type(HoAAlertsDB) ~= "table" then
            HoAAlertsDB = {}
        end
        CopyDefaults(DEFAULTS, HoAAlertsDB)
        RestorePosition(warning, "warningPos")
        RestorePosition(tracker, "trackerPos")
        -- whatever is already on the map when we load is not news
        quietUntil = GetTime() + QUIET_AFTER_START
    end
end)
