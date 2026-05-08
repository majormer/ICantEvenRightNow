-- I Can't Even Right Now (With My Bags and Bank) Core Module
-- Main addon logic, event handlers, scanning, decisions, movement, and UI.

local ADDON_NAME, ns = ...

ns.Core = {}
ns.DB = {}

local Core = ns.Core
local Data = ns.Data
local Debug = ns.Debug
local DISPLAY_NAME = "I Can't Even Right Now (With My Bags and Bank)"
local ICON_TEXTURE = "Interface\\AddOns\\ICantEvenRightNow\\ICantEvenRightNow.png"

local CContainer = C_Container
local TAB_ORDER = { "Summary", "Move", "Organize", "Vendor", "Rules", "Settings" }
local UI = {
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
    visible = {},
    bankContextOpen = false,
    bankContextClosed = false,
    vendorContextOpen = false,
    vendorContextClosed = false,
    hadBankContext = false,
    hadVendorContext = false,
    page = 1,
    pageSize = 6,
}

local BAG_SCOPE = "bags"
local BANK_SCOPE = "bank"
local EXPANSION_FILTER_ALL = 0
local EXPANSION_FILTER_NOT_CURRENT = -1
local EXPANSION_FILTER_UNKNOWN = -2
local ORGANIZE_PAGE_SIZE = 6
local VENDOR_PAGE_SIZE = 6
local STORAGE_BAGS = "Bags"
local STORAGE_PRIVATE_BANK = "Private Bank"
local STORAGE_REAGENT_BANK = "Reagent Bank"
local STORAGE_WARBAND_BANK = "Warband Bank"
local TYPE_FILTER_REAGENT = "Reagent"
local TYPE_FILTER_BOE = "BoE"
local TYPE_FILTER_WUE = "WuE"
local TYPE_FILTER_VENDOR_SELLABLE = "Vendor Sellable"
local BIND_FILTER_ALL = "All"
local BIND_FILTER_BOE = "BoE"
local BIND_FILTER_WUE = "WuE"
local BIND_FILTER_SOULBOUND = "Soulbound"
local BIND_FILTER_WARBAND = "Warbound"
local BIND_FILTER_BOP = "BoP"
local VENDOR_ACTION_RECALL = "Recall to Bags"
local VENDOR_ACTION_SELL = "Sell at Vendor"
local MINIMAP_LDB_NAME = "ICantEvenRightNow"
local BANK_FRAME_NAMES = {
    "BetterBagsBagBank",
    "BagnonFramebank",
    "BagnonFrameBank",
    "CombuctorFramebank",
    "CombuctorFrameBank",
    "LiteBagBankPanel",
    "InventorianBankFrame",
    "BankFrame",
    "BankPanelFrame",
    "BankPanel",
    "BankPanelContainerFrame",
    "AccountBankPanel",
    "AccountBankFrame",
    "AccountBankPanelFrame",
    "WarbandBankFrame",
    "WarbandBankPanel",
    "WarbandBankPanelFrame",
    "BetterBagsBankFrame",
    "BetterBags_BankFrame",
    "BetterBagsBank",
}
local BANK_FRAME_PATTERNS = {
    "betterbagsbagbank",
    "bank",
    "bagnonframebank",
    "combuctorframebank",
    "litebagbank",
    "inventorianbank",
    "bankpanel",
    "accountbank",
    "warbandbank",
    "adibagsbank",
    "sortedbank",
}
local MYTHIC_KEYSTONE_ITEM_IDS = {
    [138019] = true,
    [158923] = true,
    [180653] = true,
}

local function AppendBagID(list, bagID)
    if type(bagID) == "number" then
        table.insert(list, bagID)
    end
end

local function AppendNamedBagID(list, bagIndex, ...)
    if not bagIndex then
        return
    end
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        AppendBagID(list, rawget(bagIndex, key))
    end
end

local function UniqueBagIDs(list)
    local seen = {}
    local unique = {}
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

        -- Legacy naming seen in older clients/docs.
        AppendNamedBagID(list, bagIndex,
            "BankBag_1", "BankBag_2", "BankBag_3", "BankBag_4", "BankBag_5", "BankBag_6", "BankBag_7",
            "Bankbag_1", "Bankbag_2", "Bankbag_3", "Bankbag_4", "Bankbag_5", "Bankbag_6", "Bankbag_7")

        if #list == 0 then
            -- Prefer explicit tab IDs over Characterbanktab because that value can
            -- represent an aggregate/current tab in modern UI flows.
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
            -- Legacy fallback: reagent bank container used -3 prior to modern account bank IDs.
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
    for index = 1, select("#", ...) do
        local list = select(index, ...)
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

local NORMAL_BAG_IDS = BuildNormalBackpackIDs()
local BAG_IDS = BuildBackpackIDs()
local REAGENT_BANK_IDS = BuildReagentBankIDs()
local WARBAND_BANK_IDS = BuildWarbandBankIDs()
local PRIVATE_BANK_IDS = RemoveBagIDs(BuildPrivateBankIDs(), REAGENT_BANK_IDS, WARBAND_BANK_IDS)
local STORAGE_BY_BAG_ID = {}
for _, bagID in ipairs(PRIVATE_BANK_IDS) do STORAGE_BY_BAG_ID[bagID] = STORAGE_PRIVATE_BANK end
for _, bagID in ipairs(REAGENT_BANK_IDS) do STORAGE_BY_BAG_ID[bagID] = STORAGE_REAGENT_BANK end
for _, bagID in ipairs(WARBAND_BANK_IDS) do STORAGE_BY_BAG_ID[bagID] = STORAGE_WARBAND_BANK end

local function HasReagentBankStorage()
    return #REAGENT_BANK_IDS > 0
end

local function NormalizeLegacyBankStorageKinds(items)
    if HasReagentBankStorage() then
        return
    end
    for _, item in ipairs(items or {}) do
        if item.scope == BANK_SCOPE and item.storageKind == STORAGE_REAGENT_BANK then
            item.storageKind = STORAGE_PRIVATE_BANK
            item.location = STORAGE_PRIVATE_BANK .. " " .. tostring(item.bagID) .. " Slot " .. tostring(item.slot)
        end
    end
end

local GROUP_ORDER = {
    "Unknown / needs review",
    "Recommended bank candidates",
    "Recommended recall candidates",
    "Obsolete consumables",
    "Old BoEs",
    "Protected / blocked",
    "Ignored",
}

local function Print(msg)
    print("|cFF66CCFF" .. DISPLAY_NAME .. ":|r " .. tostring(msg))
end

local function JoinBagIDs(list)
    local parts = {}
    for _, bagID in ipairs(list or {}) do
        table.insert(parts, tostring(bagID))
    end
    return #parts > 0 and table.concat(parts, ", ") or "(none)"
end

function Core.PrintBankContainerDiagnostics()
    Core.UpdateContext()
    Print("Bank diagnostics start (bankOpen=" .. tostring(ns.DB.context.bankOpen) .. ")")

    local bagIndex = Enum and Enum.BagIndex
    if bagIndex then
        local fields = {
            "Characterbanktab", "Accountbanktab", "ReagentBank", "Reagentbank", "ReagentBag",
            "CharacterBankTab_1", "CharacterBankTab_2", "CharacterBankTab_3",
            "CharacterBankTab_4", "CharacterBankTab_5", "CharacterBankTab_6",
            "AccountBankTab_1", "AccountBankTab_2", "AccountBankTab_3",
            "AccountBankTab_4", "AccountBankTab_5",
        }
        local enumParts = {}
        for _, key in ipairs(fields) do
            local value = rawget(bagIndex, key)
            if type(value) == "number" then
                table.insert(enumParts, key .. "=" .. tostring(value))
            end
        end
        Print("Enum.BagIndex: " .. (#enumParts > 0 and table.concat(enumParts, "; ") or "(no numeric fields found)"))
    else
        Print("Enum.BagIndex unavailable")
    end

    if C_PlayerInteractionManager and C_PlayerInteractionManager.IsInteractingWithNpcOfType and Enum and Enum.PlayerInteractionType then
        local bankerOK, bankerActive = pcall(C_PlayerInteractionManager.IsInteractingWithNpcOfType, Enum.PlayerInteractionType.Banker)
        local accountBanker = rawget(Enum.PlayerInteractionType, "AccountBanker")
        local accountOK, accountActive = false, false
        if accountBanker ~= nil then
            accountOK, accountActive = pcall(C_PlayerInteractionManager.IsInteractingWithNpcOfType, accountBanker)
        end
        Print("Player interaction: Banker=" .. tostring(bankerOK and bankerActive) .. "; AccountBanker=" .. tostring(accountOK and accountActive))
    else
        Print("Player interaction bank probe unavailable")
    end

    if C_Bank then
        if C_Bank.AreAnyBankTypesViewable then
            local ok, viewable = pcall(C_Bank.AreAnyBankTypesViewable)
            Print("C_Bank.AreAnyBankTypesViewable: " .. tostring(ok and viewable))
        end
        if C_Bank.FetchViewableBankTypes then
            local ok, bankTypes = pcall(C_Bank.FetchViewableBankTypes)
            local count = 0
            if ok and type(bankTypes) == "table" then
                for _, bankType in pairs(bankTypes) do
                    if bankType ~= nil then count = count + 1 end
                end
            elseif ok and bankTypes ~= nil then
                count = 1
            end
            Print("C_Bank.FetchViewableBankTypes count: " .. tostring(ok and count or "unavailable"))
        end
    else
        Print("C_Bank unavailable")
    end

    Print("Resolved private IDs: " .. JoinBagIDs(PRIVATE_BANK_IDS))
    Print("Resolved reagent IDs: " .. JoinBagIDs(REAGENT_BANK_IDS))
    Print("Resolved warband IDs: " .. JoinBagIDs(WARBAND_BANK_IDS))
    if not HasReagentBankStorage() then
        Print("Reagent-bank container is not available in this client; profession mats use private bank storage.")
    end

    local overlapSet = BuildBagIDSet(PRIVATE_BANK_IDS, REAGENT_BANK_IDS, WARBAND_BANK_IDS)
    local overlapCounts = {}
    for bagID in pairs(overlapSet) do
        local hits = 0
        if BuildBagIDSet(PRIVATE_BANK_IDS)[bagID] then hits = hits + 1 end
        if BuildBagIDSet(REAGENT_BANK_IDS)[bagID] then hits = hits + 1 end
        if BuildBagIDSet(WARBAND_BANK_IDS)[bagID] then hits = hits + 1 end
        if hits > 1 then
            table.insert(overlapCounts, tostring(bagID))
        end
    end
    table.sort(overlapCounts, function(a, b) return tonumber(a) < tonumber(b) end)
    Print("Resolved overlaps: " .. (#overlapCounts > 0 and table.concat(overlapCounts, ", ") or "none"))

    local function ReportSlots(label, ids)
        local parts = {}
        for _, bagID in ipairs(ids) do
            local slots = CContainer.GetContainerNumSlots(bagID) or 0
            table.insert(parts, tostring(bagID) .. "=" .. tostring(slots))
        end
        Print(label .. " slots: " .. (#parts > 0 and table.concat(parts, ", ") or "(none)"))
    end

    ReportSlots("Private", PRIVATE_BANK_IDS)
    ReportSlots("Reagent", REAGENT_BANK_IDS)
    ReportSlots("Warband", WARBAND_BANK_IDS)

    local countsByStorage = {
        [STORAGE_PRIVATE_BANK] = 0,
        [STORAGE_REAGENT_BANK] = 0,
        [STORAGE_WARBAND_BANK] = 0,
    }
    for _, item in ipairs(ns.DB.scans.bank or {}) do
        local storage = item.storageKind or STORAGE_BY_BAG_ID[item.bagID] or STORAGE_PRIVATE_BANK
        if countsByStorage[storage] then
            countsByStorage[storage] = countsByStorage[storage] + 1
        end
    end
    Print("Last bank scan counts: Private=" .. tostring(countsByStorage[STORAGE_PRIVATE_BANK])
        .. ", Reagent=" .. tostring(countsByStorage[STORAGE_REAGENT_BANK])
        .. ", Warband=" .. tostring(countsByStorage[STORAGE_WARBAND_BANK]))

    Print("Bank diagnostics end")
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

local function IsBankBag(bagID)
    if bagID == -1 or bagID == -3 then
        return true
    end
    return bagID >= 5 and bagID <= 11
end

local function GetExpansionName(expansionID)
    local expansion = expansionID and Data.Expansions[expansionID]
    return expansion and expansion.name or "Unknown"
end

local function FormatTimestamp(timestamp)
    if not timestamp or timestamp == 0 then
        return "Never"
    end
    return date("%Y-%m-%d %H:%M", timestamp)
end

local function FormatMoney(copper)
    copper = copper or 0
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperOnly = copper % 100
    if gold > 0 then
        return gold .. "g " .. silver .. "s"
    elseif silver > 0 then
        return silver .. "s " .. copperOnly .. "c"
    end
    return copperOnly .. "c"
end

local function LocationKey(item)
    return table.concat({ item.scope or "?", tostring(item.bagID), tostring(item.slot), tostring(item.itemID) }, ":")
end

local function SlotKey(bagID, slot)
    return tostring(bagID) .. ":" .. tostring(slot)
end

local function GetStorageKindForBagID(bagID, scope)
    if scope == BAG_SCOPE then
        return STORAGE_BAGS
    end
    return STORAGE_BY_BAG_ID[bagID] or STORAGE_PRIVATE_BANK
end

local function FormatItemLocation(bagID, slot, scope, storageKind)
    storageKind = storageKind or GetStorageKindForBagID(bagID, scope)
    if storageKind == STORAGE_BAGS then
        return "Bag " .. tostring(bagID) .. " Slot " .. tostring(slot)
    end
    return storageKind .. " " .. tostring(bagID) .. " Slot " .. tostring(slot)
end

local function FindCuratedItem(itemID)
    for _, tableByExpansion in pairs(Data.CuratedItems) do
        if tableByExpansion[itemID] then
            return tableByExpansion[itemID]
        end
    end
    return nil
end

local function EnsureRule(itemID)
    ns.DB.rules.items[itemID] = ns.DB.rules.items[itemID] or {
        protect = false,
        neverMove = false,
        neverSell = false,
        ignore = false,
        expansionOverride = nil,
        actionOverride = nil,
        notes = nil,
        createdFrom = "Rules tab",
    }
    return ns.DB.rules.items[itemID]
end

local function IsMythicKeystone(item)
    if MYTHIC_KEYSTONE_ITEM_IDS[item.itemID] then
        return true
    end
    return item.name == "Mythic Keystone"
end

local function GetBindingDetails(bagID, slot, bindType, fallbackIsBound)
    local details = {
        bindingScope = fallbackIsBound and "Bound" or "Unbound",
        isBound = fallbackIsBound and true or false,
        isSoulbound = false,
        isWarbandBound = false,
        accountBankAllowed = not fallbackIsBound,
    }

    if bindType == 2 then
        details.bindingScope = "BoE"
    elseif bindType == 3 then
        details.bindingScope = "Bind on Use"
    elseif bindType == 4 then
        details.bindingScope = "Quest"
        details.isBound = true
    elseif bindType == 8 then
        details.bindingScope = "Battle.net Account"
        details.isWarbandBound = true
        details.accountBankAllowed = true
    end

    if not (ItemLocation and C_Item) then
        return details
    end

    local itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slot)
    if not itemLocation then
        return details
    end

    if C_Item.IsBound then
        local ok, isBound = pcall(C_Item.IsBound, itemLocation)
        if ok then
            details.isBound = isBound and true or false
            if not details.isBound and details.bindingScope == "Bound" then
                details.bindingScope = "Unbound"
            end
        end
    end

    if C_Item.IsBoundToAccountUntilEquip then
        local ok, isWarboundUntilEquipped = pcall(C_Item.IsBoundToAccountUntilEquip, itemLocation)
        if ok and isWarboundUntilEquipped then
            details.bindingScope = "Warbound Until Equipped"
            details.isWarbandBound = true
            details.accountBankAllowed = true
        end
    end

    if details.isBound then
        details.isSoulbound = true
        details.accountBankAllowed = false
        if C_Bank and C_Bank.IsItemAllowedInBankType and Enum and Enum.BankType and Enum.BankType.Account then
            local ok, allowed = pcall(C_Bank.IsItemAllowedInBankType, Enum.BankType.Account, itemLocation)
            if ok and allowed then
                details.bindingScope = "Warbound"
                details.isSoulbound = false
                details.isWarbandBound = true
                details.accountBankAllowed = true
            else
                details.bindingScope = details.bindingScope == "Quest" and "Quest" or "Soulbound"
            end
        else
            details.bindingScope = details.bindingScope == "Quest" and "Quest" or "Soulbound"
        end
    elseif details.bindingScope ~= "Warbound Until Equipped" then
        details.accountBankAllowed = true
        -- Unbound items may still be warband-eligible (e.g. current-expansion crafting mats
        -- the game allows in the account bank). Check explicitly so Organize can route them.
        if not details.isWarbandBound and itemLocation
            and C_Bank and C_Bank.IsItemAllowedInBankType
            and Enum and Enum.BankType and Enum.BankType.Account then
            local ok, allowed = pcall(C_Bank.IsItemAllowedInBankType, Enum.BankType.Account, itemLocation)
            if ok and allowed then
                details.isWarbandBound = true
            end
        end
    end

    return details
end

local function GetItemType(item)
    if item.rule and item.rule.typeOverride then
        return item.rule.typeOverride
    end
    if item.curated and item.curated.type then
        return item.curated.type
    end
    if IsMythicKeystone(item) then
        return Data.ItemTypes.SEASONAL
    end
    if item.classID == 0 then
        return Data.ItemTypes.CONSUMABLE
    elseif item.classID == 7 then
        return Data.ItemTypes.PROFESSION
    elseif item.classID == 12 then
        return Data.ItemTypes.QUEST
    elseif item.bindType == 2 and (item.classID == 2 or item.classID == 4) then
        return Data.ItemTypes.BOE
    elseif item.classID == 2 or item.classID == 4 then
        return Data.ItemTypes.EQUIPMENT
    end
    return Data.ItemTypes.UNKNOWN
end

local function IsCurrentExpansion(expansionID)
    return not expansionID or expansionID >= Data.CurrentExpansionID
end

local function IsOldExpansion(expansionID)
    return expansionID ~= nil and expansionID < Data.CurrentExpansionID
end

local function IsUnknownExpansion(expansionID)
    return expansionID == nil
end

local function SetBankOrRecallDecision(item, bankGroup, bankReason, recallReason)
    if item.scope == BANK_SCOPE then
        return "Recommended recall candidates", Data.Recommendations.RECALL, Data.Actions.RECALL, recallReason or bankReason
    end
    return bankGroup, Data.Recommendations.BANK, Data.Actions.BANK, bankReason
end

local function IsTransferableSharedValueItem(item, itemType)
    itemType = itemType or item.typeTag
    return item.accountBankAllowed
        and itemType ~= Data.ItemTypes.EQUIPMENT
        and itemType ~= Data.ItemTypes.PROFESSION
        and itemType ~= Data.ItemTypes.QUEST
        and itemType ~= Data.ItemTypes.SEASONAL
end

-- Returns a set of item subclassIDs (classID 7) used by this character's professions.
-- Returns an empty table when profession data is unavailable; callers must treat that
-- as "unknown" and fall back to the conservative default (keep mats on this character).
local function GetCharacterProfessionSubclasses()
    local subclasses = {}
    if not GetProfessions or not GetProfessionInfo then
        return subclasses
    end
    local slots = { GetProfessions() }
    for _, slot in ipairs(slots) do
        if slot then
            local _, _, _, _, _, _, skillLine = GetProfessionInfo(slot)
            local mapped = Data.ProfessionSubclasses and Data.ProfessionSubclasses[skillLine]
            if mapped then
                for _, sc in ipairs(mapped) do
                    subclasses[sc] = true
                end
            end
        end
    end
    return subclasses
end

local function GetPreferredProfessionStorage(item, charProfSubclasses)
    local noProfData = not next(charProfSubclasses)
    local isCharMat = noProfData or (charProfSubclasses[item.subclassID or -1] == true)
    if isCharMat then
        if #REAGENT_BANK_IDS > 0 then
            return STORAGE_REAGENT_BANK, "Crafting material for this character belongs in the reagent bank"
        end
        return STORAGE_PRIVATE_BANK, "Crafting material for this character belongs in character storage"
    elseif item.accountBankAllowed then
        return STORAGE_WARBAND_BANK, "Crafting material for other professions belongs in shared storage"
    end
    return STORAGE_PRIVATE_BANK, "Bound crafting material belongs in character storage"
end

local function GetPreferredBankStorage(item, itemType, charProfSubclasses)
    itemType = itemType or item.typeTag
    if itemType == Data.ItemTypes.PROFESSION then
        return GetPreferredProfessionStorage(item, charProfSubclasses or GetCharacterProfessionSubclasses())
    elseif IsTransferableSharedValueItem(item, itemType) then
        return STORAGE_WARBAND_BANK, IsUnknownExpansion(item.expansionID)
            and "Transferable item with unknown expansion belongs in shared storage"
            or "Transferable non-profession item belongs in shared storage"
    end
    return STORAGE_PRIVATE_BANK, "Item can be stored in the private bank"
end

local function BuildDecision(item)
    local rule = ns.DB.rules.items[item.itemID]
    item.rule = rule
    item.curated = FindCuratedItem(item.itemID)

    local expansionID = rule and rule.expansionOverride or item.expansionID
    if item.curated and item.curated.expansion then
        expansionID = expansionID or item.curated.expansion
    end

    local itemType = GetItemType(item)
    local blocked = {}
    local group = "Unknown / needs review"
    local recommendation = Data.Recommendations.REVIEW
    local action = Data.Actions.REVIEW
    local reason = "Needs player review before moving"
    local bankTargetStorage

    if rule and rule.ignore then
        group = "Ignored"
        recommendation = Data.Recommendations.IGNORED
        action = Data.Actions.NONE
        reason = "Ignored by item rule"
        table.insert(blocked, "Ignored")
    elseif rule and (rule.protect or rule.neverMove) then
        group = "Protected / blocked"
        recommendation = Data.Recommendations.PROTECTED
        action = Data.Actions.NONE
        reason = rule.protect and "Protected by item rule" or "Never move rule"
        table.insert(blocked, reason)
    elseif IsMythicKeystone(item) then
        expansionID = Data.CurrentExpansionID
        group = "Protected / blocked"
        recommendation = Data.Recommendations.PROTECTED
        action = Data.Actions.NONE
        reason = "Mythic Keystone is protected as current seasonal content"
        table.insert(blocked, "Mythic Keystone")
    elseif item.isBound and (item.classID == 2 or item.classID == 4) then
        group = "Protected / blocked"
        recommendation = Data.Recommendations.BLOCKED
        action = Data.Actions.NONE
        reason = "Soulbound equipment is blocked by default"
        table.insert(blocked, "Soulbound equipment")
    elseif itemType == Data.ItemTypes.QUEST then
        group = "Protected / blocked"
        recommendation = Data.Recommendations.BLOCKED
        action = Data.Actions.NONE
        reason = "Quest items are blocked by default"
        table.insert(blocked, "Quest item")
    elseif rule and rule.actionOverride then
        action = rule.actionOverride
        recommendation = action == Data.Actions.BANK and Data.Recommendations.BANK or Data.Recommendations.RECALL
        group = action == Data.Actions.BANK and "Recommended bank candidates" or "Recommended recall candidates"
        reason = "Action override rule"
    elseif item.curated and item.curated.action == Data.Actions.BANK then
        group, recommendation, action, reason = SetBankOrRecallDecision(
            item,
            "Recommended bank candidates",
            item.curated.reason or "Curated old-content table",
            "Curated item is available to recall from bank"
        )
    elseif itemType == Data.ItemTypes.CONSUMABLE and IsOldExpansion(expansionID) then
        group, recommendation, action, reason = SetBankOrRecallDecision(
            item,
            "Obsolete consumables",
            "Old expansion consumable",
            "Old expansion consumable is available to recall from bank"
        )
    elseif itemType == Data.ItemTypes.BOE and IsOldExpansion(expansionID) then
        group = "Old BoEs"
        recommendation = Data.Recommendations.REVIEW
        action = Data.Actions.REVIEW
        reason = "Old BoE, review before moving"
    elseif itemType == Data.ItemTypes.PROFESSION and IsOldExpansion(expansionID) then
        group, recommendation, action, reason = SetBankOrRecallDecision(
            item,
            "Recommended bank candidates",
            "Old expansion material",
            "Old expansion material is available to recall from bank"
        )
    elseif item.scope == BAG_SCOPE and itemType == Data.ItemTypes.PROFESSION then
        bankTargetStorage, reason = GetPreferredBankStorage(item, itemType)
        group = "Recommended bank candidates"
        recommendation = Data.Recommendations.BANK
        action = Data.Actions.BANK
    elseif IsOldExpansion(expansionID) and itemType ~= Data.ItemTypes.EQUIPMENT then
        group, recommendation, action, reason = SetBankOrRecallDecision(
            item,
            "Recommended bank candidates",
            "Old expansion item",
            "Old expansion item is available to recall from bank"
        )
    elseif item.scope == BANK_SCOPE
        and expansionID
        and IsCurrentExpansion(expansionID)
        and (itemType == Data.ItemTypes.PROFESSION or itemType == Data.ItemTypes.CONSUMABLE or itemType == Data.ItemTypes.CURRENCY_LIKE) then
        group = "Recommended recall candidates"
        recommendation = Data.Recommendations.RECALL
        action = Data.Actions.RECALL
        reason = "Current expansion item is available to recall from bank"
    elseif item.scope == BAG_SCOPE and item.bindingScope == "Warbound Until Equipped" then
        bankTargetStorage = STORAGE_WARBAND_BANK
        group = "Recommended bank candidates"
        recommendation = Data.Recommendations.BANK
        action = Data.Actions.BANK
        reason = "Warbound-until-equipped item belongs in shared storage"
    elseif item.scope == BAG_SCOPE and IsTransferableSharedValueItem(item, itemType) then
        bankTargetStorage, reason = GetPreferredBankStorage(item, itemType)
        group = "Recommended bank candidates"
        recommendation = Data.Recommendations.BANK
        action = Data.Actions.BANK
    elseif IsCurrentExpansion(expansionID) then
        group = "Protected / blocked"
        recommendation = Data.Recommendations.BLOCKED
        action = Data.Actions.NONE
        reason = "Current or unknown expansion is blocked by default"
        table.insert(blocked, "Current or unknown expansion")
    end

    local eligibleForBankMove = item.scope == BAG_SCOPE
        and not (rule and (rule.ignore or rule.protect or rule.neverMove))

    local eligibleForRecall = item.scope == BANK_SCOPE
        and not (rule and (rule.ignore or rule.protect or rule.neverMove))

    if item.scope == BAG_SCOPE and not bankTargetStorage then
        bankTargetStorage = GetPreferredBankStorage(item, itemType)
    end

    item.expansionID = expansionID
    item.expansionName = GetExpansionName(expansionID)
    item.typeTag = itemType
    item.recommendation = recommendation
    item.recommendedAction = action
    item.reason = reason
    item.group = group
    item.blockedReasons = blocked
    item.eligibleForBankMove = eligibleForBankMove
    item.eligibleForRecall = eligibleForRecall
    item.bankTargetStorage = bankTargetStorage
    item.ruleStatus = rule and "custom" or "none"
    item.key = LocationKey(item)

    return item
end

local function GetAllDecisions()
    local decisions = {}
    for _, item in ipairs(ns.DB.scans.bags or {}) do
        table.insert(decisions, BuildDecision(item))
    end
    for _, item in ipairs(ns.DB.scans.bank or {}) do
        table.insert(decisions, BuildDecision(item))
    end
    return decisions
end

local IsItemWarboundUntilEquipped

IsItemWarboundUntilEquipped = function(item)
    if item.bindingScope == "Warbound Until Equipped" then
        return true
    end

    -- WuE should be a subset of BoE-like behavior; reject explicit non-BoE binds.
    if item.bindType and item.bindType ~= 2 then
        return false
    end

    if not (ItemLocation and C_Item and C_Item.IsBoundToAccountUntilEquip) then
        return false
    end
    if type(item.bagID) ~= "number" or type(item.slot) ~= "number" then
        return false
    end
    local itemLocation = ItemLocation:CreateFromBagAndSlot(item.bagID, item.slot)
    if not itemLocation then
        return false
    end
    local ok, isWuE = pcall(C_Item.IsBoundToAccountUntilEquip, itemLocation)
    return ok and isWuE and true or false
end

local function EnsureFilterBranch(filters, key)
    filters[key] = filters[key] or {}
    return filters[key]
end

local function EnsureTabFilters(tabName)
    ns.DB.ui.tabFilters = ns.DB.ui.tabFilters or {}
    ns.DB.ui.tabFilters[tabName] = ns.DB.ui.tabFilters[tabName] or {}
    local filters = ns.DB.ui.tabFilters[tabName]
    local expansion = EnsureFilterBranch(filters, "expansion")
    local itemType = EnsureFilterBranch(filters, "type")
    local bind = EnsureFilterBranch(filters, "bind")
    local location = EnsureFilterBranch(filters, "location")
    local name = EnsureFilterBranch(filters, "name")
    if expansion.include == nil then expansion.include = EXPANSION_FILTER_ALL end
    if itemType.include == nil then itemType.include = "All" end
    if bind.include == nil then bind.include = BIND_FILTER_ALL end
    if location.include == nil then location.include = "All" end
    name.includeText = name.includeText or ""
    name.excludeText = name.excludeText or ""
    filters.hideBlocked = filters.hideBlocked and true or false
    filters.advancedEnabled = filters.advancedEnabled and true or false
    return filters
end

local function MigrateLegacyTabFilters()
    local moveFilters = EnsureTabFilters("Move")
    if not moveFilters.migratedFromLegacy then
        moveFilters.expansion.include = ns.DB.ui.expansionFilter or EXPANSION_FILTER_ALL
        moveFilters.type.include = ns.DB.ui.typeFilter or "All"
        moveFilters.location.include = ns.DB.ui.locationFilter or "All"
        moveFilters.name.includeText = ns.DB.ui.search or ""
        moveFilters.migratedFromLegacy = true
    end

    local organizeFilters = EnsureTabFilters("Organize")
    if not organizeFilters.migratedFromLegacy then
        organizeFilters.name.includeText = ns.DB.ui.organizerSearch or ""
        organizeFilters.migratedFromLegacy = true
    end

    local vendorFilters = EnsureTabFilters("Vendor")
    if not vendorFilters.migratedFromLegacy then
        vendorFilters.name.includeText = ns.DB.ui.vendorSearch or ""
        vendorFilters.migratedFromLegacy = true
    end
end

local function SetFilterInclude(tabName, key, value)
    local filters = EnsureTabFilters(tabName)
    EnsureFilterBranch(filters, key).include = value
    if tabName == "Move" then
        if key == "expansion" then
            ns.DB.ui.expansionFilter = value
        elseif key == "type" then
            ns.DB.ui.typeFilter = value
        elseif key == "location" then
            ns.DB.ui.locationFilter = value
        end
    end
    UI.page = 1
end

local IsAllFilterValue
local GetExpansionFilterLabel

local function SetFilterSearch(tabName, value)
    local filters = EnsureTabFilters(tabName)
    filters.name.includeText = value or ""
    if tabName == "Move" then
        ns.DB.ui.search = filters.name.includeText
    elseif tabName == "Organize" then
        ns.DB.ui.organizerSearch = filters.name.includeText
    elseif tabName == "Vendor" then
        ns.DB.ui.vendorSearch = filters.name.includeText
    end
    UI.page = 1
end

local function SetFilterHideBlocked(tabName, value)
    local filters = EnsureTabFilters(tabName)
    filters.hideBlocked = value and true or false
    UI.page = 1
end

local function ResetTabFilters(tabName)
    local filters = EnsureTabFilters(tabName)
    filters.expansion.include = EXPANSION_FILTER_ALL
    filters.type.include = "All"
    filters.bind.include = BIND_FILTER_ALL
    filters.location.include = "All"
    filters.name.includeText = ""
    filters.name.excludeText = ""
    filters.hideBlocked = false
    filters.advancedEnabled = false
    if tabName == "Move" then
        ns.DB.ui.expansionFilter = EXPANSION_FILTER_ALL
        ns.DB.ui.typeFilter = "All"
        ns.DB.ui.locationFilter = "All"
        ns.DB.ui.search = ""
    elseif tabName == "Organize" then
        ns.DB.ui.organizerSearch = ""
    elseif tabName == "Vendor" then
        ns.DB.ui.vendorSearch = ""
    end
    UI.page = 1
end

local function BuildFilterSummary(tabName)
    local filters = EnsureTabFilters(tabName)
    local parts = {}
    if not IsAllFilterValue(filters.expansion.include) then
        table.insert(parts, "Expansion: " .. GetExpansionFilterLabel(filters.expansion.include))
    end
    if not IsAllFilterValue(filters.type.include) then
        table.insert(parts, "Type: " .. tostring(filters.type.include))
    end
    if not IsAllFilterValue(filters.bind.include) then
        table.insert(parts, "Bind: " .. tostring(filters.bind.include))
    end
    if not IsAllFilterValue(filters.location.include) then
        table.insert(parts, "Location: " .. tostring(filters.location.include))
    end
    if filters.name.includeText ~= "" then
        table.insert(parts, "Search: " .. filters.name.includeText)
    end
    if filters.name.excludeText ~= "" then
        table.insert(parts, "Excluding: " .. filters.name.excludeText)
    end
    if filters.hideBlocked then
        table.insert(parts, "Actionable only")
    end
    return #parts > 0 and table.concat(parts, "  |  ") or "Filters: All"
end

IsAllFilterValue = function(value)
    return value == nil or value == "All" or value == EXPANSION_FILTER_ALL or value == BIND_FILTER_ALL
end

local function FilterMatchesInclude(include, matcher)
    if IsAllFilterValue(include) then
        return true
    end
    if type(include) == "table" then
        local hasSpecificValue = false
        for key, value in pairs(include) do
            local actual = value == true and key or value
            if not IsAllFilterValue(actual) then
                hasSpecificValue = true
                if matcher(actual) then
                    return true
                end
            end
        end
        return not hasSpecificValue
    end
    return matcher(include)
end

local function FilterIncludesValue(include, expected)
    if include == expected then
        return true
    end
    if type(include) == "table" then
        for key, value in pairs(include) do
            local actual = value == true and key or value
            if actual == expected then
                return true
            end
        end
    end
    return false
end

local function MatchesExpansionInclude(item, include)
    return FilterMatchesInclude(include, function(value)
        if value == EXPANSION_FILTER_NOT_CURRENT then
            return IsOldExpansion(item.expansionID)
        elseif value == EXPANSION_FILTER_UNKNOWN then
            return IsUnknownExpansion(item.expansionID)
        end
        return item.expansionID == value
    end)
end

local function IsVendorSellable(item)
    return (item.sellPrice or 0) >= 1
end

local function MatchesTypeInclude(item, include)
    return FilterMatchesInclude(include, function(value)
        if value == TYPE_FILTER_REAGENT then
            local isInReagentBank = item.storageKind == STORAGE_REAGENT_BANK
            local goesToReagentBank = item.bankTargetStorage == STORAGE_REAGENT_BANK
            local isProfessionMaterial = item.typeTag == Data.ItemTypes.PROFESSION
            return isInReagentBank or goesToReagentBank or isProfessionMaterial
        elseif value == TYPE_FILTER_BOE then
            return item.typeTag == Data.ItemTypes.BOE and not IsItemWarboundUntilEquipped(item)
        elseif value == TYPE_FILTER_WUE then
            return IsItemWarboundUntilEquipped(item)
        elseif value == TYPE_FILTER_VENDOR_SELLABLE then
            return IsVendorSellable(item)
        end
        return item.typeTag == value
    end)
end

local function MatchesBindInclude(item, include)
    return FilterMatchesInclude(include, function(value)
        if value == BIND_FILTER_BOE then
            return (item.bindingScope == "BoE" or item.bindType == 2) and not IsItemWarboundUntilEquipped(item)
        elseif value == BIND_FILTER_WUE then
            return IsItemWarboundUntilEquipped(item)
        elseif value == BIND_FILTER_SOULBOUND then
            return item.isSoulbound or item.bindingScope == "Soulbound"
        elseif value == BIND_FILTER_WARBAND then
            return item.isWarbandBound or item.bindingScope == "Warbound" or item.bindingScope == "Warbound Until Equipped"
        elseif value == BIND_FILTER_BOP then
            return item.bindType == 1 or item.bindingScope == "Soulbound" or item.isSoulbound
        end
        return true
    end)
end

local function MatchesLocationInclude(item, include)
    return FilterMatchesInclude(include, function(value)
        if value == "Bags" then
            return item.scope == BAG_SCOPE
        elseif value == "Bank" then
            return item.scope == BANK_SCOPE
        elseif value == STORAGE_PRIVATE_BANK or value == STORAGE_REAGENT_BANK or value == STORAGE_WARBAND_BANK then
            return item.storageKind == value
        end
        return true
    end)
end

local function BuildItemSearchParts(item, extraParts)
    local parts = {
        item.name or "",
        tostring(item.itemID or ""),
        item.expansionName or "",
        item.typeTag or "",
        item.location or "",
        item.reason or "",
        item.bindingScope or "",
    }
    for _, part in ipairs(extraParts or {}) do
        table.insert(parts, part or "")
    end
    return parts
end

local function TextMatchesSearch(searchText, parts)
    local search = searchText and searchText:lower() or ""
    if search == "" then
        return true
    end
    local haystack = table.concat(parts, " "):lower()
    return haystack:find(search, 1, true) ~= nil
end

local function MatchesTabFilters(item, tabName, extraParts)
    local filters = EnsureTabFilters(tabName)
    if not MatchesExpansionInclude(item, filters.expansion.include) then
        return false
    elseif not MatchesTypeInclude(item, filters.type.include) then
        return false
    elseif not MatchesBindInclude(item, filters.bind.include) then
        return false
    elseif not MatchesLocationInclude(item, filters.location.include) then
        return false
    elseif not TextMatchesSearch(filters.name.includeText, BuildItemSearchParts(item, extraParts)) then
        return false
    elseif filters.name.excludeText ~= "" and TextMatchesSearch(filters.name.excludeText, { item.name or "" }) then
        return false
    end
    return true
end

local function MatchesMoveFilter(item)
    local ui = ns.DB.ui
    if ui.mode == "Dump to Bank" and item.scope ~= BAG_SCOPE then
        return false
    elseif ui.mode == "Recall from Bank" and item.scope ~= BANK_SCOPE then
        return false
    end
    if ui.recommendedOnly then
        if ui.mode == "Dump to Bank" and item.recommendedAction ~= Data.Actions.BANK then
            return false
        elseif ui.mode == "Recall from Bank" and item.recommendedAction ~= Data.Actions.RECALL then
            return false
        elseif item.recommendedAction == Data.Actions.NONE or item.recommendedAction == Data.Actions.REVIEW then
            return false
        end
    end
    local filters = EnsureTabFilters("Move")
    if filters.hideBlocked then
        if ui.mode == "Dump to Bank" and not item.eligibleForBankMove then
            return false
        elseif ui.mode == "Recall from Bank" and not item.eligibleForRecall then
            return false
        end
    end
    return MatchesTabFilters(item, "Move")
end

GetExpansionFilterLabel = function(value)
    if value == EXPANSION_FILTER_ALL then
        return "All expansions"
    elseif value == EXPANSION_FILTER_NOT_CURRENT then
        return "Not current"
    elseif value == EXPANSION_FILTER_UNKNOWN then
        return "Unknown expansion"
    end
    return GetExpansionName(value)
end

local function GetTypeFilterOptions()
    return {
        { text = "All", value = "All" },
        { text = Data.ItemTypes.REPUTATION, value = Data.ItemTypes.REPUTATION },
        { text = Data.ItemTypes.QUEST, value = Data.ItemTypes.QUEST },
        { text = Data.ItemTypes.SEASONAL, value = Data.ItemTypes.SEASONAL },
        { text = Data.ItemTypes.PROFESSION, value = Data.ItemTypes.PROFESSION },
        { text = TYPE_FILTER_REAGENT, value = TYPE_FILTER_REAGENT },
        { text = Data.ItemTypes.CONSUMABLE, value = Data.ItemTypes.CONSUMABLE },
        { text = TYPE_FILTER_BOE, value = TYPE_FILTER_BOE },
        { text = TYPE_FILTER_WUE, value = TYPE_FILTER_WUE },
        { text = TYPE_FILTER_VENDOR_SELLABLE, value = TYPE_FILTER_VENDOR_SELLABLE },
        { text = Data.ItemTypes.UNKNOWN, value = Data.ItemTypes.UNKNOWN },
    }
end

local function GetBindFilterOptions()
    return {
        { text = "All", value = BIND_FILTER_ALL },
        { text = BIND_FILTER_BOE, value = BIND_FILTER_BOE },
        { text = BIND_FILTER_WUE, value = BIND_FILTER_WUE },
        { text = BIND_FILTER_SOULBOUND, value = BIND_FILTER_SOULBOUND },
        { text = BIND_FILTER_WARBAND, value = BIND_FILTER_WARBAND },
        { text = BIND_FILTER_BOP, value = BIND_FILTER_BOP },
    }
end

local function GetBankLocationFilterOptions()
    return {
        { text = "All", value = "All" },
        { text = STORAGE_PRIVATE_BANK, value = STORAGE_PRIVATE_BANK },
        { text = STORAGE_REAGENT_BANK, value = STORAGE_REAGENT_BANK },
        { text = STORAGE_WARBAND_BANK, value = STORAGE_WARBAND_BANK },
    }
end

local function PlanMatchesTabFilters(plan, tabName)
    local item = plan.item or {}
    return MatchesTabFilters(item, tabName, {
        plan.currentStorage or "",
        plan.targetStorage or "",
        plan.action or "",
        plan.reason or "",
        plan.blockedReason or "",
    })
end

local GetStorageBagIDs
local FindFreeSlot
local FindFreeNormalBagSlot

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
        elseif item.rule and item.rule.neverMove then
            return "Never move rule"
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
        elseif item.rule and item.rule.neverMove then
            return "Never move rule"
        elseif not FindFreeNormalBagSlot({}, item) then
            return "No empty normal bag slots"
        end
    end
    return nil
end

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

FindFreeNormalBagSlot = function(takenSlots, item)
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

local function IsMoveEligibleForCurrentMode(item)
    if ns.DB.ui.mode == "Dump to Bank" then
        return item.eligibleForBankMove and true or false
    elseif ns.DB.ui.mode == "Recall from Bank" then
        return item.eligibleForRecall and true or false
    end
    return false
end

local function SortDecisions(a, b)
    local ai, bi = 99, 99
    for index, group in ipairs(GROUP_ORDER) do
        if a.group == group then ai = index end
        if b.group == group then bi = index end
    end
    if ai ~= bi then
        return ai < bi
    end
    return (a.name or "") < (b.name or "")
end

function GetStorageBagIDs(storageKind)
    if storageKind == STORAGE_PRIVATE_BANK then
        return PRIVATE_BANK_IDS
    elseif storageKind == STORAGE_REAGENT_BANK then
        return REAGENT_BANK_IDS
    elseif storageKind == STORAGE_WARBAND_BANK then
        return WARBAND_BANK_IDS
    end
    return {}
end

function FindFreeSlot(storageKind, takenSlots, item)
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

local function BuildOrganizationPlan(item, charProfSubclasses)
    if item.scope ~= BANK_SCOPE then
        return nil
    end

    local currentStorage = item.storageKind or GetStorageKindForBagID(item.bagID, item.scope)
    local targetStorage = currentStorage
    local reason = "Already in the preferred bank tier"

    if item.rule and (item.rule.ignore or item.rule.protect or item.rule.neverMove) then
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
    local charProfSubclasses = GetCharacterProfessionSubclasses()
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

local function CreateButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 110, height or 24)
    button:SetText(text)
    return button
end

local function CreateLabel(parent, text, size)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetText(text or "")
    label:SetJustifyH("LEFT")
    if size then
        label:SetFontObject(size)
    end
    return label
end

local function CreateDropdown(parent, width, options, onSelect)
    local dropdown = CreateButton(parent, "", width or 140, 24)
    dropdown.options = options
    dropdown.onSelect = onSelect

    local menu = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(parent:GetFrameLevel() + 40)
    menu:SetSize(width or 140, #options * 22 + 8)
    menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    menu:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    menu:Hide()
    dropdown.menu = menu

    dropdown.items = {}
    for index, option in ipairs(options) do
        local item = CreateButton(menu, option.text, (width or 140) - 8, 20)
        item:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (index - 1) * 22)
        item:SetScript("OnClick", function()
            onSelect(option.value)
            menu:Hide()
            Core.RefreshUI()
        end)
        dropdown.items[index] = item
    end

    dropdown:SetScript("OnClick", function()
        menu:SetShown(not menu:IsShown())
    end)
    dropdown:SetScript("OnHide", function()
        menu:Hide()
    end)

    return dropdown
end

local function SetDropdownText(dropdown, label)
    dropdown:SetText(label .. " |TInterface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up:10:10:0:0|t")
end

local function GetExpansionOptions()
    local options = {
        { text = "All expansions",  value = EXPANSION_FILTER_ALL },
        { text = "Not current",     value = EXPANSION_FILTER_NOT_CURRENT },
        { text = "Unknown expansion", value = EXPANSION_FILTER_UNKNOWN },
    }
    for expansionID = 0, Data.CurrentExpansionID do
        local expansion = Data.Expansions[expansionID]
        if expansion then
            table.insert(options, { text = expansion.name, value = expansionID })
        end
    end
    return options
end

local function CreatePanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetFrameLevel(parent:GetFrameLevel() + 5)
    panel:SetPoint("TOPLEFT", 14, -64)
    panel:SetPoint("BOTTOMRIGHT", -14, 14)
    return panel
end

local function RaiseConsole()
    if not UI.frame then
        return
    end
    UI.frame:SetFrameStrata("FULLSCREEN_DIALOG")
    UI.frame:SetFrameLevel(100)
    UI.frame:Raise()
end

local AddRule

local function ShowTooltip(owner, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    for index, line in ipairs(lines) do
        if index == 1 then
            GameTooltip:AddLine(line, 1, 1, 1)
        else
            GameTooltip:AddLine(line, 0.75, 0.85, 1)
        end
    end
    GameTooltip:Show()
end

local function CreateEmptyLabel(parent, text)
    local label = CreateLabel(parent, text, "GameFontDisableLarge")
    label:SetPoint("CENTER", parent, "CENTER", 0, 0)
    label:SetJustifyH("CENTER")
    label:Hide()
    return label
end

local function SetEmptyLabel(label, isEmpty, text)
    if not label then
        return
    end
    if text then
        label:SetText(text)
    end
    label:SetShown(isEmpty and true or false)
end

local function CreateContextNotice(parent)
    local label = CreateLabel(parent, "", "GameFontDisableSmall")
    label:SetPoint("TOPRIGHT", 0, 0)
    label:SetWidth(250)
    label:SetJustifyH("RIGHT")
    label:Hide()
    return label
end

local function SetContextNotice(label, text)
    if not label then
        return
    end
    label:SetText(text or "")
    label:SetShown(text and text ~= "")
end

local function GetTabAvailability(tabName)
    if tabName == "Move" then
        if ns.DB.context.bankOpen then
            return true, nil
        end
        return false, "Open the bank to move selected rows."
    elseif tabName == "Organize" then
        if ns.DB.context.bankOpen then
            return true, nil
        end
        return false, "Open the bank to organize storage."
    elseif tabName == "Vendor" then
        if ns.DB.context.vendorOpen then
            return true, nil
        end
        return false, "Open a vendor to sell selected rows."
    end
    return true, nil
end

local function ApplyTabVisualState(tab, tabName, isActive)
    local isAvailable, reason = GetTabAvailability(tabName)
    tab:SetText(tabName)
    tab:SetEnabled(true)
    tab:SetAlpha(isActive and 1 or (isAvailable and 0.82 or 0.55))
    if isActive and tab.LockHighlight then
        tab:LockHighlight()
    elseif tab.UnlockHighlight then
        tab:UnlockHighlight()
    end
    local fontString = tab:GetFontString()
    if fontString and fontString.SetTextColor then
        if isActive then
            fontString:SetTextColor(1, 0.86, 0.1)
        elseif not isAvailable then
            fontString:SetTextColor(0.95, 0.55, 0.25)
        else
            fontString:SetTextColor(0.9, 0.82, 0.55)
        end
    end
    tab.availabilityReason = reason
end

local function CreateRowRuleMenu(parent, width, options)
    local menu = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(parent:GetFrameLevel() + 30)
    menu:SetSize(width or 100, #options * 22 + 8)
    menu:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    menu:Hide()

    menu.buttons = {}
    for index, option in ipairs(options) do
        local button = CreateButton(menu, option.text, (width or 100) - 8, 20)
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (index - 1) * 22)
        button:SetScript("OnClick", function()
            if menu.item then
                AddRule(menu.item, option.ruleType)
            end
            menu:Hide()
        end)
        menu.buttons[index] = button
    end

    return menu
end

local function ToggleRowRuleMenu(row, item)
    if not row.ruleMenu then
        return
    end
    row.ruleMenu.item = item
    row.ruleMenu:ClearAllPoints()
    row.ruleMenu:SetPoint("TOPRIGHT", row.rule, "BOTTOMRIGHT", 0, -2)
    row.ruleMenu:SetShown(not row.ruleMenu:IsShown())
end

local function ToggleConsole(tabName)
    if UI.frame and UI.frame:IsShown() and (not tabName or UI.activeTab == tabName) then
        UI.frame:Hide()
        return
    end
    if tabName == "Organize" then
        Core.ShowOrganizeUI()
    elseif tabName == "Vendor" then
        Core.ShowVendorUI()
    elseif tabName == "Move" then
        Core.ShowMoveUI()
    else
        Core.ShowSummaryUI()
    end
end

local function CreateIconButton(name, parent, size, tooltipLines, onClick)
    local button = CreateFrame("Button", name, parent)
    button:SetSize(size or 28, size or 28)
    button:RegisterForClicks("LeftButtonUp")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 3, -3)
    button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    button.icon:SetTexture(ICON_TEXTURE)

    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetPoint("TOPLEFT")
    button.border:SetPoint("BOTTOMRIGHT")
    button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self) ShowTooltip(self, tooltipLines) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function GetLibDBIcon()
    return LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true) or nil
end

local function GetLibDataBroker()
    return LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true) or nil
end

local function EnsureMinimapIconDB()
    ns.DB.ui.minimapIcon = ns.DB.ui.minimapIcon or {
        hide = ns.DB.ui.showMinimapIcon == false,
        minimapPos = 220,
        lock = false,
    }
    ns.DB.ui.minimapIcon.hide = ns.DB.ui.showMinimapIcon == false
    return ns.DB.ui.minimapIcon
end

local function CreateStandardMinimapButton()
    local LDB = GetLibDataBroker()
    local LDBIcon = GetLibDBIcon()
    if not LDB or not LDBIcon then
        return false
    end

    if not UI.minimapDataObject then
        UI.minimapDataObject = LDB:NewDataObject(MINIMAP_LDB_NAME, {
            type = "launcher",
            text = DISPLAY_NAME,
            icon = ICON_TEXTURE,
            OnClick = function(_, button)
                if button == "RightButton" then
                    Core.CreateUI()
                    UI.activeTab = "Settings"
                    UI.frame:Show()
                    Core.RefreshUI()
                else
                    ToggleConsole("Summary")
                end
            end,
            OnTooltipShow = function(tooltip)
                if not tooltip or not tooltip.AddLine then
                    return
                end
                tooltip:AddLine(DISPLAY_NAME, 1, 1, 1)
                tooltip:AddLine(" ")
                tooltip:AddLine("Left-click to open the cleanup console.", 0.75, 0.85, 1)
                tooltip:AddLine("Right-click for settings.", 0.75, 0.85, 1)
            end,
        })
    end

    local minimapIconDB = EnsureMinimapIconDB()
    if not UI.minimapIconRegistered then
        LDBIcon:Register(MINIMAP_LDB_NAME, UI.minimapDataObject, minimapIconDB)
        UI.minimapIconRegistered = true
    end

    if ns.DB.ui.showMinimapIcon == false then
        LDBIcon:Hide(MINIMAP_LDB_NAME)
    else
        LDBIcon:Show(MINIMAP_LDB_NAME)
    end
    if UI.minimapButton then
        UI.minimapButton:Hide()
    end
    return true
end

local function GetStandardMinimapButton()
    local LDBIcon = GetLibDBIcon()
    if LDBIcon and UI.minimapIconRegistered and LDBIcon.GetMinimapButton then
        return LDBIcon:GetMinimapButton(MINIMAP_LDB_NAME)
    end
    return nil
end

local function CreateMinimapButton()
    if CreateStandardMinimapButton() then
        return
    end
    if UI.minimapButton or not Minimap then
        return
    end

    local button = CreateIconButton("ICantEvenRightNowMinimapButton", Minimap, 32, {
        DISPLAY_NAME,
        "Click to open or close the cleanup console.",
        "Use /icanteven minimap to hide this button.",
    }, function()
        ToggleConsole("Summary")
    end)
    button:SetFrameStrata("FULLSCREEN_DIALOG")
    button:SetFrameLevel(80)
    UI.minimapButton = button
end

local function PositionMinimapButton()
    if not UI.minimapButton then
        return
    end
    UI.minimapButton:ClearAllPoints()
    UI.minimapButton:SetPoint("CENTER", Minimap, "CENTER", 56, -56)
end

local function PositionFrameButton(button, parent)
    button:SetParent(UIParent)
    button:SetFrameStrata("FULLSCREEN_DIALOG")
    button:SetFrameLevel(math.max((parent:GetFrameLevel() or 1) + 80, 90))
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -34, -30)
end

local function CreateBankButton(parent)
    if UI.bankButton then
        PositionFrameButton(UI.bankButton, parent)
        return
    end

    UI.bankButton = CreateIconButton("ICantEvenRightNowBankButton", UIParent, 28, {
        DISPLAY_NAME,
        "Open the bank organizer.",
        "Use /icanteven bankbutton to hide this button.",
    }, function()
        Core.ShowOrganizeUI()
    end)
    PositionFrameButton(UI.bankButton, parent)
end

local function CreateVendorButton(parent)
    if UI.vendorButton then
        PositionFrameButton(UI.vendorButton, parent)
        return
    end

    UI.vendorButton = CreateIconButton("ICantEvenRightNowVendorButton", UIParent, 28, {
        DISPLAY_NAME,
        "Open vendor review.",
        "Use /icanteven vendorbutton to hide this button.",
    }, function()
        Core.ShowVendorUI()
    end)
    PositionFrameButton(UI.vendorButton, parent)
end

local function GetShownGlobalFrame(names)
    for _, name in ipairs(names) do
        local frame = _G[name]
        if frame and frame.IsShown and frame:IsShown() then
            return frame
        end
    end
    return nil
end

local function GetShownNamedFrameByPattern(namePatterns)
    if not EnumerateFrames then
        return nil
    end

    local frame = EnumerateFrames()
    while frame do
        if frame.GetName and frame.IsShown and frame:IsShown() then
            local name = frame:GetName()
            if name then
                local lowerName = name:lower()
                for _, pattern in ipairs(namePatterns) do
                    if lowerName:find(pattern, 1, true) then
                        return frame
                    end
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
    if not C_Bank then
        return false
    end

    if C_Bank.AreAnyBankTypesViewable then
        local ok, viewable = pcall(C_Bank.AreAnyBankTypesViewable)
        if ok and viewable then
            return true
        end
    end

    if C_Bank.FetchViewableBankTypes then
        local ok, bankTypes = pcall(C_Bank.FetchViewableBankTypes)
        if ok and type(bankTypes) == "table" then
            for _, bankType in pairs(bankTypes) do
                if bankType ~= nil then
                    return true
                end
            end
        elseif ok and bankTypes ~= nil then
            return true
        end
    end

    if C_Bank.IsBankTypeViewable and Enum and Enum.BankType then
        local bankTypes = {
            rawget(Enum.BankType, "Character"),
            rawget(Enum.BankType, "Account"),
        }
        for _, bankType in ipairs(bankTypes) do
            if bankType ~= nil then
                local ok, viewable = pcall(C_Bank.IsBankTypeViewable, bankType)
                if ok and viewable then
                    return true
                end
            end
        end
    end

    if C_Bank.CanViewBank and Enum and Enum.BankType then
        local bankTypes = {
            rawget(Enum.BankType, "Character"),
            rawget(Enum.BankType, "Account"),
        }
        for _, bankType in ipairs(bankTypes) do
            if bankType ~= nil then
                local ok, canView = pcall(C_Bank.CanViewBank, bankType)
                if ok and canView then
                    return true
                end
            end
        end
    end

    return false
end

local function IsBankStorageAccessible()
    if not CContainer then
        return false
    end

    -- GetContainerNumFreeSlots only returns valid data when the bank is actually
    -- open and the server has sent container contents. GetContainerNumSlots returns
    -- the static slot count regardless of bank state, so we use free slots instead.
    if CContainer.GetContainerNumFreeSlots then
        local storageIDLists = { PRIVATE_BANK_IDS, REAGENT_BANK_IDS, WARBAND_BANK_IDS }
        for _, ids in ipairs(storageIDLists) do
            for _, bagID in ipairs(ids or {}) do
                local ok, freeSlots = pcall(CContainer.GetContainerNumFreeSlots, bagID)
                if ok and type(freeSlots) == "number" and freeSlots >= 0 then
                    return true
                end
            end
        end
    end

    -- Fallback: probe slot 1 of each bank bag for any item info response
    if CContainer.GetContainerItemInfo then
        local storageIDLists = { PRIVATE_BANK_IDS, REAGENT_BANK_IDS, WARBAND_BANK_IDS }
        for _, ids in ipairs(storageIDLists) do
            for _, bagID in ipairs(ids or {}) do
                local ok, info = pcall(CContainer.GetContainerItemInfo, bagID, 1)
                if ok and info ~= nil then
                    return true
                end
            end
        end
    end

    return false
end

local function IsBankInteractionType(interactionType)
    if not Enum or not Enum.PlayerInteractionType then
        return false
    end
    return interactionType == Enum.PlayerInteractionType.Banker
        or interactionType == rawget(Enum.PlayerInteractionType, "AccountBanker")
end

local function IsPlayerBankInteractionActive()
    if not C_PlayerInteractionManager or not C_PlayerInteractionManager.IsInteractingWithNpcOfType or not Enum or not Enum.PlayerInteractionType then
        return false
    end

    local interactionTypes = {
        Enum.PlayerInteractionType.Banker,
        rawget(Enum.PlayerInteractionType, "AccountBanker"),
    }
    for _, interactionType in ipairs(interactionTypes) do
        if interactionType ~= nil then
            local ok, active = pcall(C_PlayerInteractionManager.IsInteractingWithNpcOfType, interactionType)
            if ok and active then
                return true
            end
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

function Core.UpdateQuickAccessButtons()
    if not ns.DB or not ns.DB.ui then
        return
    end

    CreateMinimapButton()
    if UI.minimapIconRegistered then
        EnsureMinimapIconDB()
    elseif UI.minimapButton then
        PositionMinimapButton()
        UI.minimapButton:SetShown(ns.DB.ui.showMinimapIcon ~= false)
    end

    -- Bank/vendor launchers are intentionally disabled.
    if UI.bankButton then
        UI.bankButton:Hide()
    end
    if UI.vendorButton then
        UI.vendorButton:Hide()
    end
end

function Core.UpdateContext()
    local context = ns.DB.context
    context.bankOpen = UI.bankContextOpen or IsBankContextDetected()
    context.reagentBankOpen = IsGlobalFrameShown("ReagentBankFrame")
    context.vendorOpen = UI.vendorContextOpen or (IsGlobalFrameShown("MerchantFrame") and not UI.vendorContextClosed)
    context.auctionHouseOpen = IsGlobalFrameShown("AuctionHouseFrame")
    context.mailboxOpen = IsGlobalFrameShown("MailFrame")
    context.inCombat = InCombatLockdown() and true or false
    if context.bankOpen then
        UI.hadBankContext = true
    end
    if context.vendorOpen then
        UI.hadVendorContext = true
    end
end

function Core.PrintQuickAccessStatus()
    Core.UpdateContext()
    Core.UpdateQuickAccessButtons()
    local minimapButton = GetStandardMinimapButton() or UI.minimapButton
    local minimapMode = UI.minimapIconRegistered and "LibDBIcon" or "fallback"
    Print("Quick access: minimap " .. tostring(ns.DB.ui.showMinimapIcon ~= false)
        .. " / " .. minimapMode .. " button " .. tostring(minimapButton and minimapButton:IsShown())
    .. "; bank launcher disabled; vendor launcher disabled")
end

local function ScheduleQuickAccessRefresh()
    local function RefreshQuickAccess()
        if ns.DB and ns.DB.context then
            Core.UpdateContext()
            Core.UpdateQuickAccessButtons()
            if UI.frame and UI.frame:IsShown() then
                Core.RefreshUI()
            end
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, RefreshQuickAccess)
        C_Timer.After(0.25, RefreshQuickAccess)
        C_Timer.After(1.0, RefreshQuickAccess)
        C_Timer.After(2.5, RefreshQuickAccess)
    else
        RefreshQuickAccess()
    end
end

local function ScanContainerBag(bagID, scope, output, storageKind)
    storageKind = storageKind or GetStorageKindForBagID(bagID, scope)
    local numSlots = CContainer.GetContainerNumSlots(bagID) or 0
    for slot = 1, numSlots do
        local info = CContainer.GetContainerItemInfo(bagID, slot)
        local itemID = CContainer.GetContainerItemID(bagID, slot)
        if info and itemID then
            local name, link, quality, itemLevel, requiredLevel, itemTypeName, itemSubTypeName, maxStack, equipLoc, icon, sellPrice, classID, subclassID, bindType, expansionID = GetItemInfo(itemID)
            local bindingDetails = GetBindingDetails(bagID, slot, bindType, info.isBound and true or false)
            table.insert(output, {
                itemID = itemID,
                name = name or info.itemName or ("Item " .. itemID),
                link = link,
                icon = icon or info.iconFileID,
                quality = quality or info.quality,
                count = info.stackCount or 1,
                bagID = bagID,
                slot = slot,
                scope = scope,
                storageKind = storageKind,
                location = FormatItemLocation(bagID, slot, scope, storageKind),
                classID = classID,
                subclassID = subclassID,
                bindType = bindType,
                equipLoc = equipLoc,
                itemLevel = itemLevel,
                requiredLevel = requiredLevel,
                itemTypeName = itemTypeName,
                itemSubTypeName = itemSubTypeName,
                maxStack = maxStack,
                sellPrice = sellPrice,
                expansionID = expansionID,
                isBound = bindingDetails.isBound,
                isSoulbound = bindingDetails.isSoulbound,
                isWarbandBound = bindingDetails.isWarbandBound,
                accountBankAllowed = bindingDetails.accountBankAllowed,
                bindingScope = bindingDetails.bindingScope,
            })
        end
    end
end

function Core.ScanInventory(scope, quiet)
    Core.UpdateContext()
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
            ScanContainerBag(bagID, BAG_SCOPE, bagItems)
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
            ScanContainerBag(bagID, BANK_SCOPE, bankItems, STORAGE_PRIVATE_BANK)
        end
        for _, bagID in ipairs(REAGENT_BANK_IDS) do
            ScanContainerBag(bagID, BANK_SCOPE, bankItems, STORAGE_REAGENT_BANK)
        end
        for _, bagID in ipairs(WARBAND_BANK_IDS) do
            ScanContainerBag(bagID, BANK_SCOPE, bankItems, STORAGE_WARBAND_BANK)
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

    -- Some items may not be in the client cache yet; retry after a short delay
    -- to pick up expansionID and other fields that GetItemInfo returns as nil on first call.
    local needsRetry = false
    for _, item in ipairs(ns.DB.scans.bags or {}) do
        if item.expansionID == nil then needsRetry = true; break end
    end
    if not needsRetry then
        for _, item in ipairs(ns.DB.scans.bank or {}) do
            if item.expansionID == nil then needsRetry = true; break end
        end
    end
    if needsRetry then
        C_Timer.After(1.5, function()
            Core.ScanInventory(scope, true)
        end)
    end
end

function Core.ScheduleRescanAfterMove()
    local delays = { 0.25, 0.8, 1.6 }
    for _, delay in ipairs(delays) do
        C_Timer.After(delay, function()
            Core.ScanInventory("all", true)
        end)
    end
end

local function GetContextText()
    if ns.DB.context.inCombat then
        return "In combat"
    elseif ns.DB.context.vendorOpen then
        return "Vendor open"
    elseif ns.DB.context.bankOpen then
        return "Bank open"
    end
    return "Bags only"
end

local function CountSummary()
    local counts = {
        oldBags = 0,
        oldBank = 0,
        bankCandidates = 0,
        recallCandidates = 0,
        consumables = 0,
        boes = 0,
        unknown = 0,
        protected = 0,
    }
    for _, item in ipairs(GetAllDecisions() or {}) do
        if IsOldExpansion(item.expansionID) and item.scope == BAG_SCOPE then
            counts.oldBags = counts.oldBags + 1
        elseif IsOldExpansion(item.expansionID) and item.scope == BANK_SCOPE then
            counts.oldBank = counts.oldBank + 1
        end
        if item.recommendation == Data.Recommendations.BANK then
            counts.bankCandidates = counts.bankCandidates + 1
        elseif item.recommendation == Data.Recommendations.RECALL then
            counts.recallCandidates = counts.recallCandidates + 1
        end
        if item.group == "Obsolete consumables" then counts.consumables = counts.consumables + 1 end
        if item.group == "Old BoEs" then counts.boes = counts.boes + 1 end
        if item.group == "Unknown / needs review" then counts.unknown = counts.unknown + 1 end
        if item.group == "Protected / blocked" then counts.protected = counts.protected + 1 end
    end
    return counts
end

local function SetTab(tabName)
    UI.activeTab = tabName
    UI.page = 1
    Core.UpdateContext()
    Core.RefreshUI()
    Core.ScheduleDeferredUIRefresh()
end

function AddRule(item, ruleType)
    local rule = EnsureRule(item.itemID)
    rule.createdFrom = item.name or "Move tab"
    if ruleType == "Protect" then
        rule.protect = true
    elseif ruleType == "Ignore" then
        rule.ignore = true
    elseif ruleType == "Always Bank" then
        rule.actionOverride = Data.Actions.BANK
    elseif ruleType == "Always Recall" then
        rule.actionOverride = Data.Actions.RECALL
    elseif ruleType == "Never Move" then
        rule.neverMove = true
    elseif ruleType == "Never Sell" then
        rule.neverSell = true
    end
    Core.RefreshUI()
end

-- UI building moved to modules/UI.lua
-- UI Refresh functions moved to modules/UI.lua
function Core.ShowSummaryUI()
    Core.CreateUI()
    UI.activeTab = "Summary"
    UI.frame:Show()
    Core.RefreshUI()
end

function Core.ScheduleDeferredUIRefresh()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, function()
            if ns.DB and ns.DB.context and UI.frame and UI.frame:IsShown() then
                Core.UpdateContext()
                Core.RefreshUI()
            end
        end)
        C_Timer.After(1.0, function()
            if ns.DB and ns.DB.context and UI.frame and UI.frame:IsShown() then
                Core.UpdateContext()
                Core.RefreshUI()
            end
        end)
    end
end

function Core.ShowMoveUI()
    Core.CreateUI()
    UI.activeTab = "Move"
    UI.frame:Show()
    Core.RefreshUI()
    Core.ScheduleDeferredUIRefresh()
end

function Core.ShowOrganizeUI()
    Core.CreateUI()
    UI.activeTab = "Organize"
    UI.frame:Show()
    Core.RefreshUI()
    Core.ScheduleDeferredUIRefresh()
end

function Core.ShowVendorUI()
    Core.CreateUI()
    UI.activeTab = "Vendor"
    UI.frame:Show()
    Core.RefreshUI()
    Core.ScheduleDeferredUIRefresh()
end

-- Action functions moved to modules/Actions.lua
function Core.RegisterSlashCommands()
    SLASH_ICANTEVEN1 = "/icanteven"
    SLASH_ICANTEVEN2 = "/icant"
    SlashCmdList["ICANTEVEN"] = function(msg)
        Core.HandleSlashCommand(msg)
    end
end

local function ToggleQuickAccessSetting(key, label)
    ns.DB.ui[key] = not ns.DB.ui[key]
    Core.UpdateQuickAccessButtons()
    Print(label .. ": " .. (ns.DB.ui[key] and "shown" or "hidden"))
end

function Core.HandleSlashCommand(msg)
    local cmd, arg1 = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" then
        Core.ShowSummaryUI()
    elseif cmd == "scan" then
        Core.ScanInventory(arg1)
    elseif cmd == "summary" then
        Core.ShowSummaryUI()
    elseif cmd == "move" then
        Core.ShowMoveUI()
    elseif cmd == "dump" then
        ns.DB.ui.mode = "Dump to Bank"
        Core.SetExpansionFilterFromText(arg1)
        Core.ShowMoveUI()
    elseif cmd == "recall" then
        ns.DB.ui.mode = "Recall from Bank"
        Core.SetExpansionFilterFromText(arg1)
        Core.ShowMoveUI()
    elseif cmd == "organize" or cmd == "organizer" then
        Core.ShowOrganizeUI()
    elseif cmd == "vendor" or cmd == "sell" then
        Core.ShowVendorUI()
    elseif cmd == "settings" or cmd == "options" then
        Core.CreateUI()
        UI.activeTab = "Settings"
        UI.frame:Show()
        Core.RefreshUI()
    elseif cmd == "minimap" then
        ToggleQuickAccessSetting("showMinimapIcon", "Minimap button")
    elseif cmd == "bankbutton" then
        Print("Bank launcher is disabled in this version.")
    elseif cmd == "vendorbutton" then
        Print("Vendor launcher is disabled in this version.")
    elseif cmd == "buttons" or cmd == "quickaccess" then
        Core.PrintQuickAccessStatus()
    elseif cmd == "bankdiag" or cmd == "bankids" then
        Core.PrintBankContainerDiagnostics()
    elseif cmd == "ctx" then
        Core.UpdateContext()
        Print("=== ctx diagnostic ===")
        Print("UI.bankContextOpen=" .. tostring(UI.bankContextOpen))
        Print("IsPlayerBankInteractionActive=" .. tostring(IsPlayerBankInteractionActive()))
        Print("IsBankViewableByAPI=" .. tostring(IsBankViewableByAPI()))
        Print("IsBankStorageAccessible=" .. tostring(IsBankStorageAccessible()))
        local frameResult = GetShownGlobalFrame(BANK_FRAME_NAMES) or GetShownNamedFrameByPattern(BANK_FRAME_PATTERNS)
        Print("FrameDetected=" .. tostring(frameResult ~= nil) .. " (" .. tostring(frameResult) .. ")")
        Print("IsBankContextDetected=" .. tostring(IsBankContextDetected()))
        Print("context.bankOpen=" .. tostring(ns.DB.context.bankOpen))
        if CContainer and CContainer.GetContainerNumFreeSlots then
            local parts = {}
            local allIDs = {}
            for _, ids in ipairs({ PRIVATE_BANK_IDS, REAGENT_BANK_IDS, WARBAND_BANK_IDS }) do
                for _, bagID in ipairs(ids or {}) do table.insert(allIDs, bagID) end
            end
            for _, bagID in ipairs(allIDs) do
                local ok, free = pcall(CContainer.GetContainerNumFreeSlots, bagID)
                table.insert(parts, tostring(bagID) .. "=" .. tostring(ok and free or "err"))
            end
            Print("FreeSlots: " .. table.concat(parts, ", "))
        end
        Print("=== ctx end ===")
    elseif cmd == "rules" or cmd == "config" or cmd == "protect" then
        Core.CreateUI()
        UI.activeTab = "Rules"
        UI.frame:Show()
        Core.RefreshUI()
    elseif cmd == "debug" then
        Debug.SetDebug(not Debug.IsDebugEnabled())
        Print("Debug mode: " .. (Debug.IsDebugEnabled() and "ON" or "OFF"))
    elseif cmd == "diag" then
        Debug.RunDiagnosticDump()
    else
        Print("Commands: /icanteven, scan [bags|bank|all], summary, move, organize, vendor, rules, settings, minimap, buttons, bankdiag, debug, diag")
    end
end

function Core.OnAddonLoaded()
    ICantEvenRightNowDB = SafeCopyDefaults(Data.DefaultDB, ICantEvenRightNowDB)
    ns.DB = ICantEvenRightNowDB
    MigrateLegacyTabFilters()
    ns.DB.ui.showBankButton = false
    ns.DB.ui.showVendorButton = false
    NormalizeLegacyBankStorageKinds(ns.DB.scans.bank)
    Core.RegisterSlashCommands()
    Core.UpdateContext()
    Core.UpdateQuickAccessButtons()
    ScheduleQuickAccessRefresh()
    Print("Loaded. Type /icanteven to open the cleanup console.")
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("BANKFRAME_CLOSED")
eventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
eventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("MERCHANT_CLOSED")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
eventFrame:RegisterEvent("MAIL_SHOW")
eventFrame:RegisterEvent("MAIL_CLOSED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == ADDON_NAME then
            Core.OnAddonLoaded()
        elseif ns.DB and addonName and addonName:lower():find("betterbags", 1, true) then
            ScheduleQuickAccessRefresh()
        end
    elseif ns.DB and ns.DB.context then
        local interactionType = ...
        local bankInteraction = IsBankInteractionType(interactionType)
        local bankContextOpened = event == "BANKFRAME_OPENED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and bankInteraction)
        local bankContextClosed = event == "BANKFRAME_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and bankInteraction)
        local vendorContextOpened = event == "MERCHANT_SHOW"
        local vendorContextClosed = event == "MERCHANT_CLOSED"

        if bankContextOpened then
            UI.bankContextOpen = true
            UI.bankContextClosed = false
            UI.hadBankContext = true
        elseif bankContextClosed then
            UI.bankContextOpen = false
            UI.bankContextClosed = true
        end

        if vendorContextOpened then
            UI.vendorContextOpen = true
            UI.vendorContextClosed = false
            UI.hadVendorContext = true
        elseif vendorContextClosed then
            UI.vendorContextOpen = false
            UI.vendorContextClosed = true
        end

        Core.UpdateContext()
        if ((bankContextClosed and UI.hadBankContext) or (vendorContextClosed and UI.hadVendorContext)) and UI.frame and UI.frame:IsShown() then
            UI.frame:Hide()
        end
        if bankContextClosed then
            UI.hadBankContext = false
        end
        if vendorContextClosed then
            UI.hadVendorContext = false
        end
        if bankContextOpened then
            pcall(Core.ScanInventory, "all", true)
        end
        ScheduleQuickAccessRefresh()
    end
end)
