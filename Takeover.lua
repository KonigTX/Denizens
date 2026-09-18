--[[ Rollcall takeover ---------------------------------------------------

Puts Rollcall's structure INSIDE Blizzard's own /who pane instead of beside
it, so you keep the native chrome - portrait, NineSlice border, ESC-to-close,
remembered position, the existing search box - and only the contents change.

This is possible because /rcprobe inspect showed LFGWhoListFrame is not a pile
of hardcoded card frames. It is a modern ScrollBox:

    LFGWhoListFrame.ScrollBox          the list
    LFGWhoListFrame.ScrollBar          its bar
    LFGWhoListFrame.SetupScrollView    how Blizzard builds the view
    LFGWhoListFrame.UpdateWhoList      the single populate entry point
    LFGWhoListFrame.WhoFrameTotals     the "50 People Found" line
    LFGWhoListFrame.WhoFrameEditBox    the query box

So the takeover is small: give the ScrollBox our own element initializer
(six columns instead of a card), add clickable sort headers above it, and
re-render from ns.results whenever the list changes. Blizzard still sends the
query; we only change how the answer is shown.
--]]

local ADDON, ns = ...

local ROW_H = 20
local PANE_WIDTH = 660   -- six columns do not fit the stock 458

-- Proportional, not fixed pixels. Fixed widths totalling 432 in a 458 px pane
-- pushed Guild off the right edge entirely and clipped Zone mid-word. Weights
-- always fit whatever width the pane happens to be, and reflow if it changes.
local COLUMNS = {
    { key = "name",  title = "Name",  weight = 0.25 },
    { key = "level", title = "Lvl",   weight = 0.07 },
    { key = "class", title = "Class", weight = 0.14 },
    { key = "race",  title = "Race",  weight = 0.16 },
    { key = "zone",  title = "Zone",  weight = 0.19 },
    { key = "guild", title = "Guild", weight = 0.19 },
}

local sortKey, sortDesc = "level", false
local installed, header = false, nil

local function say(m) ns.say(m) end

-- Required Mainline ScrollBox API. Checked rather than assumed, because a
-- missing one here is the difference between a clean takeover and a silent
-- half-broken list.
local function apiPresent()
    local missing = {}
    for _, name in ipairs({ "CreateScrollBoxListLinearView", "CreateDataProvider",
                            "ScrollUtil" }) do
        if _G[name] == nil then missing[#missing + 1] = name end
    end
    if #missing > 0 then
        ns.warn("takeover unavailable - missing: " .. table.concat(missing, ", "))
        return false
    end
    return true
end

-- Usable width inside the list, minus room for the scrollbar so the last
-- column does not slide under it.
local function listWidth()
    local box = LFGWhoListFrame and LFGWhoListFrame.ScrollBox
    local w = (box and box:GetWidth() or PANE_WIDTH)
    if w < 50 then w = PANE_WIDTH end
    return w - 18
end

local function widthFor(col, total)
    return math.floor((total or listWidth()) * col.weight)
end

--==========================================================================
-- rows
--==========================================================================

local isClipped = ns.IsClipped      -- shared with the standalone window

local function initRow(row, data)
    local total = listWidth()
    if not row.cells then
        row.cells, row.hits = {}, {}
        row:SetHeight(ROW_H)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(row)
        hl:SetColorTexture(1, 1, 1, 0.10)
        for i = 1, #COLUMNS do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row.cells[i] = fs

            -- FontStrings cannot take mouse input, so each cell gets an
            -- invisible catcher over it. Mouse events are propagated so the
            -- row underneath still highlights and still takes the click.
            local hit = CreateFrame("Frame", nil, row)
            hit:EnableMouse(true)
            if hit.SetPropagateMouseClicks then hit:SetPropagateMouseClicks(true) end
            if hit.SetPropagateMouseMotion then hit:SetPropagateMouseMotion(true) end
            hit:SetScript("OnEnter", function(self)
                local label = row.cells[i]
                if label and label:GetText() and isClipped(label) then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    -- This client's signature is SetText(text [, color, alpha, wrap]) -
                    -- a COLOUR OBJECT, not r,g,b. Passing 1,1,1,true put a
                    -- boolean where a number goes. Text alone is all we need.
                    GameTooltip:SetText(label:GetText())
                    GameTooltip:Show()
                end
            end)
            hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
            -- Fallback for clients without click propagation: keep the
            -- whisper behaviour working through the catcher.
            if not hit.SetPropagateMouseClicks then
                hit:SetScript("OnMouseUp", function()
                    if row.data then ChatFrame_OpenChat("/w " .. row.data.name .. " ") end
                end)
            end
            row.hits[i] = hit
        end
    end
    row.data = data

    -- Position AND size every cell on each pass. Anchoring only at creation
    -- left the columns frozen at whatever width the pane happened to be the
    -- first time a row was built, so any reflow silently desynced the text
    -- from the headers above it.
    local x = 0
    local colour = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.token]
    for i, col in ipairs(COLUMNS) do
        local w = widthFor(col, total)
        local fs = row.cells[i]
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", x + 4, 0)
        fs:SetWidth(w - 8)
        local hit = row.hits and row.hits[i]
        if hit then
            hit:ClearAllPoints()
            hit:SetPoint("LEFT", x, 0)
            hit:SetSize(w, ROW_H)
        end
        local v = data[col.key]
        fs:SetText((v ~= nil and v ~= "") and tostring(v) or "-")
        if col.key == "name" and colour then
            fs:SetTextColor(colour.r, colour.g, colour.b)
        else
            fs:SetTextColor(0.82, 0.82, 0.82)
        end
        x = x + w
    end

    row:SetScript("OnMouseUp", function(self)
        -- Fills the chat box; never sends anything on the player's behalf.
        -- Reads row.data rather than closing over `data`, because ScrollBox
        -- recycles these frames and a stale capture would whisper whoever
        -- happened to occupy this row earlier.
        if self.data then ChatFrame_OpenChat("/w " .. self.data.name .. " ") end
    end)
end

--==========================================================================
-- sortable headers
--==========================================================================

local function buildHeader(frame)
    header = CreateFrame("Frame", nil, frame)
    header:SetPoint("BOTTOMLEFT", frame.ScrollBox, "TOPLEFT", 0, 2)
    header:SetPoint("BOTTOMRIGHT", frame.ScrollBox, "TOPRIGHT", 0, 2)
    header:SetHeight(ROW_H)

    local total = listWidth()
    local x = 0
    for _, col in ipairs(COLUMNS) do
        local w = widthFor(col, total)
        local b = CreateFrame("Button", nil, header)
        b:SetPoint("LEFT", x, 0)
        b:SetSize(w, ROW_H)
        col.button = b

        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(b)
        bg:SetColorTexture(0, 0, 0, 0.35)

        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", 4, 0)
        col.fs = fs

        b:SetScript("OnClick", function()
            if sortKey == col.key then sortDesc = not sortDesc
            else sortKey, sortDesc = col.key, false end
            ns.RenderTakeover()
        end)
        x = x + w
    end
end

--==========================================================================
-- render
--==========================================================================

function ns.RenderTakeover()
    local frame = LFGWhoListFrame
    if not (installed and frame) then return end

    local rows = ns.Filter(ns.results, "")
    ns.Sort(rows, sortKey, sortDesc)

    for _, col in ipairs(COLUMNS) do
        if col.fs then
            local arrow = ""
            if col.key == sortKey then arrow = sortDesc and " v" or " ^" end
            col.fs:SetText(col.title .. arrow)
        end
    end

    frame.ScrollBox:SetDataProvider(CreateDataProvider(rows), true)

    -- Just the count. The cap hint and the queue depth belong in the /rc
    -- panel, which is the surface for running and cancelling scans - in the
    -- browsing pane they were noise on every single query.
    local totals = frame.WhoFrameTotals
    if totals and totals.SetText then
        totals:SetText(string.format("%d found", #rows))
    end
end

--==========================================================================
-- install
--==========================================================================

-- Re-lay the headers when the pane's width changes, and redraw so the rows
-- follow. Without this the headers and the text under them drift apart.
function ns.ReflowTakeover()
    if not installed then return end
    local total, x = listWidth(), 0
    for _, col in ipairs(COLUMNS) do
        local w = widthFor(col, total)
        if col.button then
            col.button:ClearAllPoints()
            col.button:SetPoint("LEFT", x, 0)
            col.button:SetSize(w, ROW_H)
        end
        x = x + w
    end
    ns.RenderTakeover()
end

local function install(frame)
    -- Six columns do not fit the stock 458 px pane - Guild fell off the edge
    -- entirely. Widening the real frame beats shrinking the text into it.
    pcall(function()
        if frame:GetWidth() < PANE_WIDTH then frame:SetWidth(PANE_WIDTH) end
    end)

    local view = CreateScrollBoxListLinearView()
    view:SetElementInitializer("Frame", initRow)
    view:SetElementExtent(ROW_H)
    ScrollUtil.InitScrollBoxListWithScrollBar(frame.ScrollBox, frame.ScrollBar, view)

    buildHeader(frame)

    -- Blizzard's own populate call. Overriding the field (rather than
    -- hooksecurefunc) is what stops its card layout from repainting over
    -- ours. /who is not a protected action, so there is nothing here that
    -- taint would block.
    frame.UpdateWhoList = function() ns.RenderTakeover() end

    installed = true
    ns.takeover = true      -- Core stops hiding the pane once we own it

    -- Reflow if anything ever resizes the pane under us.
    frame:HookScript("OnSizeChanged", function()
        if ns.ReflowTakeover then ns.ReflowTakeover() end
    end)
    ns.log("installed into the default /who pane.")
    ns.RenderTakeover()
end

-- Every reason this can fail is now SAID OUT LOUD. The previous version
-- returned silently from four different places and the result was
-- indistinguishable from "the addon did nothing", which is exactly what
-- happened: LFGWhoListFrame does not exist at PLAYER_LOGIN (the LFG UI is
-- loaded on demand), so install() bailed AND the OnShow hook that would have
-- retried was itself inside `if LFGWhoListFrame then`. It could never recover.
local hooked, attempts = false, 0

local function tryInstall(reason)
    if installed then return true end
    -- Taking over Blizzard's pane means writing to a frame that lives under
    -- LFGParentFrame - the Group Finder - where queueing is a PROTECTED
    -- action. Addon writes taint the frame, and a tainted protected path is
    -- what produces "Interface action failed because of an AddOn". So this is
    -- a setting, not a given: a user who never wants that risk can run the
    -- standalone window and touch none of Blizzard's frames.
    if RollcallDB and RollcallDB.settings and RollcallDB.settings.takeover == false then
        return false
    end
    local frame = _G.LFGWhoListFrame
    if not frame then
        if reason == "manual" then
            say("LFGWhoListFrame does not exist yet - open /who once, then retry.")
        end
        return false
    end

    -- It exists now, so make sure we get another chance if this attempt fails.
    if not hooked then
        hooked = true
        frame:HookScript("OnShow", function() tryInstall("onshow") end)
    end

    if not frame.ScrollBox then
        ns.warn("no .ScrollBox on the pane - cannot take it over.")
        return false
    end
    if not apiPresent() then return false end

    -- A runtime error in here used to vanish into the event handler. Catch it
    -- and print it, because a silent failure looks identical to success.
    local ok, err = pcall(install, frame)
    if not ok then
        ns.warn("takeover errored: " .. tostring(err))
        return false
    end
    return true
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("WHO_LIST_UPDATE")
f:SetScript("OnEvent", function(_, event)
    if event == "WHO_LIST_UPDATE" then
        if not installed then tryInstall("whoupdate") end
        ns.RenderTakeover()
        return
    end
    -- The LFG UI is demand-loaded, so keep trying for a while rather than
    -- assuming the frame is there the moment we log in.
    if not installed then
        tryInstall(event)
        if not installed and attempts == 0 and C_Timer then
            attempts = 1
            local ticker
            ticker = C_Timer.NewTicker(2, function()
                attempts = attempts + 1
                if installed or attempts > 15 then
                    ticker:Cancel()
                elseif tryInstall("retry") then
                    ticker:Cancel()
                end
            end)
        end
    end
end)

SLASH_RCTAKE1 = "/rctakeover"
SlashCmdList.RCTAKE = function()
    if installed then
        say("already installed.")
    elseif not tryInstall("manual") then
        say("see above for why. Run this with the /who pane OPEN.")
    end
end
