local T = ...
local F = require("fixtures")

-- Set bonuses and upgrade tracks (player's rules, 2026-09-26):
-- a class set replaced by the one you wear can go; a piece that completes a
-- bonus is your call with the trade spelled out; gear below what you wear
-- that can't be upgraded can go; "keep for now" asks again after an upgrade.
local PLAYER = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" }
local STR = { ITEM_MOD_STRENGTH_SHORT = 10 }

local function plate(w, itemID, def)
    local base = { classID = 4, subclassID = 4, itemLevel = 289, requiredLevel = 90, bindType = 1, quality = 4,
        sellPrice = 5000, expansionID = 11, stats = STR }
    for k, v in pairs(def) do base[k] = v end
    w:defineItem(itemID, base)
end

local function game(extra)
    local g = T.game({ player = PLAYER, setup = function(w)
        F.defineItems(w)
        -- Wearing 3 pieces of the current class set at 308.
        for i, slot in ipairs({ 1, 3, 7 }) do
            local loc = ({ "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_LEGS" })[i]
            plate(w, 9100 + i, { name = "New Piece " .. i, equipLoc = loc, itemLevel = 308, setID = 2055,
                tooltipLines = { "New Set (3/5)", "Classes: Warrior", "Set: New bonus (active: no count)", "(4) Set: More" } })
            w.equippedItems[slot], w.equipped[slot] = 9100 + i, 308
        end
        for _, slot in ipairs({ 5, 6, 8, 9, 10, 11, 13, 14, 15, 16 }) do w.equipped[slot] = 305 end
        -- One ring of a 2-piece set worn at 289.
        w:defineItem(9201, { name = "Worn Band", classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER",
            itemLevel = 289, requiredLevel = 90, bindType = 1, quality = 4, sellPrice = 5000, expansionID = 11,
            setID = 1971, tooltipLines = { "Voidlight Bindings (1/2)", "(2) Set: Twilight Barrage" } })
        w.equippedItems[12], w.equipped[12] = 9201, 289
        -- In the bags: an old class set piece, the other ring, a helm with no set.
        plate(w, 9001, { name = "Old Crown", equipLoc = "INVTYPE_HEAD", setID = 1978,
            tooltipLines = { "Relentless Rider's Lament (0/5)", "Classes: Warrior", "(2) Set: Old", "(4) Set: Older" } })
        w:defineItem(9202, { name = "Omission", classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER",
            itemLevel = 289, requiredLevel = 90, bindType = 1, quality = 4, sellPrice = 5000, expansionID = 11,
            setID = 1971, tooltipLines = { "Voidlight Bindings (1/2)", "(2) Set: Twilight Barrage" } })
        plate(w, 9301, { name = "Casque", equipLoc = "INVTYPE_WAIST" })
        plate(w, 9302, { name = "Upgradable Gauntlets", equipLoc = "INVTYPE_HAND", itemLevel = 300,
            tooltipLines = { "Upgrade Level: Hero 2/6" } })
        w:put(0, 1, 9001, 1, { bound = true })
        w:put(0, 2, 9202, 1, { bound = true })
        w:put(0, 3, 9301, 1, { bound = true })
        w:put(0, 4, 9302, 1, { bound = true })
        if extra then extra(w) end
    end })
    local P = g:P()
    P.SetCharacterRole("Main-R", "main")
    P.RefreshEquipped()
    g:Core().ScanInventory("bags", true)
    return g
end

local function explain(g, itemID)
    for _, item in ipairs(g:P().GetScanList("bags")) do
        if item.itemID == itemID then return g:P().ExplainScanned(item), item end
    end
end

T.test("sets: the worn sets are recorded with piece counts", function()
    local g = game()
    local sets = g:P().GetCurrentCharacter().equippedSets
    T.eq(sets[2055].count, 3)
    T.ok(sets[2055].classSet)
    T.eq(sets[2055].level, 308)
    T.eq(sets[1971].count, 1)
    T.ok(not sets[1971].classSet, "the ring set is not a class set")
end)

T.test("sets: an old class set replaced by the one you wear can go", function()
    local e = explain(game(), 9001)
    T.eq(e.primary.id, "set_replaced")
    T.eq(e.disposition, "free")
    T.contains(e.evidence, "3 pieces of New Set at 308")
end)

T.test("sets: a piece that completes a bonus is your call, with the cost", function()
    local e = explain(game(), 9202)
    T.eq(e.primary.id, "set_completes")
    T.eq(e.disposition, "review")
    T.contains(e.evidence, "completes Voidlight Bindings (2)")
    T.contains(e.evidence, "costs 16 item levels")
end)

T.test("gear below what you wear that can't be upgraded can go; upgradable stays your call", function()
    local g = game()
    local casque = explain(g, 9301)
    T.eq(casque.primary.id, "outgrown_no_upgrade")
    T.eq(casque.disposition, "free")
    local gloves = explain(g, 9302)
    T.eq(gloves.primary.id, "outgrown_gear")
    T.contains(gloves.evidence, "can be upgraded (Hero 2/6)")
end)

T.test("keep for now holds an item until the slot gets better, then asks again", function()
    local g = game()
    local P = g:P()
    local _, casque = explain(g, 9301)
    P.SetKeepReason(9301, "fornow", "Casque", nil, casque)
    local kept = explain(g, 9301)
    T.eq(kept.primary.id, "keep_for_now")
    T.contains(kept.evidence, "better than 305")
    g.world.equipped[6] = 315                    -- a better belt goes on
    P.RefreshEquipped()
    local again = explain(g, 9301)
    T.eq(again.primary.id, "outgrown_no_upgrade")
    T.contains(again.evidence, "You kept it for now at 305; you now wear 315")
end)

T.test("sets: an unreadable tooltip never counts as 'can't be upgraded'", function()
    local g = game(function(w) w.items[9301].tooltipLoading = true end)
    local e = explain(g, 9301)
    T.eq(e.primary.id, "outgrown_gear")
    T.ok((g:P().ItemDataPending(select(2, explain(g, 9301)))), "getting ready waits for the tooltip")
end)

T.test("sets: Home asks about a replaced class set; Keep for now silences it until an upgrade", function()
    local g = game()
    local P = g:P()
    local function notice()
        for _, n in ipairs(P.GetHomeNotices()) do if n.id == "old-class-set" then return n end end
    end
    local n = notice()
    T.ok(n, "asked proactively")
    T.contains(n.text, "1 piece of Relentless Rider's Lament can go")
    n.buttons[2].onClick()
    T.eq(notice(), nil, "kept for now")
    T.eq(explain(g, 9001).primary.id, "keep_for_now")
    g.world.equipped[1] = 315                    -- a better helm goes on
    P.RefreshEquipped()
    T.ok(notice(), "asked again after the upgrade")
    T.contains(explain(g, 9001).evidence, "You kept it for now at 308; you now wear 315")
end)

T.test("upgradable gear whose track can't reach what you wear can go", function()
    local g = game(function(w)
        plate(w, 9303, { name = "Veteran Casque", equipLoc = "INVTYPE_WRIST", itemLevel = 279,
            tooltipLines = { "Upgrade Level: Veteran 1/6" } })
        w:put(0, 5, 9303, 1, { bound = true })
    end)
    local e = explain(g, 9303)
    T.eq(e.primary.id, "outgrown_no_upgrade")
    T.contains(e.evidence, "even fully upgraded (Veteran 1/6) it would reach about 299")
    -- Hero 2/6 at 300 could reach 316, past the 305 worn: still your call.
    T.eq(explain(g, 9302).primary.id, "outgrown_gear")
end)

T.test("item level 1 'gear' is a possible keepsake, not outgrown gear", function()
    local g = game(function(w)
        w:defineItem(9401, { name = "Signet Curiosity", classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER",
            itemLevel = 1, requiredLevel = 0, bindType = 8, quality = 1, sellPrice = 0, expansionID = 11 })
        w:put(0, 6, 9401, 1)
    end)
    local e = explain(g, 9401)
    T.eq(e.primary.id, "possible_keepsake")
    T.eq(e.disposition, "review")
end)
