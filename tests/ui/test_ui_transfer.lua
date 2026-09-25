local T = ...
local F = require("fixtures")
local I = F.ITEMS

local function visibleRowNames(panel)
    local names = {}
    for _, row in ipairs(panel.rows) do
        if row:IsShown() then table.insert(names, row.nameText:GetText()) end
    end
    return table.concat(names, "|")
end

T.test("deposit flow through the Transfer screen with real clicks", function()
    local game = T.game({ setup = F.setup(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
        w:put(0, 2, I.LINEN, 40)
    end) })
    game:openBank()
    game:slash("transfer")
    local UI = game:UI()
    local panel = UI.frame.panels.Transfer
    UI.transferSource, UI.transferDest = "Bags", "Bank (All Tabs)"
    game:Core().RefreshUI()
    local names = visibleRowNames(panel)
    T.contains(names, "Draenic Healing Potion")
    T.contains(names, "Linen Cloth")

    game:click(panel.selectAll)
    T.contains(panel.execute:GetText(), "Deposit")
    game:click(panel.execute)
    game:advance(2)
    T.eq(game.world:getStack(0, 1), nil, "potion deposited")
    T.eq(game.world:getStack(0, 2), nil, "linen deposited")
end)
