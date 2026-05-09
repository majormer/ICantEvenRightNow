-- I Can't Even Right Now (With My Bags and Bank) — Filter Logic
-- Filter state management, matching functions, and filter option builders.

local ADDON_NAME, ns = ...

local Core = ns.Core
local Data = ns.Data
local P    = ns.Private

local UI = P.UI

local EXPANSION_FILTER_ALL         = P.EXPANSION_FILTER_ALL
local EXPANSION_FILTER_NOT_CURRENT = P.EXPANSION_FILTER_NOT_CURRENT
local EXPANSION_FILTER_UNKNOWN     = P.EXPANSION_FILTER_UNKNOWN

local BIND_FILTER_ALL       = P.BIND_FILTER_ALL
local BIND_FILTER_BOE       = P.BIND_FILTER_BOE
local BIND_FILTER_WUE       = P.BIND_FILTER_WUE
local BIND_FILTER_SOULBOUND = P.BIND_FILTER_SOULBOUND
local BIND_FILTER_WARBAND   = P.BIND_FILTER_WARBAND
local BIND_FILTER_BOP       = P.BIND_FILTER_BOP

local TYPE_FILTER_REAGENT         = P.TYPE_FILTER_REAGENT
local TYPE_FILTER_WUE             = P.TYPE_FILTER_WUE
local TYPE_FILTER_VENDOR_SELLABLE = P.TYPE_FILTER_VENDOR_SELLABLE

local STORAGE_PRIVATE_BANK = P.STORAGE_PRIVATE_BANK
local STORAGE_REAGENT_BANK = P.STORAGE_REAGENT_BANK
local STORAGE_WARBAND_BANK = P.STORAGE_WARBAND_BANK

local BAG_SCOPE  = P.BAG_SCOPE
local BANK_SCOPE = P.BANK_SCOPE

local IsCurrentExpansion    = P.IsCurrentExpansion
local IsOldExpansion        = P.IsOldExpansion
local IsUnknownExpansion    = P.IsUnknownExpansion
local GetExpansionName      = P.GetExpansionName
local IsItemWarboundUntilEquipped = P.IsItemWarboundUntilEquipped

-- ===========================================================================
-- Equip slot → inventory slot mapping
-- Used now for ilvl filtering; ready for "Upgrade for current character" feature.
-- For slots with two positions (rings, trinkets), both are listed so we can
-- compare against the weaker of the two when checking upgrade potential.
-- ===========================================================================

local INVTYPE_TO_SLOTS = {
    INVTYPE_HEAD           = {1},
    INVTYPE_NECK           = {2},
    INVTYPE_SHOULDER       = {3},
    INVTYPE_BODY           = {4},   -- shirt
    INVTYPE_CHEST          = {5},
    INVTYPE_ROBE           = {5},
    INVTYPE_WAIST          = {6},
    INVTYPE_LEGS           = {7},
    INVTYPE_FEET           = {8},
    INVTYPE_WRIST          = {9},
    INVTYPE_HAND           = {10},
    INVTYPE_FINGER         = {11, 12},
    INVTYPE_TRINKET        = {13, 14},
    INVTYPE_CLOAK          = {15},
    INVTYPE_WEAPON         = {16},
    INVTYPE_WEAPONMAINHAND = {16},
    INVTYPE_2HWEAPON       = {16},
    INVTYPE_SHIELD         = {17},
    INVTYPE_WEAPONOFFHAND  = {17},
    INVTYPE_HOLDABLE       = {17},
    INVTYPE_RANGED         = {18},
    INVTYPE_RANGEDRIGHT    = {18},
}

-- Returns true if the item can be equipped (has a valid equipLoc).
local function IsEquippable(item)
    local loc = item.equipLoc
    return loc and loc ~= "" and loc ~= "INVTYPE_NON_EQUIP" and loc ~= "INVTYPE_NON_EQUIP_IGNORE"
end

-- Returns the effective item level of the currently equipped item in the slot(s)
-- for the given equipLoc, or nil if no mapping or no item is equipped.
-- For two-slot types (rings, trinkets) returns the LOWER of the two, so an
-- item that beats it is a genuine upgrade.
local function GetEquippedItemLevel(equipLoc)
    local slots = INVTYPE_TO_SLOTS[equipLoc]
    if not slots then return nil end
    local result = nil
    for _, slotID in ipairs(slots) do
        local ilvl = GetInventoryItemLevel("player", slotID) or 0
        if result == nil or ilvl < result then
            result = ilvl
        end
    end
    return result
end

P.INVTYPE_TO_SLOTS       = INVTYPE_TO_SLOTS
P.IsEquippable           = IsEquippable
P.GetEquippedItemLevel   = GetEquippedItemLevel

-- ===========================================================================
-- Filter branch helpers
-- ===========================================================================

local function EnsureFilterBranch(filters, key)
    filters[key] = filters[key] or {}
    return filters[key]
end

local function EnsureTabFilters(tabName)
    ns.DB.ui.tabFilters = ns.DB.ui.tabFilters or {}
    ns.DB.ui.tabFilters[tabName] = ns.DB.ui.tabFilters[tabName] or {}
    local filters = ns.DB.ui.tabFilters[tabName]
    local expansion = EnsureFilterBranch(filters, "expansion")
    local itemType  = EnsureFilterBranch(filters, "type")
    local bind      = EnsureFilterBranch(filters, "bind")
    local location  = EnsureFilterBranch(filters, "location")
    local name      = EnsureFilterBranch(filters, "name")
    local itemLevel = EnsureFilterBranch(filters, "itemLevel")
    local slot      = EnsureFilterBranch(filters, "slot")
    local upgrade   = EnsureFilterBranch(filters, "upgrade")
    if expansion.include == nil then expansion.include = EXPANSION_FILTER_ALL end
    if itemType.include == nil  then itemType.include  = "All" end
    if bind.include == nil      then bind.include      = BIND_FILTER_ALL end
    if location.include == nil  then location.include  = "All" end
    if slot.include == nil      then slot.include      = "All" end
    if upgrade.include == nil   then upgrade.include   = "All" end
    -- itemLevel.min and itemLevel.max default to nil (no filter)
    name.includeText = name.includeText or ""
    name.excludeText = name.excludeText or ""
    filters.hideBlocked    = filters.hideBlocked    and true or false
    filters.advancedEnabled = filters.advancedEnabled and true or false
    return filters
end

local function MigrateLegacyTabFilters()
    local moveFilters = EnsureTabFilters("Move")
    if not moveFilters.migratedFromLegacy then
        moveFilters.expansion.include = ns.DB.ui.expansionFilter or EXPANSION_FILTER_ALL
        moveFilters.type.include      = ns.DB.ui.typeFilter      or "All"
        moveFilters.location.include  = ns.DB.ui.locationFilter  or "All"
        moveFilters.name.includeText  = ns.DB.ui.search          or ""
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

P.EnsureTabFilters        = EnsureTabFilters
P.MigrateLegacyTabFilters = MigrateLegacyTabFilters

-- ===========================================================================
-- Filter value sentinel
-- ===========================================================================

local function IsAllFilterValue(value)
    return value == nil
        or value == "All"
        or value == EXPANSION_FILTER_ALL
        or value == BIND_FILTER_ALL
end

P.IsAllFilterValue = IsAllFilterValue

-- ===========================================================================
-- Filter state mutations
-- ===========================================================================

local function SetFilterInclude(tabName, key, value)
    local filters = EnsureTabFilters(tabName)
    EnsureFilterBranch(filters, key).include = value
    -- Keep legacy DB keys in sync for backward compat
    if tabName == "Move" then
        if key == "expansion" then
            ns.DB.ui.expansionFilter = value
        elseif key == "type" then
            ns.DB.ui.typeFilter = value
        elseif key == "location" then
            ns.DB.ui.locationFilter = value
        end
    end
end

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
end

local function SetFilterHideBlocked(tabName, value)
    local filters = EnsureTabFilters(tabName)
    filters.hideBlocked = value and true or false
end

-- Maps equipLoc -> canonical slot label used by the slot filter.
local EQUIPLOC_TO_SLOT_LABEL = {
    INVTYPE_HEAD             = "Head",
    INVTYPE_NECK             = "Neck",
    INVTYPE_SHOULDER         = "Shoulder",
    INVTYPE_BODY             = "Shirt",
    INVTYPE_CHEST            = "Chest",
    INVTYPE_ROBE             = "Chest",
    INVTYPE_WAIST            = "Waist",
    INVTYPE_LEGS             = "Legs",
    INVTYPE_FEET             = "Feet",
    INVTYPE_WRIST            = "Wrist",
    INVTYPE_HAND             = "Hands",
    INVTYPE_FINGER           = "Finger",
    INVTYPE_TRINKET          = "Trinket",
    INVTYPE_CLOAK            = "Back",
    INVTYPE_WEAPON           = "One-Hand",
    INVTYPE_WEAPONMAINHAND   = "One-Hand",
    INVTYPE_WEAPONOFFHAND    = "Off-Hand",
    INVTYPE_HOLDABLE         = "Off-Hand",
    INVTYPE_2HWEAPON         = "Two-Hand",
    INVTYPE_SHIELD           = "Off-Hand",
    INVTYPE_RANGED           = "Ranged",
    INVTYPE_RANGEDRIGHT      = "Ranged",
    INVTYPE_TABARD           = "Tabard",
}
P.EQUIPLOC_TO_SLOT_LABEL = EQUIPLOC_TO_SLOT_LABEL

local function GetSlotLabel(item)
    return item.equipLoc and EQUIPLOC_TO_SLOT_LABEL[item.equipLoc]
end

local function MatchesSlotInclude(item, include)
    return FilterMatchesInclude(include, function(value)
        return GetSlotLabel(item) == value
    end)
end

local function SetFilterItemLevel(tabName, min, max)
    local filters = EnsureTabFilters(tabName)
    EnsureFilterBranch(filters, "itemLevel")
    filters.itemLevel.min = (min and min ~= "") and tonumber(min) or nil
    filters.itemLevel.max = (max and max ~= "") and tonumber(max) or nil
end

local function SetFilterSlot(tabName, value)
    local filters = EnsureTabFilters(tabName)
    EnsureFilterBranch(filters, "slot")
    filters.slot.include = value
end

local function ResetTabFilters(tabName)
    local filters = EnsureTabFilters(tabName)
    filters.expansion.include = EXPANSION_FILTER_ALL
    filters.type.include      = "All"
    filters.bind.include      = BIND_FILTER_ALL
    filters.location.include  = "All"
    filters.name.includeText  = ""
    filters.name.excludeText  = ""
    filters.hideBlocked       = false
    filters.advancedEnabled   = false
    if filters.itemLevel then
        filters.itemLevel.min = nil
        filters.itemLevel.max = nil
    end
    if filters.slot then
        filters.slot.include = "All"
    end
    if filters.upgrade then
        filters.upgrade.include = "All"
    end
    if tabName == "Move" then
        ns.DB.ui.expansionFilter = EXPANSION_FILTER_ALL
        ns.DB.ui.typeFilter      = "All"
        ns.DB.ui.locationFilter  = "All"
        ns.DB.ui.search          = ""
    elseif tabName == "Organize" then
        ns.DB.ui.organizerSearch = ""
    elseif tabName == "Vendor" then
        ns.DB.ui.vendorSearch = ""
    end
end

local function SetFilterUpgrade(tabName, value)
    local filters = EnsureTabFilters(tabName)
    filters.upgrade.include = value
end

P.SetFilterInclude     = SetFilterInclude
P.SetFilterSearch      = SetFilterSearch
P.SetFilterHideBlocked = SetFilterHideBlocked
P.SetFilterItemLevel   = SetFilterItemLevel
P.SetFilterSlot        = SetFilterSlot
P.SetFilterUpgrade     = SetFilterUpgrade
P.ResetTabFilters      = ResetTabFilters

-- ===========================================================================
-- Label helpers
-- ===========================================================================

local function GetExpansionFilterLabel(value)
    if value == EXPANSION_FILTER_ALL         then return "All expansions" end
    if value == EXPANSION_FILTER_NOT_CURRENT then return "Not current" end
    if value == EXPANSION_FILTER_UNKNOWN     then return "Unknown expansion" end
    return GetExpansionName(value)
end

local function GetMultiSelectLabel(include, allLabel)
    if IsAllFilterValue(include) or type(include) ~= "table" then
        return allLabel or "All"
    end
    local parts = {}
    for k, v in pairs(include) do
        local actual = v == true and k or v
        if not IsAllFilterValue(actual) then
            table.insert(parts, actual)
        end
    end
    if #parts == 0  then return allLabel or "All" end
    if #parts <= 2  then return table.concat(parts, ", ") end
    return parts[1] .. " +" .. (#parts - 1)
end

local function BuildFilterSummary(tabName)
    local filters = EnsureTabFilters(tabName)
    local parts = {}
    if not IsAllFilterValue(filters.expansion.include) then
        table.insert(parts, "Expansion: " .. GetExpansionFilterLabel(filters.expansion.include))
    end
    if not IsAllFilterValue(filters.type.include) then
        table.insert(parts, "Type: " .. GetMultiSelectLabel(filters.type.include, "All"))
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
    if filters.slot and not IsAllFilterValue(filters.slot.include) then
        local label = GetMultiSelectLabel(filters.slot.include, "All")
        table.insert(parts, "Slot: " .. label)
    end
    if filters.itemLevel then
        local ilvl = filters.itemLevel
        if ilvl.min and ilvl.max then
            table.insert(parts, "iLvl: " .. ilvl.min .. "-" .. ilvl.max)
        elseif ilvl.min then
            table.insert(parts, "iLvl: ≥" .. ilvl.min)
        elseif ilvl.max then
            table.insert(parts, "iLvl: ≤" .. ilvl.max)
        end
    end
    return #parts > 0 and table.concat(parts, "  |  ") or "Filters: All"
end

P.GetExpansionFilterLabel = GetExpansionFilterLabel
P.GetMultiSelectLabel     = GetMultiSelectLabel
P.BuildFilterSummary      = BuildFilterSummary

-- ===========================================================================
-- Filter matching
-- ===========================================================================

local function FilterMatchesInclude(include, matcher)
    if IsAllFilterValue(include) then return true end
    if type(include) == "table" then
        local hasSpecificValue = false
        for key, value in pairs(include) do
            local actual = value == true and key or value
            if not IsAllFilterValue(actual) then
                hasSpecificValue = true
                if matcher(actual) then return true end
            end
        end
        return not hasSpecificValue
    end
    return matcher(include)
end

local function FilterIncludesValue(include, expected)
    if include == expected then return true end
    if type(include) == "table" then
        for key, value in pairs(include) do
            local actual = value == true and key or value
            if actual == expected then return true end
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
            local isInReagentBank   = item.storageKind == STORAGE_REAGENT_BANK
            local goesToReagentBank = item.bankTargetStorage == STORAGE_REAGENT_BANK
            local isProfMaterial    = item.typeTag == Data.ItemTypes.PROFESSION
            return isInReagentBank or goesToReagentBank or isProfMaterial
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
            return item.isWarbandBound
                or item.bindingScope == "Warbound"
                or item.bindingScope == "Warbound Until Equipped"
        elseif value == BIND_FILTER_BOP then
            return item.bindType == 1 or item.bindingScope == "Soulbound" or item.isSoulbound
        end
        return true
    end)
end

local function MatchesLocationInclude(item, include)
    return FilterMatchesInclude(include, function(value)
        if value == "Bags"  then return item.scope == BAG_SCOPE end
        if value == "Bank"  then return item.scope == BANK_SCOPE end
        if value == STORAGE_PRIVATE_BANK
            or value == STORAGE_REAGENT_BANK
            or value == STORAGE_WARBAND_BANK then
            return item.storageKind == value
        end
        return true
    end)
end

local function BuildItemSearchParts(item, extraParts)
    local parts = {
        item.name          or "",
        tostring(item.itemID or ""),
        item.expansionName or "",
        item.typeTag       or "",
        item.location      or "",
        item.reason        or "",
        item.bindingScope  or "",
    }
    for _, part in ipairs(extraParts or {}) do
        table.insert(parts, part or "")
    end
    return parts
end

local function TextMatchesSearch(searchText, parts)
    local search = searchText and searchText:lower() or ""
    if search == "" then return true end
    local haystack = table.concat(parts, " "):lower()
    return haystack:find(search, 1, true) ~= nil
end

local function MatchesTabFilters(item, tabName, extraParts)
    local filters = EnsureTabFilters(tabName)
    if not MatchesExpansionInclude(item, filters.expansion.include) then return false end
    if not MatchesTypeInclude(item, filters.type.include)           then return false end
    if not MatchesBindInclude(item, filters.bind.include)           then return false end
    if not MatchesLocationInclude(item, filters.location.include)   then return false end
    if filters.slot and not IsAllFilterValue(filters.slot.include) then
        if not MatchesSlotInclude(item, filters.slot.include) then return false end
    end
    -- Upgrade filter: compares item level against equipped items in the same slot(s).
    -- Non-equippable or items with uncached data (itemLevel nil) pass through.
    if filters.upgrade and not IsAllFilterValue(filters.upgrade.include) then
        if IsEquippable(item) and item.itemLevel and item.itemLevel > 0 then
            local equippedIlvl = GetEquippedItemLevel(item.equipLoc)
            if equippedIlvl ~= nil then
                local isUpgrade = item.itemLevel > equippedIlvl
                if filters.upgrade.include == "Upgrade" and not isUpgrade then return false end
                if filters.upgrade.include == "Not Upgrade" and isUpgrade then return false end
            end
        end
    end
    -- Item level filter: when active, restricts to equippable gear within the range.
    -- Items without cached GetItemInfo data (equipLoc/itemLevel nil) pass through;
    -- non-equippable items with known type are hidden entirely.
    local ilvl = filters.itemLevel
    if ilvl and (ilvl.min or ilvl.max) then
        local hasGearData = item.equipLoc and item.equipLoc ~= ""
        if hasGearData then
            -- Known non-equippable: hide
            if not IsEquippable(item) then return false end
            -- Known equippable: apply range if level is available
            local level = item.itemLevel
            if level and level > 0 then
                if ilvl.min and level < ilvl.min then return false end
                if ilvl.max and level > ilvl.max then return false end
            end
            -- itemLevel nil or 0 with valid equipLoc = uncached data; pass through
        else
            -- equipLoc nil = either non-gear or uncached; hide only if other gear signals absent
            -- Use classID 2 (Weapon) or 4 (Armor) as fallback signal
            if item.classID == 2 or item.classID == 4 then
                -- Gear by classID but no equipLoc/ilvl data yet; pass through
            else
                return false
            end
        end
    end
    local searchParts = BuildItemSearchParts(item, extraParts)
    if not TextMatchesSearch(filters.name.includeText, searchParts) then return false end
    if filters.name.excludeText ~= "" and TextMatchesSearch(filters.name.excludeText, { item.name or "" }) then
        return false
    end
    return true
end

local function PlanMatchesTabFilters(plan, tabName)
    local item = plan.item or {}
    return MatchesTabFilters(item, tabName, {
        plan.currentStorage or "",
        plan.targetStorage  or "",
        plan.action         or "",
        plan.reason         or "",
        plan.blockedReason  or "",
    })
end

P.FilterMatchesInclude    = FilterMatchesInclude
P.FilterIncludesValue     = FilterIncludesValue
P.MatchesExpansionInclude = MatchesExpansionInclude
P.IsVendorSellable        = IsVendorSellable
P.MatchesTypeInclude      = MatchesTypeInclude
P.MatchesBindInclude      = MatchesBindInclude
P.MatchesLocationInclude  = MatchesLocationInclude
P.BuildItemSearchParts    = BuildItemSearchParts
P.TextMatchesSearch       = TextMatchesSearch
P.MatchesTabFilters       = MatchesTabFilters
P.PlanMatchesTabFilters   = PlanMatchesTabFilters

-- ===========================================================================
-- Filter option builders (used by UI dropdowns)
-- ===========================================================================

local function GetTypeFilterOptions()
    return {
        { text = "All",                           value = "All" },
        { text = Data.ItemTypes.REPUTATION,       value = Data.ItemTypes.REPUTATION },
        { text = Data.ItemTypes.QUEST,            value = Data.ItemTypes.QUEST },
        { text = Data.ItemTypes.SEASONAL,         value = Data.ItemTypes.SEASONAL },
        { text = Data.ItemTypes.PROFESSION,       value = Data.ItemTypes.PROFESSION },
        { text = TYPE_FILTER_REAGENT,             value = TYPE_FILTER_REAGENT },
        { text = Data.ItemTypes.CONSUMABLE,       value = Data.ItemTypes.CONSUMABLE },
        { text = TYPE_FILTER_VENDOR_SELLABLE,     value = TYPE_FILTER_VENDOR_SELLABLE },
        { text = Data.ItemTypes.UNKNOWN,          value = Data.ItemTypes.UNKNOWN },
    }
end

local function GetBindFilterOptions()
    return {
        { text = "All",            value = BIND_FILTER_ALL },
        { text = BIND_FILTER_BOE,  value = BIND_FILTER_BOE },
        { text = BIND_FILTER_SOULBOUND, value = BIND_FILTER_SOULBOUND },
        { text = "Warband / WuE",  value = BIND_FILTER_WARBAND },
    }
end

local function GetBankLocationFilterOptions()
    return {
        { text = "All",                value = "All" },
        { text = STORAGE_PRIVATE_BANK, value = STORAGE_PRIVATE_BANK },
        { text = STORAGE_REAGENT_BANK, value = STORAGE_REAGENT_BANK },
        { text = STORAGE_WARBAND_BANK, value = STORAGE_WARBAND_BANK },
    }
end

local function GetExpansionOptions()
    local options = {
        { text = "All expansions",    value = EXPANSION_FILTER_ALL },
        { text = "Not current",       value = EXPANSION_FILTER_NOT_CURRENT },
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

local function GetSlotFilterOptions()
    return {
        { text = "All",      value = "All" },
        { text = "Head",     value = "Head" },
        { text = "Neck",     value = "Neck" },
        { text = "Shoulder", value = "Shoulder" },
        { text = "Back",     value = "Back" },
        { text = "Chest",    value = "Chest" },
        { text = "Wrist",    value = "Wrist" },
        { text = "Hands",    value = "Hands" },
        { text = "Waist",    value = "Waist" },
        { text = "Legs",     value = "Legs" },
        { text = "Feet",     value = "Feet" },
        { text = "Finger",   value = "Finger" },
        { text = "Trinket",  value = "Trinket" },
        { text = "One-Hand", value = "One-Hand" },
        { text = "Two-Hand", value = "Two-Hand" },
        { text = "Off-Hand", value = "Off-Hand" },
        { text = "Ranged",   value = "Ranged" },
        { text = "Shirt",    value = "Shirt" },
        { text = "Tabard",   value = "Tabard" },
    }
end

P.GetTypeFilterOptions       = GetTypeFilterOptions
P.GetBindFilterOptions       = GetBindFilterOptions
P.GetBankLocationFilterOptions = GetBankLocationFilterOptions
P.GetExpansionOptions        = GetExpansionOptions
local function GetUpgradeFilterOptions()
    return {
        { text = "All",         value = "All" },
        { text = "Upgrade",     value = "Upgrade" },
        { text = "Not Upgrade", value = "Not Upgrade" },
    }
end

P.GetSlotFilterOptions       = GetSlotFilterOptions
P.GetUpgradeFilterOptions    = GetUpgradeFilterOptions

-- ===========================================================================
-- Saved Filters ("Favorites")
-- Presets store the five categorical filter fields: expansion, bind, type,
-- slot, upgrade. ilvl range and search text are excluded — they are too
-- query-specific to be useful as reusable presets.
-- ===========================================================================

local DEFAULT_SAVED_FILTERS = {
    {
        name      = "Old Gear Dump",
        expansion = EXPANSION_FILTER_NOT_CURRENT,
        bind      = BIND_FILTER_ALL,
        type      = "All",
        slot      = "All",
        upgrade   = "All",
    },
    {
        name      = "Upgrade Check",
        expansion = EXPANSION_FILTER_ALL,
        bind      = BIND_FILTER_ALL,
        type      = "All",
        slot      = "All",
        upgrade   = "Upgrade",
    },
}

-- Seeds the two default presets the first time the addon runs (or when the
-- saved-filter list is empty and the seed flag has never been set).
local function SeedDefaultSavedFilters()
    if ns.DB.savedFiltersSeeded then return end
    ns.DB.savedFilters = ns.DB.savedFilters or {}
    if #ns.DB.savedFilters == 0 then
        for _, preset in ipairs(DEFAULT_SAVED_FILTERS) do
            table.insert(ns.DB.savedFilters, {
                name      = preset.name,
                expansion = preset.expansion,
                bind      = preset.bind,
                type      = preset.type,
                slot      = preset.slot,
                upgrade   = preset.upgrade,
            })
        end
    end
    ns.DB.savedFiltersSeeded = true
end

local function GetSavedFilters()
    return ns.DB.savedFilters or {}
end

-- Returns a dropdown-ready options list from the current saved filter list.
local function GetSavedFiltersOptions()
    local opts = {}
    for _, preset in ipairs(ns.DB.savedFilters or {}) do
        table.insert(opts, { text = preset.name, value = preset.name })
    end
    return opts
end

-- Looks up a saved preset by name. Returns the preset table, or nil.
local function FindSavedFilter(name)
    for _, preset in ipairs(ns.DB.savedFilters or {}) do
        if preset.name == name then return preset end
    end
    return nil
end

-- Applies a saved preset to the given tab's filter state.
local function ApplySavedFilter(preset, tabName)
    if not preset then return end
    local filters = EnsureTabFilters(tabName)
    filters.expansion.include = preset.expansion
    filters.bind.include      = preset.bind
    filters.type.include      = preset.type
    EnsureFilterBranch(filters, "slot")
    filters.slot.include      = preset.slot
    EnsureFilterBranch(filters, "upgrade")
    filters.upgrade.include   = preset.upgrade
end

-- Saves the current categorical filter state under the given name.
-- Overwrites any existing preset with the same name.
local function SaveFilter(name, tabName)
    if not name or name == "" then return false end
    local filters = EnsureTabFilters(tabName)
    local preset = {
        name      = name,
        expansion = filters.expansion.include,
        bind      = filters.bind.include,
        type      = filters.type.include,
        slot      = filters.slot and filters.slot.include or "All",
        upgrade   = filters.upgrade and filters.upgrade.include or "All",
    }
    ns.DB.savedFilters = ns.DB.savedFilters or {}
    for i, existing in ipairs(ns.DB.savedFilters) do
        if existing.name == name then
            ns.DB.savedFilters[i] = preset
            return true
        end
    end
    table.insert(ns.DB.savedFilters, preset)
    return true
end

-- Removes the preset with the given name. Returns true if found and removed.
local function DeleteSavedFilter(name)
    if not name or name == "" then return false end
    ns.DB.savedFilters = ns.DB.savedFilters or {}
    for i, preset in ipairs(ns.DB.savedFilters) do
        if preset.name == name then
            table.remove(ns.DB.savedFilters, i)
            return true
        end
    end
    return false
end

P.SeedDefaultSavedFilters = SeedDefaultSavedFilters
P.GetSavedFilters         = GetSavedFilters
P.GetSavedFiltersOptions  = GetSavedFiltersOptions
P.FindSavedFilter         = FindSavedFilter
P.ApplySavedFilter        = ApplySavedFilter
P.SaveFilter              = SaveFilter
P.DeleteSavedFilter       = DeleteSavedFilter
