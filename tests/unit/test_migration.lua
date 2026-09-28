local T = ...
local S = require("fixtures.saves")

local function findTask(db, name)
    for _, preset in ipairs(db.savedFilters or {}) do
        if preset.name == name then return preset end
    end
end

local function latestReport(db)
    local reports = db.migrationReports or {}
    return reports[#reports]
end

local function notPortedText(report)
    local parts = {}
    for _, entry in ipairs(report.notPorted or {}) do parts[#parts + 1] = entry.text end
    for _, entry in ipairs(report.converted or {}) do parts[#parts + 1] = entry.text end
    return table.concat(parts, "\n")
end

T.test("fresh install gets the current schema and no migration report", function()
    local game = T.game()
    local db = game:db()
    T.eq(db.schemaVersion, game:P().SCHEMA_VERSION)
    T.eq(db.migrationReports, nil)
end)

T.test("0.2.0 save: rules ported, removed flags reported, legacy filters imported", function()
    local game = T.game({ savedVariables = S.v020() })
    local db = game:db()
    T.eq(db.schemaVersion, game:P().SCHEMA_VERSION)
    -- Protect rule ported unchanged.
    T.ok(db.rules.items[2001].protect, "protect rule kept")
    -- Never Move becomes Protect (safest equivalent) and is reported.
    T.ok(db.rules.items[1001].protect, "never move converted to protect")
    T.eq(db.rules.items[1001].neverMove, nil, "removed flag no longer on the rule")
    local report = latestReport(db)
    T.ok(report, "report written")
    T.eq(report.fromVersion, "0.2.0 or earlier")
    local text = notPortedText(report)
    T.contains(text, "Draenic Healing Potion")
    T.contains(text, "Linen Cloth")
    -- Legacy top-level filters become an imported task.
    local task = findTask(db, "Imported: Move filters")
    T.ok(task, "imported move task created")
    T.eq(task.expansion, 3)
    T.eq(task.search, "ore")
    T.eq(task.source, "Bags")
    T.eq(task.dest, "Bank (All Tabs)")
    -- Legacy UI keys are parked, not deleted.
    T.eq(db.ui.mode, nil)
    T.eq(db.legacy.ui.mode, "Dump to Bank")
    T.eq(db.legacy.rules[1002].actionOverride, "Bank")
end)

T.test("0.3.0 save: only non-default legacy tab filters are imported", function()
    local game = T.game({ savedVariables = S.v030() })
    local db = game:db()
    T.ok(findTask(db, "Imported: Vendor filters"), "vendor filters imported")
    T.eq(findTask(db, "Imported: Move filters"), nil, "default move filters dropped silently")
    T.eq(findTask(db, "Imported: Organize filters"), nil)
    T.eq(findTask(db, "Imported: Vendor filters").dest, "Vendor")
    T.eq(db.ui.tabFilters.Vendor, nil, "legacy tab removed from active filters")
    T.ok(db.legacy.tabFilters.Vendor, "legacy tab kept under legacy")
    T.ok(db.ui.tabFilters.Transfer, "transfer filters kept")
    T.eq(#db.errorLog >= 1 and db.errorLog[1].msg, "old error", "error log kept")
    T.ok(db.rules.items[1001].neverSell and db.rules.items[2002].ignore, "rules kept")
end)

T.test("0.5.0 save: presets and settings preserved exactly", function()
    local original = S.v050()
    local game = T.game({ savedVariables = original })
    local db = game:db()
    for _, preset in ipairs(original.savedFilters) do
        T.same(findTask(db, preset.name), preset, "preset " .. preset.name)
    end
    T.eq(db.ui.transferSort, "Item Level")
    T.eq(db.ui.minimapIcon.minimapPos, 180)
    T.eq(db.ui.minimapIcon.lock, true)
    T.same(db.rules.items[180653], original.rules.items[180653])
    T.eq(latestReport(db).fromVersion, "0.5.0")
end)

T.test("migration backs up user data before changing it", function()
    local original = S.v020()
    local game = T.game({ savedVariables = original })
    local backup = game:db().migrationBackup["0.2.0 or earlier"]
    T.ok(backup, "backup stored")
    T.same(backup.rules, original.rules)
    T.same(backup.ui, original.ui)
end)

T.test("running the migration again changes nothing", function()
    local game = T.game({ savedVariables = S.v030() })
    local once = T.deepcopy(game:db())
    local again = T.deepcopy(once)
    again.schemaVersion = 0
    local P = game:P()
    local result = P.RunMigrations(again)
    -- Same rules, same tasks, no duplicated imports.
    T.same(result.rules, once.rules)
    local count = 0
    for _, preset in ipairs(result.savedFilters) do
        if preset.name == "Imported: Vendor filters" then count = count + 1 end
    end
    T.eq(count, 1, "imported task not duplicated")
end)

T.test("a failing migration leaves saved data untouched and the addon usable", function()
    local broken = S.v050()
    broken.rules.items = "corrupted"
    local game = T.game({ savedVariables = broken })
    local db = game:db()
    T.eq(db.rules.items, "corrupted", "original data kept as-is")
    T.ok(db.migrationError, "error recorded")
    T.contains(game:printed(), "could not update")
end)

T.test("upgrade notice mentions items that need attention", function()
    local game = T.game({ savedVariables = S.v020() })
    local out = game:printed()
    T.contains(out, "/icanteven migration")
    local mark = game:logMark()
    game:slash("migration")
    local report = game:printed(mark)
    T.contains(report, "0.2.0 or earlier")
    T.contains(report, "Linen Cloth")
end)

T.test("imported filters alone do not trigger the attention notice", function()
    local game = T.game({ savedVariables = S.v030() })
    T.notContains(game:printed(), "need attention")
    T.ok(game:P().LatestMigrationReport(), "report still available")
end)

T.test("real 0.5.0 save migrates (local fixture, skipped when absent)", function()
    local real = S.loadFile(ROOT .. "/tests/fixtures/local/real_0.5.0_save.lua")
    if not real then return end
    local game = T.game({ savedVariables = real })
    local db = game:db()
    for itemID, rule in pairs(real.rules.items) do
        T.same(db.rules.items[itemID], rule, "rule " .. tostring(itemID))
    end
    for _, preset in ipairs(real.savedFilters or {}) do
        T.same(findTask(db, preset.name), preset, "preset " .. tostring(preset.name))
    end
    local report = latestReport(db)
    T.ok(report, "report written")
    game:slash("")
    T.ok(game:UI().frame:IsShown(), "console opens after migration")
end)
