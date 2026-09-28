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

T.test("recipes: learn it when the character has the profession and doesn't know it; free once known", function()
    local function recipeGame(known, hasProfession)
        local game = mageWith(function(w)
            w:put(0, 1, 7101, 1)
        end, function(w)
            w:defineItem(7101, { name = "Plans: Demonsteel Helm", classID = 9, subclassID = 4,
                itemType = "Recipe", itemSubType = "Blacksmithing", quality = 2,
                tooltipLines = known and { "Already known" } or {} })
        end)
        game:db().characters["Mage-R"].professions = hasProfession and { { name = "Blacksmithing", skillLine = 164 } } or {}
        game:Core().ScanInventory("bags", true)
        return game
    end
    local function scannedItem(game)
        for _, it in ipairs(game:P().GetScanList("bags")) do if it.itemID == 7101 then return it end end
    end
    local game = recipeGame(false, true)
    local e = explain(game, 7101)
    T.eq(e.primary.id, "collectible_unlearned") T.contains(e.evidence, "Blacksmithing recipe")
    local channels = game:P().ItemChannels(scannedItem(game))
    T.eq(channels.use, true) T.contains(channels.useWhat, "learn the recipe")

    game = recipeGame(true, true)
    T.eq(explain(game, 7101).primary.id, "collectible_learned")
    T.eq(explain(game, 7101).disposition, "free")

    game = recipeGame(false, false)
    e = explain(game, 7101)
    T.eq(e.primary.id, "recipe_other_profession") T.contains(e.evidence, "doesn't have Blacksmithing")
    channels = game:P().ItemChannels(scannedItem(game))
    T.eq(channels.use, false) T.contains(channels.why.use, "doesn't have Blacksmithing")
end)

T.test("pets: a learned pet at its collection limit can go even from the current expansion", function()
    local function petGame(collected, limit)
        return mageWith(function(w)
            w:put(0, 1, 7201, 1)
            w.collections.pets[9201] = collected
            w.collections.pets[9202] = 1   -- some other pet: the journal counts as loaded
        end, function(w)
            w:defineItem(7201, { name = "Lost Star", classID = 15, subclassID = 2, quality = 2, sellPrice = 250000,
                expansionID = 11, petSpeciesID = 9201, petLimit = limit })
        end)
    end
    local e = explain(petGame(1, 1), 7201)
    T.eq(e.primary.id, "collectible_complete") T.eq(e.disposition, "free")
    e = explain(petGame(1, 3), 7201)
    T.eq(e.primary.id, "current_expansion", "room for more copies: still a keep")
    e = explain(petGame(0, 3), 7201)
    local ids = {}
    for _, r in ipairs(e.reasons) do ids[r.id] = true end
    T.ok(ids.collectible_unlearned, "not learned: use it") T.eq(e.disposition, "keep")
end)

T.test("heirlooms: a copy the journal already has can go, unless it's an upgrade for an alt", function()
    local game = mageWith(function(w)
        w:put(0, 1, 7301, 1)
        w.collections.heirlooms[7301] = true
    end, function(w)
        w:defineItem(7301, { name = "Tattered Dreadmist Mantle", classID = 4, subclassID = 1, quality = 7,
            itemLevel = 69, equipLoc = "INVTYPE_SHOULDER", expansionID = 0, sellPrice = 0 })
    end)
    local e = explain(game, 7301)
    T.eq(e.primary.id, "heirloom_copy") T.eq(e.disposition, "free")
    T.contains(e.evidence, "Heirloom Journal")
    -- Not in the journal (a heirloom that was never learned): no such claim.
    game = mageWith(function(w) w:put(0, 1, 7301, 1) end, function(w)
        w:defineItem(7301, { name = "Tattered Dreadmist Mantle", classID = 4, subclassID = 1, quality = 7,
            itemLevel = 69, equipLoc = "INVTYPE_SHOULDER", expansionID = 0, sellPrice = 0 })
    end)
    T.ok(explain(game, 7301).primary.id ~= "heirloom_copy")
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
T.test("a learned pet isn't 'not learned' while the pet journal is still loading", function()
    local game = mageWith(function(w)
        w:put(0, 1, 7002, 1)
        w.collections.pets[4542] = 1
        w.petJournalLoading = true
    end, function(w) w:defineItem(7002, { name = "Slim", classID = 15, subclassID = 2, petSpeciesID = 4542, sellPrice = 100000 }) end)
    local e = explain(game, 7002)
    T.ok(e.primary.id ~= "collectible_unlearned", "not judged before the journal loads")
    T.ok(e.disposition ~= "free" and e.disposition ~= "keep", "no verdict yet")
    local item
    for _, it in ipairs(game:P().GetScanList("bags")) do if it.itemID == 7002 then item = it end end
    T.ok(game:P().ItemDataPending(item), "Getting ready waits for the journal")
    game.world.petJournalLoading = false
    game.world:fire("PET_JOURNAL_LIST_UPDATE")
    T.eq(explain(game, 7002).primary.id, "collectible_learned")
end)

T.test("a quest in progress is read from the quest log when the container info lags (after a reload)", function()
    local game = mageWith(function(w)
        w:put(0, 1, I.QUEST_START, 1)
        w.quests.active[90001] = true
        w.containerQuestInfoStale = true
    end)
    T.eq(explain(game, I.QUEST_START).primary.id, "quest_active")
end)

T.test("/icanteven explain prints the facts behind an item's verdict", function()
    local game = mageWith(function(w) w:put(0, 1, I.JUNK, 3) end)
    game:Core().ScanInventory("bags", true)
    local lines = game:P().ExplainLines("tusk")
    T.ok(#lines >= 4, "four lines per item")
    T.contains(lines[1], "free")
    T.contains(lines[3], "can: vendor yes")
    T.contains(lines[4], "can go and sellable true")
    T.contains(game:P().ExplainLines("nothing-here")[1], "No scanned item")
end)

T.test("a pet's species is remembered when the client drops the item's data (saved)", function()
    local game = mageWith(function(w)
        w:put(0, 1, 7003, 1)
        w.collections.pets[4543] = 1
    end, function(w) w:defineItem(7003, { name = "Slim", classID = 15, subclassID = 2, petSpeciesID = 4543, sellPrice = 100000 }) end)
    T.eq(explain(game, 7003).primary.id, "collectible_learned")
    T.eq(game:db().knownPetSpecies[7003], 4543, "saved")
    game.world.items[7003].petInfoDropped = true
    T.eq(explain(game, 7003).primary.id, "collectible_learned", "still learned from the saved species")
end)

T.test("a companion-pet item the game hasn't described is pending, not 'no clear reason'", function()
    local game = mageWith(function(w)
        w:put(0, 1, 7004, 1)
    end, function(w) w:defineItem(7004, { name = "Mystery Pet", classID = 15, subclassID = 2, petSpeciesID = 4544, petInfoDropped = true, sellPrice = 100 }) end)
    local e = explain(game, 7004)
    T.eq(e.primary.id, "details_loading")
    local item
    for _, it in ipairs(game:P().GetScanList("bags")) do if it.itemID == 7004 then item = it end end
    T.ok(game:P().ItemDataPending(item), "Getting ready waits")
end)

T.test("a quest-starting item keeps its quest when the container info has no questID (saved)", function()
    local game = mageWith(function(w)
        w:put(0, 1, I.QUEST_START, 1)
        w.quests.completed[90001] = true
    end)
    T.eq(explain(game, I.QUEST_START).primary.id, "quest_done")
    T.eq(game:db().knownQuestItem[I.QUEST_START], 90001, "saved")
    game.world.containerQuestInfoDropped = true
    T.eq(explain(game, I.QUEST_START).primary.id, "quest_done", "judged from the quest log, not the dropped info")
end)

T.test("utility items (a bound device with a Use effect) stay in the bags: no deposit task offers them", function()
    local game = mageWith(function(w)
        w:put(0, 1, 49040, 1, { bound = true })
        w:put(0, 2, I.LINEN, 20)
    end, function(w) w:defineItem(49040, { name = "Jeeves", classID = 0, subclassID = 0, itemSubType = "Explosives and Devices",
        quality = 3, sellPrice = 12345, expansionID = 2, bindType = 1, useSpell = "Summon Jeeves" }) end)
    local e = explain(game, 49040)
    T.eq(e.primary.id, "utility_item")
    T.eq(e.disposition, "keep")
    game:openBank()
    local P = game:P()
    local ids = {}
    for _, plan in ipairs(P.GetTaskPlans(P.FindTask("Deposit Old Items"))) do ids[plan.item.itemID] = true end
    T.no(ids[49040], "Jeeves stays in the bags")
    T.ok(ids[I.LINEN], "other old items still deposit")
    -- The same gadget sitting in the bank isn't a utility item: it keeps its ordinary verdict.
    game.world:put(6, 1, 49040, 1, { bound = true })
    game:Core().ScanInventory("all", true)
    local banked
    for _, it in ipairs(P.GetScanList("bank")) do if it.itemID == 49040 then banked = it end end
    T.ok(banked, "in the bank")
    T.ok(P.ExplainScanned(banked).primary.id ~= "utility_item", "not a utility item while banked")
end)

T.test("a gear token with a class restriction is kept for a character of that class, and can go when none is", function()
    local function tokenGame(classes)
        return mageWith(function(w) w:put(0, 1, 203641, 1, { tooltipBinding = "warbound" }) end,
            function(w) w:defineItem(203641, { name = "Primalist Cloth Boots", classID = 4, subclassID = 0,
                equipLoc = "INVTYPE_NON_EQUIP_IGNORE", itemLevel = 72, requiredLevel = 70, quality = 4, sellPrice = 5000,
                expansionID = 9, bindType = 7, useSpell = "Create Primalist Cloth Boots",
                tooltipLines = { "Classes: " .. classes } }) end)
    end
    local e = explain(tokenGame("Mage, Priest, Warlock"), 203641)   -- the played character is a Mage
    T.eq(e.primary.id, "gear_token_for")
    T.eq(e.disposition, "keep")
    T.contains(e.evidence, "Mage")
    e = explain(tokenGame("Warrior, Paladin, Death Knight"), 203641)
    T.eq(e.primary.id, "gear_token_unused")
    T.eq(e.disposition, "free")
    -- No class line read yet: the player's call.
    local plain = mageWith(function(w) w:put(0, 1, 203641, 1, { tooltipBinding = "warbound" }) end,
        function(w) w:defineItem(203641, { name = "Primalist Cloth Boots", classID = 4, subclassID = 0,
            equipLoc = "INVTYPE_NON_EQUIP_IGNORE", itemLevel = 72, requiredLevel = 70, quality = 4, sellPrice = 5000,
            expansionID = 9, bindType = 7, useSpell = "Create Primalist Cloth Boots" }) end)
    T.eq(explain(plain, 203641).primary.id, "gear_token")
end)

T.test("deck cards are for sale even in the current expansion (the player doesn't assemble decks)", function()
    local game = mageWith(function(w) w:put(0, 1, 7201, 3) end,
        function(w) w:defineItem(7201, { name = "Six of Blood", classID = 7, subclassID = 16, quality = 3, maxStack = 20,
            sellPrice = 100, expansionID = 11, bindType = 0 }) end)
    local e = explain(game, 7201)
    T.eq(e.primary.id, "deck_card")
    T.eq(e.disposition, "free")
    game:db().prices = { ["c:7201"] = { price = 500000, at = game.env.time() } }
    game:Core().ScanInventory("bags", true)
    local card
    for _, it in ipairs(game:P().GetScanList("bags")) do if it.itemID == 7201 then card = it end end
    T.ok(game:P().IsAuctionCandidate(card), "an auction candidate once priced")
    -- Not a card: "Vial of Something" doesn't match the rank words.
    game.world:defineItem(7202, { name = "Vial of Blood", classID = 7, subclassID = 16, quality = 3, maxStack = 20, sellPrice = 100, expansionID = 11 })
    game.world:put(0, 2, 7202, 1)
    T.ok(explain(game, 7202).primary.id ~= "deck_card")
end)
