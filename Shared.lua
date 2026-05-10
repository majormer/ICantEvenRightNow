-- I Can't Even Right Now (With My Bags and Bank) — Shared Internals
-- Constants, bag ID resolution, storage utilities, context detection, and shared state.
-- All public symbols are exposed on ns.Private for access by other addon modules.

local ADDON_NAME, ns = ...

ns.Core    = ns.Core    or {}
ns.DB      = ns.DB      or {}
ns.Private = {}

local Core = ns.Core
local Data = ns.Data
local P    = ns.Private

-- ---------------------------------------------------------------------------
-- Display / identity constants
-- ---------------------------------------------------------------------------
P.DISPLAY_NAME     = "I Can't Even Right Now (With My Bags and Bank)"
P.ICON_TEXTURE     = "Interface\\AddOns\\ICantEvenRightNow\\ICantEvenRightNow.png"
P.MINIMAP_LDB_NAME = "ICantEvenRightNow"

-- ---------------------------------------------------------------------------
-- Storage kind string constants (also used as dropdown values)
-- ---------------------------------------------------------------------------
P.STORAGE_BAGS          = "Bags"
P.STORAGE_PRIVATE_BANK  = "Private Bank"
P.STORAGE_REAGENT_BANK  = "Reagent Bank"
P.STORAGE_WARBAND_BANK  = "Warband Bank"
P.STORAGE_ALL_BANK_TABS = "Bank (All Tabs)"
P.BANK_TAB_PREFIX       = "BankTab:"

-- ---------------------------------------------------------------------------
-- Scope constants (used in scanned item records)
-- ---------------------------------------------------------------------------
P.BAG_SCOPE  = "bags"
P.BANK_SCOPE = "bank"

-- ---------------------------------------------------------------------------
-- Filter sentinel values
-- ---------------------------------------------------------------------------
P.EXPANSION_FILTER_ALL         = 0
P.EXPANSION_FILTER_NOT_CURRENT = -1
P.EXPANSION_FILTER_UNKNOWN     = -2

P.BIND_FILTER_ALL      = "All"
P.BIND_FILTER_BOE      = "BoE"
P.BIND_FILTER_WUE      = "WuE"
P.BIND_FILTER_SOULBOUND = "Soulbound"
P.BIND_FILTER_WARBAND  = "Warbound"
P.BIND_FILTER_BOP      = "BoP"

P.TYPE_FILTER_REAGENT        = "Reagent"
P.TYPE_FILTER_BOE            = "BoE"
P.TYPE_FILTER_WUE            = "WuE"
P.TYPE_FILTER_VENDOR_SELLABLE = "Vendor Sellable"

-- Armor type filter values (Armor classID=4, subClassID values)
P.ARMOR_FILTER_ALL    = "All"
P.ARMOR_FILTER_CLOTH  = 1
P.ARMOR_FILTER_LEATHER = 2
P.ARMOR_FILTER_MAIL   = 3
P.ARMOR_FILTER_PLATE  = 4

-- ---------------------------------------------------------------------------
-- Vendor action constants (plan.action values)
-- ---------------------------------------------------------------------------
P.VENDOR_ACTION_RECALL = "Recall to Bags"
P.VENDOR_ACTION_SELL   = "Sell at Vendor"

-- ---------------------------------------------------------------------------
-- Miscellaneous constants
-- ---------------------------------------------------------------------------
P.ORGANIZE_PAGE_SIZE = 6
P.VENDOR_PAGE_SIZE   = 6
P.TAB_ORDER = { "Summary", "Transfer", "Rules", "Settings" }

P.MYTHIC_KEYSTONE_ITEM_IDS = {
    [138019] = true,
    [158923] = true,
    [180653] = true,
}

-- Enum.BagSlotFlags bitmask values for bank tab deposit filters.
-- Source: https://warcraft.wiki.gg/wiki/API_C_Bank.FetchPurchasedBankTabData
P.BAG_SLOT_FLAGS_EQUIPMENT   = 0x2
P.BAG_SLOT_FLAGS_CONSUMABLES = 0x4
P.BAG_SLOT_FLAGS_PROFESSION  = 0x8
P.BAG_SLOT_FLAGS_JUNK        = 0x10
P.BAG_SLOT_FLAGS_REAGENTS    = 0x80

-- Frame names / patterns for bank context detection
P.BANK_FRAME_NAMES = {
    "BetterBagsBagBank", "BagnonFramebank", "BagnonFrameBank",
    "CombuctorFramebank", "CombuctorFrameBank", "LiteBagBankPanel",
    "InventorianBankFrame", "BankFrame", "BankPanelFrame", "BankPanel",
    "BankPanelContainerFrame", "AccountBankPanel", "AccountBankFrame",
    "AccountBankPanelFrame", "WarbandBankFrame", "WarbandBankPanel",
    "WarbandBankPanelFrame", "BetterBagsBankFrame", "BetterBags_BankFrame",
    "BetterBagsBank",
}
P.BANK_FRAME_PATTERNS = {
    "betterbagsbagbank", "bank", "bagnonframebank", "combuctorframebank",
    "litebagbank", "inventorianbank", "bankpanel", "accountbank",
    "warbandbank", "adibagsbank", "sortedbank",
}

-- ---------------------------------------------------------------------------
-- UI shared state table (mutated in place; never replaced)
-- ---------------------------------------------------------------------------
P.UI = {
    frame = nil,
    minimapButton = nil,
    minimapDataObject = nil,
    minimapIconRegistered = false,
    bankButton = nil,
    vendorButton = nil,
    tabs = {},
    activeTab = "Summary",
    rows = {},
    ruleRows = {},
    selected = {},
    organizeSelected = {},
    organizeVisible = {},
    vendorSelected = {},
    vendorVisible = {},
    transferSelected = {},
    transferVisible = {},
    transferSource = "Bags",
    transferDest = "Bank (All Tabs)",
    visible = {},
    bankContextOpen = false,
    bankContextClosed = false,
    vendorContextOpen = false,
    vendorContextClosed = false,
    hadBankContext = false,
    hadVendorContext = false,
}

-- ---------------------------------------------------------------------------
-- File-local aliases
-- ---------------------------------------------------------------------------
local STORAGE_BAGS          = P.STORAGE_BAGS
local STORAGE_PRIVATE_BANK  = P.STORAGE_PRIVATE_BANK
local STORAGE_REAGENT_BANK  = P.STORAGE_REAGENT_BANK
local STORAGE_WARBAND_BANK  = P.STORAGE_WARBAND_BANK
local STORAGE_ALL_BANK_TABS = P.STORAGE_ALL_BANK_TABS
local BANK_TAB_PREFIX       = P.BANK_TAB_PREFIX
local BAG_SCOPE             = P.BAG_SCOPE
local BANK_SCOPE            = P.BANK_SCOPE
local BANK_FRAME_NAMES      = P.BANK_FRAME_NAMES
local BANK_FRAME_PATTERNS   = P.BANK_FRAME_PATTERNS
local CContainer = C_Container

-- ===========================================================================
-- Bag ID resolution
-- ===========================================================================

local function AppendBagID(list, bagID)
    if type(bagID) == "number" then
        table.insert(list, bagID)
    end
end

local function AppendNamedBagID(list, bagIndex, ...)
    if not bagIndex then return end
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        AppendBagID(list, rawget(bagIndex, key))
    end
end

local function UniqueBagIDs(list)
    local seen, unique = {}, {}
    for _, bagID in ipairs(list or {}) do
        if type(bagID) == "number" and not seen[bagID] then
            seen[bagID] = true
            table.insert(unique, bagID)
        end
    end
    return unique
end

local function BuildBackpackIDs()
    local bagIndex = Enum and Enum.BagIndex
    if bagIndex and bagIndex.Backpack then
        local list = {}
        AppendBagID(list, bagIndex.Backpack)
        AppendBagID(list, bagIndex.Bag_1)
        AppendBagID(list, bagIndex.Bag_2)
        AppendBagID(list, bagIndex.Bag_3)
        AppendBagID(list, bagIndex.Bag_4)
        AppendBagID(list, rawget(bagIndex, "ReagentBag"))
        AppendBagID(list, rawget(bagIndex, "Reagentbag"))
        return list
    end
    return { 0, 1, 2, 3, 4 }
end

local function BuildNormalBackpackIDs()
    local bagIndex = Enum and Enum.BagIndex
    if bagIndex and bagIndex.Backpack then
        local list = {}
        AppendBagID(list, bagIndex.Backpack)
        AppendBagID(list, bagIndex.Bag_1)
        AppendBagID(list, bagIndex.Bag_2)
        AppendBagID(list, bagIndex.Bag_3)
        AppendBagID(list, bagIndex.Bag_4)
        return list
    end
    return { 0, 1, 2, 3, 4 }
end

local function BuildPrivateBankIDs()
    local bagIndex = Enum and Enum.BagIndex
    if bagIndex then
        local list = {}
        AppendNamedBagID(list, bagIndex,
            "CharacterBankTab_1", "CharacterBankTab_2", "CharacterBankTab_3",
            "CharacterBankTab_4", "CharacterBankTab_5", "CharacterBankTab_6")
        AppendNamedBagID(list, bagIndex,
            "BankBag_1", "BankBag_2", "BankBag_3", "BankBag_4", "BankBag_5", "BankBag_6", "BankBag_7",
            "Bankbag_1", "Bankbag_2", "Bankbag_3", "Bankbag_4", "Bankbag_5", "Bankbag_6", "Bankbag_7")
        if #list == 0 then
            local reagentBagID = rawget(bagIndex, "ReagentBag")
            if reagentBagID == 5 then
                list = { 6, 7, 8, 9, 10, 11 }
            else
                list = { 5, 6, 7, 8, 9, 10, 11 }
            end
        end
        return UniqueBagIDs(list)
    end
    return { -1, 5, 6, 7, 8, 9, 10, 11 }
end

local function BuildReagentBankIDs()
    local bagIndex = Enum and Enum.BagIndex
    local list = {}
    if bagIndex then
        AppendNamedBagID(list, bagIndex, "Reagentbank", "ReagentBank")
        local hasModernAccountAggregate = rawget(bagIndex, "Accountbanktab") == -3
        local hasModernAccountTabs = rawget(bagIndex, "AccountBankTab_1") ~= nil
        if #list == 0 and not (hasModernAccountAggregate or hasModernAccountTabs) then
            AppendBagID(list, -3)
        end
    else
        AppendBagID(list, -3)
    end
    return UniqueBagIDs(list)
end

local function BuildWarbandBankIDs()
    local bagIndex = Enum and Enum.BagIndex
    local list = {}
    if bagIndex then
        AppendBagID(list, bagIndex.AccountBankTab_1)
        AppendBagID(list, bagIndex.AccountBankTab_2)
        AppendBagID(list, bagIndex.AccountBankTab_3)
        AppendBagID(list, bagIndex.AccountBankTab_4)
        AppendBagID(list, bagIndex.AccountBankTab_5)
    end
    return list
end

local function BuildBagIDSet(...)
    local set = {}
    for i = 1, select("#", ...) do
        local list = select(i, ...)
        for _, bagID in ipairs(list or {}) do
            set[bagID] = true
        end
    end
    return set
end

local function RemoveBagIDs(list, ...)
    local blocked = BuildBagIDSet(...)
    local filtered = {}
    for _, bagID in ipairs(list or {}) do
        if not blocked[bagID] then
            AppendBagID(filtered, bagID)
        end
    end
    return filtered
end

local NORMAL_BAG_IDS   = BuildNormalBackpackIDs()
local BAG_IDS          = BuildBackpackIDs()
local REAGENT_BANK_IDS = BuildReagentBankIDs()
local WARBAND_BANK_IDS = BuildWarbandBankIDs()
local PRIVATE_BANK_IDS = RemoveBagIDs(BuildPrivateBankIDs(), REAGENT_BANK_IDS, WARBAND_BANK_IDS)

-- Shared mutable lookup: bagID → storageKind. Populated here; updated by RefreshBankTabData.
P.STORAGE_BY_BAG_ID = {}
local STORAGE_BY_BAG_ID = P.STORAGE_BY_BAG_ID
for _, bagID in ipairs(PRIVATE_BANK_IDS) do STORAGE_BY_BAG_ID[bagID] = STORAGE_PRIVATE_BANK end
for _, bagID in ipairs(REAGENT_BANK_IDS)  do STORAGE_BY_BAG_ID[bagID] = STORAGE_REAGENT_BANK  end
for _, bagID in ipairs(WARBAND_BANK_IDS)  do STORAGE_BY_BAG_ID[bagID] = STORAGE_WARBAND_BANK  end

-- Expose bag ID lists (read-only by other modules)
P.NORMAL_BAG_IDS   = NORMAL_BAG_IDS
P.BAG_IDS          = BAG_IDS
P.REAGENT_BANK_IDS = REAGENT_BANK_IDS
P.WARBAND_BANK_IDS = WARBAND_BANK_IDS
P.PRIVATE_BANK_IDS = PRIVATE_BANK_IDS

-- Shared mutable bank tab cache. Use wipe() to clear; never replace with a new table.
P.BANK_TAB_DATA = {}
local BANK_TAB_DATA = P.BANK_TAB_DATA

-- Reagent Bank was removed in Patch 11.2.0 (TOC 110200, released August 5 2025).
-- Source: https://warcraft.wiki.gg/wiki/Patch_11.2.0
P.HAS_REAGENT_BANK = #REAGENT_BANK_IDS > 0
local HAS_REAGENT_BANK = P.HAS_REAGENT_BANK

P.BuildBagIDSet = BuildBagIDSet

-- ===========================================================================
-- Bank tab helpers
-- ===========================================================================

local function BankTabStorageKey(bagID)
    return BANK_TAB_PREFIX .. tostring(bagID)
end

local function GetBankTabLabel(tab)
    if tab.name and tab.name ~= "" then
        return "Bank: " .. tab.name
    end
    return "Bank Tab " .. tostring(tab.bagID)
end

P.BankTabStorageKey = BankTabStorageKey
P.GetBankTabLabel   = GetBankTabLabel

-- ===========================================================================
-- Storage utilities
-- ===========================================================================

local function GetStorageKindForBagID(bagID, scope)
    if scope == BAG_SCOPE then return STORAGE_BAGS end
    return STORAGE_BY_BAG_ID[bagID] or STORAGE_PRIVATE_BANK
end

local function GetStorageDisplayName(storageKind)
    if storageKind == "Bags"               then return "Bags" end
    if storageKind == STORAGE_PRIVATE_BANK  then return "Private Bank" end
    if storageKind == STORAGE_REAGENT_BANK  then return "Reagent Bank" end
    if storageKind == STORAGE_WARBAND_BANK  then return "Warband Bank" end
    if storageKind == STORAGE_ALL_BANK_TABS then return STORAGE_ALL_BANK_TABS end
    if storageKind == "Vendor"              then return "Vendor" end
    if storageKind and storageKind:sub(1, #BANK_TAB_PREFIX) == BANK_TAB_PREFIX then
        local bagID = tonumber(storageKind:sub(#BANK_TAB_PREFIX + 1))
        if bagID then
            for _, tab in ipairs(BANK_TAB_DATA) do
                if tab.bagID == bagID then return GetBankTabLabel(tab) end
            end
        end
        return "Bank Tab"
    end
    return storageKind or "Unknown"
end

local function GetStorageBagIDs(storageKind)
    if storageKind == STORAGE_PRIVATE_BANK  then return PRIVATE_BANK_IDS end
    if storageKind == STORAGE_REAGENT_BANK  then return REAGENT_BANK_IDS end
    if storageKind == STORAGE_WARBAND_BANK  then return WARBAND_BANK_IDS end
    if storageKind == STORAGE_ALL_BANK_TABS then
        if #BANK_TAB_DATA > 0 then
            local ids = {}
            for _, tab in ipairs(BANK_TAB_DATA) do
                table.insert(ids, tab.bagID)
            end
            return ids
        end
        return PRIVATE_BANK_IDS
    end
    if storageKind and storageKind:sub(1, #BANK_TAB_PREFIX) == BANK_TAB_PREFIX then
        local bagID = tonumber(storageKind:sub(#BANK_TAB_PREFIX + 1))
        if bagID then return { bagID } end
    end
    return {}
end

P.GetStorageKindForBagID = GetStorageKindForBagID
P.GetStorageDisplayName  = GetStorageDisplayName
P.GetStorageBagIDs       = GetStorageBagIDs

-- ===========================================================================
-- Bank tab data refresh
-- Source: https://warcraft.wiki.gg/wiki/API_C_Bank.FetchPurchasedBankTabData
-- ===========================================================================

local function RefreshBankTabData()
    wipe(BANK_TAB_DATA)
    if not (C_Bank and C_Bank.FetchPurchasedBankTabData) then return end
    if not (Enum and Enum.BankType) then return end
    local tabs = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character)
    if not tabs then return end
    for _, tab in ipairs(tabs) do
        local entry = { bagID = tab.ID, name = tab.name or "", flags = tab.depositFlags or 0 }
        table.insert(BANK_TAB_DATA, entry)
        STORAGE_BY_BAG_ID[tab.ID] = BankTabStorageKey(tab.ID)
    end
    -- Notify UI to rebuild source/dest dropdowns (defined later in UI.lua).
    if Core.RefreshTransferDropdowns then
        Core.RefreshTransferDropdowns()
    end
end

P.RefreshBankTabData = RefreshBankTabData

-- ===========================================================================
-- Legacy storage normalization
-- ===========================================================================

local function NormalizeLegacyBankStorageKinds(items)
    if HAS_REAGENT_BANK then return end
    for _, item in ipairs(items or {}) do
        if item.scope == BANK_SCOPE and item.storageKind == STORAGE_REAGENT_BANK then
            item.storageKind = STORAGE_PRIVATE_BANK
            item.location = STORAGE_PRIVATE_BANK .. " " .. tostring(item.bagID) .. " Slot " .. tostring(item.slot)
        end
    end
end

P.NormalizeLegacyBankStorageKinds = NormalizeLegacyBankStorageKinds

-- ===========================================================================
-- General utilities
-- ===========================================================================

local function Print(msg)
    print("|cFF66CCFF" .. P.DISPLAY_NAME .. ":|r " .. tostring(msg))
end

local function FormatTimestamp(timestamp)
    if not timestamp or timestamp == 0 then return "Never" end
    return date("%Y-%m-%d %H:%M", timestamp)
end

local function FormatMoney(copper)
    copper = copper or 0
    local gold       = math.floor(copper / 10000)
    local silver     = math.floor((copper % 10000) / 100)
    local copperOnly = copper % 100
    if gold > 0   then return gold .. "g " .. silver .. "s" end
    if silver > 0 then return silver .. "s " .. copperOnly .. "c" end
    return copperOnly .. "c"
end

local function LocationKey(item)
    return table.concat({ item.scope or "?", tostring(item.bagID), tostring(item.slot), tostring(item.itemID) }, ":")
end

local function SlotKey(bagID, slot)
    return tostring(bagID) .. ":" .. tostring(slot)
end

local function GetExpansionName(expansionID)
    local expansion = expansionID and Data.Expansions[expansionID]
    return expansion and expansion.name or "Unknown"
end

local function FormatItemLocation(bagID, slot, scope, storageKind)
    storageKind = storageKind or GetStorageKindForBagID(bagID, scope)
    if storageKind == STORAGE_BAGS then
        return "Bag " .. tostring(bagID) .. " Slot " .. tostring(slot)
    end
    return storageKind .. " " .. tostring(bagID) .. " Slot " .. tostring(slot)
end

local function JoinBagIDs(list)
    local parts = {}
    for _, bagID in ipairs(list or {}) do
        table.insert(parts, tostring(bagID))
    end
    return #parts > 0 and table.concat(parts, ", ") or "(none)"
end

local function SafeCopyDefaults(defaults, target)
    target = target or {}
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = SafeCopyDefaults(value, target[key])
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

P.Print              = Print
P.FormatTimestamp    = FormatTimestamp
P.FormatMoney        = FormatMoney
P.LocationKey        = LocationKey
P.SlotKey            = SlotKey
P.GetExpansionName   = GetExpansionName
P.FormatItemLocation = FormatItemLocation
P.JoinBagIDs         = JoinBagIDs
P.SafeCopyDefaults   = SafeCopyDefaults

-- ===========================================================================
-- Transfer source/dest option builders (used by UI dropdowns)
-- ===========================================================================

local function GetTransferSourceOptions()
    local opts = { { text = "Bags", value = "Bags" } }
    local bankOpen = ns.DB and ns.DB.context and ns.DB.context.bankOpen
    if bankOpen then
        if #BANK_TAB_DATA > 0 then
            table.insert(opts, { text = STORAGE_ALL_BANK_TABS, value = STORAGE_ALL_BANK_TABS })
            for _, tab in ipairs(BANK_TAB_DATA) do
                local key = BankTabStorageKey(tab.bagID)
                table.insert(opts, { text = GetBankTabLabel(tab), value = key })
            end
        else
            table.insert(opts, { text = STORAGE_PRIVATE_BANK, value = STORAGE_PRIVATE_BANK })
        end
        table.insert(opts, { text = STORAGE_WARBAND_BANK, value = STORAGE_WARBAND_BANK })
    end
    return opts
end

local function GetTransferDestOptions()
    local opts = GetTransferSourceOptions()
    local bankOpen = ns.DB and ns.DB.context and ns.DB.context.bankOpen
    if bankOpen then
        -- bank options already included by GetTransferSourceOptions
    end
    local vendorOpen = ns.DB and ns.DB.context and ns.DB.context.vendorOpen
    if vendorOpen then
        table.insert(opts, { text = "Vendor", value = "Vendor" })
    end
    return opts
end

P.GetTransferSourceOptions = GetTransferSourceOptions
P.GetTransferDestOptions   = GetTransferDestOptions

-- ===========================================================================
-- Bank context detection
-- ===========================================================================

local function GetShownGlobalFrame(names)
    for _, name in ipairs(names) do
        local frame = _G[name]
        if frame and frame.IsShown and frame:IsShown() then return frame end
    end
    return nil
end

local function GetShownNamedFrameByPattern(namePatterns)
    if not EnumerateFrames then return nil end
    local frame = EnumerateFrames()
    while frame do
        if frame.GetName and frame.IsShown and frame:IsShown() then
            local name = frame:GetName()
            if name then
                local lowerName = name:lower()
                for _, pattern in ipairs(namePatterns) do
                    if lowerName:find(pattern, 1, true) then return frame end
                end
            end
        end
        frame = EnumerateFrames(frame)
    end
    return nil
end

local function IsGlobalFrameShown(name)
    local frame = _G[name]
    return frame and frame.IsShown and frame:IsShown() or false
end

local function IsBankViewableByAPI()
    if not C_Bank then return false end
    if C_Bank.AreAnyBankTypesViewable then
        local ok, viewable = pcall(C_Bank.AreAnyBankTypesViewable)
        if ok and viewable then return true end
    end
    if C_Bank.FetchViewableBankTypes then
        local ok, bankTypes = pcall(C_Bank.FetchViewableBankTypes)
        if ok and type(bankTypes) == "table" then
            for _, bankType in pairs(bankTypes) do
                if bankType ~= nil then return true end
            end
        elseif ok and bankTypes ~= nil then
            return true
        end
    end
    if C_Bank.IsBankTypeViewable and Enum and Enum.BankType then
        for _, key in ipairs({ "Character", "Account" }) do
            local bankType = rawget(Enum.BankType, key)
            if bankType ~= nil then
                local ok, viewable = pcall(C_Bank.IsBankTypeViewable, bankType)
                if ok and viewable then return true end
            end
        end
    end
    if C_Bank.CanViewBank and Enum and Enum.BankType then
        for _, key in ipairs({ "Character", "Account" }) do
            local bankType = rawget(Enum.BankType, key)
            if bankType ~= nil then
                local ok, canView = pcall(C_Bank.CanViewBank, bankType)
                if ok and canView then return true end
            end
        end
    end
    return false
end

local function IsBankStorageAccessible()
    if not CContainer then return false end
    if CContainer.GetContainerNumFreeSlots then
        for _, ids in ipairs({ PRIVATE_BANK_IDS, REAGENT_BANK_IDS, WARBAND_BANK_IDS }) do
            for _, bagID in ipairs(ids or {}) do
                local ok, freeSlots = pcall(CContainer.GetContainerNumFreeSlots, bagID)
                if ok and type(freeSlots) == "number" and freeSlots >= 0 then return true end
            end
        end
    end
    if CContainer.GetContainerItemInfo then
        for _, ids in ipairs({ PRIVATE_BANK_IDS, REAGENT_BANK_IDS, WARBAND_BANK_IDS }) do
            for _, bagID in ipairs(ids or {}) do
                local ok, info = pcall(CContainer.GetContainerItemInfo, bagID, 1)
                if ok and info ~= nil then return true end
            end
        end
    end
    return false
end

local function IsBankInteractionType(interactionType)
    if not Enum or not Enum.PlayerInteractionType then return false end
    return interactionType == Enum.PlayerInteractionType.Banker
        or interactionType == rawget(Enum.PlayerInteractionType, "AccountBanker")
end

local function IsPlayerBankInteractionActive()
    if not C_PlayerInteractionManager or not C_PlayerInteractionManager.IsInteractingWithNpcOfType
        or not Enum or not Enum.PlayerInteractionType then
        return false
    end
    local types = {
        Enum.PlayerInteractionType.Banker,
        rawget(Enum.PlayerInteractionType, "AccountBanker"),
    }
    for _, interactionType in ipairs(types) do
        if interactionType ~= nil then
            local ok, active = pcall(C_PlayerInteractionManager.IsInteractingWithNpcOfType, interactionType)
            if ok and active then return true end
        end
    end
    return false
end

local function IsBankContextDetected()
    return IsPlayerBankInteractionActive()
        or (GetShownGlobalFrame(BANK_FRAME_NAMES) or GetShownNamedFrameByPattern(BANK_FRAME_PATTERNS)) ~= nil
        or IsBankViewableByAPI()
        or IsBankStorageAccessible()
end

P.GetShownGlobalFrame           = GetShownGlobalFrame
P.GetShownNamedFrameByPattern   = GetShownNamedFrameByPattern
P.IsGlobalFrameShown            = IsGlobalFrameShown
P.IsBankViewableByAPI           = IsBankViewableByAPI
P.IsBankStorageAccessible       = IsBankStorageAccessible
P.IsBankInteractionType         = IsBankInteractionType
P.IsPlayerBankInteractionActive = IsPlayerBankInteractionActive
P.IsBankContextDetected         = IsBankContextDetected
