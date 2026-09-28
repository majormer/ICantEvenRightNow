local T = ...
local F = require("fixtures")
local S = require("fixtures.saves")
local I = F.ITEMS

-- Log in `player` on top of saved data from a previous session.
local function loginAs(saved, player, populate, extra)
    local opts = { savedVariables = saved, player = player, setup = F.setup(populate) }
    for k, v in pairs(extra or {}) do opts[k] = v end
    return T.game(opts)
end

local MAIN = { name = "Mainchar", realm = "Stormrage", level = 90, classFile = "WARRIOR", className = "Warrior" }
local CRAFTER = { name = "Stitcher", realm = "Stormrage", level = 12, classFile = "MAGE", className = "Mage",
    professions = { { name = "Tailoring", skillLine = 197 }, { name = "Enchanting", skillLine = 333 } } }
local FARMER = { name = "Garrisonbob", realm = "Stormrage", level = 40, classFile = "HUNTER", className = "Hunter" }

T.test("login records the character with class, level, professions", function()
    local game = loginAs(nil, CRAFTER)
    local char = game:P().GetCurrentCharacter()
    T.eq(char.key, "Stitcher-Stormrage")
    T.eq(char.classFile, "MAGE")
    T.eq(char.armorSubclass, 1)
    T.eq(char.level, 12)
    T.eq(#char.professions, 2)
    T.eq(char.professions[1].name, "Tailoring")
    T.eq(game:P().GetRole(char), "unassigned")
end)

T.test("each character keeps its own bags; the Warband snapshot is shared", function()
    local g1 = loginAs(nil, MAIN, function(w)
        w:put(0, 1, I.OLD_POTION, 5)
        w:put(12, 1, I.WARBOUND_TOY, 1)
    end)
    g1:openBank()
    local saved = g1:logout()
    local g2 = loginAs(saved, CRAFTER, function(w)
        w:put(0, 1, I.LINEN, 20)
        w:put(12, 1, I.WARBOUND_TOY, 1)
    end)
    local P = g2:P()
    local bags = P.GetScanList("bags")
    T.eq(#bags, 0, "crafter has not scanned yet; main's bags are not shown")
    g2:Core().ScanInventory("bags", true)
    bags = P.GetScanList("bags")
    T.eq(#bags, 1)
    T.eq(bags[1].itemID, I.LINEN)
    -- Main's snapshot is intact.
    local main = P.GetCharacter("Mainchar-Stormrage")
    T.eq(main.scans.bags[1].itemID, I.OLD_POTION)
    -- The Warband snapshot scanned by main is visible to the crafter.
    local bank = P.GetScanList("bank")
    T.eq(#bank, 1)
    T.eq(bank[1].itemID, I.WARBOUND_TOY)
end)

T.test("roles: unassigned characters never count as beneficiaries", function()
    local g1 = loginAs(nil, MAIN)
    local saved = g1:logout()
    local g2 = loginAs(saved, CRAFTER)
    local P = g2:P()
    T.eq(#P.CharactersWith("receivesGear"), 0, "nobody assigned yet")
    P.SetCharacterRole("Mainchar-Stormrage", "main")
    P.SetCharacterRole("Stitcher-Stormrage", "crafter")
    local gear = P.CharactersWith("receivesGear")
    T.eq(#gear, 1)
    T.eq(gear[1].key, "Mainchar-Stormrage")
    T.eq(#P.CharactersWith("receivesMaterials"), 2)
    P.SetCharacterRole("Stitcher-Stormrage", "utility")
    T.eq(#P.CharactersWith("receivesMaterials"), 1)
end)

T.test("role suggestions follow level, professions, and leveling", function()
    local P = loginAs(nil, MAIN):P()
    T.eq((P.SuggestRole(P.GetCurrentCharacter())), "main")
    local P2 = loginAs(nil, CRAFTER):P()
    local role, reason = P2.SuggestRole(P2.GetCurrentCharacter())
    T.eq(role, "crafter")
    T.contains(reason, "Tailoring")
    local P3 = loginAs(nil, FARMER):P()
    T.eq((P3.SuggestRole(P3.GetCurrentCharacter())), "utility")
end)

T.test("a character that gained levels recently is suggested as Leveling", function()
    local g1 = loginAs(nil, { name = "Newbie", realm = "Stormrage", level = 30, classFile = "PRIEST" })
    local saved = g1:logout()
    local g2 = loginAs(saved, { name = "Newbie", realm = "Stormrage", level = 34, classFile = "PRIEST" })
    local P = g2:P()
    T.eq((P.SuggestRole(P.GetCurrentCharacter())), "leveling")
end)

T.test("suggestions learn from three similar characters", function()
    local saved
    for i = 1, 3 do
        local g = loginAs(saved, { name = "Crafty" .. i, realm = "R", level = 20, classFile = "MAGE",
            professions = { { name = "Alchemy", skillLine = 171 } } })
        g:P().SetCharacterRole("Crafty" .. i .. "-R", "utility")
        saved = g:logout()
    end
    local g = loginAs(saved, { name = "Crafty4", realm = "R", level = 22, classFile = "MAGE",
        professions = { { name = "Mining", skillLine = 186 } } })
    local P = g:P()
    local role, reason = P.SuggestRole(P.GetCurrentCharacter())
    T.eq(role, "utility", "learned from the player's own choices")
    T.contains(reason, "3 similar")
end)

T.test("bulk: accept suggestions for all unassigned characters", function()
    local saved = loginAs(nil, MAIN):logout()
    saved = loginAs(saved, CRAFTER):logout()
    local g = loginAs(saved, FARMER)
    local P = g:P()
    local changed = P.AcceptRoleSuggestions()
    T.eq(changed, 3)
    T.eq(P.GetRole(P.GetCharacter("Mainchar-Stormrage")), "main")
    T.eq(P.GetRole(P.GetCharacter("Stitcher-Stormrage")), "crafter")
    T.eq(P.GetRole(P.GetCharacter("Garrisonbob-Stormrage")), "utility")
end)

T.test("same-as-last: the most recently configured other character", function()
    local g = loginAs(loginAs(nil, CRAFTER):logout(), FARMER)
    local P = g:P()
    P.SetCharacterRole("Stitcher-Stormrage", "crafter")
    local last = P.LastConfiguredCharacter("Garrisonbob-Stormrage")
    T.eq(last.key, "Stitcher-Stormrage")
end)

T.test("upgrade: old account-wide scans go to the right owners", function()
    local old = S.v050()
    old.scans.bags = { { itemID = I.OLD_POTION, scope = "bags", bagID = 0, slot = 1, name = "Draenic Healing Potion" } }
    old.scans.bank = {
        { itemID = I.WARBOUND_TOY, scope = "bank", bagID = 12, slot = 1, storageKind = "Warband Bank" },
        { itemID = I.LINEN, scope = "bank", bagID = 6, slot = 1, storageKind = "Private Bank" },
    }
    local game = loginAs(old, MAIN)
    local db = game:db()
    T.eq(db.scans, nil, "account-wide scans removed")
    T.eq(db.schemaVersion, game:P().SCHEMA_VERSION)
    local char = game:P().GetCurrentCharacter()
    T.eq(char.scans.bags[1].itemID, I.OLD_POTION, "first character claims the old bag scan")
    T.eq(db.warband.items[1].itemID, I.WARBOUND_TOY, "warband items become the account snapshot")
    T.eq(db.unassignedBankScan.items[1].itemID, I.LINEN, "character bank kept unassigned")
    T.eq(db.pendingBagScanClaim, nil, "claim consumed")
end)

T.test("realm spelling never creates a duplicate character", function()
    local g = loginAs(nil, { name = "Spaced", realm = "Area 52", level = 90, classFile = "MAGE" })
    T.eq(g:P().GetCurrentCharacter().key, "Spaced-Area52")
    local count = 0
    for _ in pairs(g:db().characters) do count = count + 1 end
    T.eq(count, 1)
end)

T.test("logout strips transient decision fields from saved snapshots", function()
    local g = loginAs(nil, MAIN, function(w) w:put(0, 1, I.OLD_POTION, 5) end)
    g:db().rules.items[I.OLD_POTION] = { protect = true }
    g:Core().ScanInventory("bags", true)
    g:P().GetAllDecisions()                       -- decorates records with rule, reason, ...
    local saved = g:logout()
    local record = saved.characters["Mainchar-Stormrage"].scans.bags[1]
    T.eq(record.rule, nil, "no duplicated rule table")
    T.eq(record.blockedReasons, nil)
    T.eq(record.itemID, I.OLD_POTION, "scan data kept")
    -- Next session still works.
    local g2 = loginAs(saved, MAIN, function(w) w:put(0, 1, I.OLD_POTION, 5) end)
    T.eq(g2:P().GetAllDecisions()[1].rule.protect, true)
end)