-- I Can't Even Right Now (With My Bags and Bank) — BetterBags categories
-- Optional (off until the player enables it). Categories are display only:
-- they change where items appear in BetterBags and never trigger actions.
--
-- Verified 2026-09-25 against BetterBags main (v0.5.11, Interface 120100):
--   LibStub("AceAddon-3.0"):GetAddon("BetterBags") -> :GetModule("Categories"/"Context")
--   Categories:RegisterCategoryFunction(id, fn(data) -> name|nil)   (duplicate id asserts)
--   Categories:WipeCategory(ctx, name); Categories:ReprocessAllItems(ctx)
-- Categories are assigned per item ID, not per slot, so only decisions that
-- hold for every copy of an item are published.

local ADDON_NAME, ns = ...

local Core = ns.Core
local P    = ns.Private

local FUNCTION_ID = "ICantEvenRightNow_categories"
local REFRESH_DELAY = 1.0

-- Highest priority first; the category function returns the first match.
local CATEGORIES = {
    { name = "Protected",       match = function(item, rule) return rule and rule.protect end },
    { name = "Never Sell",      match = function(item, rule) return rule and rule.neverSell end },
    { name = "Waiting for You", match = function(item) return P.HandoffWaitingForMe and P.HandoffWaitingForMe(item.itemID) ~= nil end },
    { name = "Sell Candidates", match = function(item) return P.CanGoAndSellable and P.CanGoAndSellable(item) end },
    { name = "For the Warband", match = function(item) return P.IsShareableItem and P.IsShareableItem(item) end },
    { name = "Old Content",     match = function(item, rule)
        return P.IsOldExpansion(item.expansionID) and not (rule and (rule.ignore or rule.keepReason))
    end },
}
P.BETTERBAGS_CATEGORIES = CATEGORIES

local state = { registered = false, pendingRefresh = false, needsRefreshAfterCombat = false }
P.BetterBagsState = state

local function GetBetterBags()
    if not LibStub then return nil end
    local ok, ace = pcall(LibStub, "AceAddon-3.0", true)
    if not ok or not ace or not ace.GetAddon then return nil end
    local okAddon, addon = pcall(ace.GetAddon, ace, "BetterBags", true)
    if not okAddon then return nil end
    return addon
end

function P.IsBetterBagsLoaded()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("BetterBags") or false
end

function P.BetterBagsEnabled()
    return ns.DB and ns.DB.ui and ns.DB.ui.betterBagsCategories == true
end

-- Build the addon's item shape from BetterBags' ItemData.
local function ItemFromData(data)
    local info = data and data.itemInfo
    if not info or not info.itemID then return nil end
    -- BetterBags has no binding scope; derive it from bindType like the scanner.
    local bindType = info.bindType
    local bound = info.isBound or (data.bindingInfo and data.bindingInfo.bound) or false
    local bindingScope, warbound = nil, false
    if bindType == 7 or bindType == 8 then
        bindingScope, warbound = "Warbound", true
    elseif bindType == 9 then
        bindingScope, warbound = "Warbound Until Equipped", true
    elseif bindType == 2 and not bound then
        bindingScope = "BoE"
    end
    return {
        bindingScope = bindingScope,
        isWarbandBound = warbound,
        itemID = info.itemID,
        link = info.itemLink,
        name = info.itemName,
        classID = info.classID,
        subclassID = info.subclassID,
        expansionID = info.expacID,
        quality = info.itemQuality,
        sellPrice = info.sellPrice,
        equipLoc = info.itemEquipLoc,
        itemLevel = info.currentItemLevel or info.itemLevel,
        bindType = info.bindType,
        isBound = info.isBound,
        count = 1,
        questID = data.questInfo and data.questInfo.questID or nil,
        isQuestItem = data.questInfo and data.questInfo.isQuestItem or false,
    }
end

-- The category for an item, or nil. Exposed for tests and diagnostics.
function P.CategoryForItem(item)
    if not item or not P.BetterBagsEnabled() then return nil end
    local rule = ns.DB.rules and ns.DB.rules.items and ns.DB.rules.items[item.itemID]
    for _, category in ipairs(CATEGORIES) do
        local ok, matched = pcall(category.match, item, rule)
        if ok and matched then return category.name end
    end
    return nil
end

local function Register()
    if state.registered or not P.BetterBagsEnabled() then return end
    local addon = GetBetterBags()
    if not addon then return end
    local ok, categories = pcall(addon.GetModule, addon, "Categories")
    if not ok or not categories or not categories.RegisterCategoryFunction then return end
    local registered = pcall(categories.RegisterCategoryFunction, categories, FUNCTION_ID, function(data)
        return P.CategoryForItem(ItemFromData(data))
    end)
    state.registered = registered and true or false
end

-- Clear our categories and ask BetterBags to re-evaluate. Deferred out of combat.
local function RefreshNow()
    state.pendingRefresh = false
    if InCombatLockdown and InCombatLockdown() then
        state.needsRefreshAfterCombat = true
        return
    end
    local addon = GetBetterBags()
    if not addon then return end
    local okCat, categories = pcall(addon.GetModule, addon, "Categories")
    local okCtx, contextModule = pcall(addon.GetModule, addon, "Context")
    if not okCat or not categories then return end
    local ctx = okCtx and contextModule and contextModule.New and contextModule:New("ICantEvenRightNow_Refresh") or nil
    for _, category in ipairs(CATEGORIES) do
        if categories.WipeCategory then pcall(categories.WipeCategory, categories, ctx, category.name) end
    end
    if categories.ReprocessAllItems then pcall(categories.ReprocessAllItems, categories, ctx) end
end

function P.RequestBetterBagsRefresh()
    if not state.registered and not P.BetterBagsEnabled() then return end
    if state.pendingRefresh then return end
    state.pendingRefresh = true
    C_Timer.After(REFRESH_DELAY, RefreshNow)
end

function P.OnCombatEnded()
    if state.needsRefreshAfterCombat then
        state.needsRefreshAfterCombat = false
        P.RequestBetterBagsRefresh()
    end
end

-- Called when BetterBags loads (before or after this addon).
function P.OnBetterBagsLoaded()
    Register()
end

function P.SetBetterBagsCategories(enabled)
    ns.DB.ui.betterBagsCategories = enabled and true or false
    ns.DB.ui.betterBagsDecided = true
    if enabled then Register() end
    P.RequestBetterBagsRefresh()
end

-- In-context opt-in (O4): ask once when BetterBags is present.
P.RegisterHomeNotice(function()
    if not P.IsBetterBagsLoaded() or ns.DB.ui.betterBagsDecided then return nil end
    return {
        id = "betterbags", priority = 72,
        text = "BetterBags detected. Show this addon's categories in your bags (Protected, Sell Candidates, "
            .. "For the Warband, Old Content...)? Display only; you can change it in Settings.",
        buttons = {
            { label = "Show categories", style = "primary", onClick = function()
                P.SetBetterBagsCategories(true)
                Core.RefreshUI()
            end },
            { label = "No thanks", onClick = function()
                P.SetBetterBagsCategories(false)
                Core.RefreshUI()
            end },
        },
    }
end)

-- Changes that can move items between categories.
Core.OnRulesChanged = function() P.RequestBetterBagsRefresh() end
Core.OnRosterChanged = function() P.RequestBetterBagsRefresh() end
