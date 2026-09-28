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

T.test("keep N, the rest go: duplicates and commodity stacks split per stack", function()
    -- Two copies of a sword, one better: keep 1 -> the higher item level stays, the other sells.
    local g = game(function(w)
        w:put(0, 1, I.OLD_SWORD, 1)
        w:put(0, 2, I.OLD_SWORD, 1)
    end)
    local P = g:P()
    g:slash("decide " .. I.OLD_SWORD .. " sell keep 1")
    g:Core().ScanInventory("bags", true)
    local copies = {}
    for _, it in ipairs(P.GetScanList("bags")) do if it.itemID == I.OLD_SWORD then copies[#copies + 1] = it end end
    T.eq(#copies, 2)
    local kept, sold = 0, 0
    for _, it in ipairs(copies) do
        local eff = P.EffectiveDecision(it)
        if eff.choice == "keep" then
            kept = kept + 1
            T.eq(P.ExplainScanned(it).primary.id, "decided_keep")
            T.no(P.CanGoAndSellable(it), "the kept copy stays")
        else
            sold = sold + 1
            T.eq(eff.choice, "sell")
            T.eq(P.ExplainScanned(it).primary.id, "decided_sell")
            T.ok(P.CanGoAndSellable(it), "the surplus copy goes")
        end
    end
    T.eq(kept, 1) T.eq(sold, 1)
    -- The kept copy stays kept when the surplus copy moves next to it (a pull into the bags).
    g = T.game({ player = PLAYER, setup = F.setup(function(w)
        w:put(0, 1, I.OLD_SWORD, 1)     -- bags
        w:put(6, 1, I.OLD_SWORD, 1)     -- bank
    end) })
    P = g:P()
    P.SetCharacterRole("Main-R", "main")
    g:openBank()
    g:Core().ScanInventory("all", true)
    g:slash("decide " .. I.OLD_SWORD .. " sell keep 1")
    local function surplusScopes()
        local out = {}
        for _, scope in ipairs({ "bags", "bank" }) do
            for _, it in ipairs(P.GetScanList(scope)) do
                if it.itemID == I.OLD_SWORD then out[scope] = P.EffectiveDecision(it).choice end
            end
        end
        return out
    end
    T.eq(surplusScopes().bank, "keep") T.eq(surplusScopes().bags, "sell", "gear: the banked copy is kept, the bag copy goes")
    -- The kept copy itself moves (pulled into the bags next to the surplus one): the GUID keeps it kept.
    local keptGUID = g.world.containers[6].slots[1].guid
    g.world.containers[6].slots[1] = nil
    g.world:put(0, 2, I.OLD_SWORD, 1, { guid = keptGUID })
    g:Core().ScanInventory("all", true)
    for _, it in ipairs(P.GetScanList("bags")) do
        if it.itemID == I.OLD_SWORD then
            T.eq(P.EffectiveDecision(it).choice, it.slot == 2 and "keep" or "sell", "slot " .. it.slot)
        end
    end
    -- Four stacks of 20 ore, keep 60 and auction the rest: exactly one stack is a candidate.
    g = game(function(w) for slot = 1, 4 do w:put(0, slot, I.VALUABLE_ORE, 20) end end)
    P = g:P()
    price(g, I.VALUABLE_ORE, 900000)
    g:slash("decide " .. I.VALUABLE_ORE .. " auction keep 60")
    g:Core().ScanInventory("bags", true)
    local candidates, keeps = 0, 0
    for _, it in ipairs(P.GetScanList("bags")) do
        if it.itemID == I.VALUABLE_ORE then
            if P.IsAuctionCandidate(it) then candidates = candidates + 1 else keeps = keeps + 1 end
        end
    end
    T.eq(candidates, 1) T.eq(keeps, 3)
    T.eq(P.GetDecision(I.VALUABLE_ORE).keepCount, 60)
    -- The paste parser understands the same form.
    local applied = P.ApplyDecisionLines("/icanteven decide " .. I.VALUABLE_ORE .. " auction keep 40   -- ore")
    T.eq(applied, 1) T.eq(P.GetDecision(I.VALUABLE_ORE).keepCount, 40)
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

-- In game (2026-09-28), five pasted "carry" lines answered "Unknown choice":
-- the screen's Carry is a keep with the note "carry", and the command
-- accepts the same word.
T.test("decide carry: keeps the item in the bags, like the screen's Carry", function()
    local g = game(function(w) w:put(0, 1, I.NEW_FLASK, 5) end)
    local P = g:P()
    T.contains(P.DecideCommand(I.NEW_FLASK .. " carry"), "-> carry (keep it in your bags)")
    g:Core().ScanInventory("bags", true)
    local e = P.ExplainScanned(scanned(g, I.NEW_FLASK))
    T.eq(e.primary.id, "decided_carry")
    T.eq(e.disposition, "keep")
    T.contains(P.DecideCommand("nonsense"), "carry|use")
end)

-- A plain Keep on gear lapses once nobody would upgrade with it (Minormer's
-- bags, 2026-09-28: 15 pieces kept as his upgrades sat there after he had
-- equipped the best). Off-spec gear and explicit keeps do not lapse.
local DRUID = { name = "Main", realm = "R", level = 90, classFile = "DRUID" }
local function druidGame(populate)
    local g = T.game({ player = DRUID, setup = function(w)
        F.defineItems(w)
        w:defineItem(8910, { name = "Agile Vest", classID = 4, subclassID = 2, quality = 3, equipLoc = "INVTYPE_CHEST",
            itemLevel = 250, requiredLevel = 80, bindType = 1, sellPrice = 100, expansionID = 11,
            stats = { ITEM_MOD_AGILITY_SHORT = 100 } })
        w:defineItem(8911, { name = "Wise Vest", classID = 4, subclassID = 2, quality = 3, equipLoc = "INVTYPE_CHEST",
            itemLevel = 250, requiredLevel = 80, bindType = 1, sellPrice = 100, expansionID = 11,
            stats = { ITEM_MOD_INTELLECT_SHORT = 100 } })
        w:defineItem(8912, { name = "Worn Agile Vest", classID = 4, subclassID = 2, quality = 3, equipLoc = "INVTYPE_CHEST",
            itemLevel = 220, requiredLevel = 80, bindType = 1, sellPrice = 100, expansionID = 11,
            stats = { ITEM_MOD_AGILITY_SHORT = 80 } })
        w.collections.appearances = w.collections.appearances or {}
        populate(w)
    end })
    g:P().SetCharacterRole("Main-R", "main")
    return g
end
local function wear(g, slot, itemID, level)
    g.world.equippedItems[slot], g.world.equipped[slot] = itemID, level
    g:P().RefreshEquipped()
    g:Core().ScanInventory("bags", true)
end

T.test("a plain keep on gear lapses once it is no longer an upgrade; keeping again settles it", function()
    local g = druidGame(function(w)
        w:put(0, 1, 8910, 1)
        w.equippedItems[5], w.equipped[5] = 8912, 220   -- wearing 220 Agility: the 250 vest is an upgrade
    end)
    local P = g:P()
    g:Core().ScanInventory("bags", true)
    T.contains(P.WhoBenefits(scanned(g, 8910)) or "", "Upgrade for you")
    P.SetDecision(8910, "keep", { note = "keepsake" })   -- the screen's plain Keep
    g:Core().ScanInventory("bags", true)
    T.eq(P.ExplainScanned(scanned(g, 8910)).primary.id, "decided_keep")
    -- The player equips something better: the keep lapses and asks again.
    wear(g, 5, 8910, 250)
    local e = P.ExplainScanned(scanned(g, 8910))
    T.eq(e.primary.id, "decision_lapsed")
    T.eq(e.disposition, "review")
    T.contains(e.evidence, "nobody would upgrade with it now")
    -- Keeping it again is an answer: it stays kept.
    T.contains(P.DecideCommand("8910 keep"), "Decided:")
    g:Core().ScanInventory("bags", true)
    T.eq(P.ExplainScanned(scanned(g, 8910)).primary.id, "decided_keep")
    T.ok(P.GetDecision(8910).reaffirmed, "reaffirmed")
end)

T.test("off-spec gear and explicit keeps never lapse", function()
    -- Wearing Agility at 300; an Intellect vest at 250 is off-spec, not outgrown.
    local g = druidGame(function(w)
        w:put(0, 1, 8911, 1)
        w:put(0, 2, 8910, 1)
        w.equippedItems[5], w.equipped[5] = 8912, 300
    end)
    local P = g:P()
    P.SetDecision(8911, "keep")
    P.SetDecision(8910, "keep", { note = "for a Guardian set" })
    g:Core().ScanInventory("bags", true)
    T.eq(P.ExplainScanned(scanned(g, 8911)).primary.id, "decided_keep", "off-spec Intellect vest stays kept")
    T.eq(P.ExplainScanned(scanned(g, 8910)).primary.id, "decided_keep", "a keep with a note stays kept")
    T.no(P.KeepLapsed(scanned(g, 8911), P.GetDecision(8911)))
    -- The same Agility vest with a plain keep would lapse.
    P.SetDecision(8910, "keep")
    g:Core().ScanInventory("bags", true)
    T.eq(P.ExplainScanned(scanned(g, 8910)).primary.id, "decision_lapsed")
end)

-- In game (2026-09-28) two off-hand pieces read "Upgrade for Minormer": his
-- off-hand slot is empty because he wields a staff.
T.test("an off-hand piece is no upgrade next to a two-hander, and its plain keep lapses", function()
    local g = druidGame(function(w)
        w:defineItem(8920, { name = "Staff of Testing", classID = 2, subclassID = 10, quality = 3, equipLoc = "INVTYPE_2HWEAPON",
            itemLevel = 250, requiredLevel = 80, bindType = 1, sellPrice = 100, expansionID = 11,
            stats = { ITEM_MOD_INTELLECT_SHORT = 100 } })
        w:defineItem(8921, { name = "Dawnlit Beacon", classID = 4, subclassID = 0, quality = 2, equipLoc = "INVTYPE_HOLDABLE",
            itemLevel = 192, requiredLevel = 80, bindType = 2, sellPrice = 100, expansionID = 11,
            stats = { ITEM_MOD_INTELLECT_SHORT = 50 } })
        w:put(0, 1, 8921, 1)
        w.equippedItems[16], w.equipped[16] = 8920, 250
    end)
    local P = g:P()
    P.RefreshEquipped()
    g:Core().ScanInventory("bags", true)
    T.ok(P.GetCurrentCharacter().twoHander, "the staff is recorded")
    T.no((P.WhoBenefits(scanned(g, 8921)) or ""):find("Upgrade for you", 1, true), "not an upgrade")
    P.SetDecision(8921, "keep")
    g:Core().ScanInventory("bags", true)
    T.eq(P.ExplainScanned(scanned(g, 8921)).primary.id, "decision_lapsed")
    -- The Transfer upgrade filter agrees: once deposited, the beacon is not
    -- offered back by Pull Bank Upgrades.
    g.world:addBankTab(0, 6, "Main", 0, 20)
    g.world:addBankTab(2, 12, "Tab 1", 0, 5)
    g.world:put(12, 1, 8921, 1)
    g:openBank()
    for _, c in ipairs(P.GetTaskCards()) do
        if c.name == "Pull Bank Upgrades" then T.eq(c.ready, 0, "no off-hand upgrade under a staff") end
    end
end)

-- In game (2026-09-28) a level 83 Hunter's bags and bank read "Upgrade for
-- Dorftastic" on ranged weapons down to item level 13: ranged weapons were
-- mapped to the removed ranged slot (18), never recorded, so level 0.
T.test("ranged weapons compare against the main hand (the ranged slot is gone)", function()
    local HUNTER = { name = "Main", realm = "R", level = 83, classFile = "HUNTER" }
    local g = T.game({ player = HUNTER, setup = function(w)
        F.defineItems(w)
        w:defineItem(9301, { name = "Worn Bow", classID = 2, subclassID = 2, quality = 3, equipLoc = "INVTYPE_RANGED",
            itemLevel = 139, requiredLevel = 70, bindType = 1, sellPrice = 100, expansionID = 11,
            stats = { ITEM_MOD_AGILITY_SHORT = 50 } })
        w:defineItem(9302, { name = "Old Crossbow", classID = 2, subclassID = 18, quality = 4, equipLoc = "INVTYPE_RANGEDRIGHT",
            itemLevel = 15, requiredLevel = 10, bindType = 1, sellPrice = 100, expansionID = 3,
            stats = { ITEM_MOD_AGILITY_SHORT = 5 } })
        w:defineItem(9303, { name = "Better Gun", classID = 2, subclassID = 3, quality = 3, equipLoc = "INVTYPE_RANGEDRIGHT",
            itemLevel = 160, requiredLevel = 70, bindType = 1, sellPrice = 100, expansionID = 11,
            stats = { ITEM_MOD_AGILITY_SHORT = 60 } })
        w:put(0, 1, 9302, 1)
        w:put(0, 2, 9303, 1)
        w.equippedItems[16], w.equipped[16] = 9301, 139
    end })
    local P = g:P()
    P.SetCharacterRole("Main-R", "leveling")
    P.RefreshEquipped()
    g:Core().ScanInventory("bags", true)
    T.ok(P.GetCurrentCharacter().twoHander, "a bow fills both hands")
    T.no((P.WhoBenefits(scanned(g, 9302)) or ""):find("Upgrade", 1, true), "item level 15 is no upgrade over 139")
    T.contains(P.WhoBenefits(scanned(g, 9303)) or "", "Upgrade for you")
end)

-- In game (Dorftastic, level 83 Hunter wearing 139, 2026-09-28) item level 15
-- Firelands epics stayed "your call": set pieces ("costs 130 item levels in
-- that slot") and bows (weapons were never outgrown).
T.test("gear far below what its wearers use is outgrown, set piece or weapon", function()
    local HUNTER = { name = "Main", realm = "R", level = 83, classFile = "HUNTER" }
    local g = T.game({ player = HUNTER, setup = function(w)
        F.defineItems(w)
        w:defineItem(9401, { name = "Worn Bow", classID = 2, subclassID = 2, quality = 3, equipLoc = "INVTYPE_RANGED",
            itemLevel = 139, requiredLevel = 70, bindType = 1, sellPrice = 100, expansionID = 11,
            stats = { ITEM_MOD_AGILITY_SHORT = 50 } })
        w:defineItem(9402, { name = "Ancient Epic Bow", classID = 2, subclassID = 2, quality = 4, equipLoc = "INVTYPE_RANGED",
            itemLevel = 15, requiredLevel = 10, bindType = 1, sellPrice = 300, expansionID = 3,
            stats = { ITEM_MOD_AGILITY_SHORT = 5 } })
        w:defineItem(9403, { name = "Nearly As Good Bow", classID = 2, subclassID = 2, quality = 3, equipLoc = "INVTYPE_RANGED",
            itemLevel = 130, requiredLevel = 70, bindType = 1, sellPrice = 100, expansionID = 11,
            stats = { ITEM_MOD_AGILITY_SHORT = 45 } })
        w:put(0, 1, 9402, 1)
        w:put(0, 2, 9403, 1)
        w.equippedItems[16], w.equipped[16] = 9401, 139
    end })
    local P = g:P()
    P.SetCharacterRole("Main-R", "leveling")
    P.RefreshEquipped()
    g:Core().ScanInventory("bags", true)
    local e = P.ExplainScanned(scanned(g, 9402))
    T.eq(e.primary.id, "outgrown_no_upgrade", "item level 15 against 139 can go")
    T.contains(e.evidence, "far below")
    T.ok(P.ExplainScanned(scanned(g, 9403)).primary.id ~= "outgrown_no_upgrade",
        "a weapon close to the worn one stays your call")
end)
