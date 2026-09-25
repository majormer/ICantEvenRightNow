local T = ...
local F = require("fixtures")
local I = F.ITEMS

local function homeCard(game, name)
    local panel = game:UI().frame.panels.Home
    for _, widget in ipairs(panel.cards) do
        if widget:IsShown() and widget.card and widget.card.name == name then return widget end
    end
    return nil
end

local function bagGame(populate, extra)
    local opts = { setup = F.setup(populate) }
    for k, v in pairs(extra or {}) do opts[k] = v end
    return T.game(opts)
end

T.test("the console opens on Home with task cards", function()
    local game = bagGame(function(w) w:put(0, 1, I.OLD_POTION, 5) end)
    game:slash("")
    T.eq(game:UI().activeTab, "Home")
    local card = homeCard(game, "Deposit Old Items")
    T.ok(card, "Deposit Old Items card shown")
    T.contains(card.summary:GetText(), "waiting: Visit a bank", "bank task waits for a bank")
end)

T.test("at a bank the card is ready and opens its review list", function()
    local game = bagGame(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
        w:put(0, 2, I.LINEN, 20)
    end)
    game:openBank()
    game:slash("")
    local card = homeCard(game, "Deposit Old Items")
    T.contains(card.summary:GetText(), "2 ready")
    game:click(card.open)
    local UI = game:UI()
    T.eq(UI.activeTab, "Transfer")
    local panel = UI.frame.panels.Transfer
    T.eq(panel.taskTitle:GetText(), "Deposit Old Items")
    T.eq(next(UI.transferSelected), nil, "nothing pre-selected by default")
end)

T.test("pre-selection setting selects safe movable items only", function()
    local game = bagGame(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
        w:put(0, 2, I.LINEN, 20)
    end)
    game:db().rules.items[I.LINEN] = { protect = true }
    game:db().ui.preselectQuickTasks = true
    game:openBank()
    game:slash("")
    game:click(homeCard(game, "Deposit Old Items").open)
    local UI = game:UI()
    local selected = {}
    for _, plan in ipairs(UI.transferVisible) do
        if UI.transferSelected[plan.key] then selected[plan.item.itemID] = true end
    end
    T.ok(selected[I.OLD_POTION], "potion pre-selected")
    T.no(selected[I.LINEN], "protected linen never pre-selected")
    T.contains(UI.frame.panels.Transfer.execute:GetText(), "Deposit 1")
end)

T.test("editing a task marks it modified instead of losing its name", function()
    local game = bagGame(function(w) w:put(0, 1, I.OLD_POTION, 5) end)
    game:openBank()
    game:slash("")
    game:click(homeCard(game, "Deposit Old Items").open)
    local panel = game:UI().frame.panels.Transfer
    game:type(panel.search, "potion")
    game:Core().RefreshUI()
    T.eq(panel.taskTitle:GetText(), "Deposit Old Items (modified)")
end)

T.test("Deposit to Warband lists only items other characters benefit from", function()
    local game = bagGame(function(w)
        w:put(0, 1, I.OLD_SWORD, 1)                 -- BoE: shareable
        w:put(0, 2, I.NEW_FLASK, 2)                 -- current consumable for this character
    end)
    game:openBank()
    local card
    for _, c in ipairs(game:P().GetTaskCards()) do if c.name == "Deposit to Warband" then card = c end end
    T.eq(card.ready, 1, "only the BoE sword counts")
end)

T.test("Save as task adds a Home card that can be removed", function()
    local game = bagGame(function(w) w:put(0, 1, I.OLD_POTION, 5) end)
    game:openBank()
    game:slash("transfer")
    local UI = game:UI()
    local panel = UI.frame.panels.Transfer
    UI.transferCustomizeOpen = true
    game:Core().RefreshUI()
    game:type(panel.presetNameInput, "My Potions")
    game:click(panel.savePreset)
    game:click(panel.homeButton)
    local card = homeCard(game, "My Potions")
    T.ok(card, "saved task on Home")
    T.ok(card.remove:IsShown(), "saved tasks can be removed")
    game:click(card.remove)
    T.eq(homeCard(game, "My Potions"), nil, "removed")
end)

T.test("identical stacks share one row; selecting it selects every stack", function()
    local game = bagGame(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
        w:put(0, 2, I.OLD_POTION, 7)
    end)
    game:openBank()
    game:slash("transfer")
    local UI = game:UI()
    UI.transferSource, UI.transferDest = "Bags", "Bank (All Tabs)"
    game:Core().RefreshUI()
    local panel = UI.frame.panels.Transfer
    T.contains(panel.rows[1].nameText:GetText(), "x12 in 2 stacks")
    T.no(panel.rows[2]:IsShown(), "second stack is not a separate row")
    game:click(panel.rows[1])
    T.contains(panel.execute:GetText(), "Deposit 2")
end)

T.test("compact rows show nine items per screen", function()
    local game = bagGame(function(w)
        for slot = 1, 12 do
            w:defineItem(9100 + slot, { name = "Thing " .. slot, classID = 15, expansionID = 2, sellPrice = 1 })
            w:put(0, slot, 9100 + slot, 1)
        end
    end)
    game:db().ui.compactRows = true
    game:openBank()
    game:slash("transfer")
    local UI = game:UI()
    UI.transferSource, UI.transferDest = "Bags", "Bank (All Tabs)"
    game:Core().RefreshUI()
    local shown = 0
    for _, row in ipairs(UI.frame.panels.Transfer.rows) do if row:IsShown() then shown = shown + 1 end end
    T.eq(shown, 9)
end)

T.test("vendor sales stop at 12 per click so every sale can be bought back", function()
    local game = bagGame(function(w)
        for slot = 1, 15 do w:put(0, slot, I.OLD_POTION, 1) end
    end)
    game:openVendor()
    game:slash("transfer")
    local UI = game:UI()
    UI.transferSource, UI.transferDest = "Bags", "Vendor"
    game:Core().RefreshUI()
    local panel = UI.frame.panels.Transfer
    game:click(panel.selectAll)
    T.eq(panel.execute:GetText(), "Sell 12 of 15")
    game:click(panel.execute)
    T.eq(#game.world.sold, 12)
    T.eq(#game.world.lostToBuyback, 0, "nothing pushed out of buyback")
    T.contains(panel.execute:GetText(), "Sell 3")
    game:click(panel.execute)
    T.eq(#game.world.sold, 15)
end)

T.test("opening a bank shows a notice with the top task; Open goes to its list", function()
    local game = bagGame(function(w) w:put(0, 1, I.OLD_POTION, 5) end)
    game:openBank()
    local notice = game:UI().contextNoticeFrame
    T.ok(notice and notice:IsShown(), "notice shown")
    T.contains(notice.text:GetText(), "Deposit Old Items: 1 ready")
    game:click(notice.open)
    T.eq(game:UI().activeTab, "Transfer")
    T.no(notice:IsShown())
end)

T.test("notice setting: off shows nothing, open opens the console", function()
    local game = bagGame(function(w) w:put(0, 1, I.OLD_POTION, 5) end)
    game:db().ui.contextNotice = "off"
    game:openBank()
    T.no(game:UI().contextNoticeFrame and game:UI().contextNoticeFrame:IsShown())
    T.no(game:UI().frame and game:UI().frame:IsShown())
    game:closeBank()
    game:db().ui.contextNotice = "open"
    game:openBank()
    T.ok(game:UI().frame:IsShown(), "console opened")
    T.eq(game:UI().activeTab, "Home")
end)

T.test("closing the bank hides the notice", function()
    local game = bagGame(function(w) w:put(0, 1, I.OLD_POTION, 5) end)
    game:openBank()
    game:closeBank()
    T.no(game:UI().contextNoticeFrame:IsShown())
end)

T.test("Home asks this character's role once, with a suggestion", function()
    local game = bagGame(function(w) end, { player = { name = "Solo", realm = "R", level = 90, classFile = "MAGE" } })
    game:slash("")
    local panel = game:UI().frame.panels.Home
    T.ok(panel.notice:IsShown())
    T.contains(panel.notice.text:GetText(), "Main / Active")
    game:click(panel.notice.buttons[1])
    T.eq(game:P().GetRole(game:P().GetCurrentCharacter()), "main")
    T.notContains(panel.notice.text:GetText() or "", "What is", "role question gone once answered")
end)

T.test("Characters tab lists the roster and accepts suggestions in bulk", function()
    local saved = T.game({ player = { name = "Alt", realm = "R", level = 12, classFile = "MAGE",
        professions = { { name = "Tailoring", skillLine = 197 } } } }):logout()
    local game = T.game({ savedVariables = saved, player = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" } })
    game:slash("characters")
    local panel = game:UI().frame.panels.Characters
    T.contains(panel.rows[1].name:GetText(), "Main-R  (you)")
    T.contains(panel.rows[2].suggestion:GetText(), "Crafter")
    game:click(panel.acceptAll)
    local P = game:P()
    T.eq(P.GetRole(P.GetCharacter("Alt-R")), "crafter")
    T.eq(P.GetRole(P.GetCharacter("Main-R")), "main")
end)
