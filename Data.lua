-- I Can't Even Right Now (With My Bags and Bank) Data Module
-- Contains static data tables for item classification, expansion info, and curated item lists

local ns = select(2, ...)
ns.Data = {}

-- Expansion definitions
ns.Data.Expansions = {
    [1] = { name = "Classic", id = 1 },
    [2] = { name = "The Burning Crusade", id = 2 },
    [3] = { name = "Wrath of the Lich King", id = 3 },
    [4] = { name = "Cataclysm", id = 4 },
    [5] = { name = "Mists of Pandaria", id = 5 },
    [6] = { name = "Warlords of Draenor", id = 6 },
    [7] = { name = "Legion", id = 7 },
    [8] = { name = "Battle for Azeroth", id = 8 },
    [9] = { name = "Shadowlands", id = 9 },
    [10] = { name = "Dragonflight", id = 10 },
    [11] = { name = "The War Within", id = 11 },
    [12] = { name = "Midnight", id = 12 },
}

ns.Data.CurrentExpansionID = 12

-- Item type classifications
ns.Data.ItemTypes = {
    REPUTATION = "Reputation",
    QUEST = "Quest",
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
        [141652] = { type = "CurrencyLike", expansion = 7, action = "Bank", reason = "Old expansion currency-like item" },
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
