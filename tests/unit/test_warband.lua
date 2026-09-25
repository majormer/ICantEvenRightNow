local T = ...
local F = require("fixtures")
local I = F.ITEMS
local FLAG = { Equipment = 0x2, Consumables = 0x4, Reagents = 0x80, Current = 0x100, Legacy = 0x200 }

-- Three Warband tabs: Gear (equipment), Mats (reagents, legacy only), General (no settings).
local function setupTabs(w)
    F.defineItems(w)
    w:addBankTab(0, 6, "Main", 0, 20)
    w:addBankTab(2, 12, "Gear", FLAG.Equipment, 10)
    w:addBankTab(2, 13, "Mats", FLAG.Reagents + FLAG.Legacy, 10)
    w:addBankTab(2, 14, "General", 0, 10)
    w:defineItem(8001, { name = "Midnight Silk", classID = 7, subclassID = 5, maxStack = 200, expansionID = 11, sellPrice = 50 })
end

local function game(populate)
    return T.game({ setup = function(w) setupTabs(w); if populate then populate(w) end end })
end

T.test("Warband tabs are read at a banker and cached for later", function()
    local g = game()
    g:openBank()
    local tabs = g:db().warband.tabs
    T.eq(#tabs, 3)
    T.eq(tabs[2].name, "Mats")
    g:closeBank()
    T.eq(#g:P().GetWarbandTabs(), 3, "cached names available with the bank closed")
    T.eq(g:P().GetStorageDisplayName("WarbandTab:13"), "Warband: Mats")
end)

T.test("each Warband tab is a source and destination; routed option offered", function()
    local g = game()
    g:openBank()
    local P = g:P()
    local values = {}
    for _, opt in ipairs(P.GetTransferDestOptions()) do values[opt.value] = opt.text end
    T.eq(values["WarbandTab:12"], "Warband: Gear")
    T.eq(values["WarbandTab:14"], "Warband: General")
    T.ok(values[P.STORAGE_WARBAND_ROUTED], "routed destination offered")
end)

T.test("routing follows each tab's own settings", function()
    local g = game()
    g:openBank()
    local P = g:P()
    local function routeOf(def)
        local route = P.RouteToWarbandTab(def)
        return route and route.tab.name
    end
    T.eq(routeOf({ classID = 7, subclassID = 5, expansionID = 0, quality = 1 }), "Mats", "old cloth to Mats")
    T.eq(routeOf({ classID = 7, subclassID = 5, expansionID = 11, quality = 1 }), "General", "current cloth skips legacy-only Mats")
    T.eq(routeOf({ classID = 2, equipLoc = "INVTYPE_WEAPON", expansionID = 3, quality = 3 }), "Gear")
    T.eq(routeOf({ classID = 0, subclassID = 1, expansionID = 5, quality = 1 }), "General")
    local route = P.RouteToWarbandTab({ classID = 7, subclassID = 5, expansionID = 0, quality = 1 })
    T.contains(route.reason, "accepts Reagents")
end)

T.test("Deposit to Warband sends items to their matching tabs", function()
    local g = game(function(w)
        w:put(0, 1, I.LINEN, 40)
        w:put(0, 2, I.OLD_SWORD, 1)
        w:put(0, 3, I.OLD_POTION, 5)
        w:put(0, 4, I.BOUND_HELM, 1, { bound = true })
    end)
    g:openBank()
    local P, UI = g:P(), g:UI()
    local dest = P.STORAGE_WARBAND_ROUTED
    UI.transferSource, UI.transferDest = "Bags", dest
    local candidates = P.GetTransferCandidates("Bags", dest)
    UI.transferVisible, UI.transferSelected = candidates, {}
    local blocked = {}
    for _, plan in ipairs(candidates) do
        if plan.movable then UI.transferSelected[plan.key] = true else blocked[plan.item.itemID] = plan.blocked end
    end
    T.eq(blocked[I.BOUND_HELM], "Not eligible for Warband Bank", "soulbound helm stays")
    g.world:withHardwareEvent(function() g:Core().ExecuteTransferSelected() end)
    g:advance(2)
    T.eq(g.world:findItem(I.LINEN)[1].bagID, 13, "linen in Mats")
    T.eq(g.world:findItem(I.OLD_SWORD)[1].bagID, 12, "sword in Gear")
    T.eq(g.world:findItem(I.OLD_POTION)[1].bagID, 14, "potion in General")
    T.eq(g.world:findItem(I.BOUND_HELM)[1].bagID, 0, "helm untouched")
    T.no(g.world.autoDepositCalled, "never uses Blizzard's bulk deposit")
end)

T.test("a Warband tab source lists only that tab's items", function()
    local g = game(function(w)
        w:put(12, 1, I.OLD_SWORD, 1)
        w:put(13, 1, I.LINEN, 40)
    end)
    g:openBank()
    local candidates = g:P().GetTransferCandidates("WarbandTab:13", "Bags")
    T.eq(#candidates, 1)
    T.eq(candidates[1].item.itemID, I.LINEN)
end)

T.test("no tab accepts the item: blocked with a reason", function()
    local g = T.game({ setup = function(w)
        F.defineItems(w)
        w:addBankTab(2, 12, "Gear", FLAG.Equipment, 10)
        w:put(0, 1, I.LINEN, 5)
    end })
    g:openBank()
    local P = g:P()
    local plan = P.GetTransferCandidates("Bags", P.STORAGE_WARBAND_ROUTED)[1]
    T.no(plan.movable)
    T.contains(plan.blocked, "No Warband tab accepts")
end)

T.test("tabs without settings are detected (for the onboarding hint)", function()
    local g = T.game({ setup = function(w)
        F.defineItems(w)
        w:addBankTab(2, 12, "A", 0, 10)
    end })
    g:openBank()
    T.ok(g:P().WarbandTabsHaveNoSettings())
end)
