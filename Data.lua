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
    UNKNOWN = "Unknown",
}

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
    lastScan = {
        bags = 0,
        bank = 0,
    },
    scans = {
        bags = {},
        bank = {},
    },
    ui = {
        mode = "Dump to Bank",
        expansionFilter = 0,
        typeFilter = "All",
        rarityFilter = "All",
        locationFilter = "All",
        recommendedOnly = true,
        organizerShowAll = false,
        vendorShowAll = false,
        organizerSearch = "",
        vendorSearch = "",
        tabFilters = {
            Move = {
                expansion = { include = 0 },
                type = { include = "All" },
                bind = { include = "All" },
                location = { include = "All" },
                name = { includeText = "", excludeText = "" },
                hideBlocked = false,
                advancedEnabled = false,
                migratedFromLegacy = false,
            },
            Organize = {
                expansion = { include = 0 },
                type = { include = "All" },
                bind = { include = "All" },
                location = { include = "All" },
                name = { includeText = "", excludeText = "" },
                hideBlocked = false,
                advancedEnabled = false,
                migratedFromLegacy = false,
            },
            Vendor = {
                expansion = { include = 0 },
                type = { include = "All" },
                bind = { include = "All" },
                location = { include = "All" },
                name = { includeText = "", excludeText = "" },
                hideBlocked = false,
                advancedEnabled = false,
                migratedFromLegacy = false,
            },
        },
        showMinimapIcon = true,
        minimapIcon = {
            hide = false,
            minimapPos = 220,
            lock = false,
        },
        showBankButton = false,
        showVendorButton = false,
        search = "",
    },
    errorLog = {},  -- Persisted Lua error entries: { time, msg }. Capped at 50.
}
