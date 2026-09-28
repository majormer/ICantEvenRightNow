-- I Can't Even Right Now (With My Bags and Bank) Data Module
-- Contains static data tables for item classification, expansion info, and curated item lists

local ns = select(2, ...)
ns.Data = {}

-- Expansion definitions
-- IDs match WoW's LE_EXPANSION_* globals (0-based).
-- GetItemInfo() returns expansionID using these same values.
ns.Data.Expansions = {
    [LE_EXPANSION_CLASSIC]              = { name = EXPANSION_NAME0, id = LE_EXPANSION_CLASSIC },
    [LE_EXPANSION_BURNING_CRUSADE]      = { name = EXPANSION_NAME1, id = LE_EXPANSION_BURNING_CRUSADE },
    [LE_EXPANSION_WRATH_OF_THE_LICH_KING] = { name = EXPANSION_NAME2, id = LE_EXPANSION_WRATH_OF_THE_LICH_KING },
    [LE_EXPANSION_CATACLYSM]            = { name = EXPANSION_NAME3, id = LE_EXPANSION_CATACLYSM },
    [LE_EXPANSION_MISTS_OF_PANDARIA]    = { name = EXPANSION_NAME4, id = LE_EXPANSION_MISTS_OF_PANDARIA },
    [LE_EXPANSION_WARLORDS_OF_DRAENOR]  = { name = EXPANSION_NAME5, id = LE_EXPANSION_WARLORDS_OF_DRAENOR },
    [LE_EXPANSION_LEGION]               = { name = EXPANSION_NAME6, id = LE_EXPANSION_LEGION },
    [LE_EXPANSION_BATTLE_FOR_AZEROTH]   = { name = EXPANSION_NAME7, id = LE_EXPANSION_BATTLE_FOR_AZEROTH },
    [LE_EXPANSION_SHADOWLANDS]          = { name = EXPANSION_NAME8, id = LE_EXPANSION_SHADOWLANDS },
    [LE_EXPANSION_DRAGONFLIGHT]         = { name = EXPANSION_NAME9, id = LE_EXPANSION_DRAGONFLIGHT },
    [LE_EXPANSION_WAR_WITHIN]           = { name = EXPANSION_NAME10, id = LE_EXPANSION_WAR_WITHIN },
    [LE_EXPANSION_MIDNIGHT]             = { name = EXPANSION_NAME11, id = LE_EXPANSION_MIDNIGHT },
}

ns.Data.CurrentExpansionID = LE_EXPANSION_MIDNIGHT

-- Item type classifications
ns.Data.ItemTypes = {
    REPUTATION = "Reputation",
    QUEST = "Quest",
    SEASONAL = "Seasonal",
    PROFESSION = "Profession",
    CONSUMABLE = "Consumable",
    BOE = "BoE",
    CURRENCY_LIKE = "CurrencyLike",
    EQUIPMENT = "Equipment",
    MATERIAL = "Material",
    HOUSING = "Housing",
    UNKNOWN = "Unknown",
}

-- Housing lumber (class 7, subclass "Other", Warbound, 1,000-stack): one per
-- expansion tier, used by every crafting profession for decor recipes at
-- that tier's proficiency. Matched by ID because the subclass says nothing.
-- Verified 2026-09-28 (ItemSparse build 12.1.0.69933, warcraft.wiki.gg).
ns.Data.HousingLumber = {
    [245586] = "Classic",            -- Ironwood Lumber
    [242691] = "Outland",            -- Olemba Lumber
    [251762] = "Northrend",          -- Coldwind Lumber
    [251764] = "Cataclysm",          -- Ashwood Lumber
    [251763] = "Pandaria",           -- Bamboo Lumber
    [251766] = "Draenor",            -- Shadowmoon Lumber
    [251767] = "Legion",             -- Fel-Touched Lumber
    [251768] = "Battle for Azeroth", -- Darkpine Lumber
    [251772] = "Shadowlands",        -- Arden Lumber
    [251773] = "Dragonflight",       -- Dragonpine Lumber
    [248012] = "The War Within",     -- Dornic Fir Lumber
    [256963] = "Midnight",           -- Thalassian Lumber
    [269010] = "any",                -- Essence of Lumber: trades for 20 lumber of your choice
}
-- Gathering professions have no decor recipes.
ns.Data.GatheringSkillLines = { [182] = true, [186] = true, [393] = true, [356] = true }

ns.Data.Actions = {
    BANK = "Bank",
    RECALL = "Recall",
    SELL = "Sell",
    REVIEW = "Review",
    NONE = "None",
}

-- Curated item tables (to be populated with actual item IDs)
ns.Data.CuratedItems = {
    -- Legion currency-like items
    Legion = {
        -- Ancient Mana
        [141652] = { type = "CurrencyLike", expansion = LE_EXPANSION_LEGION, action = "Bank", reason = "Old expansion currency-like item" },
        -- Add more curated items as needed
    },
    -- Other expansions will be added here
}

-- Map profession skill line IDs to the item subclass IDs (classID 7) that profession uses.
-- Skill line IDs match the 7th return value of GetProfessionInfo().
-- Item subclass IDs (classID 7, Trade Goods):
--   1=Parts  2=Explosives  3=Devices  4=Jewelcrafting  5=Cloth  6=Leather
--   7=Metal & Stone  8=Cooking  9=Herb  10=Elemental  11=Other  12=Enchanting  14=Inscription
ns.Data.ProfessionSubclasses = {
    [164] = { 7, 10 },           -- Blacksmithing:  Metal & Stone, Elemental
    [202] = { 1, 2, 3, 7, 10 },  -- Engineering:    Parts, Explosives, Devices, Metal & Stone, Elemental
    [186] = { 7 },               -- Mining:         Metal & Stone
    [165] = { 6, 10 },           -- Leatherworking: Leather, Elemental
    [393] = { 6 },               -- Skinning:       Leather
    [197] = { 5, 10 },           -- Tailoring:      Cloth, Elemental
    [333] = { 12 },              -- Enchanting:     Enchanting
    [171] = { 9, 10 },           -- Alchemy:        Herb, Elemental
    [182] = { 9 },               -- Herbalism:      Herb
    [755] = { 4, 7, 10 },        -- Jewelcrafting:  Jewelcrafting, Metal & Stone, Elemental
    [773] = { 14, 9 },           -- Inscription:    Inscription, Herb
    [185] = { 8 },               -- Cooking:        Cooking
}

-- Default database structure
ns.Data.DefaultDB = {
    rules = {
        items = {}, -- Item ID -> rule mapping
    },
    context = {
        bankOpen = false,
        reagentBankOpen = false,
        warbandBankOpen = false,
        vendorOpen = false,
        auctionHouseOpen = false,
        mailboxOpen = false,
        inCombat = false,
    },
    -- Roster and per-character snapshots (Characters.lua). Keyed "Name-Realm".
    characters = {},
    -- Account-wide Warband bank snapshot and tab data.
    warband = { items = {}, scannedAt = 0, tabs = {} },
    -- First date each item was seen per location (Reasons.lua).
    timeHeld = {},
    ui = {
        tabFilters = {},
        showMinimapIcon = true,
        minimapIcon = {
            hide = false,
            minimapPos = 220,
            lock = false,
        },
        showBankButton = false,
        showVendorButton = false,
        transferSort = "Name",
        preselectQuickTasks = false, -- H3: off by default (player decision)
        groupIdenticalRows = true,
        compactRows = false,
        contextNotice = "notice",    -- "notice" | "open" | "off" at a bank or vendor
        whereTooltip = true,         -- W5: item tooltips show where the account holds the item
        tipsEnabled = true,          -- O5: first-time tips (seen flags in db.tipsSeen, account-wide)
        betterBagsCategories = false, -- Section 8: off until the player enables it
        auctionIncludeCurrent = false, -- Auction Candidates may include current-expansion items (farmers)
        enhancedLogging = false,     -- Troubleshooting: record actions into debugLog (Log.lua)
        auctionMailReminder = true,  -- Warn before auction mail on any character is deleted (Mail.lua)
    },
    debugLog = { lines = {}, nextIndex = 1, count = 0 }, -- Enhanced logging ring buffer (Log.lua)
    vendorRefused = {}, -- [itemID] = { name, reason, at }: items vendors refused to buy (Transfer.lua)
    knownPetSpecies = {}, -- [itemID] = speciesID, remembered because the client drops pet item data (Reasons.lua)
    knownQuestItem = {}, -- [itemID] = questID, remembered because container quest info lags after a reload (Scanner.lua)
    auctionRefused = {}, -- [itemID] = { name, reason, at }: items the auction house refused to list (Transfer.lua)
    decisions = {}, -- [itemID] = { choice, at, until_, reason, note, by }: the player's triage decisions (Triage.lua)
    errorLog = {},  -- Persisted Lua error entries: { time, msg }. Capped at 50.
    savedFilters = {},       -- User-named workflows; legacy filter-only presets remain supported.
    savedFiltersSeeded = false, -- Set true after default presets are written once
    savedWorkflowSchemaVersion = 0,
    -- schemaVersion, migrationBackup, migrationReports, legacy: managed by Migration.lua
}
