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
    local game = bagGame(function(w) w:put(0, 1, I.LINEN, 20) end)
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
    T.contains(card.summary:GetText(), "1 ready", "the old potion can go: it isn't banked")
    game:click(card.open)
    local UI = game:UI()
    T.eq(UI.activeTab, "Transfer")
    local panel = UI.frame.panels.Transfer
    T.eq(panel.taskTitle:GetText(), "Deposit Old Items")
    T.eq(next(UI.transferSelected), nil, "nothing pre-selected by default")
end)

T.test("pre-selection setting selects safe movable items only", function()
    local game = bagGame(function(w)
        w:put(0, 1, I.LINEN, 20)
        w:put(0, 2, I.VALUABLE_ORE, 20)
    end)
    game:db().rules.items[I.VALUABLE_ORE] = { protect = true }
    game:db().ui.preselectQuickTasks = true
    game:openBank()
    game:slash("")
    game:click(homeCard(game, "Deposit Old Items").open)
    local UI = game:UI()
    local selected = {}
    for _, plan in ipairs(UI.transferVisible) do
        if UI.transferSelected[plan.key] then selected[plan.item.itemID] = true end
    end
    T.ok(selected[I.LINEN], "linen pre-selected")
    T.no(selected[I.VALUABLE_ORE], "protected ore never pre-selected")
    T.contains(UI.frame.panels.Transfer.execute:GetText(), "Deposit 1")
end)

T.test("editing a task marks it modified instead of losing its name", function()
    local game = bagGame(function(w) w:put(0, 1, I.LINEN, 20) end)
    game:openBank()
    game:slash("")
    game:click(homeCard(game, "Deposit Old Items").open)
    local panel = game:UI().frame.panels.Transfer
    game:type(panel.search, "linen")
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
    local game = bagGame(function(w) w:put(0, 1, I.LINEN, 20) end)
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
    T.contains(panel.rows[2].suggestion:GetText(), "Crafting only")
    game:click(panel.acceptAll)
    local P = game:P()
    T.eq(P.GetRole(P.GetCharacter("Alt-R")), "crafter")
    T.eq(P.GetRole(P.GetCharacter("Main-R")), "main")
end)

T.test("filter-only presets from 0.4/0.5 get no route-based count and keep the chosen route", function()
    local game = bagGame(function(w) w:put(0, 1, I.OLD_SWORD, 1) end)
    local db = game:db()
    db.savedFilters[#db.savedFilters + 1] = { name = "Legacy Upgrades", expansion = 0, bind = "All",
        type = "All", slot = "All", upgrade = "Upgrade" }
    game:openBank()
    local card
    for _, c in ipairs(game:P().GetTaskCards()) do if c.name == "Legacy Upgrades" then card = c end end
    T.eq(card.ready, 0, "not counted as a bags-to-bank deposit")
    T.eq(game:P().CardSummary(card), "Filter preset (no route)")
    local UI = game:UI()
    game:slash("transfer")
    UI.transferSource, UI.transferDest = "Bank (All Tabs)", "Bags"
    game:P().OpenTask("Legacy Upgrades")
    T.eq(UI.transferSource, "Bank (All Tabs)", "route unchanged")
    T.eq(UI.transferDest, "Bags")
    T.eq(game:db().ui.tabFilters.Transfer.upgrade.include, "Upgrade", "filters applied")
end)

T.test("Deposit Old Items leaves out items headed out (can go, auction candidates)", function()
    local game = bagGame(function(w)
        w:put(0, 1, I.LINEN, 20)          -- kept: banked
        w:put(0, 2, I.OLD_POTION, 5)      -- can go: sell it, don't bank it
        w:put(0, 3, I.VALUABLE_ORE, 20)   -- worth far more at auction: list it
    end)
    game:db().prices = { ["c:" .. I.VALUABLE_ORE] = { price = 500000, at = game.env.time() } }
    game:openBank()
    local P = game:P()
    local names = {}
    for _, plan in ipairs(P.GetTaskPlans(P.FindTask("Deposit Old Items"))) do names[plan.item.itemID] = true end
    T.ok(names[I.LINEN], "kept old material is banked")
    T.no(names[I.OLD_POTION], "can-go potion stays in the bags for the vendor")
    for _, item in ipairs(P.GetScanList(P.BAG_SCOPE)) do
        if item.itemID == I.VALUABLE_ORE then T.ok(P.IsAuctionCandidate(item), "ore is an auction candidate") end
    end
    T.no(names[I.VALUABLE_ORE], "auction candidate stays in the bags for the auction house")
end)

T.test("at a bank, Auction Candidates is bank work only while candidates are in a bank", function()
    local game = bagGame(function(w)
        w:put(0, 1, I.LINEN, 20)
        w:put(0, 2, I.VALUABLE_ORE, 20)   -- auction candidate, already in the bags
    end)
    game:db().prices = { ["c:" .. I.VALUABLE_ORE] = { price = 500000, at = game.env.time() } }
    game:openBank()
    game:advance(9)
    local P = game:P()
    T.ok(P.FindTask("Auction Candidates"), "auction task available")
    local top = P.GetTopReadyCard()
    T.ok(top and top.name ~= "Auction Candidates", "the notice names real bank work")
    local cards, bankTasks = P.GetTaskCards(), 0
    for _, card in ipairs(cards) do
        if card.name == "Auction Candidates" then T.eq(card.bankWork, 0) end
        if not card.filterOnly and not card.task.count and not card.task.open and card.ready + card.waiting > 0 then
            local source, dest = P.GetTaskRoute(card.task)
            if P.NeedsBankStorage(source) or P.NeedsBankStorage(dest) then bankTasks = bankTasks + 1 end
        end
    end
    local plan = P.TripPlan(cards) or ""
    T.contains(plan, "here: bank (" .. bankTasks .. " task", "bags-only candidates aren't a bank task")
    T.contains(plan, "auction house (1 to list)")
end)

T.test("Deposit Old Items keeps items for a quest in progress in the bags", function()
    local game = bagGame(function(w)
        w:put(0, 1, I.LINEN, 20)
        w:put(0, 2, I.QUEST_START, 1)
        w.quests.active[90001] = true
    end)
    game:openBank()
    local P = game:P()
    local names = {}
    for _, plan in ipairs(P.GetTaskPlans(P.FindTask("Deposit Old Items"))) do names[plan.item.itemID] = true end
    T.ok(names[I.LINEN])
    T.no(names[I.QUEST_START], "active quest item stays in the bags")
    game.world.quests.active[90001] = nil
    game:Core().ScanInventory("all", true)
    names = {}
    for _, plan in ipairs(P.GetTaskPlans(P.FindTask("Deposit Old Items"))) do names[plan.item.itemID] = true end
    T.ok(names[I.QUEST_START], "a quest not started yet can be banked (your call)")
end)

T.test("Consolidate Warbound Gear reads the character bank tabs and leaves out gear that can go", function()
    local game = bagGame(function(w)
        w:put(6, 1, I.OLD_SWORD, 1, { warboundUntilEquipped = true })   -- character bank: kept for an alt
        w:put(6, 2, I.BOUND_HELM, 1, { tooltipBinding = "warbound" })   -- character bank: appearance collected, can go
        w:put(6, 3, I.WARBOUND_TOY, 1)                                   -- character bank: Warbound, not gear
        w.collections.appearances[70002] = true
    end)
    game:P().SetCharacterRole("Main-R", "main")
    game:openBank()
    local P = game:P()
    local task = P.FindTask("Consolidate Warbound Gear")
    T.eq((P.GetTaskRoute(task)), P.STORAGE_ALL_BANK_TABS)
    local ids = {}
    for _, plan in ipairs(P.GetTaskPlans(task)) do ids[plan.item.itemID] = plan.item end
    T.ok(ids[I.OLD_SWORD], "Warbound-until-equipped gear kept for an alt is consolidated")
    T.no(ids[I.BOUND_HELM], "gear that can go is pulled to sell, not consolidated")
    T.no(ids[I.WARBOUND_TOY], "Warbound non-gear belongs to Deposit to Warband")
end)
