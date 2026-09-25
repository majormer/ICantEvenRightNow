-- I Can't Even Right Now (With My Bags and Bank) — Warband Routing
-- Sends each item to the Warband tab whose own Blizzard "assign to" settings
-- (depositFlags) match it, so routing follows choices the player already made
-- in the game's bank tab settings. Never calls C_Bank.AutoDepositItemsIntoBank:
-- that bypasses item rules and the review step.

local ADDON_NAME, ns = ...

local Data = ns.Data
local P    = ns.Private

-- Enum.BagSlotFlags (verified 2026-09-25, warcraft.wiki.gg).
local FLAG = {
    Equipment      = 0x2,
    Consumables    = 0x4,
    ProfessionGoods = 0x8,
    Junk           = 0x10,
    QuestItems     = 0x20,
    Reagents       = 0x80,
    ExpansionCurrent = 0x100,
    ExpansionLegacy  = 0x200,
}
P.BAG_SLOT_FLAG = FLAG

local CATEGORY_FLAGS = { FLAG.Equipment, FLAG.Consumables, FLAG.ProfessionGoods, FLAG.Junk, FLAG.QuestItems, FLAG.Reagents }
local CATEGORY_LABEL = {
    [FLAG.Equipment] = "Equipment", [FLAG.Consumables] = "Consumables",
    [FLAG.ProfessionGoods] = "Profession Goods", [FLAG.Junk] = "Junk",
    [FLAG.QuestItems] = "Quest Items", [FLAG.Reagents] = "Reagents",
}

local function HasFlag(flags, flag)
    return bit.band(flags or 0, flag) ~= 0
end

-- The Blizzard category an item falls into (one flag), or nil.
local function ItemCategoryFlag(item)
    if item.quality == 0 then return FLAG.Junk end
    if item.classID == 12 or item.isQuestItem then return FLAG.QuestItems end
    if item.classID == 2 or item.classID == 4 then return FLAG.Equipment end
    if item.classID == 0 then return FLAG.Consumables end
    if item.classID == 7 then return FLAG.Reagents end
    -- Recipes (9) and profession tools/equipment (19).
    if item.classID == 9 or item.classID == 19 then return FLAG.ProfessionGoods end
    return nil
end
P.ItemCategoryFlag = ItemCategoryFlag

local function TabCategoryFlags(tab)
    local list = {}
    for _, flag in ipairs(CATEGORY_FLAGS) do
        if HasFlag(tab.flags, flag) then table.insert(list, flag) end
    end
    return list
end

-- Score a tab for an item: nil if the tab's settings exclude it.
-- 3 = category and expansion both match, 2 = category matches,
-- 1 = general tab (no category settings) that allows the item's expansion.
local function ScoreTab(tab, item)
    local wantsCurrent = HasFlag(tab.flags, FLAG.ExpansionCurrent)
    local wantsLegacy = HasFlag(tab.flags, FLAG.ExpansionLegacy)
    local expansionMatch = nil
    if wantsCurrent or wantsLegacy then
        local isOld = P.IsOldExpansion(item.expansionID)
        local ok = (isOld and wantsLegacy) or ((not isOld) and wantsCurrent)
        if not ok then return nil end
        expansionMatch = true
    end
    local categories = TabCategoryFlags(tab)
    if #categories == 0 then
        return expansionMatch and 1.5 or 1, nil
    end
    local itemFlag = ItemCategoryFlag(item)
    for _, flag in ipairs(categories) do
        if flag == itemFlag then
            return expansionMatch and 3 or 2, CATEGORY_LABEL[flag]
        end
    end
    return nil
end

-- Returns { bagID, tab, reason } for the best Warband tab, or nil with a reason.
local function RouteToWarbandTab(item)
    local tabs = P.GetWarbandTabs()
    if #tabs == 0 then return nil, "No Warband tabs are known yet: visit a bank" end
    local best, bestScore, bestLabel
    for _, tab in ipairs(tabs) do
        local score, label = ScoreTab(tab, item)
        if score and (not bestScore or score > bestScore) then
            best, bestScore, bestLabel = tab, score, label
        end
    end
    if not best then return nil, "No Warband tab accepts this item (check the tabs' settings)" end
    local tabName = best.name ~= "" and best.name or ("Tab " .. tostring(best.bagID - 11))
    local reason
    if bestLabel then
        reason = tabName .. " (accepts " .. bestLabel .. ")"
    else
        reason = tabName .. " (general tab)"
    end
    return { bagID = best.bagID, tab = best, reason = reason }
end
P.RouteToWarbandTab = RouteToWarbandTab

-- True when no known Warband tab has any "assign to" settings.
function P.WarbandTabsHaveNoSettings()
    local tabs = P.GetWarbandTabs()
    if #tabs == 0 then return false end
    for _, tab in ipairs(tabs) do
        if #TabCategoryFlags(tab) > 0 or HasFlag(tab.flags, FLAG.ExpansionCurrent)
            or HasFlag(tab.flags, FLAG.ExpansionLegacy) then
            return false
        end
    end
    return true
end
