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
-- FindFreeSlot
-- Finds a free slot in the given storageKind. Tries stacking first.
-- ===========================================================================

local function FindFreeSlot(storageKind, takenSlots, item)
    if item and item.itemID and (item.maxStack or 1) > 1 then
        for _, bagID in ipairs(GetStorageBagIDs(storageKind)) do
            local numSlots = CContainer.GetContainerNumSlots(bagID) or 0
            for slot = 1, numSlots do
                local key = SlotKey(bagID, slot)
                if not takenSlots[key] and CContainer.GetContainerItemID(bagID, slot) == item.itemID then
                    local info = CContainer.GetContainerItemInfo(bagID, slot)
                    local stackCount = info and info.stackCount or 0
                    if stackCount < item.maxStack then
                        return bagID, slot, key
                    end
                end
            end
        end
    end

    for _, bagID in ipairs(GetStorageBagIDs(storageKind)) do
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

P.FindFreeSlot = FindFreeSlot

-- ===========================================================================
-- FindFreeNormalBagSlot
-- Finds a free slot in NORMAL_BAG_IDS (regular bag slots only).
-- ===========================================================================

local function FindFreeNormalBagSlot(takenSlots, item)
    if item and item.itemID and (item.maxStack or 1) > 1 then
        for _, bagID in ipairs(NORMAL_BAG_IDS) do
            local numSlots = CContainer.GetContainerNumSlots(bagID) or 0
            for slot = 1, numSlots do
                local key = SlotKey(bagID, slot)
                if not takenSlots[key] and CContainer.GetContainerItemID(bagID, slot) == item.itemID then
                    local info = CContainer.GetContainerItemInfo(bagID, slot)
                    local stackCount = info and info.stackCount or 0
                    if stackCount < item.maxStack then
                        return bagID, slot, key
                    end
                end
            end
        end
    end

    for _, bagID in ipairs(NORMAL_BAG_IDS) do
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

P.FindFreeNormalBagSlot = FindFreeNormalBagSlot

-- ===========================================================================
-- GetCandidateBankStorages
-- Returns bank storage kinds to try, in preference order.
-- ===========================================================================

local function GetCandidateBankStorages(item)
    local preferred = item.bankTargetStorage or GetPreferredBankStorage(item, item.typeTag)
    local ordered = { preferred, STORAGE_PRIVATE_BANK, STORAGE_WARBAND_BANK, STORAGE_REAGENT_BANK }
    local seen = {}
    local candidates = {}
    for _, storage in ipairs(ordered) do
        if type(storage) == "string" and not seen[storage] and #GetStorageBagIDs(storage) > 0 then
            seen[storage] = true
            table.insert(candidates, storage)
        end
    end
    return candidates
end

-- ===========================================================================
-- GetMoveBlockReason (legacy mode-based; used by old Move/Organize tabs)
-- ===========================================================================

local function GetMoveBlockReason(item)
    if ns.DB.context.inCombat then
        return "Cannot move items in combat"
    elseif not ns.DB.context.bankOpen then
        return "Open the bank first"
    end

    if ns.DB.ui.mode == "Dump to Bank" then
        if item.scope ~= BAG_SCOPE then
            return "Only bag items can be banked from this mode"
        elseif item.rule and item.rule.ignore then
            return "Ignored by item rule"
        elseif item.rule and item.rule.protect then
            return "Protected by item rule"
        end

        local candidates = GetCandidateBankStorages(item)
        if #candidates == 0 then
            return "No bank storage is available"
        end
        for _, storage in ipairs(candidates) do
            if FindFreeSlot(storage, {}, item) then
                item.bankTargetStorage = storage
                return nil
            end
        end
        return "No empty slots in available bank storage"
    elseif ns.DB.ui.mode == "Recall from Bank" then
        if item.scope ~= BANK_SCOPE then
            return "Only bank items can be recalled from this mode"
        elseif item.rule and item.rule.ignore then
            return "Ignored by item rule"
        elseif item.rule and item.rule.protect then
            return "Protected by item rule"
        elseif not FindFreeNormalBagSlot({}, item) then
            return "No empty normal bag slots"
        end
    end
    return nil
end

-- ===========================================================================
-- MoveItemToBankTarget
-- Picks the best bank storage for an item and moves it there.
-- ===========================================================================

local function MoveItemToBankTarget(item, takenSlots)
    if not CContainer.PickupContainerItem then
        return false, "Container pickup API unavailable"
    end

    local candidates = GetCandidateBankStorages(item)
    if #candidates == 0 then
        return false, "No bank storage is available"
    end

    for _, storage in ipairs(candidates) do
        local toBag, toSlot, toKey = FindFreeSlot(storage, takenSlots or {}, item)
        if toBag and toSlot then
            item.bankTargetStorage = storage
            CContainer.PickupContainerItem(item.bagID, item.slot)
            CContainer.PickupContainerItem(toBag, toSlot)
            if GetCursorInfo() ~= "item" then
                if takenSlots and toKey then
                    takenSlots[toKey] = true
                end
                return true
            end
            ClearCursor()
        end
    end

    return false, "No empty compatible slots in available bank storage"
end

-- ===========================================================================
-- MoveBankItemToNormalBag / MoveBankItemToStorageTarget
-- ===========================================================================

local function MoveBankItemToNormalBag(item, takenSlots)
    local toBag, toSlot, toKey = FindFreeNormalBagSlot(takenSlots or {}, item)
    if not toBag or not toSlot then
        return false, "No empty normal bag slots"
    end
    if not CContainer.PickupContainerItem then
        return false, "Container pickup API unavailable"
    end
    CContainer.PickupContainerItem(item.bagID, item.slot)
    CContainer.PickupContainerItem(toBag, toSlot)
    if GetCursorInfo() == "item" then
        ClearCursor()
        return false, "Normal bag slot rejected item"
    end
    if takenSlots and toKey then
        takenSlots[toKey] = true
    end
    return true
end

local function MoveBankItemToStorageTarget(item, targetStorage, takenSlots)
    local toBag, toSlot, toKey = FindFreeSlot(targetStorage, takenSlots or {}, item)
    if toBag and toSlot and toKey and CContainer.PickupContainerItem then
        CContainer.PickupContainerItem(item.bagID, item.slot)
        CContainer.PickupContainerItem(toBag, toSlot)
        if GetCursorInfo() == "item" then
            ClearCursor()
            return false, "Target slot rejected item"
        end
        if takenSlots then
            takenSlots[toKey] = true
        end
        return true
    end

    if not CContainer.PickupContainerItem then
        return false, "Container pickup API unavailable"
    end
    return false, "No empty slots in " .. targetStorage
end

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

local function NeedsBankStorage(s)
    return s ~= "Bags" and s ~= "Vendor"
        and (s == STORAGE_PRIVATE_BANK or s == STORAGE_REAGENT_BANK
             or s == STORAGE_WARBAND_BANK or s == STORAGE_ALL_BANK_TABS
             or (s and s:sub(1, #BANK_TAB_PREFIX) == BANK_TAB_PREFIX))
end

local function GetTransferBlockReason(item, source, dest)
    if ns.DB.context.inCombat then return "In combat" end
    if source == dest then return "Source and destination are the same" end

    local needsBank = NeedsBankStorage(source) or NeedsBankStorage(dest)
    if needsBank and not IsBankContextDetected() then
        return "Bank is not open"
    end

    if dest == "Vendor" then
        if not ns.DB.context.vendorOpen then return "Vendor is not open" end
        if not IsVendorSellable(item) then return "Not vendor-sellable" end
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

    if dest == "Bags" then
        if not FindFreeNormalBagSlot({}, item) then
            return "No empty bag slots"
        end
    elseif dest ~= "Vendor" then
        local slot1 = FindFreeSlot(dest, {}, item)
        if not slot1 then
            return "No empty slots in " .. dest
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
        local matches = (itemSource == source)
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
-- ExecuteTransferMove (internal)
-- ===========================================================================

local function ExecuteTransferMove(item, dest, takenSlots)
    if dest == "Vendor" then
        if CContainer.UseContainerItem then
            CContainer.UseContainerItem(item.bagID, item.slot)
            return true, nil
        end
        return false, "UseContainerItem API unavailable"
    elseif dest == "Bags" then
        return MoveBankItemToNormalBag(item, takenSlots)
    else
        local toBag, toSlot, toKey = FindFreeSlot(dest, takenSlots or {}, item)
        if toBag and toSlot and CContainer.PickupContainerItem then
            CContainer.PickupContainerItem(item.bagID, item.slot)
            CContainer.PickupContainerItem(toBag, toSlot)
            if GetCursorInfo() == "item" then
                ClearCursor()
                return false, "Target slot rejected item"
            end
            if takenSlots and toKey then takenSlots[toKey] = true end
            return true, nil
        end
        if not CContainer.PickupContainerItem then
            return false, "Container pickup API unavailable"
        end
        return false, "No empty slots in " .. dest
    end
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
        Print("Cannot transfer " .. (item.name or ("Item " .. item.itemID)) .. ": " .. blocked)
        return
    end
    local moved, err = ExecuteTransferMove(item, dest, {})
    if moved then
        UI.transferSelected[plan.key] = nil
        RemoveMovedItemsFromScan({ [item.key] = true })
        Core.RefreshUI()
        Print("Transferred: " .. (item.name or ("Item " .. item.itemID)))
        Core.ScheduleRescanAfterMove()
    else
        Print("Transfer failed: " .. (err or "unknown error"))
    end
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
    local takenSlots = {}
    local blockedDetails = {}
    for _, plan in ipairs(UI.transferVisible or {}) do
        if UI.transferSelected[plan.key] then
            local item = plan.item
            local blockReason = GetTransferBlockReason(item, source, dest)
            if blockReason then
                blocked = blocked + 1
                if #blockedDetails < 3 then
                    table.insert(blockedDetails, (item.name or ("Item " .. item.itemID)) .. ": " .. blockReason)
                end
            else
                local didMove, err = ExecuteTransferMove(item, dest, takenSlots)
                if didMove then
                    movedKeys[item.key] = true
                    moved = moved + 1
                else
                    blocked = blocked + 1
                    if #blockedDetails < 3 then
                        table.insert(blockedDetails, (item.name or ("Item " .. item.itemID)) .. ": " .. (err or "failed"))
                    end
                end
            end
        end
    end
    UI.transferSelected = {}
    RemoveMovedItemsFromScan(movedKeys)
    Core.RefreshUI()
    Print("Transfer complete: " .. moved .. " moved, " .. blocked .. " blocked.")
    if #blockedDetails > 0 then
        Print("Blocked: " .. table.concat(blockedDetails, "; "))
    end
    if moved > 0 then
        Core.ScheduleRescanAfterMove()
    end
end
