local T = ...
local F = require("fixtures")
local I = F.ITEMS

-- Triage decisions (Triage.lua): stored preferences every task reads.
local PLAYER = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" }

local function game(populate, opts)
    local o = { player = PLAYER, setup = F.setup(populate) }
    for k, v in pairs(opts or {}) do o[k] = v end
    local g = T.game(o)
    g:P().SetCharacterRole("Main-R", "main")
    g:Core().ScanInventory("bags", true)
    return g
end

local function scanned(g, itemID, scope)
    for _, it in ipairs(g:P().GetScanList(scope or "bags")) do if it.itemID == itemID then return it end end
    error("not scanned: " .. tostring(itemID))
end

local function price(g, itemID, copper)
    local def = g.world.items[itemID]
    local key = def.maxStack > 1 and ("c:" .. itemID) or ("i:" .. itemID .. ":" .. g.env.GetRealmName())
    g:db().prices = g:db().prices or {}
    g:db().prices[key] = { price = copper, at = g.env.time() }
end

T.test("decisions: set, read, clear; a defer runs out after the setting's days", function()
    local g = game(function(w) w:put(0, 1, I.OLD_SWORD, 1) end)
    local P = g:P()
    T.eq(P.GetDecision(I.OLD_SWORD), nil)
    local record = P.SetDecision(I.OLD_SWORD, "sell", { name = "Old Sword" })
    T.eq(record.choice, "sell")
    T.eq(P.GetDecision(I.OLD_SWORD).choice, "sell")
    T.eq(select(2, P.SetDecision(I.OLD_SWORD, "eat")), "Unknown choice: eat")
    P.SetDecision(I.OLD_SWORD, "defer")
    T.no(P.GetDecision(I.OLD_SWORD).due)
    g.world:advance(31 * 24 * 3600)
    T.ok(P.GetDecision(I.OLD_SWORD).due, "due after 30 days")
    T.ok(P.ClearDecision(I.OLD_SWORD))
    T.eq(P.GetDecision(I.OLD_SWORD), nil)
end)

T.test("decide sell: the item can go to a vendor whatever its auction price, no price-first nag", function()
    local g = game(function(w) w:put(0, 1, I.OLD_SWORD, 1) end)
    local P = g:P()
    price(g, I.OLD_SWORD, 5000000)   -- 500g at auction
    g:Core().ScanInventory("bags", true)
    local sword = scanned(g, I.OLD_SWORD)
    T.ok(P.IsValueFlagged(sword, "Vendor"), "protected from the vendor before the decision")
    P.SetDecision(I.OLD_SWORD, "sell")
    g:Core().ScanInventory("bags", true)
    sword = scanned(g, I.OLD_SWORD)
    local e = P.ExplainScanned(sword)
    T.eq(e.primary.id, "decided_sell")
    T.eq(e.disposition, "free")
    T.no(P.IsValueFlagged(sword, "Vendor"))
    T.no(P.NeedsPriceCheck(sword))
    T.no(P.IsAuctionCandidate(sword), "not an auction candidate any more")
    T.ok(P.CanGoAndSellable(sword))
end)

T.test("a sell decision the vendor refuses asks again: review verdict, back in the triage queue", function()
    local g = game(function(w) w:put(0, 1, I.OLD_SWORD, 1) end)
    local P = g:P()
    P.SetDecision(I.OLD_SWORD, "sell")
    g:db().vendorRefused = { [I.OLD_SWORD] = { name = "Old Sword", reason = "The merchant doesn't want that item.", at = 1 } }
    g:Core().ScanInventory("bags", true)
    local e = P.ExplainScanned(scanned(g, I.OLD_SWORD))
    T.eq(e.primary.id, "decision_blocked") T.contains(e.evidence, "vendors won't buy it")
    T.eq(e.disposition, "review")
    T.no(P.CanGoAndSellable(scanned(g, I.OLD_SWORD)))
    T.eq(#P.BuildTriageQueue("bags"), 1, "needs a new decision")
    g:openBank()
    local ids = {}
    for _, plan in ipairs(P.GetTaskPlans(P.FindTask("Deposit Old Items"))) do ids[plan.item.itemID] = true end
    T.no(ids[I.OLD_SWORD], "not offered for deposit while the question is open")
    local frame = P.ShowTriage("bags")
    T.contains(frame.previousDecision:GetText(), "not possible")
end)

T.test("decide auction: a candidate despite a keep reason; never offered to the vendor", function()
    local g = game(function(w) w:put(0, 1, I.NEW_FLASK, 5) end)   -- current expansion: kept by default
    local P = g:P()
    price(g, I.NEW_FLASK, 100000)
    g:Core().ScanInventory("bags", true)
    T.no(P.IsAuctionCandidate(scanned(g, I.NEW_FLASK)))
    P.SetDecision(I.NEW_FLASK, "auction")
    g:Core().ScanInventory("bags", true)
    local flask = scanned(g, I.NEW_FLASK)
    T.eq(P.ExplainScanned(flask).primary.id, "decided_auction")
    T.ok(P.IsAuctionCandidate(flask))
    T.no(P.CanGoAndSellable(flask), "not for the vendor")
    -- Binding still wins: a soulbound item can't become a candidate by decision.
    g.world:put(0, 2, I.BOUND_HELM, 1, { bound = true })
    P.SetDecision(I.BOUND_HELM, "auction")
    g:Core().ScanInventory("bags", true)
    T.no(P.IsAuctionCandidate(scanned(g, I.BOUND_HELM)))
end)

T.test("decide destroy / keep / use: the verdict follows the decision", function()
    local g = game(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
        w:put(0, 2, I.LINEN, 20)
        w:put(0, 3, I.QUEST_START, 1)
    end)
    local P = g:P()
    P.SetDecision(I.OLD_POTION, "destroy")
    P.SetDecision(I.LINEN, "keep", { reason = "for a future alt" })
    P.SetDecision(I.QUEST_START, "use")
    g:Core().ScanInventory("bags", true)
    local potion = P.ExplainScanned(scanned(g, I.OLD_POTION))
    T.eq(potion.primary.id, "decided_destroy")
    T.no(P.CanGoAndSellable(scanned(g, I.OLD_POTION)), "destroy, not sell")
    local linen = P.ExplainScanned(scanned(g, I.LINEN))
    T.eq(linen.primary.id, "decided_keep") T.contains(linen.evidence, "future alt")
    T.eq(P.ExplainScanned(scanned(g, I.QUEST_START)).primary.id, "decided_use")
    -- A deposit task doesn't offer items decided out.
    g:openBank()
    local ids = {}
    for _, plan in ipairs(P.GetTaskPlans(P.FindTask("Deposit Old Items"))) do ids[plan.item.itemID] = true end
    T.no(ids[I.OLD_POTION], "headed out (destroy)")
    T.ok(ids[I.LINEN], "kept material still deposits")
end)

T.test("a deferred item is quiet until the date, then asks again", function()
    local g = game(function(w) w:put(0, 1, I.OLD_SWORD, 1) end)
    local P = g:P()
    P.SetDecision(I.OLD_SWORD, "defer", { days = 10 })
    g:Core().ScanInventory("bags", true)
    T.eq(P.ExplainScanned(scanned(g, I.OLD_SWORD)).primary.id, "decided_defer")
    g.world:advance(11 * 24 * 3600)
    g:Core().ScanInventory("bags", true)
    local e = P.ExplainScanned(scanned(g, I.OLD_SWORD))
    T.eq(e.primary.id, "decision_due")
    T.eq(e.disposition, "review")
end)

T.test("decisions to sell/auction/destroy are dropped once the item is gone for two scans two minutes apart; keep stays", function()
    local g = game(function(w) w:put(0, 1, I.OLD_SWORD, 1) w:put(0, 2, I.LINEN, 20) end)
    local P = g:P()
    P.SetDecision(I.OLD_SWORD, "sell")
    P.SetDecision(I.LINEN, "keep")
    local sword = g.world.containers[0].slots[1]
    g.world.containers[0].slots[1] = nil   -- in transit (or sold)
    g:Core().ScanInventory("bags", true)
    T.eq(P.GetDecision(I.OLD_SWORD).choice, "sell", "one missing scan is not enough: a pull in progress looks the same")
    -- It comes back (the move settled): the clock resets.
    g.world.containers[0].slots[1] = sword
    g:Core().ScanInventory("bags", true)
    T.eq(P.GetDecision(I.OLD_SWORD).missingSince, nil)
    g.world.containers[0].slots[1] = nil   -- sold for real
    g:Core().ScanInventory("bags", true)
    g.world:advance(60)
    g:Core().ScanInventory("bags", true)
    T.eq(P.GetDecision(I.OLD_SWORD).choice, "sell", "still within the grace period")
    g.world:advance(90)
    g:Core().ScanInventory("bags", true)
    T.eq(P.GetDecision(I.OLD_SWORD), nil, "swept after two minutes gone")
    T.eq(P.GetDecision(I.LINEN).choice, "keep")
end)

T.test("channels: destroy is closed by Protect; use exists for an unlearned collectible or an unstarted quest", function()
    local g = game(function(w)
        w:put(0, 1, I.QUEST_START, 1)
        w:put(0, 2, I.OLD_SWORD, 1)
    end)
    local P = g:P()
    g:db().rules.items[I.OLD_SWORD] = { protect = true }
    g:Core().ScanInventory("bags", true)
    local quest = P.ItemChannels(scanned(g, I.QUEST_START))
    T.eq(quest.use, true) T.contains(quest.useWhat, "start the quest")
    T.eq(quest.destroy, true)
    local sword = P.ItemChannels(scanned(g, I.OLD_SWORD))
    T.eq(sword.destroy, false) T.contains(sword.why.destroy, "Protected")
    T.eq(sword.use, false)
end)

T.test("/icanteven export writes the classified inventory to the saved data; /icanteven decide feeds a decision back", function()
    local g = game(function(w)
        w:put(0, 1, I.OLD_SWORD, 1)
        w:put(0, 2, I.QUEST_START, 1)
    end)
    local P = g:P()
    price(g, I.OLD_SWORD, 900000)
    g:Core().ScanInventory("bags", true)
    local mark = g:logMark()
    g:slash("export bags")
    T.contains(g:printed(mark), "Exported 2 item(s)")
    local export = g:db().export
    T.eq(export.scope, "bags")
    T.eq(#export.items, 2)
    local byID = {}
    for _, rec in ipairs(export.items) do byID[rec.itemID] = rec end
    local sword = byID[I.OLD_SWORD]
    T.eq(sword.name, g.world.items[I.OLD_SWORD].name) T.eq(sword.scope, "bags") T.eq(sword.binding, "BoE")
    T.ok(sword.primary and sword.disposition, "verdict exported")
    T.eq(sword.channels.auction, true)
    T.eq(sword.auctionPrice, 900000)
    T.eq(sword.wowhead, "https://www.wowhead.com/item=" .. I.OLD_SWORD)
    T.eq(byID[I.QUEST_START].wowheadQuest, "https://www.wowhead.com/quest=90001")
    mark = g:logMark()
    g:slash("decide " .. I.OLD_SWORD .. " sell")
    T.contains(g:printed(mark), "Decided: " .. g.world.items[I.OLD_SWORD].name .. " -> sell")
    T.eq(P.GetDecision(I.OLD_SWORD).choice, "sell")
    g:slash("decide " .. I.OLD_SWORD .. " defer 5")
    T.contains(g:printed(g:logMark() - 1), "until")
    g:slash("decide " .. I.OLD_SWORD .. " clear")
    T.eq(P.GetDecision(I.OLD_SWORD), nil)
end)

T.test("migration to schema 3 adds the decisions table to an old save", function()
    local S = require("fixtures.saves")
    local g = T.game({ player = PLAYER, savedVariables = S.v050() })
    T.eq(g:db().schemaVersion, g:P().SCHEMA_VERSION)
    T.eq(type(g:db().decisions), "table")
end)

T.test("decide keep with the note 'carry' keeps the item out of every deposit task", function()
    local g = game(function(w) w:put(0, 1, I.LINEN, 20) w:put(0, 2, I.OLD_POTION, 5) end)
    local P = g:P()
    g:slash("decide " .. I.LINEN .. " keep carry")
    g:openBank()
    local ids = {}
    for _, plan in ipairs(P.GetTaskPlans(P.FindTask("Deposit Old Items"))) do ids[plan.item.itemID] = true end
    T.no(ids[I.LINEN], "carried: not deposited")
    T.eq(P.ExplainScanned(scanned(g, I.LINEN)).primary.id, "decided_carry")
end)

T.test("decision lines paste: exported lines apply as-is, comments and bad lines are reported", function()
    local g = game(function(w) w:put(0, 1, I.OLD_SWORD, 1) w:put(0, 2, I.LINEN, 20) end)
    local P = g:P()
    local text = table.concat({
        "/icanteven decide " .. I.OLD_SWORD .. " sell   -- Old Sword x1",
        I.LINEN .. " keep carry",
        "",
        "abc nonsense",
        "12345 eat",
    }, "\n")
    local applied, skipped, messages = P.ApplyDecisionLines(text)
    T.eq(applied, 2) T.eq(skipped, 2)
    T.eq(P.GetDecision(I.OLD_SWORD).choice, "sell")
    T.eq(P.GetDecision(I.LINEN).note, "carry")
    T.contains(messages[1], "Usage")
end)
