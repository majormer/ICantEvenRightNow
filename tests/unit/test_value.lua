local T = ...
local F = require("fixtures")
local I = F.ITEMS

-- Install a fake Auctionator API. prices[itemID] = copper, ages[itemID] = days.
local function withAuctionator(prices, ages)
    return function(w)
        w.addonsLoaded.Auctionator = true
        rawset(w.env, "Auctionator", { API = { v1 = {
            GetAuctionPriceByItemLink = function(caller, link)
                assert(caller == "ICantEvenRightNow", "callerID required")
                return prices[w.parseItemID(link)]
            end,
            GetAuctionAgeByItemLink = function(_, link) return (ages or {})[w.parseItemID(link)] end,
            GetAuctionPriceByItemID = function(_, id) return prices[id] end,
            GetAuctionAgeByItemID = function(_, id) return (ages or {})[id] end,
            GetDisenchantPriceByItemLink = function() return 400000 end,
        } } })
    end
end

local function game(populate, extra)
    return T.game({ setup = function(w)
        F.defineItems(w)
        F.addBank(w)
        if extra then extra(w) end
        populate(w)
    end })
end

local function scanned(g, itemID)
    g:Core().ScanInventory("bags", true)
    for _, item in ipairs(g:P().GetScanList("bags")) do
        if item.itemID == itemID then return item end
    end
end

T.test("Auctionator price with age; stale after the freshness limit", function()
    local g = game(function(w) w:put(0, 1, I.OLD_SWORD, 1) end,
        withAuctionator({ [I.OLD_SWORD] = 2500000 }, { [I.OLD_SWORD] = 2 }))
    local price = g:P().GetAuctionPrice(scanned(g, I.OLD_SWORD))
    T.eq(price.price, 2500000)
    T.eq(price.source, "Auctionator")
    T.ok(price.fresh, "2 days is fresh for gear (limit 7)")
    local g2 = game(function(w) w:put(0, 1, I.OLD_SWORD, 1) end,
        withAuctionator({ [I.OLD_SWORD] = 2500000 }, { [I.OLD_SWORD] = 10 }))
    T.no(g2:P().GetAuctionPrice(scanned(g2, I.OLD_SWORD)).fresh, "10 days is stale")
end)

T.test("TSM is used when Auctionator is absent", function()
    local g = game(function(w) w:put(0, 1, I.VALUABLE_ORE, 20) end, function(w)
        rawset(w.env, "TSM_API", {
            ToItemString = function(link) return "i:" .. w.parseItemID(link) end,
            GetCustomPriceValue = function(source, itemString)
                if source == "DBMarket" and itemString == "i:" .. I.VALUABLE_ORE then return 90000 end
            end,
        })
    end)
    local price = g:P().GetAuctionPrice(scanned(g, I.VALUABLE_ORE))
    T.eq(price.source, "TSM")
    T.eq(price.price, 90000)
end)

T.test("vendor protection: valuable items are flagged, not pre-selected, and not in 'Sell Items That Can Go'", function()
    local g = game(function(w)
        w:put(0, 1, I.VALUABLE_ORE, 20)   -- worth 9g each at auction, 25c at vendor
        w:put(0, 2, I.JUNK, 3)
    end, withAuctionator({ [I.VALUABLE_ORE] = 90000 }, { [I.VALUABLE_ORE] = 1 }))
    local P = g:P()
    P.SetCharacterRole(P.currentCharacterKey, "main")
    local ore = scanned(g, I.VALUABLE_ORE)
    T.ok(P.IsValueFlagged(ore, "Vendor"))
    local advice, reason = P.AuctionAdvice(ore)
    T.eq(advice, "auction")
    T.contains(reason, "after the auction cut")
    g:db().ui.preselectQuickTasks = true
    g:openVendor()
    g:slash("")
    P.OpenTask("Sell Items That Can Go")
    local UI = g:UI()
    for _, plan in ipairs(UI.transferVisible) do
        T.neq(plan.item.itemID, I.VALUABLE_ORE, "ore not offered for vendor sale")
    end
    -- Even in a manual vendor route, the ore is never pre-selected.
    UI.transferSource, UI.transferDest = "Bags", "Vendor"
    P.PreselectTask({ preset = { source = "Bags", dest = "Vendor" } })
    for _, plan in ipairs(P.GetTransferCandidates("Bags", "Vendor")) do
        if plan.item.itemID == I.VALUABLE_ORE then T.no(UI.transferSelected[plan.key], "not pre-selected") end
    end
end)

T.test("soulbound items are never auction candidates", function()
    local g = game(function(w) w:put(0, 1, I.BOUND_HELM, 1, { bound = true }) end,
        withAuctionator({ [I.BOUND_HELM] = 9999999 }))
    T.eq((g:P().AuctionAdvice(scanned(g, I.BOUND_HELM))), nil)
end)

T.test("Price My Items looks up only owned tradeable items, paced, and stores them", function()
    local g = game(function(w)
        w:put(0, 1, I.VALUABLE_ORE, 20)
        w:put(0, 2, I.OLD_SWORD, 1)
        w:put(0, 3, I.BOUND_HELM, 1, { bound = true })
        w.ahPrices = { [I.VALUABLE_ORE] = 80000, [I.OLD_SWORD] = 3000000 }
    end)
    local P = g:P()
    g:Core().ScanInventory("bags", true)
    g:openAuctionHouse()
    g:slash("")
    local card
    for _, c in ipairs(P.GetTaskCards()) do if c.name == "Price My Items" then card = c end end
    T.eq(card.ready, 2, "two tradeable items need prices")
    g.world:withHardwareEvent(function() P.OpenTask("Price My Items") end)
    g:advance(5)
    T.eq(g.world.ahQueries, 2, "one query per item")
    local ore = scanned(g, I.VALUABLE_ORE)
    local price = P.GetAuctionPrice(ore)
    T.eq(price.price, 80000)
    T.eq(price.source, "your scan")
    T.ok(g:db().prices["c:" .. I.VALUABLE_ORE], "commodity stored region-wide")
end)

T.test("no price source: Home explains how to get auction values", function()
    local g = game(function(w) end)
    g:P().SetCharacterRole(g:P().currentCharacterKey, "main")
    g:slash("")
    T.contains(g:UI().frame.panels.Home.notice.text:GetText(), "Install Auctionator")
end)

T.test("stale own prices raise a refresh notice", function()
    local g = game(function(w)
        w:put(0, 1, I.VALUABLE_ORE, 20)
        w.ahPrices = { [I.VALUABLE_ORE] = 80000 }
    end)
    local P = g:P()
    P.SetCharacterRole(P.currentCharacterKey, "main")
    g:Core().ScanInventory("bags", true)
    g:openAuctionHouse()
    g.world:withHardwareEvent(function() P.StartPriceLookup() end)
    g:advance(2)
    g:closeAuctionHouse()
    g:advance(9 * 24 * 3600)
    g:slash("")
    T.contains(g:UI().frame.panels.Home.notice.text:GetText(), "days old")
end)

T.test("tooltip value lines: auction, disenchant with enchanter, account count", function()
    local saved = T.game({ player = { name = "Ench", realm = "R", level = 70, classFile = "MAGE",
        professions = { { name = "Enchanting", skillLine = 333 } } },
        setup = F.setup(function(w) w:put(0, 1, I.OLD_SWORD, 1) end) })
    saved:Core().ScanInventory("bags", true)
    saved:P().SetCharacterRole("Ench-R", "crafter")
    local g = T.game({ savedVariables = saved:logout(), setup = function(w)
        F.defineItems(w); F.addBank(w)
        withAuctionator({ [I.OLD_SWORD] = 2500000 }, { [I.OLD_SWORD] = 1 })(w)
        w:put(0, 1, I.OLD_SWORD, 1)
    end })
    local lines = table.concat(g:P().ValueTooltipLines(scanned(g, I.OLD_SWORD)), "\n")
    T.contains(lines, "Auction: ~250g")
    T.contains(lines, "Disenchant: ~40g 0s (Ench, Enchanter)")
    T.contains(lines, "On your account: 2")
end)

T.test("sell cards don't count items worth far more at auction as ready", function()
    local g = game(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
        w:put(0, 2, I.OLD_POTION, 1)
    end, withAuctionator({ [I.OLD_POTION] = 250000 }, { [I.OLD_POTION] = 1 }))
    local P = g:P()
    P.SetCharacterRole(P.currentCharacterKey, "main")
    g:openVendor()
    local card
    for _, c in ipairs(P.GetTaskCards()) do if c.name == "Sell Old Consumables" then card = c end end
    T.ok(card, "card exists")
    T.eq(card.ready, 0, "not ready to sell")
    T.eq(card.worthMore, 2)
    T.contains(P.CardSummary(card), "worth more at auction")
end)

T.test("at a vendor with nothing to sell, no notice (not an auction task)", function()
    local g = game(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
    end, withAuctionator({ [I.OLD_POTION] = 250000 }, { [I.OLD_POTION] = 1 }))
    local P = g:P()
    P.SetCharacterRole(P.currentCharacterKey, "main")
    g:openVendor()
    g:advance(9)
    T.eq(P.GetTopReadyCard(), nil)
    local notice = g:UI().contextNoticeFrame
    T.ok(not notice or not notice:IsShown(), "no notice")
end)

T.test("unpriced tradeable items: scan at the auction house before selling them", function()
    local g = game(function(w)
        w:defineItem(8950, { name = "Unpriced Boots", classID = 4, subclassID = 4, equipLoc = "INVTYPE_FEET",
            itemLevel = 100, requiredLevel = 10, bindType = 2, quality = 3, sellPrice = 5000, expansionID = 11,
            appearanceSourceID = 895001 })
        w.collections.appearances[895001] = true
        w:put(0, 1, 8950, 1)
        w:put(0, 2, I.JUNK, 3)
    end, withAuctionator({}, {}))
    local P = g:P()
    P.SetCharacterRole(P.currentCharacterKey, "main")
    local boots = scanned(g, 8950)
    T.ok(P.NeedsPriceCheck(boots), "no price yet")
    g:openVendor()
    g:advance(9)
    local card
    for _, c in ipairs(P.GetTaskCards()) do if c.name == "Sell Items That Can Go" then card = c end end
    T.contains(P.CardSummary(card), "1 to price at the auction house first")
    g:slash("")
    P.OpenTask("Sell Items That Can Go")
    g:click(g:UI().frame.panels.Transfer.selectAll)
    for _, plan in ipairs(g:UI().transferVisible) do
        if plan.item.itemID == 8950 then T.no(g:UI().transferSelected[plan.key], "left unselected") end
        if plan.item.itemID == I.JUNK then T.ok(g:UI().transferSelected[plan.key], "junk still selected") end
    end
    T.contains(g:UI().inventoryStatus, "price them at the auction house first")
end)
