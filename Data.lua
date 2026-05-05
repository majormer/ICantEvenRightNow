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

ns.Data.Recommendations = {
    BANK = "BankCandidate",
    RECALL = "RecallCandidate",
    REVIEW = "NeedsReview",
    PROTECTED = "Protected",
    IGNORED = "Ignored",
    BLOCKED = "Blocked",
}

ns.Data.Actions = {
    BANK = "Bank",
    RECALL = "Recall",
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
        search = "",
    },
}
