-- I Can't Even Right Now (With My Bags and Bank) — Transfer
-- Movement execution: block-reason checking, slot finding, plan building, execute actions.

local ADDON_NAME, ns = ...

local Core = ns.Core
local Data = ns.Data
local P    = ns.Private

local BAG_SCOPE  = P.BAG_SCOPE
local BANK_SCOPE = P.BANK_SCOPE

local STORAGE_PRIVATE_BANK   = P.STORAGE_PRIVATE_BANK
local STORAGE_REAGENT_BANK   = P.STORAGE_REAGENT_BANK
local STORAGE_WARBAND_BANK   = P.STORAGE_WARBAND_BANK
local STORAGE_ALL_BANK_TABS  = P.STORAGE_ALL_BANK_TABS
local BANK_TAB_PREFIX        = P.BANK_TAB_PREFIX
local VENDOR_ACTION_RECALL   = P.VENDOR_ACTION_RECALL
local VENDOR_ACTION_SELL     = P.VENDOR_ACTION_SELL

local NORMAL_BAG_IDS   = P.NORMAL_BAG_IDS
local PRIVATE_BANK_IDS = P.PRIVATE_BANK_IDS
local REAGENT_BANK_IDS = P.REAGENT_BANK_IDS
local WARBAND_BANK_IDS = P.WARBAND_BANK_IDS
local BANK_TAB_DATA    = P.BANK_TAB_DATA

local UI = P.UI

local GetStorageBagIDs       = P.GetStorageBagIDs
local GetStorageDisplayName  = P.GetStorageDisplayName
local IsBankContextDetected  = P.IsBankContextDetected
local Print                  = P.Print
local SlotKey                = P.SlotKey

local GetPreferredBankStorage       = P.GetPreferredBankStorage
local IsOldExpansion                = P.IsOldExpansion
local IsUnknownExpansion            = P.IsUnknownExpansion
local IsTransferableSharedValueItem = P.IsTransferableSharedValueItem
local GetAllDecisions               = P.GetAllDecisions
local EnsureRule                    = P.EnsureRule
local RemoveMovedItemsFromScan      = P.RemoveMovedItemsFromScan

local EnsureTabFilters          = P.EnsureTabFilters
local IsAllFilterValue          = P.IsAllFilterValue
local GetMultiSelectLabel       = P.GetMultiSelectLabel
local GetExpansionFilterLabel   = P.GetExpansionFilterLabel
local BuildFilterSummary        = P.BuildFilterSummary
local IsVendorSellable          = P.IsVendorSellable
local PlanMatchesTabFilters     = P.PlanMatchesTabFilters
local MatchesTabFilters         = P.MatchesTabFilters

local CContainer = C_Container

-- ===========================================================================
-- FindFreeSlot / FindFreeNormalBagSlot
-- Finds a target slot in the given bags. Tries stacking first. Never returns
-- the item's own slot, a locked slot, or a slot already claimed in takenSlots.
-- ===========================================================================

local function IsItemOwnSlot(item, bagID, slot)
    return item and item.bagID == bagID and item.slot == slot
end

local function FindFreeSlotInBags(bagIDs, takenSlots, item)
    if item and item.itemID and (item.maxStack or 1) > 1 then
        for _, bagID in ipairs(bagIDs) do
            local numSlots = CContainer.GetContainerNumSlots(bagID) or 0
            for slot = 1, numSlots do
                local key = SlotKey(bagID, slot)
                if not takenSlots[key] and not IsItemOwnSlot(item, bagID, slot)
                    and CContainer.GetContainerItemID(bagID, slot) == item.itemID then
                    local info = CContainer.GetContainerItemInfo(bagID, slot)
                    local stackCount = info and info.stackCount or 0
                    if info and not info.isLocked and stackCount < item.maxStack then
                        return bagID, slot, key
                    end
                end
            end
        end
    end

    for _, bagID in ipairs(bagIDs) do
        local numSlots = CContainer.GetContainerNumSlots(bagID) or 0
        for slot = 1, numSlots do
            local key = SlotKey(bagID, slot)
            if not takenSlots[key] and not CContainer.GetContainerItemID(bagID, slot) then
                return bagID, slot, key
            end
        end
    end
    return nil, nil, nil
end

-- Block-reason check only: is there room for this item in these bags?
-- An empty slot anywhere answers yes for every item, so that part is cached
-- per bag set for the current refresh; stacking is checked only when full.
local function HasRoomIn(bagIDs, item)
    local cache = P.evaluationCache
    local key = table.concat(bagIDs, ",")
    local hasEmpty = cache and cache.emptySlots and cache.emptySlots[key]
    if hasEmpty == nil then
        hasEmpty = false
        for _, bagID in ipairs(bagIDs) do
            local numSlots = CContainer.GetContainerNumSlots(bagID) or 0
            for slot = 1, numSlots do
                if not CContainer.GetContainerItemID(bagID, slot) then hasEmpty = true break end
            end
            if hasEmpty then break end
        end
        if cache then
            cache.emptySlots = cache.emptySlots or {}
            cache.emptySlots[key] = hasEmpty
        end
    end
    if hasEmpty then return true end
    if not item or (item.maxStack or 1) <= 1 then return false end
    if not cache then return FindFreeSlotInBags(bagIDs, {}, item) ~= nil end
    -- Full bags: one pass records which item IDs still have a partial,
    -- unlocked stack to join, instead of searching every slot per item.
    cache.partialStacks = cache.partialStacks or {}
    local partial = cache.partialStacks[key]
    if not partial then
        partial = {}
        for _, bagID in ipairs(bagIDs) do
            local numSlots = CContainer.GetContainerNumSlots(bagID) or 0
            for slot = 1, numSlots do
                local info = CContainer.GetContainerItemInfo(bagID, slot)
                local itemID = info and CContainer.GetContainerItemID(bagID, slot)
                if itemID and not info.isLocked then
                    partial[itemID] = partial[itemID] or {}
                    table.insert(partial[itemID], { bagID = bagID, slot = slot, count = info.stackCount or 0 })
                end
            end
        end
        cache.partialStacks[key] = partial
    end
    for _, stack in ipairs(partial[item.itemID] or {}) do
        if stack.count < item.maxStack and not IsItemOwnSlot(item, stack.bagID, stack.slot) then return true end
    end
    return false
end

local function FindFreeSlot(storageKind, takenSlots, item)
    return FindFreeSlotInBags(GetStorageBagIDs(storageKind), takenSlots, item)
end

P.FindFreeSlot = FindFreeSlot

local function FindFreeNormalBagSlot(takenSlots, item)
    return FindFreeSlotInBags(NORMAL_BAG_IDS, takenSlots, item)
end

P.FindFreeNormalBagSlot = FindFreeNormalBagSlot

-- ===========================================================================
-- IsSharedValueItem
-- ===========================================================================

local function IsSharedValueItem(item)
    if item.accountBankAllowed and (item.isWarbandBound or item.bindingScope == "Warbound" or item.bindingScope == "Warbound Until Equipped") then
        return true
    end
    if item.accountBankAllowed and item.typeTag == Data.ItemTypes.BOE then
        return true
    end
    if item.accountBankAllowed and IsOldExpansion(item.expansionID) and item.typeTag ~= Data.ItemTypes.EQUIPMENT then
        return true
    end
    if IsTransferableSharedValueItem(item) then
        return true
    end
    return false
end

P.IsSharedValueItem = IsSharedValueItem

-- ===========================================================================
-- Organization plans (bank-to-bank tier sorting)
-- ===========================================================================

local function BuildOrganizationPlan(item, charProfSubclasses)
    if item.scope ~= BANK_SCOPE then
        return nil
    end

    local currentStorage = item.storageKind or P.GetStorageKindForBagID(item.bagID, item.scope)
    local targetStorage = currentStorage
    local reason = "Already in the preferred bank tier"

    if item.rule and (item.rule.ignore or item.rule.protect) then
        reason = "Rule-protected item"
    elseif item.typeTag == Data.ItemTypes.SEASONAL or item.typeTag == Data.ItemTypes.QUEST then
        targetStorage = STORAGE_PRIVATE_BANK
        reason = "Character/session item belongs in private storage"
    elseif item.isSoulbound or item.bindingScope == "Soulbound" or item.bindingScope == "Quest" then
        targetStorage = STORAGE_PRIVATE_BANK
        reason = "Soulbound or character-bound item"
    elseif item.typeTag == Data.ItemTypes.PROFESSION then
        targetStorage, reason = GetPreferredBankStorage(item, item.typeTag, charProfSubclasses)
        if currentStorage == targetStorage then
            reason = "Already in the preferred bank tier"
        end
    elseif IsSharedValueItem(item) then
        targetStorage = STORAGE_WARBAND_BANK
        if item.typeTag == Data.ItemTypes.BOE then
            reason = "BoE equipment can be shared through Warband storage"
        elseif item.bindingScope == "Warbound" or item.bindingScope == "Warbound Until Equipped" then
            reason = "Warband-bound item belongs in Warband storage"
        elseif item.isWarbandBound then
            reason = "Item is eligible for Warband storage"
        elseif IsOldExpansion(item.expansionID) then
            reason = "Old transferable item is better in shared storage"
        elseif IsUnknownExpansion(item.expansionID) then
            reason = "Transferable item with unknown expansion is better in shared storage"
        else
            reason = "Transferable non-profession item is better in shared storage"
        end
    end

    local needsMove = targetStorage ~= currentStorage
    local targetAvailable = #GetStorageBagIDs(targetStorage) > 0
    local hasFreeSlot = false
    if needsMove and targetAvailable then
        hasFreeSlot = FindFreeSlot(targetStorage, {}, item) ~= nil
    end

    return {
        key = "organize:" .. item.key,
        item = item,
        currentStorage = currentStorage,
        targetStorage = targetStorage,
        reason = reason,
        needsMove = needsMove,
        movable = needsMove and targetAvailable and hasFreeSlot and not ns.DB.context.inCombat,
        blockedReason = needsMove and (not targetAvailable and "Target bank is not available" or (not hasFreeSlot and "No empty target slots" or nil)) or nil,
    }
end

local function GetOrganizationPlans(showAll)
    local charProfSubclasses = P.GetCharacterProfessionSubclasses()
    local plans = {}
    for _, item in ipairs(GetAllDecisions() or {}) do
        local plan = BuildOrganizationPlan(item, charProfSubclasses)
        if plan and (showAll or plan.needsMove) then
            table.insert(plans, plan)
        end
    end
    table.sort(plans, function(a, b)
        if a.movable ~= b.movable then
            return a.movable
        end
        if a.targetStorage ~= b.targetStorage then
            return a.targetStorage < b.targetStorage
        end
        return (a.item.name or "") < (b.item.name or "")
    end)
    return plans
end

P.GetOrganizationPlans = GetOrganizationPlans

-- ===========================================================================
-- Vendor plans
-- ===========================================================================

local function GetVendorBlockReason(item)
    local rule = item.rule
    if rule and rule.ignore then
        return "Ignored by item rule"
    elseif rule and rule.protect then
        return "Protected by item rule"
    elseif rule and rule.neverSell then
        return "Never sell rule"
    elseif item.typeTag ~= Data.ItemTypes.CONSUMABLE then
        return "Only old consumables are vendor candidates"
    elseif not IsOldExpansion(item.expansionID) then
        return "Not old expansion content"
    elseif not item.sellPrice or item.sellPrice <= 0 then
        return "No vendor value"
    elseif item.quality == nil or item.quality > 2 then
        return "Quality is above conservative auto-sell threshold"
    end
    return nil
end

local function BuildVendorPlan(item)
    if item.scope ~= BAG_SCOPE and item.scope ~= BANK_SCOPE then
        return nil
    end

    local blockReason = GetVendorBlockReason(item)
    local isCandidate = blockReason == nil
    local action = item.scope == BANK_SCOPE and VENDOR_ACTION_RECALL or VENDOR_ACTION_SELL
    local contextReady = action == VENDOR_ACTION_RECALL and ns.DB.context.bankOpen
        or action == VENDOR_ACTION_SELL and ns.DB.context.vendorOpen
    local contextMessage = action == VENDOR_ACTION_RECALL and "Open the bank to recall this item" or "Open a vendor to sell this item"
    local value = (item.sellPrice or 0) * (item.count or 1)

    return {
        key = "vendor:" .. item.key,
        item = item,
        action = action,
        isCandidate = isCandidate,
        movable = isCandidate and contextReady and not ns.DB.context.inCombat,
        blockedReason = blockReason or (contextReady and nil or contextMessage),
        reason = isCandidate and "Old low-risk consumable with vendor value" or blockReason,
        value = value,
    }
end

local function GetVendorPlans(showAll)
    local plans = {}
    for _, item in ipairs(GetAllDecisions() or {}) do
        local plan = BuildVendorPlan(item)
        if plan and (showAll or plan.isCandidate) then
            table.insert(plans, plan)
        end
    end
    table.sort(plans, function(a, b)
        if a.movable ~= b.movable then
            return a.movable
        end
        if a.action ~= b.action then
            return a.action < b.action
        end
        if a.value ~= b.value then
            return a.value > b.value
        end
        return (a.item.name or "") < (b.item.name or "")
    end)
    return plans
end

P.GetVendorPlans = GetVendorPlans

-- ===========================================================================
-- Transfer pipeline: block reason and candidates
-- ===========================================================================

local NeedsBankStorage = P.NeedsBankStorage
local STORAGE_WARBAND_ROUTED = P.STORAGE_WARBAND_ROUTED

-- The bags a move to `dest` may land in. For the routed Warband destination
-- this is the single tab whose settings match the item.
local function GetTargetBagIDs(item, dest)
    if dest == STORAGE_WARBAND_ROUTED then
        local route = P.RouteToWarbandTab(item)
        if not route then return {}, nil end
        local bagIDs = {}
        for _, bagID in ipairs(route.bagIDs) do table.insert(bagIDs, bagID) end
        -- The player allowed general tabs for items whose assigned tabs are full.
        if UI.warbandFallback then
            for _, bagID in ipairs(route.fallbackBagIDs) do table.insert(bagIDs, bagID) end
        end
        return bagIDs, route
    end
    return GetStorageBagIDs(dest), nil
end
P.GetTargetBagIDs = GetTargetBagIDs

-- Block reason prefix when a tab assigned to the item is full but a general
-- tab has room; the Transfer panel then offers to use general tabs.
local WARBAND_ASSIGNED_FULL = "Assigned tab full: "
P.WARBAND_ASSIGNED_FULL = WARBAND_ASSIGNED_FULL

local function GetTransferBlockReason(item, source, dest)
    if ns.DB.context.inCombat then return "In combat" end
    if source == dest then return "Source and destination are the same" end
    if dest == "Vendor" and P.MerchantRefused and P.MerchantRefused(item.itemID) then
        return "Vendors won't buy this item"
    end

    local needsBank = NeedsBankStorage(source) or NeedsBankStorage(dest)
    if needsBank and not ns.DB.context.bankOpen then
        -- Full detection walks every frame; do it at most once per refresh.
        local cache = P.evaluationCache
        local detected
        if cache and cache.bankDetected ~= nil then
            detected = cache.bankDetected
        else
            detected = IsBankContextDetected() and true or false
            if cache then cache.bankDetected = detected end
        end
        if not detected then return "Bank is not open" end
    end

    if dest == "Vendor" then
        if not ns.DB.context.vendorOpen then return "Vendor is not open" end
        if not IsVendorSellable(item) then return "Not vendor-sellable" end
    elseif dest == P.STORAGE_AUCTION_HOUSE then
        if not ns.DB.context.auctionHouseOpen then return "Auction house is not open" end
        if item.scope ~= BAG_SCOPE then return "Only items in your bags can be listed" end
        local channels = P.ItemChannels(item)
        if not channels.auction then return channels.why.auction end
        local price, why = P.ListingPrice(item)
        if not price then return why end
    elseif dest == P.STORAGE_DESTROY then
        if item.scope ~= BAG_SCOPE then return "Only items in your bags can be destroyed" end
        local channels = P.ItemChannels(item)
        if not channels.destroy then return channels.why.destroy end
    elseif P.IsWarbandStorage(dest) then
        local channels = P.ItemChannels(item)
        if not channels.warbandBank then return channels.why.warbandBank end
    end

    if item.rule then
        if item.rule.protect then return "Protected by item rule" end
        if item.rule.ignore then return "Ignored by item rule" end
        if item.rule.neverSell and dest == "Vendor" then return "Never sell rule" end
    end

    for _, reason in ipairs(item.blockedReasons or {}) do
        if reason:find("Equipped") or reason:find("Mythic Keystone") then
            return reason
        end
    end

    if dest == STORAGE_WARBAND_ROUTED then
        if item.scope ~= BAG_SCOPE and item.storageKind == STORAGE_WARBAND_BANK then
            return "Already in the Warband Bank"
        end
        local route, why = P.RouteToWarbandTab(item)
        if not route then return why end
    elseif dest ~= "Bags" and dest ~= "Vendor" and dest ~= P.STORAGE_AUCTION_HOUSE and dest ~= P.STORAGE_DESTROY and item.scope ~= BAG_SCOPE then
        for _, bagID in ipairs(GetStorageBagIDs(dest)) do
            if bagID == item.bagID then
                return "Already in " .. GetStorageDisplayName(dest)
            end
        end
    end

    if dest == "Bags" then
        if not HasRoomIn(NORMAL_BAG_IDS, item) then
            return "No empty bag slots"
        end
    elseif dest ~= "Vendor" and dest ~= P.STORAGE_AUCTION_HOUSE and dest ~= P.STORAGE_DESTROY then
        local bagIDs, route = GetTargetBagIDs(item, dest)
        if not HasRoomIn(bagIDs, item) then
            if route and route.assigned and #route.fallbackBagIDs > 0 and not UI.warbandFallback
                and HasRoomIn(route.fallbackBagIDs, item) then
                return WARBAND_ASSIGNED_FULL .. (route.reason or "")
            end
            return "No empty slots in " .. (route and route.reason or GetStorageDisplayName(dest))
        end
    end

    return nil
end

P.GetTransferBlockReason = GetTransferBlockReason

local function GetTransferCandidates(source, dest)
    local candidates = {}
    for _, item in ipairs(GetAllDecisions() or {}) do
        local itemSource
        if item.scope == BAG_SCOPE then
            itemSource = "Bags"
        else
            itemSource = item.storageKind or "Unknown"
        end
        -- "Private Bank" as source is monolithic: it matches both STORAGE_PRIVATE_BANK
        -- items (scanned without tab data) and any named BankTab:N items (scanned with
        -- tab data active). Named tab sources match only their exact storageKind.
        -- "Bank (All Tabs)" matches any character bank item regardless of tab.
        local isBankTabItem = itemSource == STORAGE_PRIVATE_BANK
            or itemSource:sub(1, #BANK_TAB_PREFIX) == BANK_TAB_PREFIX
        local warbandTabMatch = P.IsWarbandTabStorage(source) and item.storageKind == STORAGE_WARBAND_BANK
            and P.WarbandTabStorageKey(item.bagID) == source
        local matches = (itemSource == source) or warbandTabMatch
            or (source == STORAGE_PRIVATE_BANK and itemSource:sub(1, #BANK_TAB_PREFIX) == BANK_TAB_PREFIX)
            or (source == STORAGE_ALL_BANK_TABS and isBankTabItem)
        if matches then
            local blocked = GetTransferBlockReason(item, source, dest)
            table.insert(candidates, {
                item = item,
                key = item.key,
                blocked = blocked,
                movable = blocked == nil,
                source = source,
                dest = dest,
            })
        end
    end
    table.sort(candidates, function(a, b)
        if a.movable ~= b.movable then return a.movable end
        return (a.item.name or "") < (b.item.name or "")
    end)
    return candidates
end

P.GetTransferCandidates = GetTransferCandidates

-- ===========================================================================
-- Target slot reservations
-- A move leaves the target slot looking empty until the server confirms it, so
-- slots used by recent moves stay reserved until the follow-up rescan has run.
-- ===========================================================================

local SLOT_RESERVATION_SECONDS = 2
local reservedTargetSlots = {}
local reservationGeneration = 0

-- A target slot stays reserved until its item has arrived (or 30 s). In game
-- 32 Warband deposits took longer than the old fixed 2 s, so the space
-- summary showed a tab as having room that was about to be filled.
local RESERVATION_LIMIT = 30
local function ReleaseArrivedSlots()
    local now = GetTime()
    for key, info in pairs(reservedTargetSlots) do
        local arrived = type(info) == "table" and CContainer.GetContainerItemID(info.bag, info.slot) ~= nil
        if arrived or type(info) ~= "table" or now - info.at >= RESERVATION_LIMIT then
            reservedTargetSlots[key] = nil
        end
    end
    return next(reservedTargetSlots) ~= nil
end

local function HoldReservedSlotsUntilSettled()
    reservationGeneration = reservationGeneration + 1
    local generation = reservationGeneration
    local function check()
        if generation ~= reservationGeneration then return end
        if ReleaseArrivedSlots() then
            C_Timer.After(SLOT_RESERVATION_SECONDS, check)
        elseif UI.frame and UI.frame:IsShown() then
            -- The player's moves have settled: show the real space once.
            Core.RefreshUI()
        end
    end
    C_Timer.After(SLOT_RESERVATION_SECONDS, check)
end

-- Slots in a bag claimed by moves that haven't arrived yet.
function P.SlotsLanding(bagID)
    local count = 0
    for _, info in pairs(reservedTargetSlots) do
        if type(info) == "table" and info.bag == bagID and not CContainer.GetContainerItemID(info.bag, info.slot) then
            count = count + 1
        end
    end
    return count
end

-- ===========================================================================
-- VerifySourceSlot
-- Scan data can be stale (bags sorted, items looted, scans saved from an
-- earlier session). Never act on a scanned bag/slot without confirming the
-- same item is still there and can be picked up.
-- ===========================================================================

local STALE_SLOT_REASON = "Item has moved since the last scan"

local function VerifySourceSlot(item)
    if GetCursorInfo() then
        return "Cursor is holding something"
    end
    if CContainer.GetContainerItemID(item.bagID, item.slot) ~= item.itemID then
        return STALE_SLOT_REASON
    end
    local info = CContainer.GetContainerItemInfo(item.bagID, item.slot)
    if not info then
        return STALE_SLOT_REASON
    end
    if info.isLocked then
        return "Item is locked"
    end
    return nil
end

-- ===========================================================================
-- ExecuteTransferMove (internal)
-- ===========================================================================

-- Slots just sold or moved from. The server settles a few moments later, and
-- a rescan in between (bag updates fire right away) would list the item again
-- as ready; in game, 4 of 11 sold items reappeared for about 2 seconds.
-- Hidden while the source slot is still locked by the move (big batches take
-- several seconds: in game 9 of 22 reappeared after a fixed 5 s), up to 30 s.
local PENDING_SECONDS = 30
local pendingFromSlots = {}

local function MarkPendingFromSlot(item)
    pendingFromSlots[P.LocationKey(item)] = GetTime() + PENDING_SECONDS
end

function P.IsPendingFromSlot(item, isLocked)
    local key = P.LocationKey(item)
    local expires = pendingFromSlots[key]
    if not expires then return false end
    if GetTime() >= expires then pendingFromSlots[key] = nil return false end
    -- Unlocked and still there after the first moment: the move didn't happen.
    if isLocked == false and GetTime() >= expires - PENDING_SECONDS + 3 then
        pendingFromSlots[key] = nil
        return false
    end
    return true
end

local function ItemLabel(item)
    return item.name or ("Item " .. item.itemID)
end

-- ===========================================================================
-- Sale confirmation
-- The server can refuse a sale after UseContainerItem returns: in game a
-- traveling vendor answered "The merchant doesn't want that item." (UI error
-- 42) and the items stayed in the bags while the addon reported them sold.
-- So each sale is checked a moment later (slot emptied, gold earned) and the
-- report says what really happened. Refused items are remembered in saved
-- data and blocked at every vendor: the refusal belongs to the item (players
-- report the same for items like Lucky Duck at any vendor; no API tells, the
-- item info still shows a sell price). /icanteven refused [clear] reviews them.
-- ===========================================================================
local SALE_CHECK_DELAY = 1.5
local SALE_CHECK_TRIES = 4
local saleWatch = nil          -- { items, errors, moneyBefore, tries }

local function RefusedStore()
    ns.DB.vendorRefused = ns.DB.vendorRefused or {}
    return ns.DB.vendorRefused
end

-- Only the merchant's own refusal is remembered. Other errors are
-- temporary: in game, 2 of 12 sales in one click failed with "That object is
-- busy." and were wrongly saved as refused (fixed 2026-09-26).
local VENDOR_REFUSAL_ERROR = 42   -- UI_ERROR_MESSAGE errorType (ERR_VENDOR_DOESNT_BUY)
local function IsRefusalMessage(message)
    if type(message) ~= "string" then return false end
    if ERR_VENDOR_DOESNT_BUY and message == ERR_VENDOR_DOESNT_BUY then return true end
    return message:find("doesn't want", 1, true) ~= nil
end

-- The saved refusal for an item ({ name, reason, at }), or nil. Entries
-- saved for another reason (the "busy" bug) are dropped.
function P.MerchantRefused(itemID)
    if not (itemID and ns.DB) then return nil end
    local entry = RefusedStore()[itemID]
    if entry and not IsRefusalMessage(entry.reason) then
        RefusedStore()[itemID] = nil
        return nil
    end
    return entry
end

-- Lines describing the remembered refusals; `clear` forgets them.
function P.RefusedItemsReport(clear)
    local store = RefusedStore()
    local lines = {}
    for itemID, entry in pairs(store) do
        lines[#lines + 1] = "  " .. tostring(entry.name or ("Item " .. itemID)) .. " (" .. itemID .. "): "
            .. tostring(entry.reason or "refused")
            .. (entry.at and date and (", " .. date("%Y-%m-%d", entry.at)) or "")
    end
    table.sort(lines)
    if clear then
        ns.DB.vendorRefused = {}
    end
    local auction = {}
    for itemID, entry in pairs(ns.DB.auctionRefused or {}) do
        auction[#auction + 1] = "  " .. tostring(entry.name or ("Item " .. itemID)) .. " (" .. itemID .. "): "
            .. tostring(entry.reason or "refused") .. (entry.at and date and (", " .. date("%Y-%m-%d", entry.at)) or "")
    end
    table.sort(auction)
    if clear then
        ns.DB.auctionRefused = {}
        return { #lines .. " vendor and " .. #auction .. " auction refusal(s) cleared: they will be offered again." }
    end
    if #lines == 0 and #auction == 0 then return { "No items remembered as refused by vendors or the auction house." } end
    if #lines > 0 then
        table.insert(lines, 1, #lines .. " item(s) vendors refused to buy (not offered for sale; /icanteven refused clear to retry):")
    end
    if #auction > 0 then
        lines[#lines + 1] = #auction .. " item(s) the auction house refused (not offered for listing):"
        for _, line in ipairs(auction) do lines[#lines + 1] = line end
    end
    return lines
end

if CreateFrame then
    local saleFrame = CreateFrame("Frame")
    saleFrame:RegisterEvent("UI_ERROR_MESSAGE")
    saleFrame:SetScript("OnEvent", function(_, _, errorType, message)
        if saleWatch and type(message) == "string" then
            table.insert(saleWatch.errors, message)
            if errorType == VENDOR_REFUSAL_ERROR or IsRefusalMessage(message) then
                saleWatch.refusals = (saleWatch.refusals or 0) + 1
            else
                saleWatch.otherErrors = (saleWatch.otherErrors or 0) + 1
                saleWatch.otherReason = message
            end
        end
    end)
end

local function MoneyText(copper)
    if not copper then return nil end
    return GetCoinTextureString and GetCoinTextureString(copper)
        or (math.floor(copper / 10000) .. "g " .. math.floor(copper / 100) % 100 .. "s")
end

local CheckSales
CheckSales = function()
    local watch = saleWatch
    if not watch then return end
    local sold, refused, waiting = {}, {}, false
    for _, item in ipairs(watch.items) do
        local id = CContainer.GetContainerItemID(item.bagID, item.slot)
        local info = CContainer.GetContainerItemInfo(item.bagID, item.slot)
        if id == item.itemID and info and info.isLocked then
            waiting = true
        elseif id == item.itemID then
            table.insert(refused, item)
        else
            table.insert(sold, item)
        end
    end
    if waiting and watch.tries < SALE_CHECK_TRIES then
        watch.tries = watch.tries + 1
        C_Timer.After(SALE_CHECK_DELAY, CheckSales)
        return
    end
    saleWatch = nil
    local reason = watch.errors[#watch.errors]
    local earned = GetMoney and watch.moneyBefore and (GetMoney() - watch.moneyBefore) or nil
    local earnedText = earned and earned > 0 and (" (" .. MoneyText(earned) .. ")") or ""
    P.Log("transfer", "confirmed: %d sold, %d not sold, earned %s%s", #sold, #refused, tostring(earned),
        reason and (" (" .. table.concat(watch.errors, "; ") .. ")") or "")
    -- A refusal is only remembered when every unsold item is explained by
    -- the merchant's refusal and nothing else went wrong in this click.
    local certain = #refused > 0 and (watch.refusals or 0) >= #refused and (watch.otherErrors or 0) == 0
    if #refused > 0 and not certain then
        local names = {}
        for _, item in ipairs(refused) do
            pendingFromSlots[P.LocationKey(item)] = nil
            P.Log("transfer", "not sold (try again): %s (%s %s:%s)", tostring(item.name), tostring(item.itemID),
                tostring(item.bagID), tostring(item.slot))
            if #names < 3 then names[#names + 1] = ItemLabel(item) end
        end
        UI.inventoryStatus = #sold .. " sold, " .. #refused .. " not sold: click Sell to try again"
        Print("Sold " .. #sold .. " of " .. #watch.items .. earnedText .. ". Not sold: " .. table.concat(names, ", ")
            .. (#refused > #names and ", ..." or "") .. " (" .. (watch.otherReason or reason or "no answer from the vendor")
            .. "). Select them and click Sell to try again.")
        Core.ScanInventory("bags", true)
        return
    end
    reason = reason and IsRefusalMessage(reason) and reason or (ERR_VENDOR_DOESNT_BUY or "The merchant doesn't want that item.")
    local names = {}
    for _, item in ipairs(refused) do
        RefusedStore()[item.itemID] = { name = item.name, reason = reason or "The merchant didn't buy it",
            at = time and time() or 0 }
        pendingFromSlots[P.LocationKey(item)] = nil
        P.Log("transfer", "refused by the merchant: %s (%s %s:%s)", tostring(item.name), tostring(item.itemID),
            tostring(item.bagID), tostring(item.slot))
        if #names < 3 then names[#names + 1] = ItemLabel(item) end
    end
    if #refused > 0 then
        UI.inventoryStatus = #sold .. " sold, " .. #refused .. " refused by the merchant"
        Print("Sold " .. #sold .. " of " .. #watch.items .. earnedText
            .. ". The merchant refused " .. #refused .. ": " .. table.concat(names, ", ")
            .. (#refused > #names and ", ..." or "") .. (reason and (" (" .. reason .. ")") or "") .. ".")
        Print("No vendor will buy " .. (#refused == 1 and "it" or "them") .. ": destroy "
            .. (#refused == 1 and "it" or "them") .. " if you don't need "
            .. (#refused == 1 and "it" or "them") .. " (drag out of your bag, drop on the game world, confirm), or keep "
            .. (#refused == 1 and "it" or "them") .. ". /icanteven refused lists every item vendors refused.")
        -- They are back in the bags: show that (the result of the player's click).
        Core.ScanInventory("bags", true)
    else
        UI.inventoryStatus = "Sold " .. #sold .. earnedText
        Print("Sold " .. #sold .. earnedText .. ".")
        if UI.frame and UI.frame:IsShown() then Core.RefreshUI() end
    end
end

-- Start listening before the first sale (the merchant's error can arrive
-- before the click's loop ends). `moneyBefore`: gold before the click.
local function BeginSales(moneyBefore)
    if not saleWatch then
        saleWatch = { items = {}, errors = {}, moneyBefore = moneyBefore, tries = 0 }
    end
end

-- Check the sales sent since BeginSales shortly.
local function WatchSales(items)
    local watch = saleWatch
    if not watch then return end
    for _, item in ipairs(items) do table.insert(watch.items, item) end
    if #watch.items == 0 or not C_Timer then
        saleWatch = nil
        return
    end
    if not watch.scheduled then
        watch.scheduled = true
        C_Timer.After(SALE_CHECK_DELAY, CheckSales)
    end
end

-- The game's own answer on whether a bag item can be posted (nil when the
-- API isn't there). Diagnostics only: in game it said no for every item
-- whose data the client hadn't loaded yet (85 items after a reload) and yes
-- for a Warbound item the game then refused. The channels model decides;
-- the game's answer after posting is the confirmation.
function P.AuctionSellValid(item)
    if not (C_AuctionHouse and C_AuctionHouse.IsSellItemValid and ItemLocation) then return nil end
    if item.scope ~= BAG_SCOPE or not item.bagID or not item.slot then return nil end
    local ok, valid = pcall(C_AuctionHouse.IsSellItemValid, ItemLocation:CreateFromBagAndSlot(item.bagID, item.slot), false)
    if not ok then return nil end
    return valid and true or false
end

-- ===========================================================================
-- Listing confirmation. PostItem returns before the game answers; a refusal
-- ("Warbound items can only be given to other characters in your Warband",
-- "You cannot auction an item with used charges") arrives as UI_ERROR_MESSAGE
-- and the item stays in the bag. Refusals are remembered (ns.DB.auctionRefused)
-- so the item isn't offered again; /icanteven refused shows them.
-- ===========================================================================
local LISTING_CHECK_DELAY = 1.5
local LISTING_CHECK_TRIES = 4  -- an item stays locked while the game processes the post
local listingWatch = nil       -- { items, errors, tries }

local function AuctionRefusedStore()
    ns.DB.auctionRefused = ns.DB.auctionRefused or {}
    return ns.DB.auctionRefused
end
function P.AuctionRefused(itemID)
    return itemID and ns.DB and AuctionRefusedStore()[itemID] or nil
end
function P.ClearAuctionRefused() ns.DB.auctionRefused = {} end

-- The auction house answers a bad post with AUCTION_HOUSE_SHOW_ERROR(code)
-- (the red text mid-screen), not UI_ERROR_MESSAGE. Codes from
-- Enum.AuctionHouseError (warcraft.wiki.gg, verified 2026-09-27). Item
-- reasons are permanent and remembered; the rest are temporary.
local AUCTION_ERRORS = {
    [14] = { text = "the game won't auction an item with used charges", permanent = true },
    [15] = { text = "quest item", permanent = true },
    [16] = { text = "bound item", permanent = true, binding = "soulbound" },
    [17] = { text = "conjured item", permanent = true },
    [18] = { text = "limited-duration item", permanent = true },
    [21] = { text = "wrapped item", permanent = true },
    [26] = { text = "Warbound until equipped: only your own characters can have it", permanent = true, binding = "wue" },
    [0]  = { text = "not enough money for the deposit" },
    [7]  = { text = "the auction house is busy" },
    [8]  = { text = "the auction house is unavailable right now" },
    [10] = { text = "auction house database error" },
}
P.AUCTION_ERRORS = AUCTION_ERRORS

if CreateFrame then
    local listingFrame = CreateFrame("Frame")
    listingFrame:RegisterEvent("UI_ERROR_MESSAGE")
    listingFrame:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
    listingFrame:SetScript("OnEvent", function(_, event, a, b)
        if not listingWatch then return end
        if event == "AUCTION_HOUSE_SHOW_ERROR" then
            local known = AUCTION_ERRORS[a]
            table.insert(listingWatch.errors, { code = a, text = known and known.text or ("auction house error " .. tostring(a)),
                permanent = known and known.permanent or false, binding = known and known.binding })
        elseif type(b) == "string" then
            table.insert(listingWatch.errors, { text = b, permanent = false })
        end
    end)
end

local CheckListings
CheckListings = function()
    local watch = listingWatch
    if not watch then return end
    local listed, refused, waiting = {}, {}, false
    for _, item in ipairs(watch.items) do
        local id = CContainer.GetContainerItemID(item.bagID, item.slot)
        local info = CContainer.GetContainerItemInfo(item.bagID, item.slot)
        if id == item.itemID and info and info.isLocked then
            waiting = true
        elseif id == item.itemID then
            table.insert(refused, item)
        else
            table.insert(listed, item)
        end
    end
    if waiting and (watch.tries or 0) < LISTING_CHECK_TRIES then
        watch.tries = (watch.tries or 0) + 1
        C_Timer.After(LISTING_CHECK_DELAY, CheckListings)
        return
    end
    listingWatch = nil
    local last = watch.errors[#watch.errors]
    local texts = {}
    for _, err in ipairs(watch.errors) do texts[#texts + 1] = err.text end
    P.Log("auction", "confirmed: %d listed, %d refused%s", #listed, #refused,
        #texts > 0 and (" (" .. table.concat(texts, "; ") .. ")") or "")
    for _, item in ipairs(listed) do
        Print("Listed: " .. ItemLabel(item) .. " at " .. P.FormatMoney((P.ListingPrice(item)) or 0) .. " each.")
    end
    for _, item in ipairs(refused) do
        pendingFromSlots[P.LocationKey(item)] = nil
        -- One refused item and one answer: the answer is about that item.
        local reason = (#refused == 1 or #watch.errors >= #refused) and last or nil
        if reason and reason.permanent then
            AuctionRefusedStore()[item.itemID] = { name = item.name, reason = reason.text, at = time and time() or 0 }
            -- The game knows the binding better than the tooltip read did.
            if reason.binding and ns.DB.knownBinding then ns.DB.knownBinding[item.itemID] = reason.binding end
        end
        Print("Not listed: " .. ItemLabel(item) .. " (" .. (reason and reason.text or "no answer from the auction house") .. ")."
            .. (reason and reason.permanent and " It won't be offered for auction again (/icanteven refused clear to retry)." or ""))
    end
    if #refused > 0 then
        UI.inventoryStatus = #listed .. " listed, " .. #refused .. " refused by the auction house"
        Core.ScanInventory("bags", true)
    end
end

local function WatchListings(items)
    if #items == 0 then listingWatch = nil return end
    listingWatch = listingWatch or { items = {}, errors = {} }
    for _, item in ipairs(items) do table.insert(listingWatch.items, item) end
    if C_Timer then C_Timer.After(LISTING_CHECK_DELAY, CheckListings) else CheckListings() end
end

-- Post one auction from a click (PostItem / PostCommodity need a hardware
-- event and can't run from /run; verified on warcraft.wiki.gg 2026-09-27).
-- Commodities list the whole stack at a unit price; items list one.
local function PostAuction(item)
    if not (C_AuctionHouse and C_AuctionHouse.PostItem and ItemLocation) then
        return false, "Auction house API unavailable"
    end
    local price = P.ListingPrice(item)
    if not price then return false, "No listing price" end
    -- The auction house takes one request at a time; a post sent while it's
    -- busy is dropped without a word (in game: "no answer" on two items).
    if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
        return false, "The auction house is busy: click List again in a moment"
    end
    local location = ItemLocation:CreateFromBagAndSlot(item.bagID, item.slot)
    local duration = P.LISTING_DURATION or 2
    local commodityValue = Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity or 2
    local okStatus, status = pcall(C_AuctionHouse.GetItemCommodityStatus, location)
    local commodity = okStatus and status == commodityValue
    local ok, needsConfirmation
    if commodity then
        ok, needsConfirmation = pcall(C_AuctionHouse.PostCommodity, location, duration, item.count or 1, price)
        if ok and needsConfirmation and C_AuctionHouse.ConfirmPostCommodity then
            ok = pcall(C_AuctionHouse.ConfirmPostCommodity, location, duration, item.count or 1, price)
        end
    else
        ok, needsConfirmation = pcall(C_AuctionHouse.PostItem, location, duration, 1, nil, price)
        if ok and needsConfirmation and C_AuctionHouse.ConfirmPostItem then
            ok = pcall(C_AuctionHouse.ConfirmPostItem, location, duration, 1, nil, price)
        end
    end
    if not ok then return false, "The game refused the listing: " .. tostring(needsConfirmation) end
    P.Log("auction", "posting %s x%s at %s each (%s)", tostring(item.name), tostring(item.count or 1),
        P.FormatMoney(price), commodity and "commodity" or "item")
    return true, nil
end

local function ExecuteTransferMove(item, dest, takenSlots)
    local slotProblem = VerifySourceSlot(item)
    if slotProblem then
        return false, slotProblem
    end

    if dest == "Vendor" then
        if CContainer.UseContainerItem then
            CContainer.UseContainerItem(item.bagID, item.slot)
            return true, nil
        end
        return false, "UseContainerItem API unavailable"
    end

    if dest == P.STORAGE_AUCTION_HOUSE then
        return PostAuction(item)
    end

    -- Destroy: pick up, confirm the cursor holds it, delete. DeleteCursorItem
    -- needs a hardware event and takes one item per click (verified
    -- 2026-09-27); the game's own DELETE popup covers uncommon and better.
    if dest == P.STORAGE_DESTROY then
        if not (CContainer.PickupContainerItem and DeleteCursorItem) then return false, "Destroy API unavailable" end
        CContainer.PickupContainerItem(item.bagID, item.slot)
        if GetCursorInfo() ~= "item" then return false, "Could not pick up item" end
        local ok, err = pcall(DeleteCursorItem)
        if not ok then ClearCursor() return false, "The game refused: " .. tostring(err) end
        P.Log("transfer", "destroy %s x%s (%s %s:%s)", tostring(item.name), tostring(item.count or 1),
            tostring(item.itemID), tostring(item.bagID), tostring(item.slot))
        return true, nil
    end

    if not CContainer.PickupContainerItem then
        return false, "Container pickup API unavailable"
    end

    local toBag, toSlot, toKey
    if dest == "Bags" then
        toBag, toSlot, toKey = FindFreeNormalBagSlot(takenSlots, item)
    else
        toBag, toSlot, toKey = FindFreeSlotInBags((GetTargetBagIDs(item, dest)), takenSlots, item)
    end
    if not toBag or not toSlot then
        return false, "No empty slots in " .. GetStorageDisplayName(dest)
    end

    CContainer.PickupContainerItem(item.bagID, item.slot)
    if GetCursorInfo() ~= "item" then
        return false, "Could not pick up item"
    end
    CContainer.PickupContainerItem(toBag, toSlot)
    if GetCursorInfo() then
        ClearCursor()
        return false, "Target slot rejected item"
    end
    takenSlots[toKey] = { bag = toBag, slot = toSlot, at = GetTime() }
    return true, nil
end

-- ===========================================================================
-- Core.ExecuteTransferOne / Core.ExecuteTransferSelected
-- ===========================================================================

-- Recent batches of moves (not sales), newest last, for /icanteven undo.
-- Kept in saved data so a reload doesn't lose them; undo only pre-selects
-- matching items (by item and stack count) and the player still clicks.
local UNDO_LIMIT = 10
local function UndoStack()
    ns.DB.undoStack = ns.DB.undoStack or {}
    return ns.DB.undoStack
end

local function RecordUndo(source, dest, movedItems)
    if dest == "Vendor" or dest == P.STORAGE_AUCTION_HOUSE or dest == P.STORAGE_DESTROY or #movedItems == 0 then return end
    local counts, order = {}, {}
    for _, item in ipairs(movedItems) do
        if not counts[item.itemID] then table.insert(order, item.itemID) end
        counts[item.itemID] = (counts[item.itemID] or 0) + 1
    end
    local stack = UndoStack()
    table.insert(stack, { source = source, dest = dest, counts = counts, order = order, stacks = #movedItems,
        at = time and time() or 0 })
    while #stack > UNDO_LIMIT do table.remove(stack, 1) end
end

function P.PopUndoBatch() return table.remove(UndoStack()) end
function P.PeekUndoBatch() local stack = UndoStack() return stack[#stack] end

function Core.ExecuteTransferOne(plan)
    Core.UpdateContext()
    local item = plan.item
    local source = UI.transferSource or "Bags"
    local dest = UI.transferDest or STORAGE_PRIVATE_BANK
    local blocked = GetTransferBlockReason(item, source, dest)
    if blocked then
        P.Log("transfer", "skip %s (%s) -> %s: %s (row button)", item.name, item.itemID, dest, blocked)
        Print("Cannot transfer " .. ItemLabel(item) .. ": " .. blocked)
        return
    end
    if dest == "Vendor" then BeginSales(GetMoney and GetMoney() or nil) end
    local moved, err = ExecuteTransferMove(item, dest, reservedTargetSlots)
    P.Log("transfer", "%s %s x%s (%s %s:%s) -> %s: %s (row button)", dest == "Vendor" and "sell" or "move",
        item.name, item.count or 1, item.itemID, item.bagID, item.slot, dest,
        moved and "ok" or ("failed: " .. tostring(err)))
    if moved then
        MarkPendingFromSlot(item)
        RecordUndo(source, dest, { item })
        if P.OnItemMoved then P.OnItemMoved(item, dest) end
        HoldReservedSlotsUntilSettled()
        UI.transferSelected[plan.key] = nil
        RemoveMovedItemsFromScan({ [item.key] = true })
        UI.inventoryStatus = dest == "Vendor" and "Selling 1 item..."
            or dest == P.STORAGE_AUCTION_HOUSE and "Listed 1 item" or dest == P.STORAGE_DESTROY and "Destroyed 1 item" or "Moved 1 item"
        Core.RefreshUI()
        if dest == "Vendor" then
            WatchSales({ item })
        elseif dest == P.STORAGE_AUCTION_HOUSE then
            listingWatch = listingWatch or { items = {}, errors = {} }
            WatchListings({ item })
        elseif dest == P.STORAGE_DESTROY then
            Print("Destroyed: " .. ItemLabel(item) .. (((item.quality or 0) >= 2) and " (confirm the game's prompt if it appears)." or "."))
        else
            Print("Transferred: " .. ItemLabel(item))
        end
        Core.ScheduleRescanAfterMove()
    else
        if dest == "Vendor" then WatchSales({}) end   -- nothing sent: stop listening
        UI.inventoryStatus = "Failed: " .. (err or "unknown error")
        Core.RefreshUI()
        Print("Transfer failed: " .. ItemLabel(item) .. ": " .. (err or "unknown error"))
        if err == STALE_SLOT_REASON then
            Core.ScanInventory("all", true)
        end
    end
end

-- The vendor buyback list holds 12 items (confirmed in game). Selling at most
-- 12 per click means every sale from one click can still be bought back.
local VENDOR_BATCH_SIZE = 12
P.VENDOR_BATCH_SIZE = VENDOR_BATCH_SIZE
-- The game accepts one auction per click; the rest stay selected.
local LISTING_BATCH_SIZE = 1
P.LISTING_BATCH_SIZE = LISTING_BATCH_SIZE
-- And one destroyed item per click.
local DESTROY_BATCH_SIZE = 1
P.DESTROY_BATCH_SIZE = DESTROY_BATCH_SIZE

-- Grey (junk) items don't need buyback protection, so they don't count toward
-- the 12 and are sold first; the buyback then still holds this click's
-- better items (the player's rule: the cap matters for greens and blues).
local function IsJunk(item) return item.quality == 0 end
P.IsVendorJunk = IsJunk

-- Selected plans in sale order: junk first, then everything else.
local function VendorOrder(plans)
    local junk, rest = {}, {}
    for _, plan in ipairs(plans) do
        table.insert(IsJunk(plan.item) and junk or rest, plan)
    end
    for _, plan in ipairs(rest) do table.insert(junk, plan) end
    return junk
end

function Core.ExecuteTransferSelected()
    Core.UpdateContext()
    if ns.DB.context.inCombat then
        Print("Cannot transfer items in combat.")
        return
    end
    local source = UI.transferSource or "Bags"
    local dest = UI.transferDest or STORAGE_PRIVATE_BANK
    local moved, blocked = 0, 0
    local movedKeys = {}
    local blockedDetails = {}
    local foundStaleSlot = false
    local processed = {}
    local remaining = 0
    local protectedSold = 0
    local movedItems = {}
    local plans = UI.transferVisible or {}
    if dest == "Vendor" then
        plans = VendorOrder(plans)
        BeginSales(GetMoney and GetMoney() or nil)
    elseif dest == P.STORAGE_AUCTION_HOUSE then
        listingWatch = listingWatch or { items = {}, errors = {} }   -- errors can arrive before the loop ends
    end
    local listed = 0
    for _, plan in ipairs(plans) do
        local capped = dest == "Vendor" and not IsJunk(plan.item) and protectedSold >= VENDOR_BATCH_SIZE
            or dest == P.STORAGE_AUCTION_HOUSE and listed >= LISTING_BATCH_SIZE
            or dest == P.STORAGE_DESTROY and listed >= DESTROY_BATCH_SIZE
        if UI.transferSelected[plan.key] and capped then
            remaining = remaining + 1
        elseif UI.transferSelected[plan.key] then
            processed[plan.key] = true
            local item = plan.item
            local blockReason = GetTransferBlockReason(item, source, dest)
            local didMoveAttempted = not blockReason
            if not blockReason then
                local didMove, err = ExecuteTransferMove(item, dest, reservedTargetSlots)
                P.Log("transfer", "%s %s x%s (%s %s:%s) -> %s: %s", dest == "Vendor" and "sell" or "move",
                    item.name, item.count or 1, item.itemID, item.bagID, item.slot, dest,
                    didMove and "ok" or ("blocked: " .. tostring(err)))
                if didMove then
                    MarkPendingFromSlot(item)
                    if P.OnItemMoved then P.OnItemMoved(item, dest) end
                    movedKeys[item.key] = true
                    table.insert(movedItems, item)
                    moved = moved + 1
                    listed = listed + 1
                    if not IsJunk(item) then protectedSold = protectedSold + 1 end
                else
                    blockReason = err or "failed"
                    if err == STALE_SLOT_REASON then foundStaleSlot = true end
                end
            end
            if blockReason then
                if not didMoveAttempted then
                    P.Log("transfer", "skip %s (%s): %s", item.name, item.itemID, blockReason)
                end
                blocked = blocked + 1
                if #blockedDetails < 3 then
                    table.insert(blockedDetails, ItemLabel(item) .. ": " .. blockReason)
                end
            end
        end
    end
    -- Items not reached (vendor batch limit) stay selected for the next click.
    for key in pairs(processed) do UI.transferSelected[key] = nil end
    RecordUndo(source, dest, movedItems)
    RemoveMovedItemsFromScan(movedKeys)
    if moved > 0 then
        HoldReservedSlotsUntilSettled()
    end
    if moved > 0 or blocked > 0 then
        local action = dest == "Vendor" and "sent to the vendor" or dest == P.STORAGE_AUCTION_HOUSE and "posted (checking the auction house's answer)"
        or dest == P.STORAGE_DESTROY and "destroyed" or "moved"
        UI.inventoryStatus = moved .. " " .. action .. ", " .. blocked .. " blocked"
            .. (remaining > 0 and (", " .. remaining .. " still selected") or "")
    end
    -- Sales are confirmed a moment later (the merchant can refuse them).
    if dest == "Vendor" then WatchSales(movedItems) end
    P.Log("transfer", "done %s -> %s: %d %s, %d blocked, %d still selected", source, dest, moved,
        dest == "Vendor" and "sold" or "moved", blocked, remaining)
    Core.RefreshUI()
    if dest == "Vendor" then
        Print("Selling " .. moved .. (blocked > 0 and (", " .. blocked .. " blocked") or "") .. "; checking the vendor's answer...")
    elseif dest == P.STORAGE_AUCTION_HOUSE then
        WatchListings(movedItems)
        if blocked > 0 then Print(blocked .. " blocked.") end
    elseif dest == P.STORAGE_DESTROY then
        Print("Destroyed " .. moved .. (blocked > 0 and (", " .. blocked .. " blocked") or "") .. ".")
    else
        Print("Transfer complete: " .. moved .. " moved, " .. blocked .. " blocked.")
    end
    if remaining > 0 and dest == P.STORAGE_AUCTION_HOUSE then
        Print(remaining .. " more selected. Click List again for the next one (the game allows one auction per click).")
    elseif remaining > 0 and dest == P.STORAGE_DESTROY then
        Print(remaining .. " more selected. Click Destroy again for the next one (the game allows one per click).")
    elseif remaining > 0 then
        Print(remaining .. " more selected. Click Sell again for the next batch; the vendor can buy back your last "
            .. VENDOR_BATCH_SIZE .. " sales.")
    end
    if #blockedDetails > 0 then
        Print("Blocked: " .. table.concat(blockedDetails, "; "))
    end
    if foundStaleSlot then
        Print("Some items had moved since the last scan. The list has been refreshed; review it and try again.")
        Core.ScanInventory("all", true)
    elseif moved > 0 then
        Core.ScheduleRescanAfterMove()
        -- If a sale or move didn't go through, the item shows again once its
        -- pending mark expires.
        C_Timer.After(3.5, function() Core.ScanInventory("all", true) end)
    end
end
