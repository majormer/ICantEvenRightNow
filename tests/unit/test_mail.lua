local T = ...
local F = require("fixtures")

local DAY = 86400
local START = 1790000000
local KIOSK = { name = "Kiosk", realm = "R", level = 80, classFile = "DEATHKNIGHT" }
local MAIN = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" }

local function play(player, saved, now, action)
    local g = T.game({ player = player, savedVariables = saved, now = now, setup = F.setup() })
    if action then action(g) end
    return g, g:logout()
end

local function noticeText(g)
    for _, n in ipairs(g:P().GetHomeNotices()) do
        if n.id == "auction-mail" then return n.text, n.priority end
    end
end

T.test("an auction visit marks the character and warns before its mail can expire", function()
    local _, saved = play(KIOSK, nil, START, function(g) g.world:openAuctionHouse() end)
    -- 15 days later on the main: no warning yet.
    local g1 = play(MAIN, saved, START + 15 * DAY)
    T.eq(noticeText(g1), nil)
    T.ok(g1:P().IsAuctionCharacter(g1:P().GetCharacter("Kiosk-R")), "marked by the AH visit")
    -- 22 days later: warn (8 days left).
    local g2 = play(MAIN, saved, START + 22 * DAY)
    local text, priority = noticeText(g2)
    T.contains(text, "Kiosk: Auction returns and gold may be deleted in 8 days")
    T.contains(text, "Log in as Kiosk")
    T.eq(priority, 40)
    -- 28 days: urgent.
    local _, urgent = noticeText(play(MAIN, saved, START + 28 * DAY))
    T.eq(urgent, 12)
end)

T.test("opening the mailbox records real expiry dates and clears the auction deadline", function()
    local _, saved = play(KIOSK, nil, START, function(g)
        g.world:openAuctionHouse()
        g.world.inbox = { { money = 50000, daysLeft = 29 }, { hasItem = 1, daysLeft = 12 }, { daysLeft = 2 } }
        g.world:openMailbox()
    end)
    local g = play(MAIN, saved, START + 3 * DAY)
    local text = noticeText(g)
    T.contains(text, "Kiosk: Mail with items or gold may be deleted in 9 days", "12-day item mail, 3 days later")
    local _, saved2 = play(KIOSK, saved, START + 4 * DAY, function(k)
        k.world.inbox = {}
        k.world:openMailbox()
    end)
    T.eq(noticeText(play(MAIN, saved2, START + 20 * DAY)), nil, "emptied mailbox, no AH visit since")
end)

T.test("manual Auctions mark, setting off, and the Characters row warning", function()
    local _, saved = play(KIOSK, nil, START)
    local g = play(MAIN, saved, START + 25 * DAY)
    T.eq(noticeText(g), nil, "not an auction character yet")
    g:P().SetAuctionFlag("Kiosk-R", true)
    T.contains(noticeText(g), "Kiosk: Auction mail may be deleted in 5 days")
    g:slash("characters")
    local found
    for _, row in ipairs(g:UI().frame.panels.Characters.rows) do
        if row:IsShown() and row.character and row.character.name == "Kiosk" then
            found = row
        end
    end
    T.ok(found and found.auction:GetChecked(), "Auctions box checked")
    T.contains(found.facts:GetText(), "may be deleted in 5 days")
    g:db().ui.auctionMailReminder = false
    T.eq(noticeText(g), nil, "setting off")
end)

T.test("login prints a chat line for mail at risk", function()
    local _, saved = play(KIOSK, nil, START, function(g) g.world:openAuctionHouse() end)
    local g = play(MAIN, saved, START + 26 * DAY)
    g.world:advance(10)
    T.contains(g:printed(), "Kiosk: Auction returns and gold may be deleted in 4 days.")
end)
