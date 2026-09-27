local T = ...
local F = require("fixtures")
local I = F.ITEMS

local PLAYER = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" }

local function sellAll(g)
    local P, UI = g:P(), g:UI()
    P.OpenTask("Sell Items That Can Go")
    for _, plan in ipairs(UI.transferVisible) do
        if plan.movable then UI.transferSelected[plan.key] = true end
    end
    g.world:withHardwareEvent(function() g:Core().ExecuteTransferSelected() end)
end

T.test("sold items don't reappear as ready while the server settles", function()
    local g = T.game({ player = PLAYER, asyncMoves = true, setup = F.setup(function(w)
        for slot = 1, 4 do w:put(0, slot, I.JUNK, 1) end
    end) })
    g:openVendor()
    g:Core().ShowHomeUI()
    sellAll(g)
    -- Bag updates fire and rescans run before the sales settle.
    g.world:advance(0.3)
    g:Core().ScanInventory("bags", true)
    g:Core().RefreshUI()
    T.eq(#g:UI().transferVisible, 0, "no sold item listed as ready")
    g.world:advance(8)
    T.eq(#g.world.sold, 4)
    T.eq(#g:UI().transferVisible, 0)
end)

T.test("a finished task says it's done instead of blaming filters", function()
    local g = T.game({ player = PLAYER, setup = F.setup(function(w) w:put(0, 1, I.JUNK, 1) end) })
    g:openVendor()
    g:Core().ShowHomeUI()
    sellAll(g)
    g.world:advance(8)
    g:Core().RefreshUI()
    local panel = g:UI().frame.panels.Transfer
    T.contains(panel.empty:GetText(), "All done")
    T.eq(panel.emptyAction:GetText(), "Back to Home")
end)

local function sellSelectedTo(g, predicate)
    local UI = g:UI()
    UI.transferSource, UI.transferDest = "Bags", "Vendor"
    g:Core().RefreshUI()
    for _, plan in ipairs(UI.transferVisible) do
        if plan.movable and predicate(plan.item) then UI.transferSelected[plan.key] = true end
    end
    g:Core().RefreshUI()
    g.world:withHardwareEvent(function() g:Core().ExecuteTransferSelected() end)
end

T.test("greens and better stop at 12 per click; junk sells in full, first", function()
    local g = T.game({ player = PLAYER, setup = F.setup(function(w)
        for i = 1, 14 do
            w:defineItem(9100 + i, { name = "Green " .. i, classID = 15, subclassID = 0, quality = 2,
                sellPrice = 100, expansionID = 3 })
            w:put(i <= 12 and 0 or 1, i <= 12 and i or i - 12, 9100 + i, 1)
        end
        for i = 1, 5 do w:put(2, i, I.JUNK, 1) end
    end) })
    g:openVendor()
    g:Core().ShowHomeUI()
    g:slash("transfer")
    sellSelectedTo(g, function() return true end)
    local junkSold, greensSold = 0, 0
    for _, s in ipairs(g.world.sold) do
        if s.itemID == I.JUNK then junkSold = junkSold + 1 else greensSold = greensSold + 1 end
    end
    T.eq(junkSold, 5, "all junk sold")
    T.eq(greensSold, 12, "greens capped at one buyback's worth")
    T.eq(#g.world.lostToBuyback, 5, "only junk fell out of the buyback")
    for _, lost in ipairs(g.world.lostToBuyback) do T.eq(lost.itemID, I.JUNK) end
    T.contains(g:printed(), "2 more selected")
end)

T.test("at a vendor the notice suggests selling, not auction candidates", function()
    local g = T.game({ player = PLAYER, setup = F.setup(function(w)
        for slot = 1, 3 do w:put(0, slot, I.JUNK, 1) end
    end) })
    g:openVendor()
    local card = g:P().GetTopReadyCard()
    T.ok(card, "a card")
    local _, dest = g:P().GetTaskRoute(card.task)
    T.eq(dest, "Vendor")
end)

-- A merchant that refuses an item (in game: "The merchant doesn't want that item.").
local function refusingGame()
    return T.game({ player = PLAYER, setup = F.setup(function(w)
        for slot = 1, 2 do w:put(0, slot, I.JUNK, 1) end
        w:defineItem(8801, { name = "Niffen Soup", classID = 0, subclassID = 5, quality = 1, sellPrice = 1875,
            expansionID = 9, maxStack = 20, vendorRefuses = true })
        w:put(0, 3, 8801, 1)
    end) })
end

T.test("sales are confirmed: items the merchant refuses aren't reported as sold", function()
    local g = refusingGame()
    g:openVendor()
    g:Core().ShowHomeUI()
    local mark = g:logMark()
    sellAll(g)
    g.world:advance(3)
    local chat = g:printed(mark)
    T.contains(chat, "Sold 2 of 3")
    T.contains(chat, "The merchant refused 1: Niffen Soup")
    T.contains(chat, "doesn't want that item")
    T.notContains(chat, "3 sold")
    T.eq(#g.world.sold, 2)
end)

T.test("an item a vendor refused is remembered and not offered again, until cleared", function()
    local g = refusingGame()
    g:openVendor()
    g:Core().ShowHomeUI()
    sellAll(g)
    g.world:advance(3)
    local P, UI = g:P(), g:UI()
    P.OpenTask("Sell Items That Can Go")
    local soup
    for _, plan in ipairs(UI.transferPlansAll or UI.transferVisible or {}) do
        if plan.item.itemID == 8801 then soup = plan end
    end
    T.ok(P.MerchantRefused(8801), "remembered")
    if soup then T.ok(not soup.movable, "not offered for sale again") end
    g:closeVendor()
    T.ok(P.MerchantRefused(8801), "still remembered after the vendor closes")
    T.ok(g:db().vendorRefused[8801], "in saved data (survives a reload)")
    local mark = g:logMark()
    g:slash("refused")
    T.contains(g:printed(mark), "Niffen Soup (8801)")
    g:slash("refused clear")
    T.ok(not P.MerchantRefused(8801), "cleared on request")
end)

T.test("a clean sale reports what was earned", function()
    local g = T.game({ player = PLAYER, setup = F.setup(function(w) w:put(0, 1, I.JUNK, 1) end) })
    g:openVendor()
    g:Core().ShowHomeUI()
    local mark = g:logMark()
    sellAll(g)
    T.contains(g:printed(mark), "checking the vendor's answer")
    g.world:advance(3)
    T.contains(g:printed(mark), "Sold 1")
    T.notContains(g:printed(mark), "refused")
end)

T.test("an item no vendor buys says so: destroy it or keep it", function()
    local g = refusingGame()
    g:openVendor()
    g:Core().ShowHomeUI()
    local mark = g:logMark()
    sellAll(g)
    g.world:advance(3)
    T.contains(g:printed(mark), "No vendor will buy it: destroy it")
    local P = g:P()
    local soup
    for _, item in ipairs(P.GetScanList("bags")) do if item.itemID == 8801 then soup = item end end
    local explanation = P.ExplainScanned(soup)
    T.eq(explanation.primary.id, "vendor_refused")
    T.contains(explanation.label, "destroy it or keep it")
    T.contains(explanation.evidence, "drop it on the game world")
    T.ok(not P.CanGoAndSellable(soup), "not in the sell tasks any more")
end)

T.test("a temporary sale error ('That object is busy') isn't remembered as a refusal", function()
    local g = T.game({ player = PLAYER, setup = F.setup(function(w)
        w:put(0, 1, I.JUNK, 1)
        w:defineItem(8802, { name = "Busy Boots", classID = 0, subclassID = 5, quality = 1, sellPrice = 1000,
            expansionID = 9, maxStack = 20, vendorBusy = true })
        w:put(0, 2, 8802, 1)
    end) })
    g:openVendor()
    g:Core().ShowHomeUI()
    local mark = g:logMark()
    sellAll(g)
    g.world:advance(3)
    local chat = g:printed(mark)
    T.contains(chat, "Not sold: Busy Boots (That object is busy.)")
    T.contains(chat, "try again")
    T.notContains(chat, "No vendor will buy")
    T.ok(not g:P().MerchantRefused(8802), "not remembered")
end)

T.test("a saved 'refusal' that wasn't one (the busy bug) is dropped", function()
    local g = refusingGame()
    g:db().vendorRefused = { [8803] = { name = "Old Busy Entry", reason = "That object is busy.", at = 1 } }
    T.ok(not g:P().MerchantRefused(8803))
    T.eq(g:db().vendorRefused[8803], nil)
end)

T.test("custom transfer starts clean; 'show all' lifts a task's hidden rule", function()
    local g = T.game({ player = PLAYER, setup = F.setup(function(w)
        w:put(0, 1, I.JUNK, 1)
        w:defineItem(8804, { name = "Keeper Ring", classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER",
            itemLevel = 100, requiredLevel = 10, bindType = 1, quality = 3, sellPrice = 1000, expansionID = 11 })
        w:put(0, 2, 8804, 1, { bound = true })
        w:defineItem(8805, { name = "Current Potion", classID = 0, subclassID = 1, quality = 1, sellPrice = 100,
            expansionID = 11, maxStack = 20 })
        w:put(0, 3, 8805, 1)
    end) })
    g:openVendor()
    g:Core().ShowHomeUI()
    local P, UI = g:P(), g:UI()
    P.OpenTask("Sell Items That Can Go")
    local function listed(id)
        for _, plan in ipairs(UI.transferVisible or {}) do if plan.item.itemID == id then return true end end
    end
    T.ok(not listed(8805), "the task leaves out a current-expansion potion")
    -- Custom transfer from Home: a clean list on the vendor route.
    g:Core().ShowHomeUI()
    g:click(UI.frame.panels.Home.custom)
    g:Core().RefreshUI()
    T.eq(UI.activeTaskPredicate, nil)
    T.eq(UI.transferDest, "Vendor", "at a vendor, the custom list sells")
    T.ok(listed(8805), "custom list shows everything sellable")
    -- Back in the task, sell the junk, then 'Show all items' from the empty list.
    P.OpenTask("Sell Items That Can Go")
    for _, plan in ipairs(UI.transferVisible) do if plan.item.itemID == I.JUNK then UI.transferSelected[plan.key] = true end end
    g.world:withHardwareEvent(function() g:Core().ExecuteTransferSelected() end)
    g.world:advance(8)
    g:Core().RefreshUI()
    local panel = UI.frame.panels.Transfer
    T.contains(panel.empty:GetText(), "All done")
    -- Searching inside the task for an item it leaves out explains why and offers "Show all items".
    g:type(panel.searchInput or panel.search, "Keeper")
    g:Core().RefreshUI()
    T.contains(panel.empty:GetText(), "Nothing here fits this task")
    T.eq(panel.emptyAction:GetText(), "Show all items")
    g:click(panel.emptyAction)
    T.ok(listed(8804), "the ring is listed after 'Show all items'")
end)

T.test("a refused item with an auction price suggests the auction house; letting it go isn't a vendor price", function()
    local g = refusingGame()
    g:openVendor()
    g:Core().ShowHomeUI()
    sellAll(g)
    g.world:advance(3)
    local P = g:P()
    local soup
    for _, item in ipairs(P.GetScanList("bags")) do if item.itemID == 8801 then soup = item end end
    local explanation = P.ExplainScanned(soup)
    T.eq(explanation.primary.id, "vendor_refused")
    T.notContains(P.LossText(soup, explanation) or "", "at a vendor")
    T.contains(P.LossText(soup, explanation) or "", "Vendors won't buy it")
    -- With an auction price it points to the auction house instead.
    g:db().prices = { ["c:8801"] = { price = 1900, at = g.env.time() } }
    explanation = P.ExplainScanned(soup)
    T.eq(explanation.primary.id, "vendor_refused_auction")
    T.contains(explanation.label, "sell it at the auction house")
    T.contains(explanation.evidence, "about")
end)
