-- Shared item definitions and world setups for tests.

local F = {}

-- Expansion IDs (LE_EXPANSION_*): 0 Classic ... 5 WoD ... 10 TWW, 11 Midnight.
F.ITEMS = {
    OLD_POTION   = 1001,  -- old consumable, sellable, stackable
    LINEN        = 1002,  -- classic cloth reagent (Tailoring subclass 5)
    NEW_FLASK    = 1003,  -- current-expansion consumable
    OLD_SWORD    = 2001,  -- old BoE weapon
    BOUND_HELM   = 2002,  -- soulbound plate helm
    WARBOUND_TOY = 3001,  -- warbound trinket-like item
    QUEST_START  = 4001,  -- starts a quest
    JUNK         = 5001,  -- grey junk
    VALUABLE_ORE = 6001,  -- old metal with high auction value
}

function F.defineItems(world)
    local I = F.ITEMS
    world:defineItem(I.OLD_POTION, { name = "Draenic Healing Potion", classID = 0, subclassID = 1, quality = 1,
        maxStack = 20, sellPrice = 150, expansionID = 5, itemLevel = 40 })
    world:defineItem(I.LINEN, { name = "Linen Cloth", classID = 7, subclassID = 5, quality = 1,
        maxStack = 200, sellPrice = 13, expansionID = 0, isCraftingReagent = true })
    world:defineItem(I.NEW_FLASK, { name = "Midnight Flask", classID = 0, subclassID = 3, quality = 2,
        maxStack = 20, sellPrice = 500, expansionID = 11 })
    world:defineItem(I.OLD_SWORD, { name = "Cataclysm Broadsword", classID = 2, subclassID = 7, quality = 3,
        equipLoc = "INVTYPE_WEAPON", itemLevel = 333, requiredLevel = 35, bindType = 2, sellPrice = 4000,
        expansionID = 3, appearanceSourceID = 70001 })
    world:defineItem(I.BOUND_HELM, { name = "Plate Helm of Testing", classID = 4, subclassID = 4, quality = 3,
        equipLoc = "INVTYPE_HEAD", itemLevel = 400, requiredLevel = 70, bindType = 1, sellPrice = 9000,
        expansionID = 10, appearanceSourceID = 70002 })
    world:defineItem(I.WARBOUND_TOY, { name = "Warbound Curio", classID = 15, subclassID = 0, quality = 3,
        bindType = 8, sellPrice = 0, expansionID = 9 })
    world:defineItem(I.QUEST_START, { name = "Tattered Letter", classID = 12, subclassID = 0, quality = 1,
        questID = 90001, sellPrice = 0, expansionID = 2 })
    world:defineItem(I.JUNK, { name = "Broken Tusk", classID = 15, subclassID = 0, quality = 0,
        maxStack = 20, sellPrice = 55, expansionID = 0 })
    world:defineItem(I.VALUABLE_ORE, { name = "Obsidium Ore", classID = 7, subclassID = 7, quality = 1,
        maxStack = 200, sellPrice = 25, expansionID = 3 })
end

-- Character bank: one tab (bag 6); Warband bank: one tab (bag 12).
function F.addBank(world, opts)
    opts = opts or {}
    world:addBankTab(0, 6, opts.charTabName or "Main", opts.charFlags or 0, opts.charSize or 20)
    world:addBankTab(2, 12, opts.warbandTabName or "Shared", opts.warbandFlags or 0, opts.warbandSize or 20)
end

-- A world with items defined and a bank; `populate(world)` places stacks.
function F.setup(populate, bankOpts)
    return function(world)
        F.defineItems(world)
        F.addBank(world, bankOpts)
        if populate then populate(world) end
    end
end

return F
