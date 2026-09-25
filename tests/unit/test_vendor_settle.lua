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
