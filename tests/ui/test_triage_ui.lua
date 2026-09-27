local T = ...
local F = require("fixtures")
local I = F.ITEMS

-- The triage screen (TriageUI.lua), the Destroy card, and the materials task.
local PLAYER = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" }

local function game(populate, prices)
    local g = T.game({ player = PLAYER, setup = F.setup(populate) })
    g:P().SetCharacterRole("Main-R", "main")
    local db = g:db()
    db.prices = db.prices or {}
    for itemID, price in pairs(prices or {}) do
        local key = g.world.items[itemID].maxStack > 1 and ("c:" .. itemID) or ("i:" .. itemID .. ":" .. g.env.GetRealmName())
        db.prices[key] = { price = price, at = g.env.time() }
    end
    g:Core().ScanInventory("bags", true)
    return g
end

local function scanned(g, itemID, scope)
    for _, it in ipairs(g:P().GetScanList(scope or "bags")) do if it.itemID == itemID then return it end end
    error("not scanned: " .. tostring(itemID))
end

T.test("queue: location order, stacks grouped, decided items skipped, progress counted", function()
    local g = game(function(w)
        w:put(0, 3, I.LINEN, 20)
        w:put(0, 1, I.OLD_POTION, 5)
        w:put(0, 2, I.OLD_POTION, 5)
        w:put(0, 4, I.OLD_SWORD, 1)
    end)
    local P = g:P()
    local queue = P.BuildTriageQueue("bags")
    T.eq(#queue, 3, "two potion stacks are one entry")
    T.eq(queue[1].item.itemID, I.OLD_POTION) T.eq(queue[1].count, 10) T.eq(queue[1].stacks, 2)
    T.eq(queue[2].item.itemID, I.LINEN)
    P.SetDecision(I.LINEN, "keep")
    queue = P.BuildTriageQueue("bags")
    T.eq(#queue, 2, "decided items skipped")
    local total, decided = P.TriageProgress("bags")
    T.eq(total, 3) T.eq(decided, 1)
    T.eq(#P.BuildTriageQueue("bags", true), 3, "review includes decided")
end)

T.test("options follow the channels; the recommendation follows the rules and the verdict", function()
    local g = game(function(w)
        w:put(0, 1, I.BOUND_HELM, 1, { bound = true })     -- soulbound, appearance not collected: keep
        w:put(0, 2, I.VALUABLE_ORE, 20)                    -- old ore, priced well: auction
        w:put(0, 3, I.QUEST_START, 1)                      -- quest starter: use
        w:put(0, 4, I.WARBOUND_TOY, 1)                     -- Warbound: never auction
    end, { [I.VALUABLE_ORE] = 900000 })
    local P = g:P()
    local helm = P.TriageOptions(scanned(g, I.BOUND_HELM))
    T.eq(helm.auction, false) T.contains(helm.why.auction, "Soulbound")
    T.eq(helm.sell, true) T.eq(helm.recommended, "keep")
    T.eq(helm.confirm.sell, nil, "an uncollected appearance is a keep verdict, not a rule: no confirm")
    g:db().rules.items[I.BOUND_HELM] = { protect = true }
    g:Core().ScanInventory("bags", true)
    helm = P.TriageOptions(scanned(g, I.BOUND_HELM))
    T.ok(helm.confirm.sell, "selling a protected item asks first")
    T.eq(helm.destroy, false, "Protect closes destroy")
    local ore = P.TriageOptions(scanned(g, I.VALUABLE_ORE))
    T.eq(ore.auction, true) T.eq(ore.recommended, "auction")
    local quest = P.TriageOptions(scanned(g, I.QUEST_START))
    T.eq(quest.use, true) T.eq(quest.sell, false) T.eq(quest.destroy, true)
    local toy = P.TriageOptions(scanned(g, I.WARBOUND_TOY))
    T.eq(toy.auction, false) T.contains(toy.why.auction, "Warbound")
end)

T.test("the screen: shows the item, Wowhead boxes, records decisions, confirms destroy on uncommon+", function()
    local g = game(function(w)
        w:put(0, 1, I.QUEST_START, 1)
        w:put(0, 2, I.OLD_SWORD, 1)     -- quality 3
    end, { [I.OLD_SWORD] = 900000 })
    local P = g:P()
    local frame = P.ShowTriage("bags")
    T.ok(frame:IsShown())
    T.contains(frame.title:GetText(), "Bags: 1 of 2")
    T.eq(frame.wowheadItem:GetText(), "https://www.wowhead.com/item=" .. I.QUEST_START)
    T.eq(frame.wowheadQuest:GetText(), "https://www.wowhead.com/quest=90001")
    T.ok(frame.buttons.use:IsEnabled()) T.no(frame.buttons.sell:IsEnabled(), "no vendor price")
    g:click(frame.buttons.destroy)    -- quest item, common quality: no confirm
    T.eq(P.GetDecision(I.QUEST_START).choice, "destroy")
    T.contains(frame.title:GetText(), "2 of 2")
    g:click(frame.buttons.destroy)    -- rare sword: first click asks
    T.eq(P.GetDecision(I.OLD_SWORD), nil, "not yet")
    T.contains(frame.confirmNote:GetText(), "Click again to confirm")
    g:click(frame.buttons.destroy)
    T.eq(P.GetDecision(I.OLD_SWORD).choice, "destroy")
    T.contains(frame.summary:GetText(), "2 destroy")
    T.contains(frame.title:GetText(), "Done")
end)

T.test("the screen: prices cover every stack of the item, with the unit price alongside", function()
    local g = game(function(w)
        w:put(0, 1, I.VALUABLE_ORE, 20)
        w:put(0, 2, I.VALUABLE_ORE, 10)
    end, { [I.VALUABLE_ORE] = 900000 })
    local P = g:P()
    local frame = P.ShowTriage("bags")
    local each = g.world.items[I.VALUABLE_ORE].sellPrice or 0
    T.contains(frame.can:GetText(), "for 30 (")
    T.contains(frame.can:GetText(), P.FormatMoney(each * 30) .. " for 30")
    T.contains(frame.buttons.sell:GetText(), P.FormatMoney(each * 30))
    local listing = P.ListingPrice(scanned(g, I.VALUABLE_ORE))
    T.contains(frame.buttons.auction:GetText(), P.FormatMoney(listing * 30))
end)

T.test("the screen: Leave puts the item at the end; Carry stores keep+carry; Previous goes back", function()
    local g = game(function(w)
        w:put(0, 1, I.LINEN, 20)
        w:put(0, 2, I.OLD_POTION, 5)
    end)
    local P = g:P()
    local frame = P.ShowTriage("bags")
    T.contains(frame.name:GetText(), g.world.items[I.LINEN].name)
    g:click(frame.buttons.leave)
    T.contains(frame.name:GetText(), g.world.items[I.OLD_POTION].name, "next item; linen moved to the end")
    g:click(frame.buttons.carry)
    T.eq(P.GetDecision(I.OLD_POTION).note, "carry")
    T.contains(frame.name:GetText(), g.world.items[I.LINEN].name, "linen comes back at the end")
    g:click(frame.prev)
    T.contains(frame.name:GetText(), g.world.items[I.OLD_POTION].name)
    T.contains(frame.previousDecision:GetText(), "keep")
end)

T.test("the screen is a bordered window like the console; its title-bar close stops the session", function()
    local g = game(function(w) w:put(0, 1, I.LINEN, 20) end)
    local P = g:P()
    local frame = P.ShowTriage("bags")
    T.ok(frame.TitleBg and frame.CloseButton, "built from the bordered window template")
    T.eq(frame.windowTitle:GetText(), "Justify every item")
    T.ok(frame:GetHeight() >= 460, "tall enough for content below the title bar")
    g:click(frame.CloseButton)
    T.no(frame:IsShown())
    local listed = false
    for _, name in ipairs(g.env.UISpecialFrames) do if name == "ICantEvenTriageFrame" then listed = true end end
    T.ok(listed, "Escape closes it like any game window")
    -- Enter records nothing: it is also the chat key.
    frame = P.ShowTriage("bags")
    frame:GetScript("OnKeyDown")(frame, "ENTER")
    T.eq(P.GetDecision(I.LINEN), nil, "Enter is not a choice")
    T.ok(frame:IsShown())
    -- Hiding it from outside (Escape) ends the run.
    frame:Hide()
    frame = P.ShowTriage()
    T.contains(frame.title:GetText(), "Justify every item", "reopened without a scope: the run ended, pick again")
end)

T.test("Home card 'Justify every item' counts what's left and opens the screen", function()
    local g = game(function(w) w:put(0, 1, I.LINEN, 20) w:put(0, 2, I.OLD_POTION, 5) end)
    local P = g:P()
    local card
    for _, c in ipairs(P.GetTaskCards()) do if c.name == "Justify every item" then card = c end end
    T.ok(card, "card present")
    T.eq(card.ready, 2)
    T.contains(card.summaryText, "0 of 2 decided")
    P.SetDecision(I.LINEN, "keep")
    for _, c in ipairs(P.GetTaskCards()) do if c.name == "Justify every item" then card = c end end
    T.eq(card.ready, 1)
    T.ok(P.OpenTask("Justify every item"))
    T.ok(P.TriageFrame():IsShown())
end)

T.test("Destroy Decided Items: bags only, one per click, DeleteCursorItem from the click; pulls include decided-destroy bank items", function()
    local g = game(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
        w:put(0, 2, I.LINEN, 20)
        w:put(6, 1, I.JUNK, 1)
    end)
    local P = g:P()
    P.SetDecision(I.OLD_POTION, "destroy")
    P.SetDecision(I.LINEN, "destroy")
    P.SetDecision(I.JUNK, "destroy")
    g:Core().ScanInventory("bags", true)
    local card
    for _, c in ipairs(P.GetTaskCards()) do if c.name == "Destroy Decided Items" then card = c end end
    T.eq(card.ready, 2)
    g:slash("transfer")
    local UI = g:UI()
    UI.transferSource, UI.transferDest = "Bags", P.STORAGE_DESTROY
    P.ResetTabFilters("Transfer")
    g:Core().RefreshUI()
    g.world:advance(9)
    g:Core().RefreshUI()
    local panel = UI.frame.panels.Transfer
    g:click(panel.selectAll)
    T.eq(panel.execute:GetText(), "Destroy 1 of 2")
    g:click(panel.execute)
    T.eq(#g.world.destroyed, 1, "one per click")
    T.eq(g.world.cursor, nil, "nothing left on the cursor")
    g:Core().RefreshUI()
    T.eq(panel.execute:GetText(), "Destroy 1")
    g:click(panel.execute)
    T.eq(#g.world.destroyed, 2)
    -- The banked one is offered by Pull Items That Can Go.
    g:openBank()
    local ids = {}
    for _, plan in ipairs(P.GetTaskPlans(P.FindTask("Pull Items That Can Go"))) do ids[plan.item.itemID] = true end
    T.ok(ids[I.JUNK], "decided-destroy bank item is pulled")
end)

T.test("Move Materials to Warband: crafter materials from the character bank to the Warband bank", function()
    local g = T.game({ player = PLAYER, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        w:addBankTab(2, 12, "Tab 1", 0, 20)
        w:put(6, 1, I.LINEN, 40)         -- Tailoring cloth
        w:put(6, 2, I.OLD_SWORD, 1)      -- gear, not a material
    end })
    local P = g:P()
    P.SetCharacterRole("Main-R", "main")
    P.SetCharacterRole("Stitchalt-R", "crafter")
    local alt = g:db().characters["Stitchalt-R"] or {}
    g:db().characters["Stitchalt-R"] = alt
    alt.name, alt.key, alt.role = "Stitchalt", "Stitchalt-R", alt.role or "crafter"
    alt.professions = { { name = "Tailoring", skillLine = 197 } }
    g:openBank()
    g:Core().ScanInventory("all", true)
    local task = P.FindTask("Move Materials to Warband")
    T.ok(task, "task registered")
    local ids = {}
    for _, plan in ipairs(P.GetTaskPlans(task)) do ids[plan.item.itemID] = true end
    T.ok(ids[I.LINEN], "linen a crafter uses is offered")
    T.no(ids[I.OLD_SWORD], "gear is not")
end)
