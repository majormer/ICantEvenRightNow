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
    T.ok(picker:GetFrameLevel() > UI.frame:GetFrameLevel(), "drawn above the main window")
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