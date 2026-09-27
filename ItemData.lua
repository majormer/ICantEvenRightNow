-- I Can't Even Right Now (With My Bags and Bank) — Item data
-- One place that asks the game for item details and says whether they're in.
-- Everything that judges items (stats, appearance) reads through here, and
-- Readiness.lua uses the same states to decide when results are complete.
--
-- How the client behaves (warcraft.wiki.gg, checked 2026-09-26):
-- - Item details load on demand: request them (C_Item.RequestLoadItemDataByID)
--   and wait for ITEM_DATA_LOAD_RESULT / GET_ITEM_INFO_RECEIVED (itemID, success).
-- - success false is temporary; nil (GET_ITEM_INFO_RECEIVED) means no such item.
-- - Some old items never answer, so every wait has a limit (like
--   ItemMixin:ContinueWithCancelOnItemLoad with a timeout).
-- - Stats and appearance are only trustworthy once the item is cached.
--
-- States: "ready", "loading" (asked, waiting), "failed" (gave up after
-- LOAD_LIMIT seconds; retried by Rescan or when the data turns up), "missing"
-- (the game says the item doesn't exist).

local ADDON_NAME, ns = ...

local P = ns.Private

local LOAD_LIMIT = 8

-- [itemID] = { since, state = "loading"|"failed"|"missing", what = "item"|"stats", name }
local records = {}
-- [itemID] = { [link] = stats table }
local statsCache = {}
-- [itemID] = { [link] = sourceID or false (no appearance) }
local appearanceCache = {}
-- Items read successfully this session. Details never go stale, and in game
-- C_Item.IsItemDataCachedByID flipped back to false for ~70 gear items a few
-- seconds after they were read (2026-09-26), which made them "loading" again.
local known = {}

local function Now() return GetTime and GetTime() or 0 end

-- Cache key for one item variant: item ID plus bonus IDs (what decides its
-- stats and appearance). Other link fields change on their own: the name text
-- goes blank when the client drops the item, and modifier values differed
-- between two reads of the same item in game, so whole-link keys kept missing.
-- Item string: item:ID:enchant:gem1:gem2:gem3:gem4:suffix:unique:level:spec:
-- upgradeType:difficulty:numBonusIDs:bonus1:...
local function VariantKey(item)
    local link = item.link
    local itemString = type(link) == "string" and link:match("item:[%-%d:]+")
    if not itemString then return tostring(item.itemID) end
    local fields = {}
    for field in (itemString .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
    local key = { tostring(item.itemID) }
    local numBonus = tonumber(fields[14]) or 0
    for i = 1, numBonus do key[#key + 1] = fields[14 + i] or "" end
    return table.concat(key, ":")
end

local function IsCached(itemID)
    if not (C_Item and C_Item.IsItemDataCachedByID) then return true end
    return C_Item.IsItemDataCachedByID(itemID) and true or false
end

local function Invalidate(itemID)
    statsCache[itemID] = nil
    appearanceCache[itemID] = nil
end

-- The data for an item arrived: forget the wait and anything read while it
-- was missing. After the addon settled this is flagged, not shown (Readiness).
local function Resolved(itemID)
    local rec = records[itemID]
    if not rec then return end
    records[itemID] = nil
    Invalidate(itemID)
    if rec.state == "failed" then
        P.Log("itemdata", "%s (%s) loaded after giving up", tostring(rec.name), tostring(itemID))
    end
    if P.NoteLateData then P.NoteLateData() end
end

-- Wait for `what` ("item" or "stats"): "loading" until LOAD_LIMIT, then "failed".
local function Wait(item, what)
    local itemID = item.itemID
    local rec = records[itemID]
    if not rec or rec.what ~= what then
        rec = { since = Now(), state = "loading", what = what, name = item.name }
        records[itemID] = rec
        if known[itemID] then
            -- Read before, now waiting again: worth knowing why (link shape).
            P.Log("itemdata", "waiting again for the %s of %s (%s), key %s",
                what, tostring(item.name), tostring(itemID), VariantKey(item))
        end
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    end
    if rec.state == "loading" and Now() - rec.since >= LOAD_LIMIT then
        rec.state = "failed"
        P.Log("itemdata", "gave up waiting for the %s of %s (%s) after %ds",
            what == "stats" and "stats" or "details", tostring(item.name), tostring(itemID), LOAD_LIMIT)
    end
    return rec.state
end

-- "ready", "loading", "failed" or "missing" for the item's basic details.
function P.ItemDataState(item)
    if not item or not item.itemID then return "ready" end
    local itemID = item.itemID
    local rec = records[itemID]
    if rec and rec.state == "missing" then return "missing" end
    if known[itemID] and not rec then return "ready" end
    if IsCached(itemID) then
        if rec and rec.what == "item" then Resolved(itemID) rec = nil end
        known[itemID] = true
        if not rec then return "ready" end
        return rec.state == "loading" and "ready" or rec.state
    end
    return Wait(item, "item")
end

-- The item's stat table, and its state. nil stats with "ready" = no stats.
function P.ItemStats(item)
    if not item or not item.itemID or not (C_Item and C_Item.GetItemStats) then return nil, "ready" end
    -- Only weapons and armor have stats worth waiting for (in game, waiting on
    -- ore and food flagged "details arrived late" for nothing).
    if item.classID ~= nil and item.classID ~= 2 and item.classID ~= 4 then return nil, "ready" end
    local itemID = item.itemID
    local link = item.link or ("item:" .. itemID)
    local key = VariantKey(item)
    local byLink = statsCache[itemID]
    if byLink and byLink[key] then return byLink[key], "ready" end
    local state = P.ItemDataState(item)
    if state == "loading" or state == "missing" then return nil, state end
    local ok, stats = pcall(C_Item.GetItemStats, link)
    if ok and type(stats) == "table" then
        known[itemID] = true
        statsCache[itemID] = byLink or {}
        statsCache[itemID][key] = stats
        if records[itemID] and records[itemID].what == "stats" then Resolved(itemID) end
        return stats, "ready"
    end
    -- Cached, but the stats aren't answered yet (the client can lag behind).
    return nil, Wait(item, "stats")
end

-- Appearance collected: true/false, or nil when the item has none; and the state.
function P.ItemAppearance(item)
    if not item or not item.itemID or not C_TransmogCollection then return nil, "ready" end
    local itemID = item.itemID
    local key = VariantKey(item)
    local byLink = appearanceCache[itemID]
    -- Cached: { sourceID, viaID } or false (no appearance).
    local entry = byLink and byLink[key]
    local state = "ready"
    if entry == nil then
        state = P.ItemDataState(item)
        if state == "loading" or state == "missing" then return nil, state end
        local ok, _, source = pcall(C_TransmogCollection.GetItemInfo, item.link or itemID)
        entry = ok and source and { source, false } or false
        if not entry and item.link then
            -- In game GetItemInfo(bag link) returned nothing for Steelbark
            -- Casque while GetItemInfo(itemID) gave its appearance, which the
            -- player had collected: the helm read "no appearance" and so
            -- "Your call" instead of "Can go". Ask by item ID too.
            local okID, _, sourceByID = pcall(C_TransmogCollection.GetItemInfo, itemID)
            entry = okID and sourceByID and { sourceByID, true } or false
        end
        if state == "ready" then
            appearanceCache[itemID] = byLink or {}
            appearanceCache[itemID][key] = entry
        end
    end
    if not entry then return nil, state end
    -- Found by item ID: the base item's source may not be this variant's, so
    -- ask with the link first (it accounts for bonus IDs).
    if entry[2] and item.link and C_TransmogCollection.PlayerHasTransmogByItemInfo then
        local ok, has = pcall(C_TransmogCollection.PlayerHasTransmogByItemInfo, item.link)
        if ok and has ~= nil then return has and true or false, state end
    end
    local ok, has = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, entry[1])
    return (ok and has) and true or false, state
end

-- Give up-and-retry: Rescan asks again for everything that failed.
function P.RetryFailedItemData()
    for itemID, rec in pairs(records) do
        if rec.state == "failed" then
            records[itemID] = nil
            Invalidate(itemID)
        end
    end
end

-- For diagnostics and tests.
function P.ItemDataWaits()
    local list = {}
    for itemID, rec in pairs(records) do
        list[#list + 1] = { itemID = itemID, name = rec.name, state = rec.state, what = rec.what }
    end
    return list
end

if CreateFrame then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    frame:SetScript("OnEvent", function(_, event, itemID, success)
        local rec = itemID and records[itemID]
        if not rec then return end
        if success then
            if rec.what == "item" then Resolved(itemID) end
        elseif success == nil and event == "GET_ITEM_INFO_RECEIVED" then
            rec.state = "missing"
            P.Log("itemdata", "the game has no item %s (%s)", tostring(itemID), tostring(rec.name))
        end
        -- success false: temporary; the wait limit applies.
    end)
end
