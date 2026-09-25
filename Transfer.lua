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
        return route and { route.bagID } or {}, route
    end
    return GetStorageBagIDs(dest), nil
end
P.GetTargetBagIDs = GetTargetBagIDs

local function GetTransferBlockReason(item, source, dest)
    if ns.DB.context.inCombat then return "In combat" end
    if source == dest then return "Source and destination are the same" end

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
    elseif P.IsWarbandStorage(dest) and item.accountBankAllowed == false then
        return "Not eligible for Warband Bank"
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
    elseif dest ~= "Bags" and dest ~= "Vendor" and item.scope ~= BAG_SCOPE then
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
    elseif dest ~= "Vendor" then
        local bagIDs, route = GetTargetBagIDs(item, dest)
        if not HasRoomIn(bagIDs, item) then
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

local function HoldReservedSlotsUntilSettled()
    reservationGeneration = reservationGeneration + 1
    local generation = reservationGeneration
    C_Timer.After(SLOT_RESERVATION_SECONDS, function()
        if generation == reservationGeneration then
            wipe(reservedTargetSlots)
        end
    end)
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
local PENDING_SECONDS = 5
local pendingFromSlots = {}

local function MarkPendingFromSlot(item)
    pendingFromSlots[P.LocationKey(item)] = GetTime() + PENDING_SECONDS
end

function P.IsPendingFromSlot(item)
    local key = P.LocationKey(item)
    local expires = pendingFromSlots[key]
    if not expires then return false end
    if GetTime() >= expires then pendingFromSlots[key] = nil return false end
    return true
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
    takenSlots[toKey] = true
    return true, nil
end

local function ItemLabel(item)
    return item.name or ("Item " .. item.itemID)
end

-- ===========================================================================
-- Core.ExecuteTransferOne / Core.ExecuteTransferSelected
-- ===========================================================================

function Core.ExecuteTransferOne(plan)
    Core.UpdateContext()
    local item = plan.item
    local source = UI.transferSource or "Bags"
    local dest = UI.transferDest or STORAGE_PRIVATE_BANK
    local blocked = GetTransferBlockReason(item, source, dest)
    if blocked then
        Print("Cannot transfer " .. ItemLabel(item) .. ": " .. blocked)
        return
    end
    local moved, err = ExecuteTransferMove(item, dest, reservedTargetSlots)
    if moved then
        if P.OnItemMoved then P.OnItemMoved(item, dest) end
        HoldReservedSlotsUntilSettled()
        UI.transferSelected[plan.key] = nil
        RemoveMovedItemsFromScan({ [item.key] = true })
        UI.inventoryStatus = dest == "Vendor" and "Sold 1 item" or "Moved 1 item"
        Core.RefreshUI()
        Print((dest == "Vendor" and "Sold: " or "Transferred: ") .. ItemLabel(item))
        Core.ScheduleRescanAfterMove()
    else
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
    for _, plan in ipairs(UI.transferVisible or {}) do
        if UI.transferSelected[plan.key] and dest == "Vendor" and moved >= VENDOR_BATCH_SIZE then
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
                    moved = moved + 1
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
    RemoveMovedItemsFromScan(movedKeys)
    if moved > 0 then
        HoldReservedSlotsUntilSettled()
    end
    if moved > 0 or blocked > 0 then
        local action = dest == "Vendor" and "sold" or "moved"
        UI.inventoryStatus = moved .. " " .. action .. ", " .. blocked .. " blocked"
            .. (remaining > 0 and (", " .. remaining .. " still selected") or "")
    end
    P.Log("transfer", "done %s -> %s: %d %s, %d blocked, %d still selected", source, dest, moved,
        dest == "Vendor" and "sold" or "moved", blocked, remaining)
    Core.RefreshUI()
    Print("Transfer complete: " .. moved .. " " .. (dest == "Vendor" and "sold" or "moved") .. ", " .. blocked .. " blocked.")
    if remaining > 0 then
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
        C_Timer.After(PENDING_SECONDS + 0.5, function() Core.ScanInventory("all", true) end)
    end
end
