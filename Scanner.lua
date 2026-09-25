-- I Can't Even Right Now (With My Bags and Bank) — Scanner
-- Container scanning, inventory rescanning, and bank diagnostics.

local ADDON_NAME, ns = ...

local Core = ns.Core
local Data = ns.Data
local P    = ns.Private

local BAG_IDS          = P.BAG_IDS
local PRIVATE_BANK_IDS = P.PRIVATE_BANK_IDS
local REAGENT_BANK_IDS = P.REAGENT_BANK_IDS
local WARBAND_BANK_IDS = P.WARBAND_BANK_IDS
local NORMAL_BAG_IDS   = P.NORMAL_BAG_IDS

local BAG_SCOPE  = P.BAG_SCOPE
local BANK_SCOPE = P.BANK_SCOPE
local STORAGE_REAGENT_BANK = P.STORAGE_REAGENT_BANK
local STORAGE_WARBAND_BANK = P.STORAGE_WARBAND_BANK

local UI = P.UI

local GetStorageKindForBagID = P.GetStorageKindForBagID
local FormatItemLocation     = P.FormatItemLocation
local GetBindingDetails      = P.GetBindingDetails
local NormalizeLegacyBankStorageKinds = P.NormalizeLegacyBankStorageKinds
local JoinBagIDs             = P.JoinBagIDs
local BuildBagIDSet          = P.BuildBagIDSet
local Print                  = P.Print

local CContainer = C_Container

-- ===========================================================================
-- RemoveMovedItemsFromScan
-- Removes items whose LocationKey appears in movedKeys from both bag and bank scan lists.
-- Originally missing from source; recovered from build/release/Core.lua.
-- ===========================================================================

local function RemoveMovedItemsFromScan(movedKeys)
    for _, scope in ipairs({ BAG_SCOPE, BANK_SCOPE }) do
        local kept = {}
        for _, item in ipairs(ns.DB.scans[scope] or {}) do
            if not movedKeys[P.LocationKey(item)] then
                table.insert(kept, item)
            end
        end
        ns.DB.scans[scope] = kept
    end
end

P.RemoveMovedItemsFromScan = RemoveMovedItemsFromScan

-- ===========================================================================
-- Container scanning
-- ===========================================================================

-- Returns true when the item's data is not in the client cache yet (and asks
-- the client to load it), so the caller knows a follow-up scan is worthwhile.
local function RequestItemDataIfMissing(itemID)
    if not (C_Item.IsItemDataCachedByID and C_Item.RequestLoadItemDataByID) then
        return false
    end
    if C_Item.IsItemDataCachedByID(itemID) then
        return false
    end
    C_Item.RequestLoadItemDataByID(itemID)
    return true
end

-- Scans one container into output. Returns true if any item's data was missing.
local function ScanContainerBag(bagID, scope, output, storageKind)
    storageKind = storageKind or GetStorageKindForBagID(bagID, scope)
    local missingData = false
    local numSlots = CContainer.GetContainerNumSlots(bagID) or 0
    for slot = 1, numSlots do
        local info = CContainer.GetContainerItemInfo(bagID, slot)
        local itemID = CContainer.GetContainerItemID(bagID, slot)
        if info and itemID then
            if RequestItemDataIfMissing(itemID) then
                missingData = true
            end
            -- Prefer the hyperlink from container info: it carries upgrade-level suffixes
            -- and is more likely to trigger a cache hit than a bare itemID.
            local infoKey = info.hyperlink or itemID
            local name, link, quality, itemLevel, requiredLevel, itemTypeName, itemSubTypeName,
                maxStack, equipLoc, icon, sellPrice, classID, subclassID, bindType, expansionID
                = C_Item.GetItemInfo(infoKey)
            local bindingDetails = GetBindingDetails(bagID, slot, bindType, info.isBound and true or false)
            table.insert(output, {
                itemID        = itemID,
                name          = name or info.itemName or ("Item " .. itemID),
                link          = link,
                icon          = icon or info.iconFileID,
                quality       = quality or info.quality,
                count         = info.stackCount or 1,
                bagID         = bagID,
                slot          = slot,
                scope         = scope,
                storageKind   = storageKind,
                location      = FormatItemLocation(bagID, slot, scope, storageKind),
                classID       = classID,
                subclassID    = subclassID,
                bindType      = bindType,
                equipLoc      = equipLoc,
                itemLevel     = itemLevel,
                requiredLevel = requiredLevel,
                itemTypeName  = itemTypeName,
                itemSubTypeName = itemSubTypeName,
                maxStack      = maxStack,
                sellPrice     = sellPrice,
                expansionID   = expansionID,
                isBound            = bindingDetails.isBound,
                isSoulbound        = bindingDetails.isSoulbound,
                isWarbandBound     = bindingDetails.isWarbandBound,
                accountBankAllowed = bindingDetails.accountBankAllowed,
                bindingScope       = bindingDetails.bindingScope,
            })
        end
    end
    return missingData
end

-- ===========================================================================
-- Item data retry
-- Items not yet in the client cache come back with partial info. Rescan a few
-- times while the client loads them, using one timer at most, then give up
-- until the next real scan.
-- ===========================================================================

local ITEM_DATA_RETRY_DELAY = 1.5
local ITEM_DATA_MAX_RETRIES = 3
local itemDataRetryPending = false
local itemDataRetryAttempts = 0
local itemDataRetryScope = nil

local function ScheduleItemDataRetry(scope)
    if itemDataRetryScope ~= "all" then
        itemDataRetryScope = scope
    end
    if itemDataRetryPending or itemDataRetryAttempts >= ITEM_DATA_MAX_RETRIES then
        return
    end
    itemDataRetryAttempts = itemDataRetryAttempts + 1
    itemDataRetryPending = true
    C_Timer.After(ITEM_DATA_RETRY_DELAY, function()
        itemDataRetryPending = false
        local retryScope = itemDataRetryScope or BAG_SCOPE
        itemDataRetryScope = nil
        Core.ScanInventory(retryScope, true, true)
    end)
end

-- ===========================================================================
-- Core.ScanInventory
-- ===========================================================================

function Core.ScanInventory(scope, quiet, isItemDataRetry)
    Core.UpdateContext()
    if not isItemDataRetry then
        itemDataRetryAttempts = 0
    end
    local missingData = false
    scope = (scope and scope:lower()) or BAG_SCOPE

    local scanBags = scope == "" or scope == BAG_SCOPE or scope == "all"
    local scanBank = scope == BANK_SCOPE or scope == "all"

    if scanBank and not ns.DB.context.bankOpen then
        if not quiet then
            Print("Open the bank before scanning bank contents.")
        end
        scanBank = false
    end

    if scanBags then
        local bagItems = {}
        for _, bagID in ipairs(BAG_IDS) do
            missingData = ScanContainerBag(bagID, BAG_SCOPE, bagItems) or missingData
        end
        ns.DB.scans.bags = bagItems
        ns.DB.lastScan.bags = time()
        if not quiet then
            Print("Scanned bags: " .. #bagItems .. " item stacks.")
        end
    end

    if scanBank then
        local bankItems = {}
        for _, bagID in ipairs(PRIVATE_BANK_IDS) do
            -- GetStorageKindForBagID returns a named BankTab:N key when tab data is
            -- available (populated by RefreshBankTabData on bank open), otherwise
            -- falls back to STORAGE_PRIVATE_BANK.
            missingData = ScanContainerBag(bagID, BANK_SCOPE, bankItems) or missingData
        end
        for _, bagID in ipairs(REAGENT_BANK_IDS) do
            missingData = ScanContainerBag(bagID, BANK_SCOPE, bankItems, STORAGE_REAGENT_BANK) or missingData
        end
        for _, bagID in ipairs(WARBAND_BANK_IDS) do
            missingData = ScanContainerBag(bagID, BANK_SCOPE, bankItems, STORAGE_WARBAND_BANK) or missingData
        end
        NormalizeLegacyBankStorageKinds(bankItems)
        ns.DB.scans.bank = bankItems
        ns.DB.lastScan.bank = time()
        if not quiet then
            Print("Scanned bank: " .. #bankItems .. " item stacks.")
        end
    end

    if UI.frame and UI.frame:IsShown() then
        Core.RefreshUI()
    end

    if missingData then
        ScheduleItemDataRetry(scanBank and "all" or BAG_SCOPE)
    end
end


-- ===========================================================================
-- Core.ScheduleRescanAfterMove
-- Fallback rescan once moved items have settled. BAG_UPDATE_DELAYED also
-- triggers a debounced refresh (Core.ScheduleInventoryRefresh).
-- ===========================================================================

function Core.ScheduleRescanAfterMove()
    C_Timer.After(1.0, function()
        Core.ScanInventory("all", true)
    end)
end

-- ===========================================================================
-- Core.PrintBankContainerDiagnostics
-- ===========================================================================

function Core.PrintBankContainerDiagnostics()
    Print("=== Bank Container Diagnostics ===")
    Print("Private bank bags: " .. JoinBagIDs(PRIVATE_BANK_IDS))
    Print("Reagent bank bags: " .. JoinBagIDs(REAGENT_BANK_IDS))
    Print("Warband bank bags: " .. JoinBagIDs(WARBAND_BANK_IDS))

    local allBankIDs = {}
    for _, id in ipairs(PRIVATE_BANK_IDS)  do table.insert(allBankIDs, id) end
    for _, id in ipairs(REAGENT_BANK_IDS)  do table.insert(allBankIDs, id) end
    for _, id in ipairs(WARBAND_BANK_IDS)  do table.insert(allBankIDs, id) end

    local bankSet = BuildBagIDSet(PRIVATE_BANK_IDS, REAGENT_BANK_IDS, WARBAND_BANK_IDS)

    if not CContainer then
        Print("C_Container is not available.")
        return
    end

    for _, bagID in ipairs(allBankIDs) do
        local numSlots = (CContainer.GetContainerNumSlots and CContainer.GetContainerNumSlots(bagID)) or 0
        local freeSlots = (CContainer.GetContainerNumFreeSlots and CContainer.GetContainerNumFreeSlots(bagID)) or 0
        local storageKind = GetStorageKindForBagID(bagID, BANK_SCOPE)
        Print(string.format("  Bag %d (%s): %d total slots, %d free", bagID, storageKind, numSlots, freeSlots))
    end

    if Enum and Enum.BagIndex then
        Print("Enum.BagIndex entries:")
        for key, value in pairs(Enum.BagIndex) do
            if type(value) == "number" then
                local inBank = bankSet[value] and " [BANK]" or ""
                Print(string.format("  Enum.BagIndex.%s = %d%s", key, value, inBank))
            end
        end
    else
        Print("Enum.BagIndex is not available.")
    end
end
