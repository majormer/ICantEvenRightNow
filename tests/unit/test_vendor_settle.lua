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
