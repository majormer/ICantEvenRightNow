local T = ...
local F = require("fixtures")
local I = F.ITEMS

local MAGE = { name = "Mage", realm = "R", level = 90, classFile = "MAGE" }

local function game(populate)
    local g = T.game({ player = MAGE, setup = F.setup(populate) })
    g:P().SetCharacterRole("Mage-R", "main")
    return g
end

T.test("rows show why an item is here", function()
    local g = game(function(w) w:put(0, 1, I.JUNK, 3) end)
    g:openVendor()
    g:slash("transfer")
    local UI = g:UI()
    UI.transferSource, UI.transferDest = "Bags", "Vendor"
    g:Core().RefreshUI()
    T.contains(UI.frame.panels.Transfer.rows[1].detailText:GetText(), "Can go: Junk (grey item)")
end)

T.test("tooltip explains the reason and what letting go costs", function()
    local g = game(function(w)
        w:put(0, 1, I.BOUND_HELM, 1, { bound = true })
        w.collections.appearances[70002] = true
    end)
    g:openVendor()
    g:slash("transfer")
    local UI = g:UI()
    UI.transferSource, UI.transferDest = "Bags", "Vendor"
    g:Core().RefreshUI()
    local row = UI.frame.panels.Transfer.rows[1]
    row:_fire("OnEnter")
    local lines = table.concat(g.env.GameTooltip._lines, "\n")
    T.contains(lines, "Why it's here: Appearance already collected")
    T.contains(lines, "If it goes: You keep the appearance.")
end)

T.test("keep reasons from the row menu silence suggestions and show on Rules", function()
    local g = game(function(w) w:put(0, 1, I.JUNK, 3) end)
    g:openVendor()
    g:slash("transfer")
    local UI = g:UI()
    UI.transferSource, UI.transferDest = "Bags", "Vendor"
    g:Core().RefreshUI()
    local row = UI.frame.panels.Transfer.rows[1]
    g:click(row.rule)
    local keepsake
    for _, b in ipairs(row.ruleMenu.buttons) do if b:GetText() == "Keepsake" then keepsake = b end end
    g:click(keepsake)
    T.eq(g:db().rules.items[I.JUNK].keepReason, "keepsake")
    T.contains(row.detailText:GetText(), "Keep: You marked it as a keepsake")
    g:slash("rules")
    T.eq(UI.frame.panels.Rules.rows[1].ruleText:GetText(), "Keepsake")
end)

T.test("'Sell Items That Can Go' lists only free, sellable items", function()
    local g = game(function(w)
        w:put(0, 1, I.JUNK, 3)                           -- free: junk
        w:put(0, 2, I.OLD_POTION, 5)                     -- free: spent old consumable
        w:put(0, 3, I.NEW_FLASK, 2)                      -- keep: current expansion
        w:put(0, 4, I.QUEST_START, 1)                    -- no vendor price
    end)
    g:openVendor()
    local card
    for _, c in ipairs(g:P().GetTaskCards()) do if c.name == "Sell Items That Can Go" then card = c end end
    T.eq(card.ready, 2)
end)

T.test("'Pull Items That Can Go' brings free bank items to the bags", function()
    local g = game(function(w)
        w:put(6, 1, I.JUNK, 3)
        w:put(6, 2, I.NEW_FLASK, 2)
    end)
    g:openBank()
    g:slash("")
    local card
    for _, c in ipairs(g:P().GetTaskCards()) do if c.name == "Pull Items That Can Go" then card = c end end
    T.eq(card.ready, 1)
    g:P().OpenTask("Pull Items That Can Go")
    local UI = g:UI()
    g:click(UI.frame.panels.Transfer.selectAll)
    g:click(UI.frame.panels.Transfer.execute)
    g:advance(2)
    T.eq(g.world:findItem(I.JUNK)[1].bagID < 6, true, "junk now in bags")
    T.eq(g.world:findItem(I.NEW_FLASK)[1].bagID, 6, "flask stays in the bank")
end)
