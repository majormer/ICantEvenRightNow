-- I Can't Even Right Now (With My Bags and Bank) — Saved Data Migration
-- Upgrades ICantEvenRightNowDB from any earlier release to the current schema.
--
-- Guarantees:
--   * User-authored data (rules, saved tasks, settings) is backed up inside the
--     saved data before anything changes (db.migrationBackup[<fromVersion>]).
--   * Steps run on a copy; the live table is only replaced when every step
--     succeeds. A failed migration leaves the saved data exactly as it was.
--   * Steps are idempotent and never delete old data: obsolete keys move to
--     db.legacy instead.
--   * Anything that cannot be carried over is listed in a report shown to the
--     player (db.migrationReports), with a one-line fix.

local ADDON_NAME, ns = ...

local P = ns.Private

-- Bump when a new step is appended to STEPS.
local SCHEMA_VERSION = 1
P.SCHEMA_VERSION = SCHEMA_VERSION

local EXPANSION_FILTER_ALL = P.EXPANSION_FILTER_ALL

-- Top-level ui keys used by 0.1.0 to 0.2.x before per-tab filters existed.
local LEGACY_UI_KEYS = {
    "mode", "expansionFilter", "typeFilter", "rarityFilter", "locationFilter", "recommendedOnly",
    "organizerShowAll", "vendorShowAll", "organizerSearch", "vendorSearch", "search",
}

-- Tabs removed in 0.3.0 and the route each one implied.
local LEGACY_TABS = {
    { key = "Move",     source = "Bags",            dest = P.STORAGE_ALL_BANK_TABS },
    { key = "Organize", source = nil,               dest = nil },
    { key = "Vendor",   source = "Bags",            dest = "Vendor" },
}

-- Rule fields that 0.6.0 understands; anything else is legacy.
local KNOWN_RULE_FIELDS = {
    protect = true, ignore = true, neverSell = true, notes = true, name = true,
    expansionOverride = true, typeOverride = true, createdFrom = true,
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do copy[DeepCopy(k, seen)] = DeepCopy(v, seen) end
    return copy
end
P.DeepCopy = DeepCopy

local function InferSourceVersion(db)
    if db.schemaVersion then return "0.6.0 (schema " .. tostring(db.schemaVersion) .. ")" end
    if db.savedWorkflowSchemaVersion then return "0.6.0 test build" end
    if type(db.savedFilters) == "table" then
        for _, preset in ipairs(db.savedFilters) do
            if type(preset) == "table" and preset.armorType ~= nil then return "0.5.0" end
        end
    end
    if db.savedFiltersSeeded or (type(db.savedFilters) == "table" and #db.savedFilters > 0) then return "0.4.0" end
    if db.errorLog or (type(db.ui) == "table" and type(db.ui.tabFilters) == "table") then return "0.3.0" end
    return "0.2.0 or earlier"
end
P.InferSourceVersion = InferSourceVersion

local function RuleItemName(itemID, rule)
    if type(rule) == "table" then
        if rule.name and rule.name ~= "" then return rule.name end
        local from = rule.createdFrom
        if from and from ~= "" and from ~= "Rules tab" and from ~= "Transfer tab" then return from end
    end
    return "Item #" .. tostring(itemID)
end

local function IsAll(value)
    return value == nil or value == "All" or value == EXPANSION_FILTER_ALL
end

-- True when a legacy per-tab filter holds nothing the player chose.
local function IsDefaultTabFilter(filter)
    if type(filter) ~= "table" then return true end
    local function include(branch) return type(filter[branch]) == "table" and filter[branch].include or nil end
    if not IsAll(include("expansion")) then return false end
    if type(include("type")) == "table" or not IsAll(include("type")) then return false end
    if not IsAll(include("bind")) then return false end
    if not IsAll(include("location")) then return false end
    if type(include("slot")) == "table" or not IsAll(include("slot")) then return false end
    if not IsAll(include("upgrade")) then return false end
    if not IsAll(include("armorType")) then return false end
    local name = type(filter.name) == "table" and filter.name or {}
    if (name.includeText or "") ~= "" or (name.excludeText or "") ~= "" then return false end
    if filter.hideBlocked then return false end
    local ilvl = type(filter.itemLevel) == "table" and filter.itemLevel or {}
    if ilvl.min or ilvl.max then return false end
    return true
end

local function TabFilterToTask(name, filter, source, dest)
    local function include(branch) return type(filter[branch]) == "table" and filter[branch].include or nil end
    local nameBranch = type(filter.name) == "table" and filter.name or {}
    local ilvl = type(filter.itemLevel) == "table" and filter.itemLevel or {}
    local search = nameBranch.includeText
    return {
        name = name,
        expansion = include("expansion") or EXPANSION_FILTER_ALL,
        bind = include("bind") or "All",
        type = DeepCopy(include("type") or "All"),
        slot = DeepCopy(include("slot") or "All"),
        armorType = include("armorType") or "All",
        upgrade = include("upgrade") or "All",
        source = source,
        dest = dest,
        hideBlocked = filter.hideBlocked and true or false,
        search = (search and search ~= "") and search or nil,
        itemLevelMin = ilvl.min,
        itemLevelMax = ilvl.max,
        imported = true,
    }
end

local function FindTask(db, name)
    for _, preset in ipairs(db.savedFilters or {}) do
        if type(preset) == "table" and preset.name == name then return preset end
    end
    return nil
end

local function AddNote(list, text, fix)
    table.insert(list, { text = text, fix = fix })
end

-- ---------------------------------------------------------------------------
-- Steps. Each receives the working copy and the report; must be idempotent.
-- ---------------------------------------------------------------------------

local STEPS = {}

-- Step 1: normalize any 0.1.0 to 0.5.0 save (and 0.6.0 test builds).
STEPS[1] = function(db, report)
    db.legacy = db.legacy or {}
    db.ui = db.ui or {}
    db.rules = db.rules or {}
    db.rules.items = db.rules.items or {}
    if type(db.rules.items) ~= "table" then
        error("rules.items is not a table")
    end

    -- Rules: keep known flags; convert or report removed ones.
    local portedRules = 0
    db.legacy.rules = db.legacy.rules or {}
    for itemID, rule in pairs(db.rules.items) do
        if type(rule) == "table" then
            local itemName = RuleItemName(itemID, rule)
            local legacyFields
            for field, value in pairs(rule) do
                if not KNOWN_RULE_FIELDS[field] then
                    legacyFields = legacyFields or {}
                    legacyFields[field] = value
                end
            end
            if legacyFields then
                db.legacy.rules[itemID] = db.legacy.rules[itemID] or {}
                for field, value in pairs(legacyFields) do
                    db.legacy.rules[itemID][field] = value
                    rule[field] = nil
                end
                if legacyFields.neverMove then
                    -- Protect is the closest safe equivalent: the item stays untouched.
                    rule.protect = true
                    AddNote(report.converted, "Never Move on " .. itemName .. " is now a Protect rule.",
                        "Remove the rule on the Rules tab if you want this item to be movable again.")
                end
                if legacyFields.actionOverride then
                    AddNote(report.notPorted, "Action override (" .. tostring(legacyFields.actionOverride)
                        .. ") on " .. itemName .. " no longer applies: the addon no longer recommends actions.",
                        "Use a saved task to move items like this one.")
                end
                for field in pairs(legacyFields) do
                    if field ~= "neverMove" and field ~= "actionOverride" then
                        AddNote(report.notPorted, "Setting '" .. field .. "' on " .. itemName .. " is not used anymore.", nil)
                    end
                end
            end
            if rule.protect or rule.ignore or rule.neverSell then portedRules = portedRules + 1 end
        end
    end
    report.ported.rules = portedRules

    -- Legacy per-tab filters (0.3.0 to 0.5.0) and top-level filters (0.1.0 to 0.2.x).
    db.ui.tabFilters = db.ui.tabFilters or {}
    local tabFilters = db.ui.tabFilters
    if not tabFilters.Move then
        local ui = db.ui
        local synthesized = {
            expansion = { include = ui.expansionFilter },
            type = { include = ui.typeFilter },
            location = { include = ui.locationFilter },
            name = { includeText = ui.search or "" },
        }
        if not IsDefaultTabFilter(synthesized) then tabFilters.Move = synthesized end
    end
    db.savedFilters = db.savedFilters or {}
    db.legacy.tabFilters = db.legacy.tabFilters or {}
    local imported = 0
    for _, legacyTab in ipairs(LEGACY_TABS) do
        local filter = tabFilters[legacyTab.key]
        if filter ~= nil then
            if not IsDefaultTabFilter(filter) then
                local taskName = "Imported: " .. legacyTab.key .. " filters"
                if not FindTask(db, taskName) then
                    table.insert(db.savedFilters, TabFilterToTask(taskName, filter, legacyTab.source, legacyTab.dest))
                    imported = imported + 1
                    AddNote(report.converted, "Your old " .. legacyTab.key .. " tab filters are now the saved task \""
                        .. taskName .. "\".", nil)
                end
            end
            db.legacy.tabFilters[legacyTab.key] = db.legacy.tabFilters[legacyTab.key] or filter
            tabFilters[legacyTab.key] = nil
        end
    end
    report.ported.importedFilters = imported

    -- Legacy top-level ui keys are parked under db.legacy.ui.
    db.legacy.ui = db.legacy.ui or {}
    for _, key in ipairs(LEGACY_UI_KEYS) do
        if db.ui[key] ~= nil then
            if db.legacy.ui[key] == nil then db.legacy.ui[key] = db.ui[key] end
            db.ui[key] = nil
        end
    end

    local tasks = 0
    for _, preset in ipairs(db.savedFilters) do
        if type(preset) == "table" and not preset.imported then tasks = tasks + 1 end
    end
    report.ported.tasks = tasks
    report.ported.settings = true
end

-- ---------------------------------------------------------------------------
-- Runner
-- ---------------------------------------------------------------------------

local function Backup(work, original, fromVersion)
    work.migrationBackup = work.migrationBackup or {}
    if work.migrationBackup[fromVersion] then return end
    work.migrationBackup[fromVersion] = {
        at = time and time() or 0,
        schemaVersion = original.schemaVersion,
        rules = DeepCopy(original.rules),
        savedFilters = DeepCopy(original.savedFilters),
        savedFiltersSeeded = original.savedFiltersSeeded,
        savedWorkflowSchemaVersion = original.savedWorkflowSchemaVersion,
        ui = DeepCopy(original.ui),
    }
end

-- Returns the (possibly same) table to use as the saved data, and the new
-- report when a migration ran.
local function RunMigrations(db)
    if type(db) ~= "table" then
        return { schemaVersion = SCHEMA_VERSION }, nil
    end
    local from = tonumber(db.schemaVersion) or 0
    if from >= SCHEMA_VERSION then return db, nil end

    local fromVersion = InferSourceVersion(db)
    local report = {
        fromVersion = fromVersion, fromSchema = from, toSchema = SCHEMA_VERSION,
        at = time and time() or 0, ported = {}, converted = {}, notPorted = {}, seen = false,
    }

    local work = DeepCopy(db)
    Backup(work, db, fromVersion)
    for version = from + 1, SCHEMA_VERSION do
        local ok, err = pcall(STEPS[version], work, report)
        if not ok then
            db.migrationError = {
                at = time and time() or 0, fromVersion = fromVersion, step = version, message = tostring(err),
            }
            return db, nil, err
        end
    end
    work.schemaVersion = SCHEMA_VERSION
    work.migrationError = nil
    work.migrationReports = work.migrationReports or {}
    table.insert(work.migrationReports, report)

    -- Replace contents in place so the global keeps its identity.
    for key in pairs(db) do db[key] = nil end
    for key, value in pairs(work) do db[key] = value end
    return db, report
end
P.RunMigrations = RunMigrations

-- ---------------------------------------------------------------------------
-- Report formatting (chat); the What's New card reuses these lines.
-- ---------------------------------------------------------------------------

local function MigrationReportLines(report)
    local lines = {}
    if not report then return lines end
    local ported = report.ported or {}
    table.insert(lines, "Updated your settings from " .. tostring(report.fromVersion) .. ".")
    table.insert(lines, string.format("Carried over: %d item rule%s, %d saved task%s, and your settings.",
        ported.rules or 0, (ported.rules or 0) == 1 and "" or "s",
        ported.tasks or 0, (ported.tasks or 0) == 1 and "" or "s"))
    for _, entry in ipairs(report.converted or {}) do
        table.insert(lines, "Changed: " .. entry.text .. (entry.fix and (" " .. entry.fix) or ""))
    end
    for _, entry in ipairs(report.notPorted or {}) do
        table.insert(lines, "Not carried over: " .. entry.text .. (entry.fix and (" " .. entry.fix) or ""))
    end
    return lines
end
P.MigrationReportLines = MigrationReportLines

-- True when the player should act: something was dropped, or converted in a
-- way they may want to undo. Informational notes (imported tasks) don't count.
local function NeedsAttention(report)
    if not report then return false end
    if #(report.notPorted or {}) > 0 then return true end
    for _, entry in ipairs(report.converted or {}) do
        if entry.fix then return true end
    end
    return false
end
P.MigrationNeedsAttention = NeedsAttention

function P.LatestMigrationReport()
    local reports = ns.DB and ns.DB.migrationReports
    return reports and reports[#reports] or nil
end
