-- I Can't Even Right Now (With My Bags and Bank) — Value Awareness
-- Auction prices from Auctionator or TSM when installed, or from a paced
-- lookup of the player's own items at the auction house. Every price carries
-- its source and age. Prices are advice only: nothing is ever posted or bought.
--
-- APIs verified 2026-09-25 (see .local/docs/WoW_API_Notes.md):
--   Auctionator.API.v1.GetAuctionPriceByItemLink/ID(callerID, x), GetAuctionAgeBy...
--   TSM_API.GetCustomPriceValue(priceString, itemString), TSM_API.ToItemString(link)
--   C_AuctionHouse.SendSearchQuery / Get(Commodity|Item)SearchResultInfo,
--   IsThrottledMessageSystemReady; 5% auction cut.

local ADDON_NAME, ns = ...

local Core = ns.Core
local P    = ns.Private

local UI = P.UI
local CALLER_ID = "ICantEvenRightNow"
local AUCTION_CUT = 0.05
local DAY = 24 * 3600

local DEFAULT_FRESH_DAYS = { commodity = 3, item = 7 }
local DEFAULT_MIN_GAIN = 5 * 10000          -- 5 gold over the vendor price
local LOOKUP_INTERVAL = 0.35                -- seconds between own lookups

local function Now() return time and time() or 0 end

local function Settings()
    local ui = ns.DB.ui
    ui.priceFreshDays = ui.priceFreshDays or {}
    return {
        freshCommodity = ui.priceFreshDays.commodity or DEFAULT_FRESH_DAYS.commodity,
        freshItem = ui.priceFreshDays.item or DEFAULT_FRESH_DAYS.item,
        minGain = ui.minAuctionGain or DEFAULT_MIN_GAIN,
    }
end

local function IsCommodity(item)
    return (item.maxStack or 1) > 1
end

local function Prices()
    ns.DB.prices = ns.DB.prices or {}
    return ns.DB.prices
end

-- Commodity prices are region-wide (shared by every character); other items
-- are per realm.
local function PriceKey(item)
    if IsCommodity(item) then return "c:" .. tostring(item.itemID) end
    local realm = GetRealmName and GetRealmName() or "?"
    return "i:" .. tostring(item.itemID) .. ":" .. realm
end

-- ---------------------------------------------------------------------------
-- Sources
-- ---------------------------------------------------------------------------

local function AuctionatorPrice(item)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not api then return nil end
    local price, age
    if item.link and api.GetAuctionPriceByItemLink then
        local ok, value = pcall(api.GetAuctionPriceByItemLink, CALLER_ID, item.link)
        if ok then price = value end
        if api.GetAuctionAgeByItemLink then
            local okAge, days = pcall(api.GetAuctionAgeByItemLink, CALLER_ID, item.link)
            if okAge then age = days end
        end
    end
    if not price and api.GetAuctionPriceByItemID then
        local ok, value = pcall(api.GetAuctionPriceByItemID, CALLER_ID, item.itemID)
        if ok then price = value end
        if api.GetAuctionAgeByItemID then
            local okAge, days = pcall(api.GetAuctionAgeByItemID, CALLER_ID, item.itemID)
            if okAge then age = days end
        end
    end
    if type(price) ~= "number" or price <= 0 then return nil end
    -- For gear, Auctionator may only know the base item, not this item level.
    local exact
    if (item.classID == 2 or item.classID == 4) and item.link and api.IsAuctionDataExactByItemLink then
        local okExact, value = pcall(api.IsAuctionDataExactByItemLink, CALLER_ID, item.link)
        if okExact and value ~= nil then exact = value and true or false end
    end
    return { price = price, source = "Auctionator", ageDays = age, exact = exact }
end

local function TSMPrice(item)
    if not (TSM_API and TSM_API.GetCustomPriceValue and TSM_API.ToItemString) then return nil end
    local ok, itemString = pcall(TSM_API.ToItemString, item.link or ("i:" .. tostring(item.itemID)))
    if not ok or not itemString then return nil end
    for _, source in ipairs({ "DBMarket", "DBRegionMarketAvg", "DBMinBuyout" }) do
        local okPrice, value = pcall(TSM_API.GetCustomPriceValue, source, itemString)
        if okPrice and type(value) == "number" and value > 0 then
            local okRate, rate = pcall(TSM_API.GetCustomPriceValue, "DBRegionSaleRate", itemString)
            return { price = value, source = "TSM", ageDays = nil, saleRate = okRate and rate or nil }
        end
    end
    return nil
end

local function StoredPrice(item)
    local entry = Prices()[PriceKey(item)]
    if not entry then return nil end
    return { price = entry.price, source = "your scan", ageDays = (Now() - (entry.at or 0)) / DAY }
end

function P.HasPriceSource()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return (api ~= nil) or (TSM_API ~= nil and TSM_API.GetCustomPriceValue ~= nil) or next(Prices()) ~= nil
end

-- Best available auction price for an item: { price, source, ageDays, fresh }.
local function GetAuctionPrice(item)
    if not item or not item.itemID then return nil end
    local result = AuctionatorPrice(item) or TSMPrice(item) or StoredPrice(item)
    if not result then return nil end
    local settings = Settings()
    local limit = IsCommodity(item) and settings.freshCommodity or settings.freshItem
    result.fresh = result.ageDays == nil or result.ageDays <= limit
    return result
end
P.GetAuctionPrice = GetAuctionPrice

local function FormatAge(days)
    if not days then return nil end
    if days < 1 then return "today" end
    local whole = math.floor(days + 0.5)
    return whole .. " day" .. (whole == 1 and "" or "s")
end

function P.FormatPriceSource(price)
    if not price then return "" end
    local age = FormatAge(price.ageDays)
    return price.source .. (age and (", " .. age) or "") .. (price.exact == false and ", approximate" or "")
        .. (price.fresh and "" or ", stale")
end

-- ---------------------------------------------------------------------------
-- Decisions
-- ---------------------------------------------------------------------------

local function CanBeAuctioned(item)
    if item.isBound or item.isSoulbound or item.isWarbandBound then return false end
    if item.classID == 12 or item.questID then return false end
    return true
end
P.CanBeAuctioned = CanBeAuctioned

-- Net auction proceeds for the whole stack (after the 5% cut), or nil.
local function AuctionNet(item)
    if not CanBeAuctioned(item) then return nil end
    local price = GetAuctionPrice(item)
    if not price then return nil end
    return math.floor(price.price * (item.count or 1) * (1 - AUCTION_CUT)), price
end

-- Returns "auction" | "vendor" | nil, reason text.
function P.AuctionAdvice(item)
    local net, price = AuctionNet(item)
    if not net then return nil end
    local vendor = (item.sellPrice or 0) * (item.count or 1)
    local gain = net - vendor
    if gain >= Settings().minGain then
        local slow = price.saleRate and price.saleRate > 0 and price.saleRate < 0.02
        return "auction", "About " .. P.FormatMoney(net) .. " after the auction cut vs "
            .. P.FormatMoney(vendor) .. " at a vendor (" .. P.FormatPriceSource(price) .. ")"
            .. (slow and "; rarely sells" or "")
    end
    return "vendor", "Auction gain under " .. P.FormatMoney(Settings().minGain)
end

-- Vendor protection (V3): true when selling to a vendor would give up a
-- meaningful auction price. Uses stale prices too: better to warn than lose value.
function P.IsValueFlagged(item, dest)
    if dest ~= "Vendor" then return false end
    return (P.AuctionAdvice(item)) == "auction"
end

-- Best value of an item for reports: auction (net) when it beats vendor.
function P.GetItemValue(item)
    local vendor = (item.sellPrice or 0) * (item.count or 1)
    local net = AuctionNet(item)
    if net and net > vendor then return net, "auction" end
    return vendor, "vendor"
end

-- Disenchant estimate from Auctionator or TSM, or nil.
function P.GetDisenchantValue(item)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and item.link and api.GetDisenchantPriceByItemLink then
        local ok, value = pcall(api.GetDisenchantPriceByItemLink, CALLER_ID, item.link)
        if ok and type(value) == "number" and value > 0 then return value end
    end
    if TSM_API and TSM_API.GetCustomPriceValue and TSM_API.ToItemString then
        local okString, itemString = pcall(TSM_API.ToItemString, item.link or ("i:" .. tostring(item.itemID)))
        if okString and itemString then
            local ok, value = pcall(TSM_API.GetCustomPriceValue, "Destroy", itemString)
            if ok and type(value) == "number" and value > 0 then return value end
        end
    end
    return nil
end

-- A character whose role receives materials and who has Enchanting.
function P.FindEnchanter()
    for _, char in ipairs(P.CharactersWith("receivesMaterials")) do
        for _, prof in ipairs(char.professions or {}) do
            if prof.skillLine == 333 then return char end
        end
    end
    return nil
end

-- How many of this item the account holds across all snapshots.
function P.CountAcrossAccount(itemID)
    local total, places = 0, {}
    for _, snapshot in ipairs(P.AllSnapshots()) do
        local here = 0
        for _, item in ipairs(snapshot.items) do
            if item.itemID == itemID then here = here + (item.count or 1) end
        end
        if here > 0 then
            total = total + here
            local label = snapshot.scope == "warband" and "Warband bank"
                or ((snapshot.character and snapshot.character.name or "?") .. " " .. snapshot.scope)
            table.insert(places, { label = label, count = here, scannedAt = snapshot.scannedAt })
        end
    end
    return total, places
end

-- Tooltip lines about value for a scanned item.
function P.ValueTooltipLines(item)
    local lines = {}
    local price = GetAuctionPrice(item)
    if price and CanBeAuctioned(item) then
        table.insert(lines, "Auction: ~" .. P.FormatMoney(price.price * (item.count or 1)) .. " (" .. P.FormatPriceSource(price) .. ")")
        local advice, reason = P.AuctionAdvice(item)
        if advice == "auction" then table.insert(lines, "Better at auction: " .. reason) end
    end
    local disenchant = P.GetDisenchantValue(item)
    if disenchant and (item.classID == 2 or item.classID == 4) then
        local enchanter = P.FindEnchanter()
        table.insert(lines, "Disenchant: ~" .. P.FormatMoney(disenchant)
            .. (enchanter and (" (" .. enchanter.name .. ", Enchanter)") or ""))
    end
    local total, places = P.CountAcrossAccount(item.itemID)
    if #places > 1 then
        local parts = {}
        for _, place in ipairs(places) do parts[#parts + 1] = place.label .. " " .. place.count end
        table.insert(lines, "On your account: " .. total .. " (" .. table.concat(parts, ", ") .. ")")
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- Own lookup at the auction house ("Price my items")
-- ---------------------------------------------------------------------------

local lookup = { queue = {}, active = false, done = 0, total = 0, pending = nil }
P.PriceLookupState = lookup

-- Tradeable items the player owns (current character + Warband) needing a price.
local function ItemsNeedingPrices()
    local seen, list = {}, {}
    for _, scope in ipairs({ P.BAG_SCOPE, P.BANK_SCOPE }) do
        for _, item in ipairs(P.GetScanList(scope)) do
            if item.itemID and not seen[item.itemID] and CanBeAuctioned(item) then
                local price = GetAuctionPrice(item)
                if not price or not price.fresh then
                    seen[item.itemID] = true
                    table.insert(list, item)
                end
            end
        end
    end
    return list
end
P.ItemsNeedingPrices = ItemsNeedingPrices

local function FinishLookup()
    lookup.active = false
    lookup.pending = nil
    UI.inventoryStatus = "Priced " .. lookup.done .. " item" .. (lookup.done == 1 and "" or "s")
    if UI.frame and UI.frame:IsShown() then Core.RefreshUI() end
end

local function NextLookup()
    if not lookup.active then return end
    if not ns.DB.context.auctionHouseOpen then FinishLookup() return end
    local item = table.remove(lookup.queue, 1)
    if not item then FinishLookup() return end
    local ready = not C_AuctionHouse.IsThrottledMessageSystemReady or C_AuctionHouse.IsThrottledMessageSystemReady()
    if not ready then
        table.insert(lookup.queue, 1, item)
        C_Timer.After(LOOKUP_INTERVAL, NextLookup)
        return
    end
    lookup.pending = item
    local key = C_AuctionHouse.MakeItemKey(item.itemID)
    local sorts = {}
    if Enum and Enum.AuctionHouseSortOrder then
        sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    end
    local ok = pcall(C_AuctionHouse.SendSearchQuery, key, sorts, false)
    if not ok then
        lookup.pending = nil
        C_Timer.After(LOOKUP_INTERVAL, NextLookup)
    end
end

local function RecordResult(itemID, unitPrice)
    local item = lookup.pending
    if not item or item.itemID ~= itemID then return end
    lookup.pending = nil
    lookup.done = lookup.done + 1
    if type(unitPrice) == "number" and unitPrice > 0 then
        Prices()[PriceKey(item)] = { price = unitPrice, at = Now() }
    end
    C_Timer.After(LOOKUP_INTERVAL, NextLookup)
end

-- Starts a paced lookup; must be called from a click while at the auction house.
function P.StartPriceLookup()
    if not ns.DB.context.auctionHouseOpen then
        P.Print("Visit an auction house to look up prices.")
        return false
    end
    lookup.queue = ItemsNeedingPrices()
    lookup.total = #lookup.queue
    lookup.done = 0
    lookup.active = lookup.total > 0
    if lookup.active then
        UI.inventoryStatus = "Looking up " .. lookup.total .. " prices..."
        NextLookup()
    end
    return lookup.active
end

function P.OnAuctionEvent(event, arg)
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local info = C_AuctionHouse.GetCommoditySearchResultInfo(arg, 1)
        RecordResult(arg, info and info.unitPrice)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local itemKey = arg
        local info = itemKey and C_AuctionHouse.GetItemSearchResultInfo(itemKey, 1)
        RecordResult(itemKey and itemKey.itemID, info and info.buyoutAmount)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if lookup.active then FinishLookup() end
    end
end

-- ---------------------------------------------------------------------------
-- Auctionator hand-offs (searches and shopping lists; Auctionator has no
-- posting API, so posting stays in its Selling tab)
-- ---------------------------------------------------------------------------

local SHOPPING_LIST_NAME = "I Can't Even: Auction Candidates"
P.AUCTIONATOR_LIST_NAME = SHOPPING_LIST_NAME

local function AuctionatorAPI()
    return Auctionator and Auctionator.API and Auctionator.API.v1 or nil
end

function P.HasAuctionator()
    local api = AuctionatorAPI()
    return api ~= nil and api.MultiSearchExact ~= nil
end

-- Auctionator rejects terms containing ; or ^ or wrapped in quotes.
local function CleanName(name)
    return (tostring(name or ""):gsub('[;^"]', ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function UniqueNames(items)
    local seen, names = {}, {}
    for _, item in ipairs(items) do
        local name = CleanName(item.name)
        if name ~= "" and not name:match("^Item %d+$") and not seen[name] then
            seen[name] = true
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

-- Auction candidates this character holds (bags, character bank, Warband bank).
function P.AuctionCandidateItems()
    local list, seen = {}, {}
    for _, scope in ipairs({ P.BAG_SCOPE, P.BANK_SCOPE }) do
        for _, item in ipairs(P.GetScanList(scope)) do
            if item.itemID and not seen[item.itemID] and (P.AuctionAdvice(item)) == "auction" then
                seen[item.itemID] = true
                table.insert(list, item)
            end
        end
    end
    return list
end

-- At the auction house: run an exact search for every name in Auctionator's
-- Shopping tab. Elsewhere: save them as a shopping list for next time.
local function SendToAuctionator(items, listName)
    local api = AuctionatorAPI()
    if not api then return false, "Auctionator is not installed." end
    local names = UniqueNames(items)
    if #names == 0 then return false, "Nothing to check." end
    if ns.DB.context.auctionHouseOpen and api.MultiSearchExact then
        local ok, err = pcall(api.MultiSearchExact, CALLER_ID, names)
        if not ok then return false, "Auctionator search failed: " .. tostring(err) end
        return true, "Searching " .. #names .. " item" .. (#names == 1 and "" or "s") .. " in Auctionator's Shopping tab."
    end
    if not (api.CreateShoppingList and api.ConvertToSearchString) then
        return false, "This Auctionator version can't create shopping lists."
    end
    local searchStrings = {}
    for _, name in ipairs(names) do
        local ok, term = pcall(api.ConvertToSearchString, CALLER_ID, { searchString = name, isExact = true })
        if ok and term then table.insert(searchStrings, term) end
    end
    local ok, err = pcall(api.CreateShoppingList, CALLER_ID, listName, searchStrings)
    if not ok then return false, "Could not save the shopping list: " .. tostring(err) end
    return true, "Saved " .. #searchStrings .. " item" .. (#searchStrings == 1 and "" or "s")
        .. " to the Auctionator shopping list \"" .. listName .. "\"."
end
P.SendToAuctionator = SendToAuctionator

function P.CheckCandidatesInAuctionator()
    local ok, message = SendToAuctionator(P.AuctionCandidateItems(), SHOPPING_LIST_NAME)
    P.Print(message)
    return ok
end

-- With Auctionator installed, price checks are handed to it instead of the
-- addon's own paced lookup.
function P.CheckPricesInAuctionator()
    local ok, message = SendToAuctionator(ItemsNeedingPrices(), SHOPPING_LIST_NAME)
    P.Print(message)
    return ok
end

-- ---------------------------------------------------------------------------
-- Tasks and notices
-- ---------------------------------------------------------------------------

function P.RegisterValueTasks()
    if not P.RegisterTask then return end
    P.RegisterTask({
        name = "Auction Candidates",
        description = "Items worth noticeably more at auction than at a vendor, into your bags for posting.",
        preset = { name = "Auction Candidates", source = P.STORAGE_ALL_BANK_TABS, dest = "Bags",
            expansion = 0, bind = "All", type = "All", slot = "All", armorType = "All", upgrade = "All",
            hideBlocked = true, sort = "Vendor Value" },
        predicate = function(item) return (P.AuctionAdvice(item)) == "auction" end,
        isAvailable = function() return P.HasPriceSource() end,
        secondary = {
            label = function()
                return ns.DB.context.auctionHouseOpen and "Check in Auctionator" or "Save to Auctionator"
            end,
            isAvailable = function() return P.HasAuctionator() and #P.AuctionCandidateItems() > 0 end,
            run = function() P.CheckCandidatesInAuctionator() end,
        },
    })
    P.RegisterTask({
        name = "Price My Items",
        description = "Look up auction prices for the items you own (only your items, paced).",
        isAvailable = function() return ns.DB.context.auctionHouseOpen and not P.HasAuctionator() end,
        count = function()
            local count = #ItemsNeedingPrices()
            return count, nil, 0
        end,
        open = function() P.StartPriceLookup() end,
    })
    P.RegisterTask({
        name = "Check Prices in Auctionator",
        description = "Search Auctionator for your items that have no recent price.",
        isAvailable = function() return ns.DB.context.auctionHouseOpen and P.HasAuctionator() end,
        count = function()
            local count = #ItemsNeedingPrices()
            return count, nil, 0
        end,
        open = function() P.CheckPricesInAuctionator() end,
    })
end

-- Stale-price and no-source notices on Home (V2).
P.RegisterHomeNotice(function()
    if not P.HasPriceSource() then
        if ns.DB.ui.priceSourceHintDismissed then return nil end
        return {
            id = "prices", priority = 80,
            text = "Want auction values? Install Auctionator, or visit an auction house and use \"Price My Items\".",
            buttons = { { label = "Got it", onClick = function()
                ns.DB.ui.priceSourceHintDismissed = true
                Core.RefreshUI()
            end } },
        }
    end
    local oldest
    for _, entry in pairs(Prices()) do
        if not oldest or (entry.at or 0) < oldest then oldest = entry.at or 0 end
    end
    local hasAddonSource = (Auctionator and Auctionator.API) or TSM_API
    if oldest and not hasAddonSource then
        local days = math.floor((Now() - oldest) / DAY)
        if days > Settings().freshItem then
            return {
                id = "stale-prices", priority = 60,
                text = "Your auction prices are " .. days .. " days old. Visit an auction house to refresh them.",
                buttons = {},
            }
        end
    end
    return nil
end)

P.RegisterValueTasks()
