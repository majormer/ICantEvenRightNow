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
    if expansion.include == nil then expansion.include = EXPANSION_FILTER_ALL end
    if itemType.include == nil  then itemType.include  = "All" end
    if bind.include == nil      then bind.include      = BIND_FILTER_ALL end
    if location.include == nil  then location.include  = "All" end
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

P.SetFilterInclude    = SetFilterInclude
P.SetFilterSearch     = SetFilterSearch
P.SetFilterHideBlocked = SetFilterHideBlocked
P.ResetTabFilters     = ResetTabFilters

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

P.GetTypeFilterOptions       = GetTypeFilterOptions
P.GetBindFilterOptions       = GetBindFilterOptions
P.GetBankLocationFilterOptions = GetBankLocationFilterOptions
P.GetExpansionOptions        = GetExpansionOptions
