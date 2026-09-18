--[[ Rollcall UI ---------------------------------------------------------

Built from primitives on purpose. Forever removed WhoFrame, so there is no
Blizzard who-window to reskin, and rather than bet on which other UI templates
survived the port this file uses only CreateFrame, textures, fontstrings and a
slider. Nothing here can break because a template was renamed.
--]]

local ADDON, ns = ...

local ROW_H, VISIBLE = 18, 16
local COLUMNS = {
    { key = "name",  title = "Name",  width = 130 },
    { key = "level", title = "Lvl",   width = 34  },
    { key = "class", title = "Class", width = 74  },
    { key = "race",  title = "Race",  width = 74  },
    { key = "zone",  title = "Zone",  width = 120 },
    { key = "guild", title = "Guild", width = 130 },
}
local CLASSES = { "", "Warrior", "Paladin", "Hunter", "Rogue", "Priest",
                  "Shaman", "Mage", "Warlock", "Druid" }
local RACES = { "", "Human", "Dwarf", "Night Elf", "Gnome",
                "Orc", "Undead", "Tauren", "Troll" }

local sortKey, sortDesc, offset = "level", false, 0
local view = {}

--==========================================================================
-- small widget helpers
--==========================================================================

local function panel(parent, r, g, b, a)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(parent)
    t:SetColorTexture(r, g, b, a)
    return t
end

local function label(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function editbox(parent, x, y, w)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetPoint("TOPLEFT", x, y)
    e:SetSize(w, 18)
    e:SetAutoFocus(false)
    e:SetFontObject("ChatFontNormal")
    e:SetTextInsets(4, 4, 0, 0)
    panel(e, 0, 0, 0, 0.5)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

-- A self-contained dropdown. UIDropDownMenu may or may not have survived the
-- port; this cannot care either way.
local function dropdown(parent, x, y, w, items, onPick)
    local b = CreateFrame("Button", nil, parent)
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(w, 18)
    panel(b, 0, 0, 0, 0.5)
    b.text = b:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetText("Any")
    b.value = ""

    local list = CreateFrame("Frame", nil, b)
    list:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    list:SetSize(w, #items * ROW_H + 4)
    panel(list, 0.05, 0.05, 0.05, 0.95)
    list:SetFrameStrata("DIALOG")
    list:Hide()

    for i, item in ipairs(items) do
        local row = CreateFrame("Button", nil, list)
        row:SetPoint("TOPLEFT", 2, -(i - 1) * ROW_H - 2)
        row:SetSize(w - 4, ROW_H)
        local fs = row:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
        fs:SetPoint("LEFT", 3, 0)
        fs:SetText(item == "" and "Any" or item)
        -- Create the highlight ONCE. Building it in OnEnter would allocate a
        -- fresh texture on every mouse-over and never release it.
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(row)
        hl:SetColorTexture(1, 1, 1, 0.15)
        row:SetScript("OnClick", function()
            b.value = item
            b.text:SetText(item == "" and "Any" or item)
            list:Hide()
            if onPick then onPick(item) end
        end)
    end

    b:SetScript("OnClick", function()
        if list:IsShown() then list:Hide() else list:Show() end
    end)
    return b
end

--==========================================================================
-- the window
--==========================================================================

local f = CreateFrame("Frame", "RollcallFrame", UIParent)
f:SetSize(600, 536)
f:SetPoint("CENTER")
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetFrameStrata("HIGH")
f:Hide()
panel(f, 0.06, 0.06, 0.07, 0.94)

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 12, -10)
title:SetText("Rollcall")

local close = CreateFrame("Button", nil, f)
close:SetSize(20, 20)
close:SetPoint("TOPRIGHT", -8, -8)
local ct = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
ct:SetAllPoints()
ct:SetText("x")
close:SetScript("OnClick", function() f:Hide() end)

-- ---- query builder -------------------------------------------------------
label(f, "Name",  14, -40);  local eName  = editbox(f, 14, -54, 120)
label(f, "Guild", 142, -40); local eGuild = editbox(f, 142, -54, 130)
label(f, "Zone",  280, -40); local eZone  = editbox(f, 280, -54, 130)
label(f, "Level", 418, -40)
local eMin = editbox(f, 418, -54, 34)
local eMax = editbox(f, 458, -54, 34)
eMin:SetNumeric(true); eMax:SetNumeric(true)

label(f, "Class", 14, -80)
label(f, "Race",  142, -80)
local dClass, dRace

local eRaw   -- forward declaration; the builder writes into it

local function spec()
    return {
        name = eName:GetText(), guild = eGuild:GetText(), zone = eZone:GetText(),
        class = dClass and dClass.value or "", race = dRace and dRace.value or "",
        minLevel = tonumber(eMin:GetText()), maxLevel = tonumber(eMax:GetText()),
    }
end

local function refreshRaw()
    if eRaw then eRaw:SetText(ns.BuildQuery(spec())) end
end

dClass = dropdown(f, 14, -94, 120, CLASSES, refreshRaw)
dRace  = dropdown(f, 142, -94, 130, RACES, refreshRaw)

for _, e in ipairs({ eName, eGuild, eZone, eMin, eMax }) do
    e:SetScript("OnTextChanged", refreshRaw)
end

label(f, "Query sent", 14, -120)
eRaw = editbox(f, 14, -134, 400)

local function doSearch()
    local q = strtrim(eRaw:GetText())
    ns.Send(q, function(batch) ns.Absorb(batch, false) end)
end

local function button(parent, text, x, y, w, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(w, 20)
    panel(b, 0.18, 0.30, 0.42, 1)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetAllPoints()
    fs:SetText(text)
    b.label = fs          -- so callers can relabel without guessing at regions
    b:SetScript("OnClick", onClick)
    return b
end

button(f, "Search", 420, -134, 74, doSearch)
button(f, "Deep scan", 500, -134, 84, function() ns.DeepScan(spec()) end)

-- ---- client-side filter --------------------------------------------------
label(f, "Filter results", 14, -160)
local eFilter = editbox(f, 96, -160, 200)
local status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
status:SetPoint("TOPLEFT", 310, -160)

-- ---- column headers ------------------------------------------------------
local headerY = -190
local x = 14
for _, col in ipairs(COLUMNS) do
    local b = CreateFrame("Button", nil, f)
    b:SetPoint("TOPLEFT", x, headerY)
    b:SetSize(col.width, ROW_H)
    panel(b, 0.14, 0.14, 0.16, 1)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", 3, 0)
    col.fs = fs
    b:SetScript("OnClick", function()
        if sortKey == col.key then sortDesc = not sortDesc
        else sortKey, sortDesc = col.key, false end
        offset = 0
        ns.OnResults()
    end)
    x = x + col.width
end

-- ---- rows ----------------------------------------------------------------
local rows = {}
for i = 1, VISIBLE do
    local r = CreateFrame("Button", nil, f)
    r:SetPoint("TOPLEFT", 14, headerY - i * ROW_H - 2)
    r:SetSize(562, ROW_H)
    r.cells = {}
    local cx = 0
    for ci, col in ipairs(COLUMNS) do
        local fs = r:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
        fs:SetPoint("LEFT", cx + 3, 0)
        fs:SetWidth(col.width - 6)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        r.cells[ci] = fs

        -- Invisible catcher per cell: FontStrings take no mouse input, so a
        -- truncated value has nothing to hover. Shows the full string only
        -- when it is genuinely cut off.
        local hit = CreateFrame("Frame", nil, r)
        hit:SetPoint("LEFT", cx, 0)
        hit:SetSize(col.width, ROW_H)
        hit:EnableMouse(true)
        if hit.SetPropagateMouseClicks then hit:SetPropagateMouseClicks(true) end
        if hit.SetPropagateMouseMotion then hit:SetPropagateMouseMotion(true) end
        hit:SetScript("OnEnter", function(self)
            local label = r.cells[ci]
            if label and label:GetText() and ns.IsClipped(label) then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                -- This client's signature is SetText(text [, color, alpha, wrap]) -
                -- a COLOUR OBJECT, not r,g,b. Passing 1,1,1,true put a
                -- boolean where a number goes. Text alone is all we need.
                GameTooltip:SetText(label:GetText())
                GameTooltip:Show()
            end
        end)
        hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if not hit.SetPropagateMouseClicks then
            hit:SetScript("OnMouseUp", function()
                if r.name then ChatFrame_OpenChat("/w " .. r.name .. " ") end
            end)
        end

        cx = cx + col.width
    end
    -- Clicking a row whispers-targets that player the ordinary way: it fills
    -- the chat box rather than sending anything, so nothing is ever said on
    -- the player's behalf.
    r:SetScript("OnClick", function()
        if r.name then ChatFrame_OpenChat("/w " .. r.name .. " ") end
    end)
    rows[i] = r
end

local slider = CreateFrame("Slider", nil, f)
slider:SetPoint("TOPRIGHT", -8, headerY - 2)
slider:SetSize(14, VISIBLE * ROW_H)
slider:SetOrientation("VERTICAL")
slider:SetMinMaxValues(0, 0)
slider:SetValueStep(1)
slider:SetObeyStepOnDrag(true)
panel(slider, 0, 0, 0, 0.4)
local thumb = slider:CreateTexture(nil, "ARTWORK")
thumb:SetColorTexture(0.45, 0.55, 0.65, 1)
thumb:SetSize(14, 28)
slider:SetThumbTexture(thumb)
slider:SetScript("OnValueChanged", function(_, v)
    offset = math.floor(v + 0.5)
    ns.Redraw()
end)

f:EnableMouseWheel(true)
f:SetScript("OnMouseWheel", function(_, delta)
    slider:SetValue(offset - delta)
end)

-- ---- census strip --------------------------------------------------------
-- The saved roster, stated in the two numbers that mean different things:
-- "active" is the defensible figure, "known" is an upper bound that can only
-- grow because a deleted character is indistinguishable from an absent one.
local censusLine = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
censusLine:SetPoint("TOPLEFT", 338, -506)
censusLine:SetPoint("TOPRIGHT", -14, -506)
censusLine:SetJustifyH("LEFT")

button(f, "Census report", 14, -502, 100, function()
    for _, line in ipairs(ns.Census.Summary()) do ns.say(line) end
end)
button(f, "Deep scan this", 120, -502, 100, function()
    local q = strtrim(eRaw:GetText())
    ns.log(string.format('deep scan from: "%s"', q))
    ns.DeepScanQuery(q)
end)

-- Only visible while a scan is actually running. A deep scan over a wide level
-- range can queue dozens of queries and the throttle spaces them out, so being
-- able to stop it is not optional.
local stepBtn = button(f, "Cancel scan", 226, -502, 104, function()
    if ns.hardwareGated and ns.QueueDepth() > 0 then
        ns.Pump()          -- click-driven send, if the client ever needs one
    else
        ns.CancelScan()
    end
end)
stepBtn:Hide()

local function refreshStep()
    local q = ns.QueueDepth()
    if q == 0 then stepBtn:Hide(); return end
    stepBtn:Show()
    stepBtn.label:SetText(string.format(
        ns.hardwareGated and "Continue (%d)" or "Cancel (%d)", q))
end

local function refreshCensus()
    if not (ns.Census and ns.Census.Stats) then return end
    local ok, s = pcall(ns.Census.Stats)
    if not ok or not s then return end
    censusLine:SetText(string.format(
        "roster: |cff66ff66%d|r active (7d)   %d known ever   %d guilds",
        s.active, s.known, s.guilds))
end

--==========================================================================
-- drawing
--==========================================================================

function ns.Redraw()
    for i = 1, VISIBLE do
        local row, data = rows[i], view[i + offset]
        if data then
            row.name = data.name
            local colour = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.token]
            for ci, col in ipairs(COLUMNS) do
                local v = data[col.key]
                row.cells[ci]:SetText(v ~= "" and tostring(v) or "-")
                if col.key == "name" and colour then
                    row.cells[ci]:SetTextColor(colour.r, colour.g, colour.b)
                else
                    row.cells[ci]:SetTextColor(0.85, 0.85, 0.85)
                end
            end
            row:Show()
        else
            row.name = nil
            row:Hide()
        end
    end
end

-- Called by Core whenever the result set changes.
function ns.OnResults()
    view = ns.Filter(ns.results, eFilter:GetText())
    ns.Sort(view, sortKey, sortDesc)

    for _, col in ipairs(COLUMNS) do
        local arrow = ""
        if col.key == sortKey then arrow = sortDesc and "  v" or "  ^" end
        col.fs:SetText(col.title .. arrow)
    end

    local max = math.max(0, #view - VISIBLE)
    slider:SetMinMaxValues(0, max)
    if offset > max then offset = max end
    slider:SetValue(offset)

    local msg = string.format("%d shown", #view)
    if #view ~= #ns.results then
        msg = msg .. string.format(" of %d", #ns.results)
    end
    -- The honesty line. Exactly the cap means the server stopped counting,
    -- so the number on screen is a ceiling and not a population.
    if #ns.results == ns.CAP then
        msg = msg .. "  |cffffd100(capped - try Deep scan)|r"
    end
    local q = ns.QueueDepth()
    if q > 0 then msg = msg .. string.format("  |cff88ccff[%d queued]|r", q) end
    status:SetText(msg)

    -- Draw the rows FIRST. Everything below is cosmetic, and none of it is
    -- allowed to stop the list rendering. Having them run first is what
    -- produced a blank table under a confident "49 shown": the count was
    -- set, a helper threw, and Redraw never happened.
    ns.Redraw()

    local ok, err = pcall(refreshCensus)
    if not ok then ns.warn("census strip: " .. tostring(err)) end
    ok, err = pcall(refreshStep)
    if not ok then ns.warn("scan button: " .. tostring(err)) end
end

ns.OnScanDone = ns.OnResults

-- The queue changes between replies, and replies can be 15 seconds apart once
-- the throttle backs off. Refreshing only when results arrive meant the Cancel
-- button could not appear during the long silences - precisely when it is
-- wanted. Poll it instead; it is two integers.
if C_Timer then
    C_Timer.NewTicker(0.5, function()
        if not f:IsShown() then return end
        pcall(refreshStep)
        local q = ns.QueueDepth()
        if q > 0 then
            status:SetText(string.format("%d shown  |cff88ccff[%d queued]|r",
                #view, q))
        end
    end)
end
eFilter:SetScript("OnTextChanged", function() offset = 0; ns.OnResults() end)
eRaw:SetScript("OnEnterPressed", function(self) self:ClearFocus(); doSearch() end)

--==========================================================================
-- entry point
--==========================================================================

SLASH_ROLLCALL1 = "/rc"
SLASH_ROLLCALL2 = "/rollcall"
SlashCmdList.ROLLCALL = function(msg)
    msg = strtrim(msg or "")
    if msg == "deep" or msg:match("^deep%s") then
        -- Deep scan whatever is already on screen, including a query typed
        -- into Blizzard's own box while the takeover pane is in use. An
        -- explicit argument wins: /rc deep z-"Elwynn Forest"
        local given = strtrim(msg:match("^deep%s+(.*)$") or "")
        local q = given ~= "" and given or ns.CurrentQuery()
        -- Say what it is about to do. The previous silence made a refused or
        -- empty scan look identical to a broken one.
        ns.log(string.format('deep scan from: "%s"%s', q,
            q == "" and " (no filter)" or ""))
        ns.DeepScanQuery(q)
        return
    end
    if msg == "debug" then
        ns.DumpLog(30)
        return
    end
    if msg == "debug on" or msg == "debug off" then
        ns.Census.Init()
        RollcallDB.settings.debug = (msg == "debug on")
        ns.say("live debug output " .. (RollcallDB.settings.debug and "ON" or "OFF"))
        return
    end
    if msg == "cancel" or msg == "stop" then
        if ns.CancelScan() == 0 then ns.say("no scan running.") end
        return
    end
    if msg == "census" then
        for _, line in ipairs(ns.Census.Summary()) do ns.say(line) end
        local top = ns.Census.TopGuilds(8)
        if #top > 0 then
            ns.say("  top guilds:")
            for _, g in ipairs(top) do
                ns.say(string.format("    %-28s %d", g.name, g.count))
            end
        end
        return
    end
    if msg == "wipe" then
        ns.Census.Wipe()
        ns.say("census cleared for this realm.")
        return
    end
    if msg == "takeover on" or msg == "takeover off" then
        local on = (msg == "takeover on")
        ns.Census.Init()          -- first run: the DB may not exist yet
        RollcallDB.settings.takeover = on
        ns.say("in-pane takeover " .. (on and "ENABLED" or "DISABLED")
            .. " - /reload to apply.")
        if not on then
            ns.say("the standalone window (/rc) touches none of Blizzard's frames.")
        end
        return
    end
    if msg == "help" then
        ns.say("|cffffd100/rc|r               open the window")
        ns.say("|cffffd100/rc <query>|r       search, e.g. /rc z-\"Elwynn Forest\" 4-10")
        ns.say("|cffffd100/rc deep [query]|r  census scan, defeats the 50 cap")
        ns.say("|cffffd100/rc cancel|r        stop a running scan")
        ns.say("|cffffd100/rc census|r        what the saved roster knows")
        ns.say("|cffffd100/rc wipe|r          clear the saved roster")
        ns.say("|cffffd100/rc debug|r         show the recent internal log")
        return
    end
    if msg ~= "" then
        eRaw:SetText(msg)
        f:Show()
        doSearch()
    else
        if f:IsShown() then f:Hide() else f:Show(); refreshRaw() end
    end
end

