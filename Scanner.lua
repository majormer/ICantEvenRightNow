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
    P.RemoveFromSnapshots(movedKeys)
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

-- Static item details (name, class, expansion...) by item ID, from any lookup
-- that succeeded this session or any earlier saved scan. Used when the client
-- hasn't loaded an item's data yet, so a scan never loses what was known.
local STATIC_FIELDS = {
    "name", "quality", "itemLevel", "requiredLevel", "itemTypeName", "itemSubTypeName",
    "maxStack", "equipLoc", "icon", "sellPrice", "classID", "subclassID", "bindType", "expansionID",
}
local knownItemInfo = nil

local function HasFullData(item)
    return item.classID ~= nil and item.expansionID ~= nil and type(item.name) == "string"
        and item.name ~= "" and not item.name:match("^Item %d+$")
end

local function KnownItemInfo()
    if knownItemInfo then return knownItemInfo end
    knownItemInfo = {}
    if P.AllSnapshots then
        for _, snapshot in ipairs(P.AllSnapshots()) do
            for _, item in ipairs(snapshot.items or {}) do
                if item.itemID and not knownItemInfo[item.itemID] and HasFullData(item) then
                    local info = {}
                    for _, field in ipairs(STATIC_FIELDS) do info[field] = item[field] end
                    knownItemInfo[item.itemID] = info
                end
            end
        end
    end
    return knownItemInfo
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
            local hyperlink = info.hyperlink
                or (CContainer.GetContainerItemLink and CContainer.GetContainerItemLink(bagID, slot)) or nil
            local infoKey = hyperlink or itemID
            local name, link, quality, itemLevel, requiredLevel, itemTypeName, itemSubTypeName,
                maxStack, equipLoc, icon, sellPrice, classID, subclassID, bindType, expansionID
                = C_Item.GetItemInfo(infoKey)
            if not name and infoKey ~= itemID then
                -- If the link lookup comes back empty while the item may be
                -- cached by ID, fall back to the item ID.
                name, link, quality, itemLevel, requiredLevel, itemTypeName, itemSubTypeName,
                    maxStack, equipLoc, icon, sellPrice, classID, subclassID, bindType, expansionID
                    = C_Item.GetItemInfo(itemID)
                link = hyperlink or link
            end
            local known = KnownItemInfo()
            if name then
                known[itemID] = known[itemID] or {}
                local k = known[itemID]
                k.name, k.quality, k.itemLevel, k.requiredLevel, k.itemTypeName, k.itemSubTypeName = name, quality, itemLevel, requiredLevel, itemTypeName, itemSubTypeName
                k.maxStack, k.equipLoc, k.icon, k.sellPrice, k.classID, k.subclassID, k.bindType, k.expansionID = maxStack, equipLoc, icon, sellPrice, classID, subclassID, bindType, expansionID
            else
                missingData = true
                if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
                -- Keep what an earlier scan knew until the client loads the data.
                local k = known[itemID]
                if k then
                    name, quality, itemLevel, requiredLevel, itemTypeName, itemSubTypeName = k.name, k.quality, k.itemLevel, k.requiredLevel, k.itemTypeName, k.itemSubTypeName
                    maxStack, equipLoc, icon, sellPrice, classID, subclassID, bindType, expansionID = k.maxStack, k.equipLoc, k.icon, k.sellPrice, k.classID, k.subclassID, k.bindType, k.expansionID
                end
            end
            local bindingDetails = GetBindingDetails(bagID, slot, bindType, info.isBound and true or false)
            -- Quest status belongs to the character that owns the item, so it is
            -- captured now (other characters' snapshots are read later).
            local questInfo = CContainer.GetContainerItemQuestInfo
                and CContainer.GetContainerItemQuestInfo(bagID, slot) or nil
            local questID = questInfo and questInfo.questID or nil
            local questCompleted = questID and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
                and C_QuestLog.IsQuestFlaggedCompleted(questID) or false
            table.insert(output, {
                itemID        = itemID,
                name          = P.ItemDisplayName(name or info.itemName, link or hyperlink, itemID),
                link          = link or hyperlink,
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
                isQuestItem        = questInfo and questInfo.isQuestItem or false,
                questID            = questID,
                questActive        = questInfo and questInfo.isActive or false,
                questCompleted     = questCompleted and true or false,
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

-- The client reports each requested item as it arrives. While the last scan
-- was missing data, rescan once per burst of arrivals (debounced), up to a cap
-- per real scan so a never-loading item can't cause endless rescans.
local ITEM_ARRIVAL_DEBOUNCE = 1.0
local ITEM_ARRIVAL_MAX_RESCANS = 10
local waitingForItemData = nil
local arrivalRescans = 0
local arrivalRescanPending = false

local itemDataFrame = CreateFrame("Frame")
itemDataFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemDataFrame:SetScript("OnEvent", function()
    if not waitingForItemData or arrivalRescanPending or arrivalRescans >= ITEM_ARRIVAL_MAX_RESCANS then return end
    arrivalRescanPending = true
    arrivalRescans = arrivalRescans + 1
    C_Timer.After(ITEM_ARRIVAL_DEBOUNCE, function()
        arrivalRescanPending = false
        local scope = waitingForItemData
        if not scope then return end
        if scope == "all" and not ns.DB.context.bankOpen then scope = BAG_SCOPE end
        Core.ScanInventory(scope, true, true)
    end)
end)

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
        arrivalRescans = 0
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
        P.SetScanList(BAG_SCOPE, bagItems)
        P.MarkScanned(BAG_SCOPE)
        if P.RecordTimeHeld then P.RecordTimeHeld(P.LocationKeyFor(BAG_SCOPE), bagItems) end
        if not quiet then
            Print("Scanned bags: " .. #bagItems .. " item stacks.")
        end
    end

    if scanBank then
        local bankItems = {}
        local warbandItems = {}
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
            missingData = ScanContainerBag(bagID, BANK_SCOPE, warbandItems, STORAGE_WARBAND_BANK) or missingData
        end
        NormalizeLegacyBankStorageKinds(bankItems)
        -- Character bank belongs to this character; the Warband bank is shared
        -- by the account, so its snapshot is stored once.
        P.SetScanList(BANK_SCOPE, bankItems)
        P.MarkScanned(BANK_SCOPE)
        P.SetWarbandItems(warbandItems)
        if P.RecordTimeHeld then
            P.RecordTimeHeld(P.LocationKeyFor(BANK_SCOPE), bankItems)
            P.RecordTimeHeld(P.LocationKeyFor("warband"), warbandItems)
        end
        if not quiet then
            Print("Scanned bank: " .. (#bankItems + #warbandItems) .. " item stacks.")
        end
    end

    if P.CleanupHandoffs then pcall(P.CleanupHandoffs) end

    if UI.frame and UI.frame:IsShown() then
        Core.RefreshUI()
    end

    if missingData then
        waitingForItemData = (scanBank or waitingForItemData == "all") and "all" or BAG_SCOPE
        ScheduleItemDataRetry(scanBank and "all" or BAG_SCOPE)
    else
        waitingForItemData = nil
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
