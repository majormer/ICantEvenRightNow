-- I Can't Even Right Now (With My Bags and Bank) — Item Evaluator
-- Item type classification, binding detection, decision building, and related helpers.

local ADDON_NAME, ns = ...

local Core = ns.Core
local Data = ns.Data
local P    = ns.Private

local STORAGE_BAGS          = P.STORAGE_BAGS
local STORAGE_PRIVATE_BANK  = P.STORAGE_PRIVATE_BANK
local STORAGE_REAGENT_BANK  = P.STORAGE_REAGENT_BANK
local STORAGE_WARBAND_BANK  = P.STORAGE_WARBAND_BANK
local BAG_SCOPE             = P.BAG_SCOPE
local BANK_SCOPE            = P.BANK_SCOPE
local BANK_TAB_DATA         = P.BANK_TAB_DATA   -- stable table reference (wiped, never replaced)
local BAG_SLOT_FLAGS_REAGENTS = P.BAG_SLOT_FLAGS_REAGENTS
local MYTHIC_KEYSTONE_ITEM_IDS = P.MYTHIC_KEYSTONE_ITEM_IDS
local HAS_REAGENT_BANK      = P.HAS_REAGENT_BANK

local BankTabStorageKey     = P.BankTabStorageKey
local GetExpansionName      = P.GetExpansionName
local LocationKey           = P.LocationKey
local GetStorageBagIDs      = P.GetStorageBagIDs

-- ===========================================================================
-- Item helpers
-- ===========================================================================

local function IsBankBag(bagID)
    if bagID == -1 or bagID == -3 then return true end
    return bagID >= 5 and bagID <= 11
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
        neverSell = false,
        ignore = false,
        expansionOverride = nil,
        notes = nil,
        createdFrom = "Rules tab",
    }
    return ns.DB.rules.items[itemID]
end

local function IsMythicKeystone(item)
    if MYTHIC_KEYSTONE_ITEM_IDS[item.itemID] then return true end
    return item.name == "Mythic Keystone"
end

P.IsBankBag       = IsBankBag
P.FindCuratedItem = FindCuratedItem
P.EnsureRule      = EnsureRule
P.IsMythicKeystone = IsMythicKeystone

-- ===========================================================================
-- Binding detection
-- ===========================================================================

local function GetBindingDetails(bagID, slot, bindType, fallbackIsBound)
    local details = {
        bindingScope    = fallbackIsBound and "Bound" or "Unbound",
        isBound         = fallbackIsBound and true or false,
        isSoulbound     = false,
        isWarbandBound  = false,
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

    if not (ItemLocation and C_Item) then return details end

    local itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slot)
    if not itemLocation then return details end

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
            details.bindingScope   = "Warbound Until Equipped"
            details.isWarbandBound = true
            details.accountBankAllowed = true
        end
    end

    if details.isBound then
        details.isSoulbound        = true
        details.accountBankAllowed = false
        if C_Bank and C_Bank.IsItemAllowedInBankType and Enum and Enum.BankType and Enum.BankType.Account then
            local ok, allowed = pcall(C_Bank.IsItemAllowedInBankType, Enum.BankType.Account, itemLocation)
            if ok and allowed then
                details.bindingScope   = "Warbound"
                details.isSoulbound    = false
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

local function IsItemWarboundUntilEquipped(item)
    if item.bindingScope == "Warbound Until Equipped" then return true end
    if item.bindType and item.bindType ~= 2 then return false end
    if not (ItemLocation and C_Item and C_Item.IsBoundToAccountUntilEquip) then return false end
    if type(item.bagID) ~= "number" or type(item.slot) ~= "number" then return false end
    local itemLocation = ItemLocation:CreateFromBagAndSlot(item.bagID, item.slot)
    if not itemLocation then return false end
    local ok, isWuE = pcall(C_Item.IsBoundToAccountUntilEquip, itemLocation)
    return ok and isWuE and true or false
end

P.GetBindingDetails        = GetBindingDetails
P.IsItemWarboundUntilEquipped = IsItemWarboundUntilEquipped

-- ===========================================================================
-- Item type classification
-- ===========================================================================

local function GetItemType(item)
    if item.rule and item.rule.typeOverride then return item.rule.typeOverride end
    if item.curated and item.curated.type   then return item.curated.type end
    if IsMythicKeystone(item)               then return Data.ItemTypes.SEASONAL end
    if item.classID == 0  then return Data.ItemTypes.CONSUMABLE end
    if item.classID == 7  then return Data.ItemTypes.PROFESSION end
    if item.classID == 12 then return Data.ItemTypes.QUEST end
    if item.bindType == 2 and (item.classID == 2 or item.classID == 4) then return Data.ItemTypes.BOE end
    if item.classID == 2 or item.classID == 4 then return Data.ItemTypes.EQUIPMENT end
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

P.GetItemType         = GetItemType
P.IsCurrentExpansion  = IsCurrentExpansion
P.IsOldExpansion      = IsOldExpansion
P.IsUnknownExpansion  = IsUnknownExpansion

-- ===========================================================================
-- Profession and bank storage routing
-- ===========================================================================

local function GetCharacterProfessionSubclasses()
    local subclasses = {}
    if not GetProfessions or not GetProfessionInfo then return subclasses end
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

local function IsTransferableSharedValueItem(item, itemType)
    itemType = itemType or item.typeTag
    return item.accountBankAllowed
        and itemType ~= Data.ItemTypes.EQUIPMENT
        and itemType ~= Data.ItemTypes.PROFESSION
        and itemType ~= Data.ItemTypes.QUEST
        and itemType ~= Data.ItemTypes.SEASONAL
end

local function GetPreferredProfessionStorage(item, charProfSubclasses)
    local noProfData = not next(charProfSubclasses)
    local isCharMat  = noProfData or (charProfSubclasses[item.subclassID or -1] == true)
    if isCharMat then
        for _, tab in ipairs(BANK_TAB_DATA) do
            if bit.band(tab.flags, BAG_SLOT_FLAGS_REAGENTS) ~= 0 then
                return BankTabStorageKey(tab.bagID),
                    "Crafting material belongs in the reagents bank tab (" .. tab.name .. ")"
            end
        end
        if HAS_REAGENT_BANK then
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

P.GetCharacterProfessionSubclasses = GetCharacterProfessionSubclasses
P.IsTransferableSharedValueItem    = IsTransferableSharedValueItem
P.GetPreferredProfessionStorage    = GetPreferredProfessionStorage
P.GetPreferredBankStorage          = GetPreferredBankStorage

-- ===========================================================================
-- Decision building
-- ===========================================================================

local function SetBankOrRecallDecision(item, bankReason, recallReason)
    if item.scope == BANK_SCOPE then return recallReason or bankReason end
    return bankReason
end

local function BuildDecision(item)
    local rule = ns.DB.rules.items[item.itemID]
    item.rule    = rule
    item.curated = FindCuratedItem(item.itemID)

    local expansionID = rule and rule.expansionOverride or item.expansionID
    if item.curated and item.curated.expansion then
        expansionID = expansionID or item.curated.expansion
    end

    local itemType = GetItemType(item)
    local blocked  = {}
    local reason   = "Unclassified"
    local bankTargetStorage

    if rule and rule.ignore then
        reason = "Ignored by item rule"
        table.insert(blocked, "Ignored")
    elseif rule and rule.protect then
        reason = "Protected by item rule"
        table.insert(blocked, reason)
    elseif IsMythicKeystone(item) then
        expansionID = Data.CurrentExpansionID
        reason = "Mythic Keystone is protected as current seasonal content"
        table.insert(blocked, "Mythic Keystone")
    elseif item.isBound and (item.classID == 2 or item.classID == 4) then
        reason = "Soulbound equipment"
        table.insert(blocked, "Soulbound equipment")
    elseif itemType == Data.ItemTypes.QUEST then
        reason = "Quest item"
        table.insert(blocked, "Quest item")
    elseif item.curated and item.curated.action == Data.Actions.BANK then
        reason = SetBankOrRecallDecision(item,
            item.curated.reason or "Curated old-content item",
            "Curated item in bank")
    elseif itemType == Data.ItemTypes.CONSUMABLE and IsOldExpansion(expansionID) then
        reason = SetBankOrRecallDecision(item, "Old expansion consumable", "Old expansion consumable in bank")
    elseif itemType == Data.ItemTypes.BOE and IsOldExpansion(expansionID) then
        reason = "Old BoE — review before selling"
    elseif itemType == Data.ItemTypes.PROFESSION and IsOldExpansion(expansionID) then
        reason = SetBankOrRecallDecision(item, "Old expansion material", "Old expansion material in bank")
    elseif item.scope == BAG_SCOPE and itemType == Data.ItemTypes.PROFESSION then
        bankTargetStorage, reason = GetPreferredBankStorage(item, itemType)
    elseif IsOldExpansion(expansionID) and itemType ~= Data.ItemTypes.EQUIPMENT then
        reason = SetBankOrRecallDecision(item, "Old expansion item", "Old expansion item in bank")
    elseif item.scope == BANK_SCOPE
        and expansionID
        and IsCurrentExpansion(expansionID)
        and (itemType == Data.ItemTypes.PROFESSION or itemType == Data.ItemTypes.CONSUMABLE or itemType == Data.ItemTypes.CURRENCY_LIKE) then
        reason = "Current expansion item in bank"
    elseif item.scope == BAG_SCOPE and item.bindingScope == "Warbound Until Equipped" then
        bankTargetStorage = STORAGE_WARBAND_BANK
        reason = "Warbound-until-equipped — belongs in shared storage"
    elseif item.scope == BAG_SCOPE and IsTransferableSharedValueItem(item, itemType) then
        bankTargetStorage, reason = GetPreferredBankStorage(item, itemType)
    elseif IsCurrentExpansion(expansionID) then
        reason = "Current expansion — blocked by default"
        table.insert(blocked, "Current expansion")
    end

    local eligibleForBankMove = item.scope == BAG_SCOPE
        and not (rule and (rule.ignore or rule.protect))
    local eligibleForRecall = item.scope == BANK_SCOPE
        and not (rule and (rule.ignore or rule.protect))

    if item.scope == BAG_SCOPE and not bankTargetStorage then
        bankTargetStorage = GetPreferredBankStorage(item, itemType)
    end

    item.expansionID       = expansionID
    item.expansionName     = GetExpansionName(expansionID)
    item.typeTag           = itemType
    item.reason            = reason
    item.blockedReasons    = blocked
    item.eligibleForBankMove = eligibleForBankMove
    item.eligibleForRecall  = eligibleForRecall
    item.bankTargetStorage  = bankTargetStorage
    item.ruleStatus         = rule and "custom" or "none"
    item.key                = LocationKey(item)

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

P.BuildDecision   = BuildDecision
P.GetAllDecisions = GetAllDecisions
