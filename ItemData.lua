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

P.ItemVariantKey = VariantKey

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
    -- Collected if either check says so. In game each one answered "not
    -- collected" for an item the player had collected: the link check for
    -- all five worn Relentless Rider's pieces (their source said collected),
    -- and the source found by item ID can be another variant's (Steelbark
    -- Casque, where the link check was right).
    local ok, has = pcall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, entry[1])
    if ok and has then return true, state end
    if item.link and C_TransmogCollection.PlayerHasTransmogByItemInfo then
        local okLink, hasLink = pcall(C_TransmogCollection.PlayerHasTransmogByItemInfo, item.link)
        if okLink and hasLink then return true, state end
    end
    return false, state
end

-- ---------------------------------------------------------------------------
-- Sets and upgrade tracks
-- Checked in game 2026-09-26: GetItemInfo's 16th value is the item set ID
-- (ask by item ID; link lookups can come back empty). The tooltip carries the
-- set name with pieces worn "(0/5)", each bonus "(2) Set: ...", the class
-- restriction "Classes: Death Knight" (class sets), and "Upgrade Level:
-- Hero 2/6" only when the item has an upgrade track.
-- ---------------------------------------------------------------------------

local setIDs = {}       -- [itemID] = setID or false
local factsCache = {}   -- [VariantKey] = facts

-- The item's set ID, or nil (not in a set, or not loaded yet).
function P.ItemSetID(item)
    if not item or not item.itemID or not (C_Item and C_Item.GetItemInfo) then return nil end
    local cached = setIDs[item.itemID]
    if cached ~= nil then return cached or nil end
    local info = { pcall(C_Item.GetItemInfo, item.itemID) }
    if not info[1] or info[2] == nil then return nil end
    local setID = info[17]
    setIDs[item.itemID] = setID or false
    return setID
end

-- A Lua pattern from a localized format string ("Upgrade Level: %s %d/%d").
local function FormatPattern(fmt, fallback)
    if type(fmt) ~= "string" or fmt == "" then return fallback end
    local pattern = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    pattern = pattern:gsub("%%s", "(.+)")
    pattern = pattern:gsub("%%d", "(%%d+)")
    return "^" .. pattern .. "$"
end

local UPGRADE_PATTERN = FormatPattern(ITEM_UPGRADE_TOOLTIP_FORMAT_STRING, "^Upgrade Level: (.+) (%d+)/(%d+)$")
local CLASSES_PATTERN = FormatPattern(ITEM_CLASSES_ALLOWED, "^Classes: (.+)$")
local SET_NAME_PATTERN = "^(.+) %((%d+)/(%d+)%)$"
local SET_BONUS_PATTERN = "^%((%d+)%) "
-- Active bonuses read "Set: ..." with no count (ITEM_SET_BONUS "Set: %s");
-- inactive ones "(4) Set: ..." (ITEM_SET_BONUS_GRAY). Seen in game 2026-09-26.
local ACTIVE_BONUS_PREFIX = (type(ITEM_SET_BONUS) == "string" and ITEM_SET_BONUS:match("^(.-)%%s")) or "Set: "
local KNOWN_LINE = (type(ITEM_SPELL_KNOWN) == "string" and ITEM_SPELL_KNOWN) or "Already known"

-- What the tooltip says about sets and upgrades:
-- { state, setName, setTotal, setMin (lowest inactive bonus), activeBonuses, classes,
--   upgradeTrack, upgradeCur, upgradeMax, upgradable, known ("Already known": a learned recipe) }.
-- state "ready", "loading" (tooltip reads "Retrieving item information"), or "unknown".
function P.ItemTooltipFacts(item)
    -- "unknown": no tooltip to read. Never taken as "can't be upgraded".
    if not item or not item.itemID then return { state = "unknown" } end
    local key = VariantKey(item)
    if factsCache[key] then return factsCache[key] end
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) or type(item.link) ~= "string" then
        return { state = "unknown" }
    end
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, item.link)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return { state = "unknown" } end
    local first = data.lines[1] and data.lines[1].leftText
    if first == (RETRIEVING_ITEM_INFO or "Retrieving item information") then
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, item.itemID) end
        return { state = "loading" }
    end
    local facts = { state = "ready", activeBonuses = 0 }
    local bonusCounts = {}
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" then
            local track, cur, max = text:match(UPGRADE_PATTERN)
            if track then
                facts.upgradeTrack, facts.upgradeCur, facts.upgradeMax = track, tonumber(cur), tonumber(max)
            end
            local classes = text:match(CLASSES_PATTERN)
            if classes then facts.classes = classes end
            if text == KNOWN_LINE then facts.known = true end
            -- "26 Slot Reagent Bag", "30 Slot Bag": a container's size.
            local slots = text:match("^(%d+) Slot")
            if slots and not facts.containerSlots then facts.containerSlots = tonumber(slots) end
            if not facts.setName then
                local name, _, total = text:match(SET_NAME_PATTERN)
                if name and tonumber(total) and tonumber(total) >= 2 then
                    facts.setName, facts.setTotal = name, tonumber(total)
                end
            end
            local count = text:match(SET_BONUS_PATTERN)
            if count and text:find("Set", 1, true) then bonusCounts[#bonusCounts + 1] = tonumber(count) end
            if text:sub(1, #ACTIVE_BONUS_PREFIX) == ACTIVE_BONUS_PREFIX then
                facts.activeBonuses = facts.activeBonuses + 1
            end
        end
    end
    table.sort(bonusCounts)
    facts.setMin = bonusCounts[1]
    facts.upgradable = (facts.upgradeCur and facts.upgradeMax and facts.upgradeCur < facts.upgradeMax) or false
    factsCache[key] = facts
    return facts
end

-- The item's Use effect (spell name), or nil. Cached per item ID.
local useSpells = {}
function P.ItemUseSpell(item)
    if not item or not item.itemID or not (C_Item and C_Item.GetItemSpell) then return nil end
    local cached = useSpells[item.itemID]
    if cached ~= nil then return cached or nil end
    local ok, name = pcall(C_Item.GetItemSpell, item.itemID)
    if not ok then return nil end
    if name == nil and P.ItemDataState(item) ~= "ready" then return nil end   -- ask again once loaded
    useSpells[item.itemID] = name or false
    return name
end

-- The pet journal fills in after login: until then GetNumCollectedInfo says
-- 0 for every species. In game a learned pet (Slim) read "not learned yet"
-- after each reload and flipped to "Can go" on the next scan. Ready once the
-- journal reports owned pets or PET_JOURNAL_LIST_UPDATE fires.
local petJournalLoaded = false
function P.PetJournalReady()
    if petJournalLoaded then return true end
    if not (C_PetJournal and C_PetJournal.GetNumPets) then return true end
    local ok, _, owned = pcall(C_PetJournal.GetNumPets)
    if ok and owned and owned > 0 then petJournalLoaded = true end
    return petJournalLoaded
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
    frame:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
    frame:SetScript("OnEvent", function(_, event, itemID, success)
        if event == "PET_JOURNAL_LIST_UPDATE" then
            if not petJournalLoaded then
                petJournalLoaded = true
                P.Log("itemdata", "pet journal loaded")
                -- After settling this is late data (flagged, not applied).
                if P.NoteLateData then P.NoteLateData() end
            end
            return
        end
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


-- ---------------------------------------------------------------------------
-- Housing: what the House Chest says about a decor item.
-- Returns nil when the API is missing or the item isn't a catalog entry;
-- otherwise { stored, placed, firstBonus, chestTotal, chestMax, chestFull }.
-- C_HousingCatalog.GetCatalogEntryInfoByItem takes one argument since 12.0.5.
-- ---------------------------------------------------------------------------
local houseCache = {}
function P.InvalidateHousingCache() houseCache = {} end
function P.HousingEntry(item)
    if not (item and item.itemID and C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem) then return nil end
    local cached = houseCache[item.itemID]
    if cached ~= nil then return cached or nil end
    local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByItem, item.itemID)
    if not ok or type(info) ~= "table" then houseCache[item.itemID] = false return nil end
    local entry = {
        stored = info.totalNumStored or 0,
        placed = info.totalNumPlaced or 0,
        firstBonus = info.firstAcquisitionBonus or 0,
    }
    if C_HousingCatalog.GetDecorTotalOwnedCount and C_HousingCatalog.GetDecorMaxOwnedCount then
        local okTotal, total = pcall(C_HousingCatalog.GetDecorTotalOwnedCount)
        local okMax, max = pcall(C_HousingCatalog.GetDecorMaxOwnedCount)
        if okTotal and okMax and type(total) == "number" and type(max) == "number" then
            entry.chestTotal, entry.chestMax = total, max
            entry.chestFull = max > 0 and total >= max
        end
    end
    houseCache[item.itemID] = entry
    return entry
end
