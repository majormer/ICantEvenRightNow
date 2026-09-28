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
    T.ok(notice and notice:IsShown(), "the notice says it's getting ready right away")
    T.contains(notice.text:GetText(), "Getting ready... checking 1 item")
    T.no(notice.text:GetText():find("ready %("), "no count while getting ready")
    g.world:advance(4)
    T.ok(notice:IsShown(), "notice after settling")
    T.notContains(notice.text:GetText(), "Getting ready")
    T.contains(notice.text:GetText(), "1 ready")
end)

T.test("getting ready: closing the notice while waiting keeps it closed", function()
    local g = lateAxeGame(2, false)
    local notice = g:UI().contextNoticeFrame
    g:click(notice.close)
    g.world:advance(4)
    T.no(notice:IsShown(), "stays closed after settling")
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

T.test("bound items: the tooltip's binding line wins over a flickering bank check", function()
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        -- The bank check says "not allowed" (in game it flickered), the tooltip says Warbound.
        w:defineItem(8901, { name = "Loot Gadget", classID = 0, quality = 3, sellPrice = 100, expansionID = 10,
            bindType = 1, accountBankAllowed = false })
        w:put(0, 1, 8901, 1, { bound = true, tooltipBinding = "Warbound" })
        -- And the other way: the bank check says "allowed", the tooltip says Soulbound.
        w:defineItem(8902, { name = "Sigil", classID = 7, quality = 3, sellPrice = 100, expansionID = 10,
            bindType = 1, accountBankAllowed = true })
        w:put(0, 2, 8902, 1, { bound = true, tooltipBinding = "Soulbound" })
    end })
    g:Core().ScanInventory("bags", true)
    local byID = {}
    for _, it in ipairs(g:P().GetScanList("bags")) do byID[it.itemID] = it end
    T.eq(byID[8901].bindingScope, "Warbound")
    T.ok(byID[8901].accountBankAllowed, "can go to the Warband bank")
    T.eq(byID[8902].bindingScope, "Soulbound")
    T.ok(not byID[8902].accountBankAllowed)
end)

T.test("bound items: a tooltip that's still loading reuses the known binding, or waits", function()
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:defineItem(8901, { name = "Loot Gadget", classID = 0, quality = 3, sellPrice = 100, expansionID = 10,
            bindType = 1, accountBankAllowed = false })
        w:put(0, 1, 8901, 1, { bound = true, tooltipBinding = "Warbound" })
        w:defineItem(8903, { name = "Unseen Gadget", classID = 0, quality = 3, sellPrice = 100, expansionID = 10,
            bindType = 1, accountBankAllowed = false })
        w:put(0, 2, 8903, 1, { bound = true, tooltipBinding = "Warbound", tooltipLoading = true })
    end })
    local function scanned()
        g:Core().ScanInventory("bags", true)
        local byID = {}
        for _, it in ipairs(g:P().GetScanList("bags")) do byID[it.itemID] = it end
        return byID
    end
    local byID = scanned()
    T.eq(byID[8901].bindingScope, "Warbound")
    T.ok(byID[8903].bindingPending, "binding not known yet: pending, not guessed")
    T.ok((g:P().ItemDataPending(byID[8903])), "getting ready waits for it")
    -- The client drops the first item's data: the known binding is reused.
    g.world.containers[0].slots[1].tooltipLoading = true
    g.world.containers[0].slots[2].tooltipLoading = false
    byID = scanned()
    T.eq(byID[8901].bindingScope, "Warbound", "reused while the tooltip loads")
    T.eq(byID[8903].bindingScope, "Warbound")
    T.ok(not byID[8903].bindingPending)
end)

T.test("Warband space counts slots that moves are still landing in", function()
    local g = T.game({ player = P_MAIN, asyncMoves = true, moveLatency = 5, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:addBankTab(2, 12, "Tab 1", 0, 3)
        w:put(0, 1, I.LINEN, 20)
        w:put(0, 2, I.OLD_SWORD, 1)
    end })
    g:db().ui.tipsEnabled = false
    g:openBank()
    g:slash("transfer")
    local UI, P = g:UI(), g:P()
    UI.transferSource, UI.transferDest = "Bags", P.STORAGE_WARBAND_ROUTED
    P.ResetTabFilters("Transfer")
    g:Core().RefreshUI()
    for _, plan in ipairs(UI.transferVisible) do if plan.movable then UI.transferSelected[plan.key] = true end end
    g.world:withHardwareEvent(function() g:Core().ExecuteTransferSelected() end)
    g:Core().RefreshUI()
    local notice = UI.frame.panels.Transfer.contextNotice
    T.contains(notice:GetText(), "Tab 1 1 free (2 items still landing)")
    g:advance(8)
    T.contains(notice:GetText(), "Tab 1 1 free")
    T.notContains(notice:GetText(), "landing")
end)

T.test("a full Warband bank says so and offers to make room", function()
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:addBankTab(2, 12, "Tab 1", 0, 1)
        w:put(12, 1, I.JUNK, 1)          -- the only tab is full, of junk that can go
        w:put(0, 1, I.LINEN, 20)
    end })
    g:openBank()
    g:slash("transfer")
    local UI, P = g:UI(), g:P()
    UI.transferSource, UI.transferDest = "Bags", P.STORAGE_WARBAND_ROUTED
    P.ResetTabFilters("Transfer")
    P.SetFilterHideBlocked("Transfer", true)   -- "Actionable", as tasks open
    g:Core().RefreshUI()
    local panel = UI.frame.panels.Transfer
    T.contains(panel.empty:GetText(), "The Warband bank is full")
    T.contains(panel.empty:GetText(), "1 of 5 bought")
    T.eq(panel.emptyAction:GetText(), "Pull Warband Items That Can Go")
    -- The Home card says so too, instead of "Nothing to do right now".
    local card
    for _, c in ipairs(P.GetTaskCards()) do if c.name == "Deposit to Warband" then card = c end end
    if card and (card.blocked or 0) > 0 then T.contains(P.CardSummary(card), "blocked: Warband bank full") end
end)

T.test("a full Warband bank offers no pull when nothing in it can go, and names the auction character's waiting items", function()
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:addBankTab(2, 12, "Tab 1", 0, 1)
        w:put(12, 1, I.OLD_SWORD, 1)     -- full of an item that stays
        w:put(0, 1, I.LINEN, 20)
    end })
    g:openBank()
    local UI, P = g:UI(), g:P()
    local alt = { key = "Kiosk-Feathermoon", name = "Kiosk" }
    P.AuctionCharacter = function() return alt end
    P.GetHandoffs = function(match)
        local all = { { to = alt.key, state = "deposited" }, { to = alt.key, state = "deposited" }, { to = "Other-Realm", state = "deposited" } }
        local out = {}
        for _, e in ipairs(all) do if match(e) then out[#out + 1] = e end end
        return out
    end
    g:slash("transfer")
    UI.transferSource, UI.transferDest = "Bags", P.STORAGE_WARBAND_ROUTED
    P.ResetTabFilters("Transfer")
    P.SetFilterHideBlocked("Transfer", true)
    g:Core().RefreshUI()
    local panel = UI.frame.panels.Transfer
    local text = panel.empty:GetText()
    T.contains(text, "The Warband bank is full")
    T.notContains(text, "pull out items")
    T.contains(text, "have Kiosk collect the 2 items waiting to be auctioned")
    T.contains(text, "1 of 5 bought")
    T.ok(panel.emptyAction:GetText() ~= "Pull Warband Items That Can Go" or not panel.emptyAction:IsShown())
    -- The Home card gives the same advice, not "pull items that can go".
    for _, c in ipairs(P.GetTaskCards()) do
        local summary = P.CardSummary(c)
        T.notContains(summary, "pull items that can go")
        T.notContains(summary, "pull out items that can go")
        if summary:find("Warband bank has", 1, true) then
            T.contains(summary, "have Kiosk collect the 2 items waiting to be auctioned first")
        end
    end
end)

T.test("Warbound-until-equipped is remembered while a tooltip is loading (saved across reloads)", function()
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:addBankTab(2, 12, "Tab 1", 0, 5)
        w:put(12, 1, I.OLD_SWORD, 1, { warboundUntilEquipped = true })
    end })
    g:openBank()
    local function sword()
        g:Core().ScanInventory("all", true)
        for _, it in ipairs(g:P().GetWarbandSnapshot().items) do if it.itemID == I.OLD_SWORD then return it end end
    end
    T.eq(sword().bindingScope, "Warbound Until Equipped")
    T.eq(g:db().knownBinding[I.OLD_SWORD], "wue", "saved")
    g.world.containers[12].slots[1].tooltipLoading = true    -- the client dropped the item
    local item = sword()
    T.eq(item.bindingScope, "Warbound Until Equipped", "not 'BoE' while the tooltip loads")
    T.ok(not item.bindingPending)
end)

-- In game (2026-09-28), Minormer's Home said "Nothing to do" for upgrades
-- while the Warband bank held 14 pieces his main had parked for him.
T.test("Pull Bank Upgrades reads the Warband bank when that is where the upgrades are", function()
    local function upgradeGame(bankCount, warbandCount)
        return T.game({ player = P_MAIN, setup = function(w)
            F.defineItems(w)
            w:defineItem(8902, { name = "Parked Blade", classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON",
                itemLevel = 260, requiredLevel = 80, bindType = 7, sellPrice = 100, expansionID = 10 })
            w:addBankTab(0, 6, "Main", 0, 20)
            w:addBankTab(2, 12, "Tab 1", 0, 5)
            for i = 1, bankCount do w:put(6, i, 8902, 1) end
            for i = 1, warbandCount do w:put(12, i, 8902, 1) end
            w.equipped[16] = 200
        end })
    end
    local function card(g)
        for _, c in ipairs(g:P().GetTaskCards()) do if c.name == "Pull Bank Upgrades" then return c end end
    end
    local g = upgradeGame(0, 2)
    g:openBank()
    local c = card(g)
    T.ok(c, "task exists")
    T.eq(c.ready, 2, "counts the Warband bank's upgrades")
    T.eq(c.task.preset.source, g:P().STORAGE_WARBAND_BANK)
    -- The live slot levels read 0 for a while after a reload (in game a
    -- level 1 ring "beat" a 250 one and the list shrank while scrolling):
    -- the recorded levels decide. Worn 300 at login, live 0 now: no upgrade.
    g = upgradeGame(0, 2)
    g.world.equipped[16] = 300
    g:P().RefreshEquipped()
    g.world.equipped[16] = nil
    g:openBank()
    T.eq(card(g).ready, 0, "recorded levels, not live ones")
    -- The character bank wins when it holds more.
    g = upgradeGame(3, 1)
    g:openBank()
    c = card(g)
    T.eq(c.ready, 3)
    T.eq(c.task.preset.source, g:P().STORAGE_ALL_BANK_TABS)
    -- Away from a bank (after one visit) the card still says what's waiting.
    g = upgradeGame(0, 2)
    g:openBank()
    g:closeBank()
    c = card(g)
    T.eq(c.waiting, 2)
    T.eq(c.needs, "Visit a bank")
end)

-- In game (2026-09-28), Deposit to Warband offered Minormer's 16 freshly
-- withdrawn upgrades straight back ("Upgrade for Minormer" on his own screen).
T.test("Deposit to Warband never offers gear this character should equip", function()
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:defineItem(8902, { name = "Parked Blade", classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON",
            itemLevel = 260, requiredLevel = 80, bindType = 7, sellPrice = 100, expansionID = 10 })
        w:addBankTab(0, 6, "Main", 0, 20)
        w:addBankTab(2, 12, "Tab 1", 0, 5)
        w:put(0, 1, 8902, 1)
        w.equipped[16] = 200
    end })
    g:P().SetCharacterRole("Main-R", "main")
    g:openBank()
    local P = g:P()
    local blade
    for _, item in ipairs(P.GetScanList(P.BAG_SCOPE)) do if item.itemID == 8902 then blade = item end end
    T.ok(blade, "scanned")
    T.ok(P.IsUpgradeForPlayer(blade), "it beats the equipped weapon")
    T.contains(P.WhoBenefits(blade) or "", "Upgrade for you: equip it")
    local card
    for _, c in ipairs(P.GetTaskCards()) do if c.name == "Deposit to Warband" then card = c end end
    T.ok(card, "task exists")
    T.eq(card.ready, 0, "not offered back to the Warband bank")
    -- Once it is worn (the equipment event re-reads the levels), the same
    -- piece in the bags is no upgrade any more.
    g.world.equipped[16] = 260
    P.RefreshEquipped()
    T.no(P.IsUpgradeForPlayer(blade))
end)

-- In game (2026-09-28), Pull Auctionable BoEs offered 7 used (soulbound)
-- Hexweave Bags whose own row said "it can't be auctioned".
T.test("Pull Auctionable BoEs skips BoE items that have since been bound", function()
    local function boeGame(bound)
        return T.game({ player = P_MAIN, setup = function(w)
            F.defineItems(w)
            w:addBankTab(0, 6, "Main", 0, 20)
            w:put(6, 1, I.OLD_SWORD, 1, { bound = bound })
        end })
    end
    -- The sword can go (the player decided to auction it); only then is
    -- it offered (2026-09-28: "your call" BoEs are not pulled).
    local function card(g)
        for _, c in ipairs(g:P().GetTaskCards()) do if c.name == "Pull Auctionable BoEs" then return c end end
    end
    local g = boeGame(false)
    g:P().SetDecision(I.OLD_SWORD, "sell")
    g:openBank()
    T.eq(card(g).ready, 1, "an unbound BoE that can go is auctionable")
    g:P().ClearDecision(I.OLD_SWORD)
    g:Core().ScanInventory("all", true)
    T.eq(card(g).ready, 0, "an undecided one is not pulled")
    g = boeGame(true)
    g:P().SetDecision(I.OLD_SWORD, "sell")
    g:openBank()
    T.eq(card(g).ready, 0, "a bound one is not")
end)

-- In game (2026-09-28), Deposit to Warband offered a Main's 25 Potent Healing
-- Potions: a played character keeps its current-expansion supplies.
T.test("Deposit to Warband leaves a played character's current supplies in the bags", function()
    local function potionGame(role)
        local g = T.game({ player = P_MAIN, setup = function(w)
            F.defineItems(w)
            w:addBankTab(0, 6, "Main", 0, 20)
            w:addBankTab(2, 12, "Tab 1", 0, 5)
            w:defineItem(9001, { name = "Potent Healing Potion", classID = 0, subclassID = 1, quality = 2,
                maxStack = 200, sellPrice = 14, expansionID = 11, bindType = 8 })   -- Warbound
            w:put(0, 1, 9001, 25)
        end })
        g:P().SetCharacterRole("Main-R", role)
        g:openBank()
        for _, c in ipairs(g:P().GetTaskCards()) do if c.name == "Deposit to Warband" then return c end end
    end
    T.eq(potionGame("main").ready, 0, "a Main keeps its flasks")
    T.eq(potionGame("leveling").ready, 0, "so does a Leveling alt")
    T.eq(potionGame("crafter").ready, 1, "a crafting-only alt hands them over")
end)

-- In game (2026-09-28) Kiosk's housing dyes, kept "in Warband" by the player,
-- were never offered by Deposit to Warband: unbound, not gear, not a material.
T.test("Deposit to Warband takes housing items, and anything a Utility character keeps", function()
    local function depositCard(role, itemDef)
        local g = T.game({ player = P_MAIN, setup = function(w)
            F.defineItems(w)
            w:defineItem(9101, itemDef)
            w:addBankTab(0, 6, "Main", 0, 20)
            w:addBankTab(2, 12, "Tab 1", 0, 5)
            w:put(0, 1, 9101, 6)
        end })
        g:P().SetCharacterRole("Main-R", role)
        g:P().SetDecision(9101, "keep")
        g:openBank()
        for _, c in ipairs(g:P().GetTaskCards()) do if c.name == "Deposit to Warband" then return c end end
    end
    local dye = { name = "Blue Housing Dye", classID = 20, subclassID = 1, quality = 2, maxStack = 200,
        sellPrice = 1, expansionID = 11 }
    local trinket = { name = "Shiny Pebble", classID = 15, subclassID = 4, quality = 1, maxStack = 20,
        sellPrice = 5, expansionID = 11 }
    T.eq(depositCard("main", dye).ready, 1, "housing dye goes to the Warband bank")
    T.eq(depositCard("utility", trinket).ready, 1, "a Utility character hands over what it keeps")
    T.eq(depositCard("main", trinket).ready, 0, "a Main keeps its own unbound keeps")
end)

-- In game (Dorftastic, 2026-09-28) Deposit Old Items and Deposit to Warband
-- offered the same crafting materials: one to the character bank, one to
-- the Warband bank.
T.test("Deposit Old Items leaves what Deposit to Warband takes", function()
    local saved
    for _, spec in ipairs({ { player = P_MAIN, role = "main" },
        { player = { name = "Tailor", realm = "R", level = 70, classFile = "MAGE",
            professions = { { name = "Tailoring", skillLine = 197 } } }, role = "crafter" } }) do
        local g = T.game({ savedVariables = saved, player = spec.player, setup = function(w) F.defineItems(w) end })
        g:P().SetCharacterRole(spec.player.name .. "-R", spec.role)
        saved = g:logout()
    end
    local g = T.game({ savedVariables = saved, player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:addBankTab(2, 12, "Tab 1", 0, 5)
        w:put(0, 1, I.LINEN, 20)          -- old cloth the Tailor uses
        w:put(0, 2, I.OLD_POTION, 5)      -- old consumable nobody else needs
    end })
    g:openBank()
    local P = g:P()
    local function ids(name)
        local set = {}
        for _, plan in ipairs(P.GetTaskPlans(P.FindTask(name))) do set[plan.item.itemID] = true end
        return set
    end
    T.ok(ids("Deposit to Warband")[I.LINEN], "linen goes to the Warband bank")
    T.no(ids("Deposit Old Items")[I.LINEN], "not also to the character bank")
end)

-- In game (Gnomurcy, 2026-09-28) Deposit Old Items banked two upgrades that
-- Pull Bank Upgrades then offered straight back.
T.test("Deposit Old Items never banks gear this character should equip", function()
    local g = T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:defineItem(9801, { name = "Old Upgrade Blade", classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON",
            itemLevel = 260, requiredLevel = 60, bindType = 1, sellPrice = 100, expansionID = 3 })
        w:addBankTab(0, 6, "Main", 0, 20)
        w:put(0, 1, 9801, 1, { bound = true })
        w.equipped[16] = 200
    end })
    g:P().SetCharacterRole("Main-R", "main")
    g:P().RefreshEquipped()
    g:openBank()
    local ids = {}
    for _, plan in ipairs(g:P().GetTaskPlans(g:P().FindTask("Deposit Old Items"))) do ids[plan.item.itemID] = true end
    T.no(ids[9801], "an upgrade stays in the bags")
end)

-- In game (Glowheart, a Paladin, 2026-09-28) Pull Bank Upgrades pulled a staff.
T.test("an upgrade must be a weapon the class can wield", function()
    local PALADIN = { name = "Main", realm = "R", level = 80, classFile = "PALADIN" }
    local g = T.game({ player = PALADIN, setup = function(w)
        F.defineItems(w)
        w:defineItem(9901, { name = "Big Staff", classID = 2, subclassID = 10, equipLoc = "INVTYPE_2HWEAPON",
            itemLevel = 260, requiredLevel = 60, bindType = 2, sellPrice = 100, expansionID = 3 })
        w:addBankTab(0, 6, "Main", 0, 20)
        w:put(6, 1, 9901, 1)
        w.equipped[16] = 200
    end })
    local P = g:P()
    P.SetCharacterRole("Main-R", "leveling")
    P.RefreshEquipped()
    g:openBank()
    for _, c in ipairs(P.GetTaskCards()) do
        if c.name == "Pull Bank Upgrades" then T.eq(c.ready, 0, "a paladin can't use staves") end
    end
end)
