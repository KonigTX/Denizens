--[[ Denizens census ------------------------------------------------------

Persistent population data. Every /who reply - ours, a deep scan's, or one you
typed yourself - is folded into a saved roster, so the picture accumulates
across sessions instead of dying with the window.

On what this can and cannot know
--------------------------------
A /who census is a record of who was SEEN, never of who EXISTS. Three honest
limits, stated here so the UI can stop short of claiming more:

  * Offline players are invisible. A census is a sample of the online
    population at the moments you happened to scan.
  * Deletes, renames and transfers are unobservable. A character that is gone
    looks exactly like a character that has not logged in. This is why the
    headline number is "seen in the last N days" and the all-time total is
    reported separately rather than as "the population".
  * The server caps each reply at 50, so any single query is a ceiling, not a
    count. Deep scan exists to work around that; see Core.lua.

So: treat "active" as the real figure, "known" as an upper bound that only
ever grows, and never present either as a server population.
--]]

local ADDON, ns = ...

local DB_VERSION = 1
local MAX_PLAYERS = 25000          -- prune beyond this, oldest sighting first
local ACTIVE_WINDOW = 7 * 24 * 3600

ns.Census = {}
local Census = ns.Census

local function realmKey()
    -- Forever is realmless, but GetRealmName still returns something stable,
    -- and keying by it means an Era install and a Forever install cannot
    -- pollute each other's roster.
    local realm = (GetRealmName and GetRealmName()) or "Unknown"
    local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Neutral"
    return realm .. " - " .. faction
end

local function defaults()
    return {
        version = DB_VERSION,
        settings = { takeover = true, autoRecord = true },
        realms = {},
    }
end

function Census.Init()
    if type(DenizensDB) ~= "table" or DenizensDB.version ~= DB_VERSION then
        DenizensDB = defaults()
    end
    DenizensDB.settings = DenizensDB.settings or defaults().settings
    DenizensDB.realms = DenizensDB.realms or {}
    local key = realmKey()
    DenizensDB.realms[key] = DenizensDB.realms[key] or { players = {}, scans = {} }
    Census.db = DenizensDB.realms[key]
    return Census.db
end

local function db()
    return Census.db or Census.Init()
end

--==========================================================================
-- recording
--==========================================================================

-- Fold a batch of sightings in. Returns how many were new, which is the only
-- number that tells you whether a scan is still discovering anything.
function Census.Record(rows)
    if not DenizensDB or not DenizensDB.settings.autoRecord then return 0, 0 end
    local store, now, new, updated = db().players, time(), 0, 0
    for _, r in ipairs(rows) do
        local p = store[r.name]
        if not p then
            new = new + 1
            p = { first = now, seen = 0 }
            store[r.name] = p
        else
            updated = updated + 1
        end
        p.lvl   = r.level
        p.class = r.class
        p.race  = r.race
        p.guild = r.guild
        p.area  = r.zone          -- subzone; see the note in the header
        p.last  = now
        p.seen  = p.seen + 1
    end
    Census.Prune()
    return new, updated
end

function Census.Prune()
    local store = db().players
    local n = 0
    for _ in pairs(store) do n = n + 1 end
    if n <= MAX_PLAYERS then return end

    local list = {}
    for name, p in pairs(store) do list[#list + 1] = { name = name, last = p.last or 0 } end
    table.sort(list, function(a, b) return a.last < b.last end)
    for i = 1, n - MAX_PLAYERS do store[list[i].name] = nil end
end

function Census.NoteScan(query, found)
    local scans = db().scans
    scans[#scans + 1] = { at = time(), query = query, found = found }
    while #scans > 200 do table.remove(scans, 1) end
end

--==========================================================================
-- reporting
--==========================================================================

function Census.Stats()
    local store, now = db().players, time()
    local s = {
        known = 0, active = 0, guilds = 0, guilded = 0,
        maxLevel = 0, byBracket = {}, byClass = {},
    }
    local guildSet = {}
    for _, p in pairs(store) do
        s.known = s.known + 1
        if p.last and (now - p.last) <= ACTIVE_WINDOW then s.active = s.active + 1 end
        local lvl = p.lvl or 0
        if lvl > s.maxLevel then s.maxLevel = lvl end
        local bracket = math.floor(lvl / 10) * 10
        s.byBracket[bracket] = (s.byBracket[bracket] or 0) + 1
        if p.class and p.class ~= "" then
            s.byClass[p.class] = (s.byClass[p.class] or 0) + 1
        end
        if p.guild and p.guild ~= "" then
            s.guilded = s.guilded + 1
            if not guildSet[p.guild] then
                guildSet[p.guild] = 0
                s.guilds = s.guilds + 1
            end
            guildSet[p.guild] = guildSet[p.guild] + 1
        end
    end
    s.guildSet = guildSet
    return s
end

function Census.TopGuilds(limit)
    local s = Census.Stats()
    local list = {}
    for name, count in pairs(s.guildSet) do
        list[#list + 1] = { name = name, count = count }
    end
    table.sort(list, function(a, b)
        if a.count == b.count then return a.name < b.name end
        return a.count > b.count
    end)
    while #list > (limit or 10) do table.remove(list) end
    return list
end

function Census.Summary()
    local s = Census.Stats()
    local out = {
        string.format("|cffffd100%s|r", realmKey()),
        string.format("  active (seen in 7 days): |cff66ff66%d|r", s.active),
        string.format("  known ever (upper bound, includes deleted): %d", s.known),
        string.format("  guilds seen: %d   guilded: %d%%", s.guilds,
            s.known > 0 and math.floor(s.guilded / s.known * 100) or 0),
        string.format("  highest level seen: %d", s.maxLevel),
    }
    local brackets = {}
    for b in pairs(s.byBracket) do brackets[#brackets + 1] = b end
    table.sort(brackets)
    local parts = {}
    for _, b in ipairs(brackets) do
        parts[#parts + 1] = string.format("%d-%d:%d", b == 0 and 1 or b,
            b + 9, s.byBracket[b])
    end
    if #parts > 0 then out[#out + 1] = "  levels  " .. table.concat(parts, "  ") end
    return out
end

function Census.Wipe()
    local key = realmKey()
    DenizensDB.realms[key] = { players = {}, scans = {} }
    Census.db = DenizensDB.realms[key]
end

--==========================================================================
-- wiring
--==========================================================================

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= ADDON then return end
    Census.Init()
end)
