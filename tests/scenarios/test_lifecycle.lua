-- Onboarding lifecycle scenarios (roadmap section 7, O3).
local T = ...
local F = require("fixtures")
local S = require("fixtures.saves")
local I = F.ITEMS

local DAY = 24 * 3600
local MAIN = { name = "Mainchar", realm = "R", level = 90, classFile = "WARRIOR" }
local ALT = { name = "Stitchalt", realm = "R", level = 14, classFile = "MAGE",
    professions = { { name = "Tailoring", skillLine = 197 } } }

local function session(saved, player, populate, now)
    return T.game({ savedVariables = saved, player = player, now = now, setup = F.setup(populate) })
end

local function homeNotice(game)
    game:slash("")
    local notice = game:UI().frame.panels.Home.notice
    return notice:IsShown() and notice.text:GetText() or nil, notice
end

local function clickNoticeButton(game, label)
    local _, notice = homeNotice(game)
    for _, button in ipairs(notice.buttons) do
        if button:IsShown() and button:GetText() == label then game:click(button) return true end
    end
    error("no notice button: " .. label)
end

T.test("main, first login: one role question, bank tasks wait for a bank", function()
    local g = session(nil, MAIN, function(w) w:put(0, 1, I.OLD_POTION, 5) end)
    local text = homeNotice(g)
    T.contains(text, "What is Mainchar? Suggested: Main / Active")
    T.notContains(text, "What's new", "fresh installs skip What's New")
    local card
    for _, widget in ipairs(g:UI().frame.panels.Home.cards) do
        if widget:IsShown() and widget.card.name == "Deposit Old Items" then card = widget end
    end
    T.contains(card.summary:GetText(), "Visit a bank")
    clickNoticeButton(g, "Yes, Main / Active")
    T.eq(g:P().GetRole(g:P().GetCurrentCharacter()), "main", "one click")
end)

T.test("main, first bank visit: notice, tip once, Warband tabs recorded", function()
    local g = session(nil, MAIN, function(w) w:put(0, 1, I.OLD_POTION, 5) end)
    g:P().SetCharacterRole("Mainchar-R", "main")
    g:openBank()
    T.ok(g:UI().contextNoticeFrame:IsShown(), "bank notice")
    T.eq(#g:db().warband.tabs, 1, "Warband tabs recorded")
    T.contains(homeNotice(g), "Tip: tasks find items for you")
    clickNoticeButton(g, "Got it")
    T.notContains(homeNotice(g) or "", "Tip: tasks find items")
end)

T.test("main, day 2: no questions once answered", function()
    local g = session(nil, MAIN, function(w) end)
    local P = g:P()
    P.SetCharacterRole("Mainchar-R", "main")
    homeNotice(g)
    clickNoticeButton(g, "Got it")                 -- dismiss the auction-price hint
    local saved = g:logout()
    local g2 = session(saved, MAIN, function(w) end, g.world.now + DAY)
    local text = homeNotice(g2)
    T.eq(text, nil, "nothing to answer on day 2")
end)

T.test("alt, first login: rules and tasks from the main apply; role suggested; hand-off waiting", function()
    -- Main sets a rule, saves a task, and sends linen to the alt.
    local g = session(nil, MAIN, function(w) w:put(0, 1, I.LINEN, 20) end)
    local P = g:P()
    P.SetCharacterRole("Mainchar-R", "main")
    g:db().rules.items[I.OLD_POTION] = { protect = true, name = "Draenic Healing Potion" }
    g:db().savedFilters[#g:db().savedFilters + 1] = { name = "My Mats", source = "Bags", dest = "Bank (All Tabs)",
        expansion = 0, bind = "All", type = "All", slot = "All", armorType = "All", upgrade = "All" }
    local saved = g:logout()
    -- The alt must exist before it can receive hand-offs: log it in once.
    local altFirst = session(saved, ALT, function(w) end)
    T.contains(homeNotice(altFirst), "Suggested: Crafter (Level 14 with Tailoring)")
    local sameAs
    for _, b in ipairs(altFirst:UI().frame.panels.Home.notice.buttons) do
        if b:IsShown() and b:GetText() == "Same as Mainchar" then sameAs = b end
    end
    T.ok(sameAs, "'Same as <last alt>' offered")
    T.eq(altFirst:db().rules.items[I.OLD_POTION].protect, true, "rules shared account-wide")
    local myMats
    for _, c in ipairs(altFirst:P().GetTaskCards()) do if c.name == "My Mats" then myMats = c end end
    T.ok(myMats, "saved task shared account-wide")
    clickNoticeButton(altFirst, "Yes, Crafter")
    saved = altFirst:logout()

    -- Main sends linen.
    local g2 = session(saved, MAIN, function(w) w:put(0, 1, I.LINEN, 20) end)
    g2:openBank()
    g2:P().QueueHandoff(g2:P().GetScanList("bags")[1], "Stitchalt-R")
    g2:P().OpenTask("Send to Alts")
    local UI = g2:UI()
    for _, plan in ipairs(UI.transferVisible) do if plan.movable then UI.transferSelected[plan.key] = true end end
    g2.world:withHardwareEvent(function() g2:Core().ExecuteTransferSelected() end)
    g2:advance(2)
    saved = g2:logout()

    -- Alt: Waiting for You is on Home (with the Warband snapshot main scanned).
    local g3 = T.game({ savedVariables = saved, player = ALT, setup = function(w)
        F.defineItems(w); F.addBank(w)
        w:put(12, 1, I.LINEN, 20)
    end })
    local waiting
    for _, c in ipairs(g3:P().GetTaskCards()) do if c.name == "Waiting for You" then waiting = c end end
    T.ok(waiting and waiting.total == 1, "waiting card before visiting a bank")
    T.contains(g3:P().CardSummary(waiting), "Visit a bank")
end)

T.test("alt, day 30: welcome back with bank age; max-level role check", function()
    local g = session(nil, { name = "Leveler", realm = "R", level = 70, classFile = "PRIEST" }, function(w) end)
    local P = g:P()
    P.SetCharacterRole("Leveler-R", "leveling")
    g:openBank()
    local saved = g:logout()
    local later = g.world.now + 30 * DAY
    local g2 = T.game({ savedVariables = saved, now = later,
        player = { name = "Leveler", realm = "R", level = 90, classFile = "PRIEST" }, setup = F.setup() })
    g2.world.maxLevel = 90
    local text = homeNotice(g2)
    T.contains(text, "Welcome back after 30 days.")
    T.contains(text, "Your bank list is 30 days old")
    clickNoticeButton(g2, "OK")
    T.contains(homeNotice(g2), "reached max level")
    clickNoticeButton(g2, "Switch to Main")
    T.eq(g2:P().GetRole(g2:P().GetCurrentCharacter()), "main")
end)

T.test("upgrader: What's New once, with the migration summary", function()
    local g = T.game({ savedVariables = S.v050(), player = MAIN, setup = F.setup() })
    local text = homeNotice(g)
    T.contains(text, "What's new in 0.6.0")
    T.contains(text, "carried over (3 rules, 3 saved tasks)")
    local mark = g:logMark()
    clickNoticeButton(g, "Details")
    T.contains(g:printed(mark), "Home: every task is a card")
    clickNoticeButton(g, "Got it")
    T.notContains(homeNotice(g) or "", "What's new")
    local g2 = T.game({ savedVariables = g:logout(), player = MAIN, setup = F.setup() })
    T.notContains(homeNotice(g2) or "", "What's new", "not shown again")
end)

T.test("first-time tips in the Transfer view show once per account", function()
    local g = session(nil, MAIN, function(w) w:put(0, 1, I.OLD_POTION, 5) end)
    g:openVendor()
    g:slash("transfer")
    local UI = g:UI()
    UI.transferSource, UI.transferDest = "Bags", "Vendor"
    g:Core().RefreshUI()
    T.contains(UI.frame.panels.Transfer.contextNotice:GetText(), "12 at a time")
    local saved = g:logout()
    local g2 = session(saved, ALT, function(w) w:put(0, 1, I.OLD_POTION, 5) end)
    g2:openVendor()
    g2:slash("transfer")
    local UI2 = g2:UI()
    UI2.transferSource, UI2.transferDest = "Bags", "Vendor"
    g2:Core().RefreshUI()
    T.notContains(UI2.frame.panels.Transfer.contextNotice:GetText() or "", "12 at a time", "seen on the main already")
end)
