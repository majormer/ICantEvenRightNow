local T = ...
local F = require("fixtures")
local I = F.ITEMS

-- Listing at the auction house (Transfer destination "Auction House").
local PLAYER = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" }

local function game(populate, prices)
    local g = T.game({ player = PLAYER, setup = F.setup(populate) })
    local db = g:db()
    db.prices = {}
    for itemID, price in pairs(prices or {}) do
        -- Stored prices are keyed like Value.lua: commodities by item, gear per realm.
        local key = g.world.items[itemID].maxStack > 1 and ("c:" .. itemID) or ("i:" .. itemID .. ":" .. g.env.GetRealmName())
        db.prices[key] = { price = price, at = g.env.time() }
    end
    g:openAuctionHouse()
    g:Core().UpdateContext()
    g:Core().ScanInventory("bags", true)
    return g
end

local function openList(g)
    g:slash("transfer")
    local UI, P = g:UI(), g:P()
    UI.transferSource, UI.transferDest = "Bags", P.STORAGE_AUCTION_HOUSE
    P.ResetTabFilters("Transfer")
    g:Core().RefreshUI()
    g.world:advance(9)
    g:Core().RefreshUI()
    return UI.frame.panels.Transfer
end

local function scanned(g, itemID)
    for _, it in ipairs(g:P().GetScanList("bags")) do if it.itemID == itemID then return it end end
end

T.test("listing price: undercut by 1% (at most 5g), whole silver, never below vendor", function()
    local g = game(function(w) w:put(0, 1, I.VALUABLE_ORE, 20) end, { [I.VALUABLE_ORE] = 12345 })
    local ore = scanned(g, I.VALUABLE_ORE)
    T.eq((g:P().ListingPrice(ore)), 12200, "12345 - 1% = 12222, rounded down to silver")
    g:db().prices["c:" .. I.VALUABLE_ORE].price = 40000000   -- 4,000g: the undercut is capped at 5g
    T.eq((g:P().ListingPrice(ore)), 39950000)
    g:db().prices["c:" .. I.VALUABLE_ORE].price = 10         -- below the vendor price (25c): vendor + 1, rounded up
    T.eq((g:P().ListingPrice(ore)), 100)
end)

T.test("at the auction house, Auction Candidates lists from the bags, one auction per click", function()
    local g = game(function(w)
        w:put(0, 1, I.VALUABLE_ORE, 20)
        w:put(0, 2, I.OLD_SWORD, 1)
    end, { [I.VALUABLE_ORE] = 500000, [I.OLD_SWORD] = 900000 })
    local P = g:P()
    local task = P.FindTask("Auction Candidates")
    local source, dest = P.GetTaskRoute(task)
    T.eq(source, "Bags")
    T.eq(dest, P.STORAGE_AUCTION_HOUSE)
    local panel = openList(g)
    T.eq(#g:UI().transferVisible, 2)
    g:click(panel.selectAll)
    T.eq(panel.execute:GetText(), "List 1 of 2")
    g:click(panel.execute)
    T.eq(#g.world.posted, 1, "one auction per click")
    T.eq(g.world.posted[1].duration, 2, "24 hours")
    T.eq(g.world.posted[1].unitPrice % 100, 0, "whole silver")
    g:Core().RefreshUI()
    T.eq(panel.execute:GetText(), "List 1", "the rest stays selected")
    g:click(panel.execute)
    T.eq(#g.world.posted, 2)
    local byItem = {}
    for _, post in ipairs(g.world.posted) do byItem[post.itemID] = post end
    T.eq(byItem[I.VALUABLE_ORE].quantity, 20, "a commodity lists the whole stack")
    T.eq(byItem[I.OLD_SWORD].quantity, 1)
end)

T.test("listing is blocked with a reason: bound, unconfirmed price, no price", function()
    local g = game(function(w)
        w:put(0, 1, I.BOUND_HELM, 1, { bound = true })
        w:put(0, 2, I.OLD_SWORD, 1)
        w:put(0, 3, I.LINEN, 20)
    end, { [I.OLD_SWORD] = 300000000, [I.BOUND_HELM] = 500000 })   -- the sword at 30,000g is unconfirmed
    local P = g:P()
    local reasons = {}
    for _, plan in ipairs(P.GetTransferCandidates("Bags", P.STORAGE_AUCTION_HOUSE)) do reasons[plan.item.itemID] = plan.blocked end
    T.contains(reasons[I.BOUND_HELM], "Bound")
    T.contains(reasons[I.OLD_SWORD], "unconfirmed")
    T.contains(reasons[I.LINEN], "No auction price")
end)
