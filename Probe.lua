--[[ Rollcall probe -------------------------------------------------------

Answers, from inside the running client, the things the real build must not
guess at:

  * does a third-party addon load on Forever at all
  * what Interface number this client actually wants in the TOC
  * which /who API exists here, and whether it is protected or throttled
  * the REAL field names GetWhoInfo returns - these differ between Classic
    and Mainline, and a wrong field name fails silently as a nil column

Nothing here touches public chat. Everything prints to your own chat frame
only, via print(), which is local output.
--]]

local ADDON = "Rollcall"
local f = CreateFrame("Frame")

local function say(msg)
    print("|cff66ccff" .. ADDON .. "|r " .. tostring(msg))
end

-- Report a global or namespaced function without erroring when it is absent.
local function probe(path)
    local node, walked = _G, ""
    for part in string.gmatch(path, "[^%.]+") do
        walked = (walked == "") and part or (walked .. "." .. part)
        if type(node) ~= "table" then
            return string.format("%-42s MISSING (%s is not a table)", path, walked)
        end
        node = node[part]
        if node == nil then
            return string.format("%-42s MISSING (at %s)", path, walked)
        end
    end
    local kind = type(node)
    local extra = ""
    if kind == "function" then
        -- A protected function cannot be called from addon code at all, which
        -- would be fatal for a query builder and is worth knowing up front.
        local ok, secure = pcall(issecurevariable, path)
        if ok and secure then extra = "  [SECURE/protected]" end
    end
    return string.format("%-42s %s%s", path, kind, extra)
end

local API = {
    "C_FriendList.SendWho",
    "C_FriendList.GetNumWhoResults",
    "C_FriendList.GetWhoInfo",
    "C_FriendList.SetWhoToUi",
    "C_FriendList.GetWhoInfoByIndex",
    "SendWho",
    "SetWhoToUI",
    "WhoFrame",
    "FriendsFrame",
    "SortWho",
}

local function report()
    local name, build, date, iface = GetBuildInfo()
    say("loaded. If you can read this, third-party addons RUN on Forever.")
    say(string.format("client %s build %s (%s)", name or "?", build or "?", date or "?"))
    say(string.format("|cffffd100## Interface: %s|r  <- the TOC number this client wants",
        tostring(iface)))
    say("--- /who API surface ---")
    for _, path in ipairs(API) do
        say(probe(path))
    end
end

-- Dump the actual shape of one result, so the column list is derived from the
-- client rather than from a Classic-era wiki page.
local function dumpShape()
    local n = C_FriendList and C_FriendList.GetNumWhoResults
        and C_FriendList.GetNumWhoResults() or 0
    say(string.format("--- %d result(s) ---", n))
    if n == 0 then return end
    local info = C_FriendList.GetWhoInfo(1)
    if type(info) ~= "table" then
        say("GetWhoInfo(1) returned " .. type(info) .. ", not a table")
        return
    end
    local keys = {}
    for k in pairs(info) do keys[#keys + 1] = k end
    table.sort(keys)
    say("GetWhoInfo fields:")
    for _, k in ipairs(keys) do
        say(string.format("   %-16s = %s", k, tostring(info[k])))
    end
end

-- The probe no longer runs on login or hooks WHO_LIST_UPDATE: it has done its
-- job, and leaving it listening would double-print over every real query.
-- It stays as an on-demand tool for the next time the client changes under us.
--
-- Note for whoever reads this later: the [SECURE/protected] labels this file
-- prints are MISLEADING. issecurevariable() reports whether a variable is
-- untainted, not whether a function may be called, and it cannot resolve a
-- dotted path string at all. SendWho was proven callable from addon code by
-- simply calling it. Do not read those labels as a restriction.

-- Walk a Blizzard frame so we can see what we would be taking over, rather
-- than guessing at it. Prints type, name, template-ish clues and whether a
-- child looks like a modern ScrollBox - which decides whether the default
-- pane can be restructured in place or only replaced.
local function inspect(name, depth, frame)
    frame = frame or _G[name]
    depth = depth or 0
    if not frame then say("no frame named " .. tostring(name)); return end

    if depth == 0 then
        say("--- " .. name .. " ---")
        say(string.format("shown=%s  size=%.0fx%.0f  parent=%s",
            tostring(frame:IsShown()),
            frame.GetWidth and frame:GetWidth() or 0,
            frame.GetHeight and frame:GetHeight() or 0,
            frame:GetParent() and (frame:GetParent():GetName() or "?") or "nil"))
        -- Named fields hung off the frame by Blizzard's own code are the
        -- handles we would actually use (frame.ScrollBox, frame.SearchBox...).
        local keys = {}
        for k, v in pairs(frame) do
            if type(k) == "string" then
                keys[#keys + 1] = string.format("%s:%s", k, type(v))
            end
        end
        table.sort(keys)
        say("fields: " .. (#keys > 0 and table.concat(keys, ", ") or "(none)"))
    end

    if depth > 2 then return end
    local pad = string.rep("  ", depth + 1)
    for i, child in ipairs({ frame:GetChildren() }) do
        local cname = child:GetName() or ("<anon#" .. i .. ">")
        local objType = child:GetObjectType()
        local hint = ""
        if child.ScrollTarget or child.GetDataProvider then hint = "  <-- SCROLLBOX" end
        if child.GetText and child:GetText() and child:GetText() ~= "" then
            hint = hint .. '  text="' .. child:GetText() .. '"'
        end
        say(string.format("%s%s  [%s]%s", pad, cname, objType, hint))
        inspect(cname, depth + 1, child)
    end
end

SLASH_RCPROBE1 = "/rcprobe"
SlashCmdList.RCPROBE = function(msg)
    local cmd, rest = string.match(msg or "", "^(%S*)%s*(.*)$")
    if cmd == "inspect" then
        inspect(rest ~= "" and rest or "LFGWhoListFrame")
    elseif cmd == "who" then
        if not (C_FriendList and C_FriendList.SendWho) then
            say("C_FriendList.SendWho is missing - cannot query.")
            return
        end
        -- Keep results in the UI instead of dumping 50 lines into chat.
        if C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(true) end
        say('sending /who "' .. rest .. '" ...')
        local ok, err = pcall(C_FriendList.SendWho, rest)
        if not ok then
            say("|cffff5555SendWho errored:|r " .. tostring(err))
            say("that usually means it is protected and needs a hardware event.")
        end
    else
        report()
    end
end
