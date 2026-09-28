local T = ...
local F = require("fixtures")
local I = F.ITEMS

-- P.ItemChannels: the one model of what can happen to an item.
local PLAYER = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" }

local function game(populate)
    local g = T.game({ player = PLAYER, setup = F.setup(populate) })
    g:Core().ScanInventory("bags", true)
    return g
end

local function scanned(g, itemID)
    for _, it in ipairs(g:P().GetScanList("bags")) do if it.itemID == itemID then return it end end
    error("not scanned: " .. tostring(itemID))
end

T.test("channels: soulbound is vendor-or-destroy; quest items nothing", function()
    local g = game(function(w)
        w:put(0, 1, I.BOUND_HELM, 1, { bound = true })
        w:put(0, 2, I.QUEST_START, 1)
    end)
    local P = g:P()
    local helm = P.ItemChannels(scanned(g, I.BOUND_HELM))
    T.eq(helm.vendor, true)
    T.eq(helm.auction, false) T.contains(helm.why.auction, "Soulbound")
    T.eq(helm.mail, false) T.eq(helm.trade, false)
    local quest = P.ItemChannels(scanned(g, I.QUEST_START))
    T.eq(quest.vendor, false) T.eq(quest.auction, false) T.eq(quest.warbandBank, false)
    T.contains(quest.why.auction, "Quest")
end)

T.test("channels: Warbound and Warbound-until-equipped stay in the Warband, never the auction house", function()
    local g = game(function(w)
        w:put(0, 1, I.WARBOUND_TOY, 1)
        w:put(0, 2, I.OLD_SWORD, 1, { warboundUntilEquipped = true })
    end)
    local P = g:P()
    for _, id in ipairs({ I.WARBOUND_TOY, I.OLD_SWORD }) do
        local c = P.ItemChannels(scanned(g, id))
        T.eq(c.auction, false, "auction " .. id) T.contains(c.why.auction, "Warbound")
        T.eq(c.trade, false)
        T.eq(c.mail, true, "own characters")
        T.eq(c.warbandBank, true)
        T.no(P.CanBeAuctioned(scanned(g, id)), "never an auction candidate")
    end
end)

T.test("channels: BoE and unbound items can go anywhere; an unconfirmed binding allows nothing outward", function()
    local g = game(function(w)
        w:put(0, 1, I.OLD_SWORD, 1)
        w:put(0, 2, I.LINEN, 20)
    end)
    local P = g:P()
    for _, id in ipairs({ I.OLD_SWORD, I.LINEN }) do
        local c = P.ItemChannels(scanned(g, id))
        T.eq(c.auction, true) T.eq(c.mail, true) T.eq(c.trade, true) T.eq(c.vendor, true)
    end
    local pending = P.ItemChannels(setmetatable({ bindingPending = true }, { __index = scanned(g, I.OLD_SWORD) }))
    T.eq(pending.auction, false) T.contains(pending.why.auction, "not confirmed")
end)

T.test("channels: a Never Sell rule closes the vendor and the auction house", function()
    local g = game(function(w) w:put(0, 1, I.OLD_SWORD, 1) end)
    g:db().rules.items[I.OLD_SWORD] = { neverSell = true }
    g:Core().ScanInventory("bags", true)
    local c = g:P().ItemChannels(scanned(g, I.OLD_SWORD))
    T.eq(c.vendor, false) T.eq(c.auction, false) T.contains(c.why.auction, "Never sell")
end)

T.test("a listing the game refuses is reported, remembered, and not offered again", function()
    local g = game(function(w) w:put(0, 1, I.OLD_SWORD, 1) end)
    g:db().prices = { ["i:" .. I.OLD_SWORD .. ":" .. g.env.GetRealmName()] = { price = 900000, at = g.env.time() } }
    g.world.auctionRefuses = { [I.OLD_SWORD] = 14 }   -- UsedCharges
    g:openAuctionHouse()
    g:Core().UpdateContext()
    g:Core().ScanInventory("bags", true)
    g:slash("transfer")
    local UI, P = g:UI(), g:P()
    UI.transferSource, UI.transferDest = "Bags", P.STORAGE_AUCTION_HOUSE
    P.ResetTabFilters("Transfer")
    g:Core().RefreshUI()
    g.world:advance(9)
    g:Core().RefreshUI()
    local panel = UI.frame.panels.Transfer
    g:click(panel.selectAll)
    local mark = g:logMark()
    g:click(panel.execute)
    g.world:advance(2)
    local printed = g:printed(mark)
    T.contains(printed, "Not listed")
    T.contains(printed, "used charges")
    T.notContains(printed, "Listed: ")
    T.ok(P.AuctionRefused(I.OLD_SWORD), "remembered")
    g:Core().ScanInventory("bags", true)
    local c = P.ItemChannels(scanned(g, I.OLD_SWORD))
    T.eq(c.auction, false) T.contains(c.why.auction, "refused")
    T.contains(table.concat(P.RefusedItemsReport(), "\n"), "auction house refused")
end)

T.test("an item that can't be auctioned and nobody can use goes to the vendor, whatever its auction price", function()
    local g = game(function(w)
        -- Warbound-until-equipped plate helm, appearance collected, no played character wears plate.
        w:put(0, 1, I.BOUND_HELM, 1, { warboundUntilEquipped = true })
        w.collections.appearances[70002] = true
    end)
    local P = g:P()
    P.SetCharacterRole("Main-R", "main")
    g:db().prices = { ["i:" .. I.BOUND_HELM .. ":" .. g.env.GetRealmName()] = { price = 50000000, at = g.env.time() } }
    g:Core().ScanInventory("bags", true)
    local helm = scanned(g, I.BOUND_HELM)
    T.eq(helm.bindingScope, "Warbound Until Equipped")
    T.no(P.IsValueFlagged(helm, "Vendor"), "no auction channel: the price doesn't protect it from the vendor")
    T.no(P.NeedsPriceCheck(helm))
    T.no(P.IsAuctionCandidate(helm))
    T.eq((P.GetItemValue(helm)), helm.sellPrice, "valued at the vendor price")
    T.ok(P.CanGoAndSellable(helm), "Sell Items That Can Go offers it")
end)

T.test("a post while the auction house is busy is refused up front, and the item stays selected", function()
    local g = game(function(w) w:put(0, 1, I.OLD_SWORD, 1) end)
    g:db().prices = { ["i:" .. I.OLD_SWORD .. ":" .. g.env.GetRealmName()] = { price = 900000, at = g.env.time() } }
    g:openAuctionHouse()
    g:Core().UpdateContext()
    g:Core().ScanInventory("bags", true)
    g:slash("transfer")
    local UI, P = g:UI(), g:P()
    UI.transferSource, UI.transferDest = "Bags", P.STORAGE_AUCTION_HOUSE
    P.ResetTabFilters("Transfer")
    g:Core().RefreshUI()
    g.world:advance(9)
    g:Core().RefreshUI()
    local panel = UI.frame.panels.Transfer
    g:click(panel.selectAll)
    g.world.auctionHouseBusy = true
    local mark = g:logMark()
    g:click(panel.execute)
    T.contains(g:printed(mark), "busy")
    T.eq(#(g.world.posted or {}), 0, "nothing sent")
    T.no(P.AuctionRefused(I.OLD_SWORD), "not remembered as refused")
end)

local function listingGame(code)
    local g = game(function(w) w:put(0, 1, I.OLD_SWORD, 1) end)
    g:db().prices = { ["i:" .. I.OLD_SWORD .. ":" .. g.env.GetRealmName()] = { price = 900000, at = g.env.time() } }
    g.world.auctionRefuses = { [I.OLD_SWORD] = code }
    g:openAuctionHouse()
    g:Core().UpdateContext()
    g:Core().ScanInventory("bags", true)
    g:slash("transfer")
    local UI, P = g:UI(), g:P()
    UI.transferSource, UI.transferDest = "Bags", P.STORAGE_AUCTION_HOUSE
    P.ResetTabFilters("Transfer")
    g:Core().RefreshUI()
    g.world:advance(9)
    g:Core().RefreshUI()
    return g, UI.frame.panels.Transfer
end

T.test("a 'Warbound until equipped' refusal corrects the saved binding: the item becomes Warband-only", function()
    local g, panel = listingGame(26)   -- ItemBoundToAccountUntilEquip
    local P = g:P()
    g:click(panel.selectAll)
    local mark = g:logMark()
    g:click(panel.execute)
    g.world:advance(2)
    T.contains(g:printed(mark), "Warbound until equipped")
    T.eq(g:db().knownBinding[g.world.containers[0].slots[1].guid], "wue", "binding corrected from the game's answer (this copy)")
    T.ok(P.AuctionRefused(I.OLD_SWORD))
    g:Core().ScanInventory("bags", true)
    local c = P.ItemChannels(scanned(g, I.OLD_SWORD))
    T.eq(c.auction, false)
    T.eq(c.warbandBank, true, "still goes to the Warband bank")
end)

T.test("a temporary auction house error ('busy') isn't remembered", function()
    local g, panel = listingGame(7)   -- IsBusy
    g:click(panel.selectAll)
    local mark = g:logMark()
    g:click(panel.execute)
    g.world:advance(2)
    T.contains(g:printed(mark), "busy")
    T.no(g:P().AuctionRefused(I.OLD_SWORD), "temporary: not remembered")
end)

T.test("nothing keeps it and it can't be auctioned: it can go to a vendor (no more 'no clear reason')", function()
    local g = game(function(w)
        w:defineItem(7101, { name = "Thermal Anvil", classID = 15, subclassID = 0, quality = 1, sellPrice = 990, expansionID = 4 })
        w:put(0, 1, 7101, 1)
    end)
    local P = g:P()
    g:db().prices = { ["i:7101:" .. g.env.GetRealmName()] = { price = 250000, at = g.env.time() } }
    g:db().auctionRefused[7101] = { name = "Thermal Anvil", reason = "the game won't auction an item with used charges", at = 0 }
    g:Core().ScanInventory("bags", true)
    local e = P.ExplainScanned(scanned(g, 7101))
    T.eq(e.primary.id, "no_use_no_market")
    T.eq(e.disposition, "free")
    T.contains(e.evidence, "used charges")
    T.ok(P.CanGoAndSellable(scanned(g, 7101)))
    -- A BoE item with an open auction channel and no reason stays "no clear reason".
    g.world:defineItem(7102, { name = "Odd Trinket", classID = 15, subclassID = 0, quality = 1, sellPrice = 990, expansionID = 4, bindType = 2 })
    g.world:put(0, 2, 7102, 1)
    g:Core().ScanInventory("bags", true)
    T.eq(P.ExplainScanned(scanned(g, 7102)).primary.id, "unexplained")
    -- A soulbound item with no market price (a Jeeves) is not swept up.
    g.world:defineItem(7103, { name = "Repair Bot", classID = 15, subclassID = 0, quality = 2, sellPrice = 990, expansionID = 2, bindType = 1 })
    g.world:put(0, 3, 7103, 1, { bound = true })
    g:Core().ScanInventory("bags", true)
    T.eq(P.ExplainScanned(scanned(g, 7103)).primary.id, "unexplained")
end)
