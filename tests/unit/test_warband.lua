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

local P_MAIN = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" }

local function depositAll(g)
    g:slash("transfer")
    local UI, P = g:UI(), g:P()
    UI.transferSource, UI.transferDest = "Bags", P.STORAGE_WARBAND_ROUTED
    P.ResetTabFilters("Transfer")
    g:Core().RefreshUI()
    for _, plan in ipairs(UI.transferVisible) do if plan.movable then UI.transferSelected[plan.key] = true end end
    g.world:withHardwareEvent(function() g:Core().ExecuteTransferSelected() end)
    g:advance(2)
end

T.test("several general Warband tabs fill one after another", function()
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:addBankTab(2, 12, "Tab 1", 0, 1)
        w:addBankTab(2, 13, "Tab 2", 0, 1)
        w:put(0, 1, I.LINEN, 20)
        w:put(0, 2, I.OLD_SWORD, 1)
    end })
    g:openBank()
    depositAll(g)
    local inTab2 = 0
    for _ in pairs(g.world.containers[13].slots) do inTab2 = inTab2 + 1 end
    T.eq(inTab2, 1, "the second general tab took what the first couldn't")
end)

T.test("a full assigned tab asks before using a general tab", function()
    local REAGENTS = 0x80
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:addBankTab(2, 12, "Mats", REAGENTS, 1)
        w:addBankTab(2, 13, "General", 0, 5)
        w:put(12, 1, I.OLD_SWORD, 1)     -- Mats tab full
        w:put(0, 1, I.LINEN, 20)
    end })
    g:openBank()
    g:slash("transfer")
    local UI, P = g:UI(), g:P()
    UI.transferSource, UI.transferDest = "Bags", P.STORAGE_WARBAND_ROUTED
    P.ResetTabFilters("Transfer")
    g:Core().RefreshUI()
    local panel = UI.frame.panels.Transfer
    local linen
    for _, plan in ipairs(P.GetTransferCandidates("Bags", P.STORAGE_WARBAND_ROUTED)) do
        if plan.item.itemID == I.LINEN then linen = plan end
    end
    T.contains(linen.blocked, "Assigned tab full")
    T.ok(panel.warbandFallback:IsShown(), "offers general tabs")
    g:click(panel.warbandFallback)
    T.ok(not panel.warbandFallback:IsShown())
    depositAll(g)
    T.eq(g.world:findItem(I.LINEN)[1].bagID, 13, "went to the general tab after the player agreed")
end)

T.test("no Warband tab bought: no Warband options, cards explain, picker explains", function()
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:put(0, 1, I.LINEN, 20)
    end })
    g:openBank()
    local P = g:P()
    T.eq(P.WarbandTabsPurchased(), 0)
    for _, o in ipairs(P.GetTransferDestOptions()) do
        T.ok(not P.IsWarbandStorage(o.value), "no Warband destination: " .. tostring(o.value))
    end
    local card
    for _, c in ipairs(P.GetTaskCards()) do if c.name == "Deposit to Warband" then card = c end end
    T.contains(P.CardSummary(card), "No Warband bank tab yet")
    P.ShowHandoffPicker(P.GetScanList("bags")[1])
    T.contains(g:UI().handoffPicker.title:GetText(), "Buy its first tab")
end)

T.test("Pull Warband Items That Can Go reads the Warband bank", function()
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:addBankTab(2, 12, "Tab 1", 0, 5)
        w:put(12, 1, I.JUNK, 3)
    end })
    g:openBank()
    local card
    for _, c in ipairs(g:P().GetTaskCards()) do if c.name == "Pull Warband Items That Can Go" then card = c end end
    T.ok(card, "task exists")
    T.eq(card.ready, 1)
end)

T.test("undo pre-selects the last batch's items for the reverse route", function()
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:addBankTab(2, 12, "Tab 1", 0, 5)
        w:put(12, 1, I.JUNK, 3)
        w:put(12, 2, I.LINEN, 20)
    end })
    g:openBank()
    g:slash("transfer")
    local UI, P = g:UI(), g:P()
    UI.transferSource, UI.transferDest = P.STORAGE_WARBAND_BANK, "Bags"
    P.ResetTabFilters("Transfer")
    g:Core().RefreshUI()
    for _, plan in ipairs(UI.transferVisible) do UI.transferSelected[plan.key] = true end
    g.world:withHardwareEvent(function() g:Core().ExecuteTransferSelected() end)
    g:advance(8)
    T.eq(#g.world:findItem(I.JUNK), 1)
    T.ok(g.world:findItem(I.JUNK)[1].bagID < 6, "in bags now")
    g:slash("undo")
    T.contains(g:printed(), "Undo: 2 of 2 stack(s) selected to move back to Warband Bank")
    g.world:withHardwareEvent(function() g:Core().ExecuteTransferSelected() end)
    g:advance(8)
    T.eq(g.world:findItem(I.JUNK)[1].bagID, 12, "back in the Warband bank")
end)

local function lateAxeGame(statsDelay, openHome)
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:addBankTab(2, 12, "Tab 1", 0, 5)
        -- Agility axe, Warbound until equipped: a Strength warrior can't use it.
        w:defineItem(8601, { name = "Late Axe", classID = 2, subclassID = 0, equipLoc = "INVTYPE_WEAPON",
            itemLevel = 220, requiredLevel = 90, bindType = 2, quality = 3, sellPrice = 100, expansionID = 11,
            stats = { ITEM_MOD_AGILITY_SHORT = 10 }, statsAt = 1790000000 + statsDelay })
        w:put(12, 1, 8601, 1, { warboundUntilEquipped = true })
    end })
    g:P().SetCharacterRole("Main-R", "main")
    g:P().SetLogging(true)
    g:openBank()
    if openHome ~= false then g:Core().ShowHomeUI() end
    return g
end

local function pullCard(g)
    for _, widget in ipairs(g:UI().frame.panels.Home.cards) do
        if widget:IsShown() and widget.card and widget.card.name == "Pull Warband Items That Can Go" then
            return widget.card
        end
    end
end

T.test("getting ready: no counts until the data is in, then one stable result", function()
    local g = lateAxeGame(2)
    local header = g:UI().frame.panels.Home.scanInfo
    T.contains(header:GetText(), "Getting ready... checking 1 item")
    local card = pullCard(g)
    T.eq(card and g:P().CardSummary(card) or "Getting ready...", "Getting ready...", "no count while getting ready")
    g.world:advance(4)           -- stats arrive; the addon settles
    T.notContains(header:GetText(), "Getting ready")
    T.eq(pullCard(g).ready, 1, "complete result")
end)

T.test("getting ready: the bank notice waits until the data is in", function()
    local g = lateAxeGame(2, false)
    local notice = g:UI().contextNoticeFrame
    T.ok(not notice or not notice:IsShown(), "no notice while getting ready")
    g.world:advance(4)
    notice = g:UI().contextNoticeFrame
    T.ok(notice and notice:IsShown(), "notice after settling")
    T.notContains(notice.text:GetText(), "Getting ready")
end)

T.test("data arriving after settling doesn't change the screen until Rescan", function()
    local g = lateAxeGame(15)       -- longer than the 10 s limit
    g.world:advance(11)             -- settled without the axe's stats
    local header = g:UI().frame.panels.Home.scanInfo
    T.contains(header:GetText(), "couldn't be checked")
    local before = pullCard(g) and pullCard(g).ready or 0
    g.world:advance(6)              -- stats arrive late
    g:Core().RefreshUI()            -- e.g. any unrelated refresh
    local p = g:P()
    for _, it in ipairs(p.GetWarbandSnapshot().items) do if it.itemID == 8601 then p.GearDetailsPending(it) end end
    g:Core().RefreshUI()
    T.contains(header:GetText(), "Rescan to include them", "late data is flagged, not applied silently")
    g:click(g:UI().frame.panels.Home.rescan)
    T.notContains(header:GetText(), "Rescan to include")
end)

T.test("an item described after settling is flagged, not redrawn", function()
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:defineItem(8602, { name = "Slow Rock", classID = 15, subclassID = 0, quality = 0, sellPrice = 5,
            expansionID = 0, cached = false, loadDelay = 12 })
        w:put(0, 1, 8602, 1)
    end })
    g:P().SetCharacterRole("Main-R", "main")
    g:openBank()
    g:Core().ShowHomeUI()
    local header = g:UI().frame.panels.Home.scanInfo
    g.world:advance(9)              -- settled without the rock
    T.notContains(header:GetText(), "Getting ready")
    local shownBefore = header:GetText()
    g.world:advance(5)              -- the rock's data arrives
    T.contains(header:GetText(), "Rescan to include them", "flagged")
    T.ok(shownBefore ~= header:GetText(), "only the flag changed")
end)

T.test("Warbound-until-equipped items in the Warband bank are read from the tooltip", function()
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:addBankTab(2, 12, "Tab 1", 0, 5)
        w:put(12, 1, I.OLD_SWORD, 1, { warboundUntilEquipped = true })
    end })
    g:openBank()
    local item
    for _, it in ipairs(g:P().GetWarbandSnapshot().items) do if it.itemID == I.OLD_SWORD then item = it end end
    T.eq(item.bindingScope, "Warbound Until Equipped")
    T.ok(not g:P().CanBeAuctioned(item), "can't be auctioned")
end)

T.test("bag items the game misreports as BoE are read from the tooltip", function()
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:put(0, 1, I.OLD_SWORD, 1, { warboundUntilEquipped = true, apiHidesWue = true })
    end })
    g:Core().ScanInventory("bags", true)
    local item = g:P().GetScanList("bags")[1]
    T.eq(item.bindingScope, "Warbound Until Equipped")
end)

T.test("task lists log what is left out and what joins later", function()
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:put(0, 1, I.JUNK, 1)
    end })
    g:P().SetLogging(true)
    g:openVendor()
    g:Core().ShowHomeUI()
    g:P().OpenTask("Sell Items That Can Go")
    T.contains(table.concat(g:P().GetLogLines(), " | "), "Sell Items That Can Go: 1 of 1 in the list")
    g.world:put(0, 2, I.JUNK, 1)
    g:Core().ScanInventory("bags", true)
    g:Core().RefreshUI()
    T.contains(table.concat(g:P().GetLogLines(), " | "), "JOINED Broken Tusk")
end)
