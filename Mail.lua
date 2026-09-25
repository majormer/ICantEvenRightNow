-- I Can't Even Right Now (With My Bags and Bank) — Auction mail reminder
-- Auctions expire within 48 hours and come back by mail, sale gold arrives by
-- mail, and mail is deleted 30 days after it arrives. A character that listed
-- auctions and then sat unplayed loses them. The addon can't read another
-- character's mailbox, so it records, per character:
--   auctionAt   last auction house visit (AUCTION_HOUSE_SHOW)
--   mail        what the inbox held at the last mailbox visit: when checked,
--               how many mails carry items or gold, and the soonest expiry
--   auctionFlag the player's own "Auctions" mark (Characters tab)
-- and warns, on any character, before the earliest known deadline.

local ADDON_NAME, ns = ...

local P = ns.Private

local DAY = 86400
local MAIL_LIFETIME_DAYS = 30
local AUCTION_RECENT_DAYS = 60 -- an AH visit this recent marks an auction character
local WARN_DAYS = 10           -- warn this many days before a deadline
local URGENT_DAYS = 3
P.MAIL_WARN_DAYS = WARN_DAYS

local function Now() return time and time() or 0 end

function P.IsMailReminderEnabled()
    return not (ns.DB and ns.DB.ui and ns.DB.ui.auctionMailReminder == false)
end

function P.IsAuctionCharacter(char)
    if not char then return false end
    if char.auctionFlag then return true end
    return (char.auctionAt or 0) > 0 and Now() - char.auctionAt <= AUCTION_RECENT_DAYS * DAY
end

function P.SetAuctionFlag(key, flag)
    local char = P.GetCharacter(key)
    if char then char.auctionFlag = flag and true or nil end
end

-- AUCTION_HOUSE_SHOW on the current character.
function P.NoteAuctionHouseVisit()
    local char = P.GetCurrentCharacter()
    if char then
        char.auctionAt = Now()
        P.Log("mail", "%s visited the auction house", char.key)
    end
end

-- MAIL_INBOX_UPDATE while the mailbox is open: record what can expire.
function P.RecordInbox()
    if not (GetInboxNumItems and GetInboxHeaderInfo) then return end
    local char = P.GetCurrentCharacter()
    if not char then return end
    local shown, total = GetInboxNumItems()
    shown = tonumber(shown) or 0
    local valuable, soonest = 0, nil
    for i = 1, shown do
        local _, _, _, _, money, _, daysLeft, hasItem = GetInboxHeaderInfo(i)
        if ((money or 0) > 0 or (hasItem or 0) ~= 0) and type(daysLeft) == "number" then
            valuable = valuable + 1
            if not soonest or daysLeft < soonest then soonest = daysLeft end
        end
    end
    char.mail = {
        checkedAt = Now(),
        valuable = valuable,
        total = tonumber(total) or shown,
        soonestExpiresAt = soonest and (Now() + soonest * DAY) or nil,
    }
    P.Log("mail", "%s inbox: %d mail(s) with items or gold, soonest expires in %s day(s)",
        char.key, valuable, soonest and string.format("%.1f", soonest) or "-")
end

-- The earliest known date something in this character's mail could be
-- deleted, and why. nil when nothing is known to be at risk.
function P.MailDeadline(char)
    if not char then return nil end
    local mail = char.mail
    local deadline, reason
    if mail and mail.soonestExpiresAt and (mail.valuable or 0) > 0 then
        deadline, reason = mail.soonestExpiresAt, "mail"
    end
    -- Auction returns and sale gold arrive after the last AH visit; if that
    -- visit came after the last mailbox check, count 30 days from it.
    local auctionAt = char.auctionAt or 0
    if auctionAt > 0 and auctionAt > ((mail and mail.checkedAt) or 0) then
        local fromAuctions = auctionAt + MAIL_LIFETIME_DAYS * DAY
        if not deadline or fromAuctions < deadline then deadline, reason = fromAuctions, "auctions" end
    end
    -- Marked by the player but never seen at the AH or mailbox with the addon.
    if not deadline and char.auctionFlag and not mail and (char.lastSeen or 0) > 0 then
        deadline, reason = char.lastSeen + MAIL_LIFETIME_DAYS * DAY, "unknown"
    end
    return deadline, reason
end

-- Characters whose mail deadline is within the warning window (or past).
-- Each: { character, deadline, daysLeft, reason }.
function P.MailAtRisk()
    local list = {}
    if not P.IsMailReminderEnabled() then return list end
    for _, char in ipairs(P.GetCharacters()) do
        local deadline, reason = P.MailDeadline(char)
        local relevant = reason == "mail" or P.IsAuctionCharacter(char)
        if deadline and relevant then
            local daysLeft = (deadline - Now()) / DAY
            if daysLeft <= WARN_DAYS then
                table.insert(list, { character = char, deadline = deadline, daysLeft = daysLeft, reason = reason })
            end
        end
    end
    table.sort(list, function(a, b) return a.deadline < b.deadline end)
    return list
end

-- One short phrase for a character at risk.
function P.MailRiskText(risk)
    local days = math.ceil(risk.daysLeft)
    local when
    if risk.daysLeft <= 0 then
        when = "may already have been deleted"
    elseif risk.daysLeft < 1 then
        when = "may be deleted within a day"
    else
        when = "may be deleted in " .. days .. " day" .. (days == 1 and "" or "s")
    end
    local what = risk.reason == "mail" and "Mail with items or gold"
        or (risk.reason == "auctions" and "Auction returns and gold" or "Auction mail")
    return what .. " " .. when
end
