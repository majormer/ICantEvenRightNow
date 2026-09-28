local T = ...
local F = require("fixtures")
local I = F.ITEMS

local MAIN = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" }
local TANKALT = { name = "Tankalt", realm = "R", level = 60, classFile = "PALADIN" }
local TAILOR = { name = "Tailor", realm = "R", level = 20, classFile = "MAGE",
    professions = { { name = "Tailoring", skillLine = 197 } } }

-- Build a roster by logging characters in once, returning saved data.
local function roster(roles, equippedByName)
    local saved
    for _, spec in ipairs(roles) do
        local g = T.game({ savedVariables = saved, player = spec.player, setup = function(w)
            F.defineItems(w)
            F.addBank(w)
            for slot, level in pairs((equippedByName or {})[spec.player.name] or {}) do w.equipped[slot] = level end
        end })
        g:P().SetCharacterRole(spec.player.name .. "-R", spec.role)
        saved = g:logout()
    end
    return saved
end

local function login(saved, player, populate)
    return T.game({ savedVariables = saved, player = player, setup = F.setup(populate) })
end

local function selectAndRun(game, taskName)
    local P, UI = game:P(), game:UI()
    P.OpenTask(taskName)
    for _, plan in ipairs(UI.transferVisible) do
        if plan.movable then UI.transferSelected[plan.key] = true end
    end
    game.world:withHardwareEvent(function() game:Core().ExecuteTransferSelected() end)
    game:advance(2)
end

T.test("recipients are filtered by role and usability", function()
    local saved = roster({
        { player = MAIN, role = "main" }, { player = TANKALT, role = "leveling" }, { player = TAILOR, role = "crafter" },
    })
    local g = login(saved, MAIN, function(w)
        w:put(0, 1, I.BOUND_HELM, 1)     -- plate, required level 70
        w:put(0, 2, I.LINEN, 20)
    end)
    g:Core().ScanInventory("bags", true)
    local P = g:P()
    local helm, linen
    for _, item in ipairs(P.GetScanList("bags")) do
        if item.itemID == I.BOUND_HELM then helm = item elseif item.itemID == I.LINEN then linen = item end
    end
    T.eq(#P.HandoffRecipients(helm), 0, "level-60 leveling paladin can't use a level-70 helm yet; crafter never gets gear")
    local toLinen = P.HandoffRecipients(linen)
    T.eq(toLinen[1].name, "Tailor", "the tailor who uses linen comes first")
end)

T.test("full hand-off: mark, deposit via Send to Alts, collect via Waiting for You", function()
    local saved = roster({ { player = MAIN, role = "main" }, { player = TAILOR, role = "crafter" } })
    -- On Main: mark linen for Tailor and deposit it.
    local g = login(saved, MAIN, function(w) w:put(0, 1, I.LINEN, 20) end)
    g:openBank()
    local P = g:P()
    local linen = P.GetScanList("bags")[1]
    T.ok(P.QueueHandoff(linen, "Tailor-R"))
    local sendCard
    for _, c in ipairs(P.GetTaskCards()) do if c.name == "Send to Alts" then sendCard = c end end
    T.eq(sendCard.ready, 1)
    selectAndRun(g, "Send to Alts")
    T.eq(g.world:findItem(I.LINEN)[1].bagID >= 12, true, "linen went to the Warband bank")
    T.eq(P.GetHandoffs()[1].state, "deposited")
    saved = g:logout()

    -- On Tailor: the item is waiting.
    local g2 = T.game({ savedVariables = saved, player = TAILOR, setup = function(w)
        F.defineItems(w); F.addBank(w)
        w:put(12, 1, I.LINEN, 20)
    end })
    g2:openBank()
    local P2 = g2:P()
    local waiting
    for _, c in ipairs(P2.GetTaskCards()) do if c.name == "Waiting for You" then waiting = c end end
    T.eq(waiting.ready, 1)
    selectAndRun(g2, "Waiting for You")
    T.eq(g2.world:findItem(I.LINEN)[1].bagID < 6, true, "tailor collected the linen")
    T.eq(#P2.GetHandoffs(), 0, "entry cleared once collected")
end)

T.test("stale hand-offs clear when the item is gone; sender is reminded after 14 days", function()
    local saved = roster({ { player = MAIN, role = "main" }, { player = TAILOR, role = "crafter" } })
    local g = login(saved, MAIN, function(w) w:put(0, 1, I.LINEN, 20) end)
    g:openBank()
    local P = g:P()
    P.QueueHandoff(P.GetScanList("bags")[1], "Tailor-R")
    selectAndRun(g, "Send to Alts")
    g:closeBank()
    g:advance(15 * 24 * 3600)
    g:slash("")
    local text = g:UI().frame.panels.Home.notice.text:GetText() or ""
    local notices = g:P().GetHomeNotices()
    local found = false
    for _, n in ipairs(notices) do if n.id == "handoff-reminder" then found = true; T.contains(n.text, "waiting for Tailor") end end
    T.ok(found, "reminder notice registered")
    -- Someone takes the linen out of the Warband bank elsewhere: entry clears on next scan.
    g.world.containers[12].slots = {}
    g:openBank()
    T.eq(#P.GetHandoffs(), 0)
end)

T.test("who benefits names an upgrade for a specific alt", function()
    local saved = roster({ { player = MAIN, role = "main" }, { player = TANKALT, role = "leveling" } },
        { Tankalt = { [16] = 200 } })
    local g = login(saved, MAIN, function(w)
        w:defineItem(8101, { name = "Big Sword", classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON",
            itemLevel = 300, requiredLevel = 50, bindType = 2, sellPrice = 100, expansionID = 9 })
        w:put(0, 1, 8101, 1)
    end)
    g:Core().ScanInventory("bags", true)
    local P = g:P()
    local sword = P.GetScanList("bags")[1]
    T.contains(P.WhoBenefits(sword), "Upgrade for")
    T.contains(P.WhoBenefits(sword), "Tankalt (Leveling)")
    local explanation = P.ExplainScanned(sword)
    T.eq(explanation.primary.id, "usable_gear")
    T.contains(explanation.evidence, "Upgrade for")
end)

T.test("where is it: slash search and item tooltips across the account", function()
    local g1 = T.game({ player = TAILOR, setup = F.setup(function(w) w:put(0, 1, I.LINEN, 20) end) })
    g1:Core().ScanInventory("bags", true)
    local g = T.game({ savedVariables = g1:logout(), player = MAIN, setup = F.setup(function(w) w:put(0, 1, I.LINEN, 5) end) })
    g:Core().ScanInventory("bags", true)
    local mark = g:logMark()
    g:slash("where linen")
    local out = g:printed(mark)
    T.contains(out, "Linen Cloth: 25")
    T.contains(out, "Tailor bags 20")
    local lines = table.concat(g.world:showItemTooltip(I.LINEN), "\n")
    T.contains(lines, "Your account: 25")
    g:db().ui.whereTooltip = false
    T.eq(#g.world:showItemTooltip(I.LINEN), 0, "setting turns it off")
end)

T.test("row menu 'Send to an alt...' opens a picker that queues the hand-off", function()
    local saved = roster({ { player = MAIN, role = "main" }, { player = TAILOR, role = "crafter" } })
    local g = login(saved, MAIN, function(w) w:put(0, 1, I.LINEN, 20) end)
    g:openBank()
    g:slash("transfer")
    local UI = g:UI()
    UI.transferSource, UI.transferDest = "Bags", "Bank (All Tabs)"
    g:Core().RefreshUI()
    local row = UI.frame.panels.Transfer.rows[1]
    g:click(row.rule)
    local send
    for _, b in ipairs(row.ruleMenu.buttons) do if b:GetText() == "Send to an alt..." then send = b end end
    g:click(send)
    local picker = UI.handoffPicker
    T.ok(picker:IsShown())
    T.eq(picker:GetFrameStrata(), "TOOLTIP", "above the main window's strata")
    T.contains(picker.buttons[1]:GetText(), "Tailor")
    g:click(picker.buttons[1])
    T.eq(g:P().GetHandoffs()[1].to, "Tailor-R")
    T.contains(g:printed(), "Marked Linen Cloth for Tailor")
end)
T.test("gear that isn't an upgrade for anyone is the player's call, even from the current expansion", function()
    local saved = roster({ { player = MAIN, role = "main" } }, { Main = { [16] = 305 } })
    local g = login(saved, MAIN, function(w)
        w:defineItem(8102, { name = "Old Blade", classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON",
            itemLevel = 270, requiredLevel = 80, bindType = 1, sellPrice = 100, expansionID = 11 })
        w.equipped[16] = 305
        w:put(0, 1, 8102, 1)
    end)
    g:Core().ScanInventory("bags", true)
    local P = g:P()
    local blade = P.GetScanList("bags")[1]
    local explanation = P.ExplainScanned(blade)
    T.eq(explanation.primary.id, "outgrown_gear")
    T.eq(explanation.disposition, "review")
end)
T.test("a hand-off that can't move says why on its card", function()
    local saved = roster({ { player = MAIN, role = "main" }, { player = TAILOR, role = "crafter" } })
    local g = T.game({ savedVariables = saved, player = MAIN, setup = function(w)
        F.defineItems(w)
        F.addBank(w, { warbandSize = 1 })
        w:put(0, 1, I.LINEN, 20)
        w:put(12, 1, I.OLD_SWORD, 1) -- the only Warband slot is taken
    end })
    g:openBank()
    local P = g:P()
    T.ok(P.QueueHandoff(P.GetScanList("bags")[1], "Tailor-R"))
    local card
    for _, c in ipairs(P.GetTaskCards()) do if c.name == "Send to Alts" then card = c end end
    T.eq(card.ready, 0)
    T.eq(card.blocked, 1)
    T.contains(P.CardSummary(card), "1 blocked: ")
end)

T.test("a bags-only rescan right after a row deposit keeps the hand-off", function()
    local saved = roster({ { player = MAIN, role = "main" }, { player = TAILOR, role = "crafter" } })
    local g = login(saved, MAIN, function(w) w:put(0, 1, I.LINEN, 20) end)
    g:openBank()
    local P, UI = g:P(), g:UI()
    T.ok(P.QueueHandoff(P.GetScanList("bags")[1], "Tailor-R"))
    P.OpenTask("Send to Alts")
    -- Row button (single item), like the in-game click.
    g:Core().ExecuteTransferOne(UI.transferVisible[1])
    g:Core().ScanInventory("bags", true)   -- the quick bag-update rescan
    T.eq(P.GetHandoffs()[1] and P.GetHandoffs()[1].state, "deposited")
    g.world:advance(10)                      -- later full rescans see it in the Warband bank
    T.eq(P.GetHandoffs()[1] and P.GetHandoffs()[1].state, "deposited")
end)

T.test("unknown equipment is not an upgrade target; levels read later are used", function()
    -- Tankalt's gear wasn't loaded at login: saved as zeros (like real saves).
    local saved = roster({ { player = MAIN, role = "main" }, { player = TANKALT, role = "leveling" } })
    saved.characters["Tankalt-R"].equipped = { [16] = 0, [1] = 0 }
    saved.characters["Tankalt-R"].averageItemLevel = nil
    local g = login(saved, MAIN, function(w)
        w:defineItem(8103, { name = "Old Hammer", classID = 2, subclassID = 5, equipLoc = "INVTYPE_WEAPON",
            itemLevel = 150, requiredLevel = 50, bindType = 2, sellPrice = 100, expansionID = 9 })
        w:put(0, 1, 8103, 1)
    end)
    g:Core().ScanInventory("bags", true)
    local P = g:P()
    local hammer = P.GetScanList("bags")[1]
    T.eq(#P.UpgradeUsersFor(hammer), 0, "zeros mean unknown, not empty slots")
    -- With a known average above the item, still no upgrade.
    g:db().characters["Tankalt-R"].averageItemLevel = 220
    T.eq(#P.UpgradeUsersFor(hammer), 0)
    g:db().characters["Tankalt-R"].averageItemLevel = 120
    T.eq(#P.UpgradeUsersFor(hammer), 1, "above the known average: an upgrade")
end)

T.test("gear levels are read again after login when they weren't loaded", function()
    local g = T.game({ player = MAIN, setup = function(w)
        F.defineItems(w); F.addBank(w)
        w.equippedAverage = 0         -- not loaded at login
    end })
    local char = g:P().GetCurrentCharacter()
    T.eq(next(char.equipped or {}), nil)
    g.world.equipped[16] = 280
    g.world.equippedAverage = 275
    g.world:advance(6)
    T.eq(char.equipped[16], 280)
    T.eq(char.averageItemLevel, 275)
end)

T.test("weapon types and primary stats limit who can use gear", function()
    local DRUID = { name = "Druidalt", realm = "R", level = 90, classFile = "DRUID" }
    local PRIEST = { name = "Priestalt", realm = "R", level = 90, classFile = "PRIEST" }
    local saved = roster({ { player = MAIN, role = "main" }, { player = DRUID, role = "leveling" },
        { player = PRIEST, role = "leveling" } })
    local g = login(saved, MAIN, function(w)
        w:defineItem(8201, { name = "Old Bow", classID = 2, subclassID = 2, equipLoc = "INVTYPE_RANGED",
            itemLevel = 300, requiredLevel = 80, bindType = 2, sellPrice = 1, expansionID = 9 })
        w:defineItem(8202, { name = "Old Sword", classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON",
            itemLevel = 300, requiredLevel = 80, bindType = 2, sellPrice = 1, expansionID = 9,
            stats = { ITEM_MOD_STRENGTH_SHORT = 10 } })
        w:defineItem(8203, { name = "Brute Trinket", classID = 4, subclassID = 0, equipLoc = "INVTYPE_TRINKET",
            itemLevel = 300, requiredLevel = 80, bindType = 2, sellPrice = 1, expansionID = 9,
            stats = { ITEM_MOD_STRENGTH_SHORT = 10 } })
        w:defineItem(8204, { name = "Hybrid Trinket", classID = 4, subclassID = 0, equipLoc = "INVTYPE_TRINKET",
            itemLevel = 300, requiredLevel = 80, bindType = 2, sellPrice = 1, expansionID = 9,
            stats = { ITEM_MOD_AGILITY_INTELLECT_SHORT = 10 } })
        w:put(0, 1, 8201, 1) w:put(0, 2, 8202, 1) w:put(0, 3, 8203, 1) w:put(0, 4, 8204, 1)
    end)
    g:Core().ScanInventory("bags", true)
    local P = g:P()
    local function users(id)
        for _, item in ipairs(P.GetScanList("bags")) do
            if item.itemID == id then
                local names = {}
                for _, c in ipairs(P.GearUsersFor(item)) do names[#names + 1] = c.name end
                table.sort(names)
                return table.concat(names, ",")
            end
        end
    end
    T.eq(users(8201), "Main", "a warrior can use a bow; druids and priests cannot")
    T.eq(users(8202), "Main", "swords: not druids or priests")
    T.eq(users(8203), "Main", "a Strength trinket only for the warrior")
    T.eq(users(8204), "Druidalt,Priestalt", "Agility/Intellect trinket: druid and priest, not a Strength warrior")
end)

T.test("equipment sets keep items; max-level trinkets and weapons are your call, never pre-sold", function()
    local saved = roster({ { player = MAIN, role = "main" } }, { Main = { [13] = 300, [14] = 300, [16] = 300 } })
    local g = T.game({ savedVariables = saved, player = MAIN, setup = function(w)
        F.defineItems(w) F.addBank(w)
        w.equipped[13], w.equipped[14], w.equipped[16] = 300, 300, 300
        w:defineItem(8301, { name = "Odd Trinket", classID = 4, subclassID = 0, equipLoc = "INVTYPE_TRINKET",
            itemLevel = 280, requiredLevel = 90, bindType = 1, quality = 4, sellPrice = 500, expansionID = 11 })
        w:defineItem(8302, { name = "Set Trinket", classID = 4, subclassID = 0, equipLoc = "INVTYPE_TRINKET",
            itemLevel = 270, requiredLevel = 90, bindType = 1, quality = 4, sellPrice = 500, expansionID = 11 })
        w:defineItem(8303, { name = "Leveling Sword", classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON",
            itemLevel = 180, requiredLevel = 85, bindType = 2, quality = 2, sellPrice = 50, expansionID = 11 })
        w:put(0, 1, 8301, 1) w:put(0, 2, 8302, 1) w:put(0, 3, 8303, 1)
        w.equipmentSets = { { name = "M+", items = { [13] = 8302 } } }
    end })
    g:Core().ScanInventory("bags", true)
    local P = g:P()
    local function explain(id)
        for _, item in ipairs(P.GetScanList("bags")) do if item.itemID == id then return P.ExplainScanned(item) end end
    end
    T.eq(explain(8301).primary.id, "situational_gear")
    T.eq(explain(8301).disposition, "review")
    T.eq(explain(8302).primary.id, "equipment_set")
    T.contains(explain(8302).evidence, "Main's M+ set")
    -- A set piece stays in the bags: the game can't swap in banked gear.
    local setItem
    for _, item in ipairs(P.GetScanList("bags")) do if item.itemID == 8302 then setItem = item end end
    T.ok(P.IsHeadedOut(setItem), "never offered for the bank")
    -- 180 against a worn 300 is far below (2026-09-28: item level 15 bows on a
    -- level 83 Hunter stayed "your call"); it can go like other outgrown gear.
    T.eq(explain(8303).primary.id, "outgrown_no_upgrade", "a weapon far below the worn one is outgrown")
end)

T.test("soulbound gear only counts for the character who owns it", function()
    local saved = roster({ { player = MAIN, role = "main" }, { player = TANKALT, role = "leveling" } },
        { Tankalt = { [2] = 100 } })
    local g = login(saved, MAIN, function(w)
        w.equipped[2] = 400
        w:defineItem(8401, { name = "Bound Pendant", classID = 4, subclassID = 0, equipLoc = "INVTYPE_NECK",
            itemLevel = 300, requiredLevel = 50, bindType = 1, quality = 4, sellPrice = 100, expansionID = 11 })
        w:put(0, 1, 8401, 1, { bound = true })
    end)
    g:Core().ScanInventory("bags", true)
    local P = g:P()
    local pendant = P.GetScanList("bags")[1]
    T.eq(pendant.isSoulbound, true)
    T.eq(#P.UpgradeUsersFor(pendant), 0, "Tankalt can't receive a soulbound item")
    T.ok(P.ExplainScanned(pendant).primary.id ~= "usable_gear")
end)

T.test("Deposit to Warband leaves out gear that can go", function()
    local saved = roster({ { player = MAIN, role = "main" } }, { Main = { [10] = 300 } })
    local g = T.game({ savedVariables = saved, player = MAIN, setup = function(w)
        F.defineItems(w) F.addBank(w)
        w.equipped[10] = 300
        -- Warbound-until-equipped cloth gloves: a warrior can't wear them.
        w:defineItem(8501, { name = "Silk Gloves", classID = 4, subclassID = 1, equipLoc = "INVTYPE_HAND",
            itemLevel = 250, requiredLevel = 80, bindType = 2, quality = 3, sellPrice = 100, expansionID = 11 })
        w:put(0, 1, 8501, 1, { warboundUntilEquipped = true })
    end })
    g:openBank()
    local card
    for _, c in ipairs(g:P().GetTaskCards()) do if c.name == "Deposit to Warband" then card = c end end
    T.eq(card.total, 0, "nobody can wear it: sell it, don't store it")
end)

-- The Auctions mark routes: on any other character, auctionables go to the
-- Warband bank for the auction character (the player: "only Kiosk should",
-- 2026-09-28); the auction character sees them waiting and lists them.
local KIOSK = { name = "Kiosk", realm = "R", level = 40, classFile = "DEATHKNIGHT" }
local function priceFor(g, itemID, copper)
    local def = g.world.items[itemID]
    local key = def.maxStack > 1 and ("c:" .. itemID) or ("i:" .. itemID .. ":" .. g.env.GetRealmName())
    g:db().prices = g:db().prices or {}
    g:db().prices[key] = { price = copper, at = g.env.time() }
end
local function cardNamed(g, name)
    for _, c in ipairs(g:P().GetTaskCards()) do if c.name == name then return c end end
end

T.test("auction character: auctionables are handed to it through the Warband bank", function()
    -- Main wears better than the sword, so it is outgrown, not an upgrade.
    local saved = roster({ { player = MAIN, role = "main" }, { player = KIOSK, role = "utility" } },
        { Main = { [16] = 400 } })
    local g = login(saved, MAIN, function(w)
        w:put(0, 1, I.OLD_SWORD, 1)
        w.collections.appearances[70001] = true   -- look already collected: nothing keeps it
    end)
    local P = g:P()
    P.SetAuctionFlag("Kiosk-R", true)
    T.eq(P.AuctionCharacter().name, "Kiosk")
    T.eq(P.AuctionHandoffTarget().name, "Kiosk", "another character lists")
    priceFor(g, I.OLD_SWORD, 5000000)   -- 500g at auction, 40s at a vendor
    g:Core().ScanInventory("bags", true)
    local card = cardNamed(g, "Auction Candidates")
    T.ok(card, "card exists")
    T.contains(P.CardSummary(card), "1 to hand to Kiosk")
    T.contains(card.description, "Handed to Kiosk through the Warband bank")
    T.eq(card.task.preset.dest, P.STORAGE_WARBAND_ROUTED, "the route is the Warband bank, not the auction house")
    local hasAuctionator = P.HasAuctionator
    P.HasAuctionator = function() return true end
    T.no(card.task.secondary.isAvailable(), "no Save to Auctionator while Kiosk lists")
    P.SetAuctionFlag("Kiosk-R", false)
    T.ok(card.task.secondary.isAvailable(), "offered again when this character lists")
    P.SetAuctionFlag("Kiosk-R", true)
    P.HasAuctionator = hasAuctionator
    local trip = P.TripPlan(P.GetTaskCards()) or ""
    T.no(trip:find("auction house", 1, true), "no auction house stop for this character")
    T.contains(trip, "bank")
    -- At the bank: the review deposits it; a rescan marks it waiting for Kiosk.
    g:openBank()
    selectAndRun(g, "Auction Candidates")
    T.eq(g.world:findItem(I.OLD_SWORD)[1].bagID >= 12, true, "sword went to the Warband bank")
    g:Core().ScanInventory("all", true)
    card = cardNamed(g, "Auction Candidates")
    T.contains(P.CardSummary(card), "1 in the Warband bank, waiting for Kiosk")
    T.eq(card.ready, 0, "nothing left for this character to move")
    T.ok(card.task.preset.source ~= P.STORAGE_WARBAND_BANK, "never pulls Kiosk's items back out")
    local entries = P.GetHandoffs(function(e) return e.to == "Kiosk-R" and e.state == "deposited" end)
    T.eq(#entries, 1, "a deposited hand-off for Kiosk")
    T.eq(#P.GetHandoffs(), 1, "recorded once, however often the card refreshes")
    -- Standing at an auction house, listing here is still allowed.
    g:closeBank()
    g.world:put(0, 2, I.VALUABLE_ORE, 20)
    priceFor(g, I.VALUABLE_ORE, 900000)
    g:Core().ScanInventory("bags", true)
    g:openAuctionHouse()
    T.eq(cardNamed(g, "Auction Candidates").task.preset.dest, P.STORAGE_AUCTION_HOUSE)
    g:closeAuctionHouse()
    saved = g:logout()

    -- On Kiosk: the sword is waiting, and the card lists as usual.
    local k = T.game({ savedVariables = saved, player = KIOSK, setup = function(w)
        F.defineItems(w); F.addBank(w)
        w:put(12, 1, I.OLD_SWORD, 1)
        w.collections.appearances[70001] = true
    end })
    local PK = k:P()
    T.eq(PK.AuctionHandoffTarget(), nil, "Kiosk lists its own")
    k:openBank()
    T.eq(cardNamed(k, "Waiting for You").ready, 1)
    T.contains(PK.CardSummary(cardNamed(k, "Auction Candidates")), "1 in the Warband bank")
    T.contains(PK.TripPlan(PK.GetTaskCards()) or "", "bank")
    selectAndRun(k, "Waiting for You")
    T.eq(k.world:findItem(I.OLD_SWORD)[1].bagID < 6, true, "Kiosk collected the sword")
    T.eq(#PK.GetHandoffs(), 0, "entry cleared")
    T.contains(PK.TripPlan(PK.GetTaskCards()) or "", "auction house (1 to list)")
end)

T.test("only one character carries the Auctions mark", function()
    local saved = roster({ { player = MAIN, role = "main" }, { player = KIOSK, role = "utility" } })
    local g = login(saved, MAIN, function() end)
    local P = g:P()
    P.SetAuctionFlag("Kiosk-R", true)
    P.SetAuctionFlag("Main-R", true)
    T.eq(P.AuctionCharacter().name, "Main")
    T.no(P.GetCharacter("Kiosk-R").auctionFlag)
    P.SetAuctionFlag("Main-R", false)
    T.eq(P.AuctionCharacter(), nil)
end)
