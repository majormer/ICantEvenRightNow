local T = ...
local F = require("fixtures")
local I = F.ITEMS

local MAGE = { name = "Mage", realm = "R", level = 90, classFile = "MAGE", className = "Mage",
    professions = { { name = "Tailoring", skillLine = 197 } } }

local function explain(game, itemID, locationKey)
    local P = game:P()
    game:Core().ScanInventory("bags", true)
    for _, item in ipairs(P.GetScanList("bags")) do
        if item.itemID == itemID then return P.ExplainItem(item, { locationKey = locationKey }) end
    end
    error("item not scanned: " .. tostring(itemID))
end

local function mageWith(populate, extra)
    local game = T.game({ player = MAGE, setup = function(w)
        F.defineItems(w)
        F.addBank(w)
        if extra then extra(w) end
        populate(w)
    end })
    game:P().SetCharacterRole("Mage-R", "main")
    return game
end

T.test("plate helm with collected appearance: can go when no played character wears plate", function()
    local game = mageWith(function(w)
        w:put(0, 1, I.BOUND_HELM, 1, { bound = true })
        w.collections.appearances[70002] = true
    end)
    local e = explain(game, I.BOUND_HELM)
    T.eq(e.primary.id, "appearance_collected")
    T.eq(e.disposition, "free")
end)

T.test("uncollected appearance is a reason to keep", function()
    local game = mageWith(function(w) w:put(0, 1, I.BOUND_HELM, 1, { bound = true }) end)
    local e = explain(game, I.BOUND_HELM)
    T.eq(e.disposition, "keep")
    T.eq(e.primary.id, "appearance_uncollected")
end)

T.test("gear is never 'free' before any roles are assigned", function()
    local game = T.game({ player = MAGE, setup = F.setup(function(w)
        w:put(0, 1, I.BOUND_HELM, 1, { bound = true })
        w.collections.appearances[70002] = true
    end) })
    local e = explain(game, I.BOUND_HELM)
    T.eq(e.primary.id, "roles_needed")
    T.eq(e.disposition, "review")
end)

T.test("quest starter status: completed, active, not started", function()
    local game = mageWith(function(w)
        w:put(0, 1, I.QUEST_START, 1)
        w.quests.completed[90001] = true
    end)
    T.eq(explain(game, I.QUEST_START).primary.id, "quest_done")

    game = mageWith(function(w)
        w:put(0, 1, I.QUEST_START, 1)
        w.quests.active[90001] = true
    end)
    T.eq(explain(game, I.QUEST_START).primary.id, "quest_active")

    game = mageWith(function(w) w:put(0, 1, I.QUEST_START, 1) end)
    local e = explain(game, I.QUEST_START)
    T.eq(e.primary.id, "quest_not_started")
    T.contains(e.evidence, "Wrath of the Lich King")
end)

T.test("toys: unlearned means keep, learned means it can go", function()
    local function toyGame(learned)
        return mageWith(function(w)
            w:put(0, 1, 7001, 1)
            if learned then w.collections.toys[7001] = true end
        end, function(w) w:defineItem(7001, { name = "Toy Thing", classID = 15, isToy = true }) end)
    end
    T.eq(explain(toyGame(false), 7001).primary.id, "collectible_unlearned")
    T.eq(explain(toyGame(true), 7001).primary.id, "collectible_learned")
end)

T.test("materials: kept for a crafter who uses them, free otherwise", function()
    local game = mageWith(function(w)
        w:put(0, 1, I.LINEN, 40)
        w:put(0, 2, I.VALUABLE_ORE, 10)
    end)
    local linen = explain(game, I.LINEN)
    T.eq(linen.primary.id, "used_by_crafter")
    T.contains(linen.evidence, "Mage (Tailoring)")
    T.eq(explain(game, I.VALUABLE_ORE).primary.id, "unused_material")
end)

T.test("materials before roles are assigned ask for roles", function()
    local game = T.game({ player = MAGE, setup = F.setup(function(w) w:put(0, 1, I.LINEN, 40) end) })
    T.eq(explain(game, I.LINEN).primary.id, "roles_needed")
end)

T.test("a Protect rule outranks every free reason", function()
    local game = mageWith(function(w) w:put(0, 1, I.JUNK, 3) end)
    game:db().rules.items[I.JUNK] = { protect = true }
    local e = explain(game, I.JUNK)
    T.eq(e.primary.id, "protected")
    T.eq(e.disposition, "keep")
end)

T.test("keepsake reason stops suggestions; investment reminders come due", function()
    local game = mageWith(function(w) w:put(0, 1, I.JUNK, 3) end)
    local P = game:P()
    P.SetKeepReason(I.JUNK, "keepsake", "Broken Tusk")
    T.eq(explain(game, I.JUNK).primary.id, "keepsake")
    P.SetKeepReason(I.JUNK, "investment", "Broken Tusk", 30)
    T.eq(explain(game, I.JUNK).primary.id, "keep_investment")
    game:advance(31 * 24 * 3600)
    T.eq(explain(game, I.JUNK).primary.id, "investment_due", "reminder due")
    P.SetKeepReason(I.JUNK, nil)
    T.eq(explain(game, I.JUNK).primary.id, "junk")
end)

T.test("time held: long-untouched items are flagged after a year", function()
    local game = mageWith(function(w) w:put(0, 1, I.OLD_SWORD, 1) end)
    local P = game:P()
    game:Core().ScanInventory("bags", true)
    game:advance(400 * 24 * 3600)
    local key = P.LocationKeyFor("bags")
    local e = explain(game, I.OLD_SWORD, key)
    local ids = {}
    for _, r in ipairs(e.reasons) do ids[r.id] = true end
    T.ok(ids.long_untouched, "flagged as long untouched")
    T.contains(e.held, "at least")
end)

T.test("time held restarts when an item leaves and returns", function()
    local game = mageWith(function(w) w:put(0, 1, I.OLD_SWORD, 1) end)
    local P = game:P()
    local key = P.LocationKeyFor("bags")
    game:Core().ScanInventory("bags", true)
    local first = P.GetTimeHeld(key, I.OLD_SWORD)
    game:advance(10 * 24 * 3600)
    game.world.containers[0].slots[1] = nil
    game:Core().ScanInventory("bags", true)
    T.eq(P.GetTimeHeld(key, I.OLD_SWORD), nil, "forgotten after leaving")
    game.world:put(0, 1, I.OLD_SWORD, 1)
    game:Core().ScanInventory("bags", true)
    T.ok(P.GetTimeHeld(key, I.OLD_SWORD) > first, "restarted")
end)

T.test("/icanteven why prints a grouped, read-only report", function()
    local game = mageWith(function(w)
        w:put(0, 1, I.JUNK, 3)
        w:put(0, 2, I.LINEN, 40)
        w:put(0, 3, I.QUEST_START, 1)
    end)
    local before = T.deepcopy(game.world.containers)
    local mark = game:logMark()
    game:slash("why")
    local out = game:printed(mark)
    T.contains(out, "Why is this here?")
    T.contains(out, "Can go:")
    T.contains(out, "Junk (grey item): 1")
    T.contains(out, "Worth keeping:")
    T.contains(out, "Material one of your crafters uses: 1")
    T.same(game.world.containers, before, "report changed nothing")
end)

T.test("/icanteven why all includes other characters' snapshots", function()
    local g1 = T.game({ player = { name = "Alt", realm = "R", level = 10, classFile = "ROGUE" },
        setup = F.setup(function(w) w:put(0, 1, I.JUNK, 2) end) })
    g1:Core().ScanInventory("bags", true)
    local saved = g1:logout()
    local g2 = T.game({ savedVariables = saved, player = MAGE, setup = F.setup(function(w) w:put(0, 1, I.LINEN, 5) end) })
    local mark = g2:logMark()
    g2:slash("why")
    T.notContains(g2:printed(mark), "Junk (grey item)")
    mark = g2:logMark()
    g2:slash("why all")
    T.contains(g2:printed(mark), "Junk (grey item): 1")
end)

T.test("only used-up consumables from past expansions are free; devices are not", function()
    local game = mageWith(function(w)
        w:put(0, 1, I.OLD_POTION, 5)
        w:put(0, 2, 7101, 1)
    end, function(w)
        w:defineItem(7101, { name = "Reusable Gadget", classID = 0, subclassID = 0, expansionID = 3, sellPrice = 10 })
    end)
    T.eq(explain(game, I.OLD_POTION).primary.id, "old_consumable")
    T.neq(explain(game, 7101).disposition, "free", "a device is never called free")
end)

T.test("current-expansion items are kept by default; current junk can still go", function()
    local game = mageWith(function(w)
        w:put(0, 1, I.NEW_FLASK, 2)
        w:put(0, 2, 7102, 1)
    end, function(w)
        w:defineItem(7102, { name = "New Grey Thing", classID = 15, quality = 0, expansionID = 11, sellPrice = 5 })
    end)
    T.eq(explain(game, I.NEW_FLASK).primary.id, "current_expansion")
    T.eq(explain(game, 7102).primary.id, "junk")
end)