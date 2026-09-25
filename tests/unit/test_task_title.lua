local T = ...
local F = require("fixtures")
local I = F.ITEMS

local PLAYER = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" }

T.test("opening a task from Home is not marked modified", function()
    local g = T.game({ player = PLAYER, setup = F.setup(function(w) w:put(0, 1, I.OLD_SWORD, 1) end) })
    g:openBank()
    g:Core().ShowHomeUI()
    for _, name in ipairs({ "Deposit Old Items", "Deposit to Warband", "Pull Bank Upgrades" }) do
        g:P().OpenTask(name)
        g:Core().RefreshUI()
        g.world:advance(0.1)
        T.eq(g:UI().activeTaskModified, false, name .. " opens unmodified")
        T.eq(g:UI().frame.panels.Transfer.taskTitle:GetText(), name)
    end
end)
