-- Synthetic saved-variable snapshots shaped like each released version wrote them.
-- Built from each tag's Data.lua DefaultDB plus user data typical for that version.

local S = {}

local function baseUi()
    return {
        mode = "Dump to Bank", expansionFilter = 0, typeFilter = "All", rarityFilter = "All",
        locationFilter = "All", recommendedOnly = true, organizerShowAll = false, vendorShowAll = false,
        organizerSearch = "", vendorSearch = "", showMinimapIcon = true,
        minimapIcon = { hide = false, minimapPos = 180, lock = true },
        showBankButton = false, showVendorButton = false, search = "",
    }
end

local function defaultTab()
    return {
        expansion = { include = 0 }, type = { include = "All" }, bind = { include = "All" },
        location = { include = "All" }, name = { includeText = "", excludeText = "" },
        hideBlocked = false, advancedEnabled = false, migratedFromLegacy = true,
    }
end

local function base()
    return {
        rules = { items = {} },
        context = { bankOpen = false, vendorOpen = false, inCombat = false },
        lastScan = { bags = 1780000000, bank = 1780000000 },
        scans = { bags = {}, bank = {} },
        ui = baseUi(),
    }
end

-- 0.2.0: legacy mode-based UI, removed rule flags, filters in top-level ui keys.
function S.v020()
    local db = base()
    db.ui.expansionFilter = 3
    db.ui.search = "ore"
    db.rules.items[1001] = { protect = false, neverMove = true, createdFrom = "Draenic Healing Potion" }
    db.rules.items[1002] = { actionOverride = "Bank", createdFrom = "Linen Cloth" }
    db.rules.items[2001] = { protect = true, createdFrom = "Rules tab" }
    return db
end

-- 0.3.0: per-tab filters and error log; Transfer tab added.
function S.v030()
    local db = base()
    db.errorLog = { { time = "2026-05-08 10:00:00", msg = "old error" } }
    db.ui.tabFilters = { Move = defaultTab(), Organize = defaultTab(), Vendor = defaultTab() }
    db.ui.tabFilters.Vendor.name.includeText = "potion"
    db.ui.tabFilters.Transfer = defaultTab()
    db.rules.items[1001] = { neverSell = true, name = "Draenic Healing Potion", createdFrom = "Transfer tab" }
    db.rules.items[2002] = { ignore = true, name = "Plate Helm of Testing", createdFrom = "Transfer tab" }
    return db
end

-- 0.4.0: saved filter presets (filter-only).
function S.v040()
    local db = S.v030()
    db.ui.tabFilters.Vendor.name.includeText = ""
    db.savedFilters = {
        { name = "Old Gear Dump", expansion = -1, bind = "All", type = "All", slot = "All", upgrade = "All" },
        { name = "Upgrade Check", expansion = 0, bind = "All", type = "All", slot = "All", upgrade = "Upgrade" },
        { name = "My Cloth", expansion = 0, bind = "All", type = { Reagent = true }, slot = "All", upgrade = "All" },
    }
    db.savedFiltersSeeded = true
    return db
end

-- 0.5.0: presets gain armorType; transfer sort.
function S.v050()
    local db = S.v040()
    for _, preset in ipairs(db.savedFilters) do preset.armorType = "All" end
    db.savedFilters[3].armorType = 4
    db.ui.transferSort = "Item Level"
    db.rules.items[180653] = { protect = true, createdFrom = "Mythic Keystone", ignore = false, neverSell = false }
    return db
end

-- Load a real SavedVariables file (sets ICantEvenRightNowDB) into a table.
function S.loadFile(path)
    local chunk = loadfile(path)
    if not chunk then return nil end
    local env = {}
    setfenv(chunk, env)
    chunk()
    return env.ICantEvenRightNowDB
end

return S
