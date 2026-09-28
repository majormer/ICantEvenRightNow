-- I Can't Even Right Now (With My Bags and Bank) — Enhanced logging
-- Off by default (Settings > "Enhanced logging"). When on, records what the
-- addon does into a bounded ring buffer in SavedVariables
-- (ICantEvenRightNowDB.debugLog), so a problem can be diagnosed after a
-- reload or from the saved file without the game running.
-- Keep calls out of per-frame and per-item hot loops: log summaries.

local ADDON_NAME, ns = ...

local P = ns.Private

local MAX_LINES = 2000
P.LOG_MAX_LINES = MAX_LINES

function P.IsLogging()
    return ns.DB ~= nil and ns.DB.ui ~= nil and ns.DB.ui.enhancedLogging == true
end

local function Buffer()
    local log = ns.DB.debugLog
    if type(log) ~= "table" or type(log.lines) ~= "table" then
        log = { lines = {}, nextIndex = 1, count = 0 }
        ns.DB.debugLog = log
    end
    return log
end

local function Stringify(value)
    if value == nil then return "nil" end
    if type(value) == "boolean" then return value and "true" or "false" end
    return tostring(value)
end

-- P.Log("scan", "bags: %d stacks", n). Formatting runs only when logging is on.
function P.Log(category, message, ...)
    if not P.IsLogging() then return end
    local text
    if select("#", ...) > 0 then
        local args = {}
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            args[i] = (type(v) == "number") and v or Stringify(v)
        end
        local ok, formatted = pcall(string.format, message, unpack(args, 1, select("#", ...)))
        text = ok and formatted or (Stringify(message) .. " " .. table.concat(args, " "))
    else
        text = Stringify(message)
    end
    local log = Buffer()
    local stamp = date("%Y-%m-%d %H:%M:%S")
    log.lines[log.nextIndex] = stamp .. " [" .. Stringify(category) .. "] " .. text
    log.nextIndex = log.nextIndex % MAX_LINES + 1
    log.count = math.min((log.count or 0) + 1, MAX_LINES)
end

-- Lines oldest first; `limit` keeps only the newest ones.
function P.GetLogLines(limit)
    local log = ns.DB and ns.DB.debugLog
    if type(log) ~= "table" or type(log.lines) ~= "table" or (log.count or 0) == 0 then return {} end
    local count = log.count
    local first = (count < MAX_LINES) and 1 or log.nextIndex
    local lines = {}
    for i = 0, count - 1 do
        local line = log.lines[(first - 1 + i) % MAX_LINES + 1]
        if line then lines[#lines + 1] = line end
    end
    if limit and #lines > limit then
        local newest = {}
        for i = #lines - limit + 1, #lines do newest[#newest + 1] = lines[i] end
        return newest
    end
    return lines
end

function P.ClearLog()
    if ns.DB then ns.DB.debugLog = { lines = {}, nextIndex = 1, count = 0 } end
end

function P.SetLogging(enabled)
    if not ns.DB then return end
    if not enabled then P.Log("log", "enhanced logging off") end
    ns.DB.ui.enhancedLogging = enabled and true or false
    if enabled then
        P.Log("log", "enhanced logging on (%s %s, client %s)", ADDON_NAME,
            C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?",
            GetBuildInfo and (GetBuildInfo()) or "?")
    end
end
