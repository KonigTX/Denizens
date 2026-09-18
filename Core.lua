--[[ Rollcall core -------------------------------------------------------

Query building, the send queue, result capture, sorting and the deep scan.
No UI in this file.

Everything here is built on what the client actually reported (see Probe.lua),
not on a Classic-era wiki page:

  * C_FriendList.SendWho / GetNumWhoResults / GetWhoInfo / SetWhoToUi exist
  * SortWho does NOT exist, so sorting is ours to do
  * GetWhoInfo returns: fullName, level, classStr, filename, raceStr,
    area, fullGuildName, gender.  The guild key is fullGuildName - NOT
    "guild", which is what the Classic docs would have had us write and
    which would have failed silently as an empty column.
--]]

local ADDON, ns = ...

Rollcall = ns
-- Must match "## Interface:" in Rollcall.toc. Kept here because
-- GetAddOnMetadata cannot read that field back out of the TOC.
ns.BUILT_FOR = 16001
ns.CAP = 50           -- the server's hard result cap; see DeepScan below
ns.MAX_LEVEL = 60
ns.results = {}       -- array of row tables
ns.lastQuery = ""

-- Output discipline: Rollcall prints ONE line at login and otherwise speaks
-- only when asked a question. Everything else goes to a ring buffer that
-- /rc debug can dump. Running commentary in a shared chat frame is noise, and
-- worse, it trains you to ignore the line that actually matters.
local function say(msg)
    print("|cff66ccffRollcall|r " .. tostring(msg))
end
ns.say = say

ns.errors, ns.logLines = 0, {}

function ns.log(msg)
    local line = date("%H:%M:%S") .. "  " .. tostring(msg)
    ns.logLines[#ns.logLines + 1] = line
    while #ns.logLines > 300 do table.remove(ns.logLines, 1) end
    if RollcallDB and RollcallDB.settings and RollcallDB.settings.debug then
        say(msg)
    end
end

-- Something went wrong. Counted so the login line can mention it once,
-- instead of each site shouting at the moment it happens.
function ns.warn(msg)
    ns.errors = ns.errors + 1
    ns.log("|cffff5555" .. tostring(msg) .. "|r")
end

--==========================================================================
-- Query building
--==========================================================================

-- The /who filter tokens. A value containing a space must be quoted, and an
-- unquoted multi-word zone is the single most common reason a query silently
-- returns everybody instead of the zone asked for.
local TOKEN = { name = "n", guild = "g", zone = "z", race = "r", class = "c" }

local function token(prefix, value)
    value = value and strtrim(value) or ""
    if value == "" then return nil end
    return string.format('%s-"%s"', prefix, value)
end

-- spec = { name, guild, zone, race, class, minLevel, maxLevel }
function ns.BuildQuery(spec)
    local parts = {}
    for field, prefix in pairs(TOKEN) do
        local t = token(prefix, spec[field])
        if t then parts[#parts + 1] = t end
    end
    table.sort(parts)   -- stable output, so the raw box does not jitter

    local lo, hi = tonumber(spec.minLevel), tonumber(spec.maxLevel)
    if lo and hi then
        if lo > hi then lo, hi = hi, lo end
        parts[#parts + 1] = (lo == hi) and tostring(lo)
                                       or string.format("%d-%d", lo, hi)
    elseif lo then
        parts[#parts + 1] = tostring(lo)
    elseif hi then
        parts[#parts + 1] = tostring(hi)
    end

    return table.concat(parts, " ")
end

--==========================================================================
-- The send queue
--==========================================================================
-- /who is server-throttled. Firing them back to back gets the extras silently
-- dropped, which looks exactly like "the addon is broken" - so every query
-- goes through one queue with a gap, and a query whose reply never arrives is
-- retried with a longer gap rather than abandoned.

local queue, inFlight, sentAt, gap, retries = {}, nil, 0, 2.5, 0
local MAX_RETRIES = 3

-- Bumped by CancelScan. Every deep-scan callback captures the generation it
-- was created under and returns early if it no longer matches, so a cancelled
-- scan cannot resurrect itself through a reply that was already in the air.
local generation = 0
local ignoreNextReply = false

local driver = CreateFrame("Frame")

local function pump()
    if inFlight or #queue == 0 then return end
    if GetTime() - sentAt < gap then return end
    inFlight = table.remove(queue, 1)
    sentAt, retries = GetTime(), 0
    if C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(true) end
    ns.lastQuery = inFlight.query
    C_FriendList.SendWho(inFlight.query)
end

driver:SetScript("OnUpdate", function()
    if inFlight and GetTime() - sentAt > 5 then
        -- No WHO_LIST_UPDATE came back. Assume throttled, widen the gap and
        -- put it back at the front rather than losing the sub-query and
        -- silently returning an incomplete census.
        retries = retries + 1
        if retries <= MAX_RETRIES then
            gap = math.min(gap * 1.6, 12)
            table.insert(queue, 1, inFlight)
            inFlight, sentAt = nil, GetTime()
        else
            ns.warn("gave up on " .. inFlight.query .. " (no reply)")
            local done = inFlight.onDone
            inFlight = nil
            if done then done({}) end
        end
    end
    -- Once the client has told us SendWho needs a hardware event, pumping from
    -- OnUpdate only reproduces the same refusal every frame. Stop, and let the
    -- step button carry it.
    if not ns.hardwareGated then pump() end
end)

-- Exposed so a BUTTON CLICK can drive the queue. If the client gates SendWho
-- behind a hardware event, a timer is not allowed to send and the only legal
-- way to continue a census is for the player to click - so the scan becomes
-- click-to-step rather than impossible.
function ns.Pump() pump() end

-- Stop everything: drop the queue, abandon the query already sent, and
-- invalidate any callback still holding a reference to the old scan.
function ns.CancelScan()
    local n = #queue + (inFlight and 1 or 0)
    if n == 0 then return 0 end
    generation = generation + 1
    wipe(queue)
    if inFlight then
        -- Its reply may still arrive. Discard that one rather than letting it
        -- be mistaken for a /who the player typed, which would wipe the
        -- results collected so far and replace them with a stray 50.
        ignoreNextReply = true
        inFlight = nil
    end
    sentAt = GetTime()
    ns.log(string.format("scan cancelled (%d dropped); %d kept.", n, #ns.results))
    if ns.OnResults then ns.OnResults() end
    return n
end

function ns.Send(query, onDone)
    queue[#queue + 1] = { query = query, onDone = onDone }
    pump()
end

function ns.QueueDepth() return #queue + (inFlight and 1 or 0) end

--==========================================================================
-- Result capture
--==========================================================================

local function harvest()
    local out, n = {}, C_FriendList.GetNumWhoResults()
    for i = 1, n do
        local info = C_FriendList.GetWhoInfo(i)
        if info and info.fullName and info.fullName ~= "" then
            out[#out + 1] = {
                name   = info.fullName,
                level  = info.level or 0,
                class  = info.classStr or "",
                token  = info.filename or "",      -- for class colour
                race   = info.raceStr or "",
                zone   = info.area or "",
                guild  = info.fullGuildName or "",
            }
        end
    end
    return out
end

-- Forever's own who window. Found with /fstack, because it is NOT WhoFrame -
-- that global does not exist here. It is LFGWhoListFrame, parented under
-- LFGParentFrame, built from Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.
-- SetWhoToUi(true) pops it on every reply, which during a deep scan means it
-- flashing open dozens of times over the top of ours.
local function suppressBlizzardWho()
    -- Once Takeover.lua owns the pane, hiding it would be hiding our own UI.
    if ns.takeover then return end
    local frame = _G.LFGWhoListFrame
    if frame and frame:IsShown() then frame:Hide() end
    -- It is anchored inside the LFG parent; hide that too if it opened only
    -- to carry the who list, but never if the player has LFG open themselves.
    local parent = _G.LFGParentFrame
    if parent and parent:IsShown() and not (ns.userOpenedLFG) then
        parent:Hide()
    end
end
ns.suppressBlizzardWho = suppressBlizzardWho

driver:RegisterEvent("WHO_LIST_UPDATE")
-- UI_ERROR_MESSAGE was registered here to detect /who refusals. That was a
-- mistake: the event carries EVERY red error the game raises - "Spell is not
-- ready yet", "Out of range", anything the player happens to trigger - and
-- there is no field identifying what caused it. Treating them all as /who
-- refusals meant unrelated errors inflated the throttle gap to 15 s and
-- strangled the scan, while spamming chat about spells.
--
-- The timeout path below is the honest signal: if a query gets no reply, the
-- query got no reply. That cannot be confused with anything else.

driver:SetScript("OnEvent", function(_, event, a, b)
    if ignoreNextReply then
        -- Late reply from a cancelled scan. Drop it silently.
        ignoreNextReply = false
        return
    end
    if inFlight then suppressBlizzardWho() end
    if not inFlight then
        -- Somebody else's /who (yours, typed manually). Show it anyway.
        ns.Absorb(harvest(), false)
        return
    end
    local batch = harvest()
    local done = inFlight.onDone
    inFlight, sentAt = nil, GetTime()
    if done then done(batch) else ns.Absorb(batch, false) end
    pump()
end)

-- Merge a batch into the visible set, de-duplicating by name. Deep scan
-- relies on this: overlapping level splits WILL return the same player twice.
function ns.Absorb(batch, keepExisting)
    if not keepExisting then wipe(ns.results) end
    local seen = {}
    for _, row in ipairs(ns.results) do seen[row.name] = true end
    for _, row in ipairs(batch) do
        if not seen[row.name] then
            seen[row.name] = true
            ns.results[#ns.results + 1] = row
        end
    end
    -- Every sighting feeds the persistent roster, including replies to a /who
    -- the player typed themselves - the census should grow from ordinary use,
    -- not only from deliberate scans.
    if ns.Census and ns.Census.Record then ns.Census.Record(batch) end
    if ns.OnResults then ns.OnResults() end
end

--==========================================================================
-- Deep scan - defeating the 50-result cap
--==========================================================================
-- A query that returns EXACTLY the cap is almost certainly truncated: the
-- server stopped counting, so you are looking at an arbitrary 50 of an
-- unknown number. "50 People Found" is not a population, it is a ceiling.
--
-- So: when a query comes back at the cap, split its level range in half and
-- ask again for each half. Recurse until every sub-query comes back under the
-- cap, then merge. A capped sample becomes a complete census.
--
-- Level is the right axis to split on because it is the only filter that is
-- guaranteed to partition the population cleanly and exhaustively - splitting
-- on zone or class would leave gaps.

-- Split a raw /who query into tokens, keeping quoted values intact, so that
-- z-"Stormwind City" survives as one token instead of becoming two.
local function tokenize(q)
    local out, i, n = {}, 1, #(q or "")
    while i <= n do
        local c = q:sub(i, i)
        if c:match("%s") then
            i = i + 1
        else
            local start, inQuote = i, false
            while i <= n do
                local ch = q:sub(i, i)
                if ch == '"' then inQuote = not inQuote
                elseif ch:match("%s") and not inQuote then break end
                i = i + 1
            end
            out[#out + 1] = q:sub(start, i - 1)
        end
    end
    return out
end

local function isLevelToken(t)
    return t:match("^%d+$") ~= nil or t:match("^%d+%-%d+$") ~= nil
end

-- Strip the level filter out of a raw query and report what it was, so a deep
-- scan can re-impose its own ranges over whatever the player actually typed -
-- in our builder, or in Blizzard's own box.
function ns.SplitQuery(raw)
    local base, lo, hi = {}, nil, nil
    for _, t in ipairs(tokenize(raw)) do
        if isLevelToken(t) then
            local a, b = t:match("^(%d+)%-(%d+)$")
            if a then lo, hi = tonumber(a), tonumber(b)
            else lo = tonumber(t); hi = lo end
        else
            base[#base + 1] = t
        end
    end
    return table.concat(base, " "), lo, hi
end

local function scan(base, lo, hi, depth, state)
    local query = strtrim(base .. " " ..
        ((lo == hi) and tostring(lo) or string.format("%d-%d", lo, hi)))
    local gen = generation

    ns.Send(query, function(batch)
        if gen ~= generation then return end   -- this scan was cancelled
        ns.Absorb(batch, true)
        state.pending = state.pending - 1

        if #batch >= ns.CAP and lo < hi and depth < 8 then
            local mid = math.floor((lo + hi) / 2)
            state.pending = state.pending + 2
            scan(base, lo, mid, depth + 1, state)
            scan(base, mid + 1, hi, depth + 1, state)
        elseif #batch >= ns.CAP and lo == hi then
            -- One level, still capped. Cannot split further on level; the
            -- honest thing is to say so rather than imply completeness.
            state.capped[#state.capped + 1] = lo
        end

        if state.pending == 0 then
            if ns.Census and ns.Census.NoteScan then
                ns.Census.NoteScan(base, #ns.results)
            end
            local msg = string.format("deep scan complete: %d found", #ns.results)
            if #state.capped > 0 then
                msg = msg .. string.format(
                    " |cffffd100(level %s still capped - more exist there)|r",
                    table.concat(state.capped, ", "))
            end
            ns.log(msg)
            if ns.OnScanDone then ns.OnScanDone() end
        end
    end)
end

-- Deep scan any raw query, from any source: our builder, or Blizzard's own
-- search box. Whatever level filter it carries becomes the outer bound.
function ns.DeepScanQuery(raw)
    local base, lo, hi = ns.SplitQuery(raw or "")
    lo = lo or 1
    hi = hi or ns.MAX_LEVEL
    if lo > hi then lo, hi = hi, lo end
    wipe(ns.results)
    local state = { pending = 1, capped = {} }
    ns.log(string.format('deep scan %d-%d over "%s"', lo, hi,
        base ~= "" and base or "everyone"))
    scan(base, lo, hi, 0, state)
end

function ns.DeepScan(spec)
    ns.DeepScanQuery(ns.BuildQuery(spec))
end

-- Whatever query the player last typed, wherever they typed it.
function ns.CurrentQuery()
    local box = _G.WhoFrameEditBox
    local typed = box and box.GetText and strtrim(box:GetText() or "") or ""
    if typed ~= "" then return typed end
    return ns.lastQuery or ""
end

--==========================================================================
-- Sorting and filtering (client-side: SortWho does not exist here)
--==========================================================================

local COMPARE = {
    name  = function(a, b) return a.name  < b.name  end,
    level = function(a, b) return a.level < b.level end,
    class = function(a, b) return a.class < b.class end,
    race  = function(a, b) return a.race  < b.race  end,
    zone  = function(a, b) return a.zone  < b.zone  end,
    guild = function(a, b) return a.guild < b.guild end,
}

function ns.Sort(rows, key, descending)
    local cmp = COMPARE[key] or COMPARE.name
    table.sort(rows, function(a, b)
        if a[key] == b[key] then return a.name < b.name end  -- stable tiebreak
        if descending then return cmp(b, a) end
        return cmp(a, b)
    end)
end

-- Is this text actually cut off? Only then is a tooltip worth showing - one
-- that appears over every cell is just a cursor-follower.
function ns.IsClipped(fs)
    if fs.IsTruncated then
        local ok, truncated = pcall(fs.IsTruncated, fs)
        if ok then return truncated end
    end
    -- Fallback: the unwrapped string is wider than the box holding it.
    return fs:GetStringWidth() > fs:GetWidth() + 0.5
end

-- Instant, costs no server query: narrows what is already on screen.
function ns.Filter(rows, text)
    text = strtrim(text or ""):lower()
    if text == "" then return rows end
    local out = {}
    for _, r in ipairs(rows) do
        local hay = (r.name .. " " .. r.class .. " " .. r.race .. " "
                     .. r.zone .. " " .. r.guild):lower()
        if hay:find(text, 1, true) then out[#out + 1] = r end
    end
    return out
end

--==========================================================================
-- The one line Rollcall is allowed to say on its own
--==========================================================================
-- Deliberately delayed a few seconds: the pane takeover installs after login,
-- so reporting at PLAYER_LOGIN would announce success before the part most
-- likely to fail has run. One line, after everything has settled, saying
-- exactly one of: fine / had problems / built for a different client.

local startup = CreateFrame("Frame")
startup:RegisterEvent("PLAYER_LOGIN")
startup:SetScript("OnEvent", function()
    local after = C_Timer and C_Timer.After
    local function report()
        local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        local version = (meta and meta(ADDON, "Version")) or "?"

        -- GetAddOnMetadata does not expose "Interface", so the TOC number has
        -- to be stated here and kept in step with the .toc by hand.
        local built = ns.BUILT_FOR

        -- GetBuildInfo returns MORE than four values on this client, and
        -- select(4, ...) yields all of them from the fourth on - so the old
        -- tonumber(select(4, ...)) passed the fifth value as tonumber's BASE
        -- argument, which must be a number. Name the field instead.
        local _, _, _, toc = GetBuildInfo()
        local client = tonumber(toc) or 0

        local notes = {}
        if ns.errors > 0 then
            notes[#notes + 1] = string.format(
                "|cffff5555%d problem%s|r - /rc debug", ns.errors,
                ns.errors == 1 and "" or "s")
        end
        if built > 0 and client > 0 and built ~= client then
            notes[#notes + 1] = string.format(
                "|cffffd100out of date|r - built for %d, client is %d", built, client)
        end

        if #notes == 0 then
            say(string.format("v%s loaded.  |cffffd100/rc|r for the panel, /rc help for commands.",
                version))
        else
            say(string.format("v%s loaded - %s", version, table.concat(notes, "; ")))
        end
    end
    if after then after(4, report) else report() end
end)

-- Dump the ring buffer. This is where all the running commentary went.
function ns.DumpLog(n)
    local lines = ns.logLines
    if #lines == 0 then say("log is empty.") return end
    say(string.format("last %d of %d log lines:", math.min(n or 25, #lines), #lines))
    for i = math.max(1, #lines - (n or 25) + 1), #lines do
        print("  " .. lines[i])
    end
end
