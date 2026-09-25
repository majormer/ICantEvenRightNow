-- I Can't Even Right Now (With My Bags and Bank) — Home, Characters, notices
-- Home replaces Summary and the task dropdown: every task is a card with a
-- live count, and clicking a card opens its review list. Nothing on Home
-- moves or sells anything; actions still happen in the review list.

local ADDON_NAME, ns = ...

local Core = ns.Core
local P    = ns.Private

local UI = P.UI
local BAG_SCOPE  = P.BAG_SCOPE
local BANK_SCOPE = P.BANK_SCOPE

local CARD_WIDTH, CARD_HEIGHT = 398, 100
local CARD_GAP = 10
local CARDS_PER_PAGE = 6
local CARDS_TOP = -112

local function Kit() return P.UIKit end

local function Now() return time and time() or 0 end

local function FormatAge(timestamp)
    if not timestamp or timestamp == 0 then return "never" end
    local seconds = Now() - timestamp
    if seconds < 90 then return "just now" end
    if seconds < 3600 then return math.floor(seconds / 60) .. " min ago" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. " h ago" end
    local days = math.floor(seconds / 86400)
    return days .. " day" .. (days == 1 and "" or "s") .. " ago"
end
P.FormatAge = FormatAge

local function ContextHeadline()
    local context = ns.DB.context
    if context.inCombat then return "In combat" end
    if context.vendorOpen then return "At a vendor" end
    if context.bankOpen then return "At a bank" end
    if context.auctionHouseOpen then return "At the auction house" end
    return "Bags only"
end

-- ---------------------------------------------------------------------------
-- Home notices (setup, onboarding, What's New). Other modules register more.
-- A notice: { id, text, buttons = { { label, onClick, style } }, priority }
-- ---------------------------------------------------------------------------

local NOTICE_PROVIDERS = {}
function P.RegisterHomeNotice(provider) table.insert(NOTICE_PROVIDERS, provider) end

local function GetHomeNotices()
    local notices = {}
    for _, provider in ipairs(NOTICE_PROVIDERS) do
        local ok, notice = pcall(provider)
        if ok and notice then table.insert(notices, notice) end
    end
    table.sort(notices, function(a, b) return (a.priority or 50) < (b.priority or 50) end)
    return notices
end
P.GetHomeNotices = GetHomeNotices

-- Role question for the current character (onboarding O1/O3).
P.RegisterHomeNotice(function()
    local char = P.GetCurrentCharacter()
    if not char or char.role or char.roleQuestionDismissed then return nil end
    local role, reason = P.SuggestRole(char)
    local label = P.GetRoleLabel(role)
    local buttons = {
        { label = "Yes, " .. label, style = "primary", onClick = function()
            P.SetCharacterRole(char.key, role)
            Core.RefreshUI()
        end },
    }
    local last = P.LastConfiguredCharacter(char.key)
    if last and last.role ~= role then
        buttons[#buttons + 1] = { label = "Same as " .. last.name, onClick = function()
            P.SetCharacterRole(char.key, last.role)
            Core.RefreshUI()
        end }
    end
    buttons[#buttons + 1] = { label = "Choose...", onClick = function() Kit().SetTab("Characters") end }
    buttons[#buttons + 1] = { label = "Later", onClick = function()
        char.roleQuestionDismissed = true
        Core.RefreshUI()
    end }
    return {
        id = "role", priority = 20,
        text = "What is " .. (char.name or "this character") .. "? Suggested: " .. label .. " (" .. reason .. ").",
        buttons = buttons,
    }
end)

-- ---------------------------------------------------------------------------
-- Home tab
-- ---------------------------------------------------------------------------

local function CreateCard(parent, index)
    local kit = Kit()
    local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
    card:SetSize(CARD_WIDTH, CARD_HEIGHT)
    local column = (index - 1) % 2
    local rowIndex = math.floor((index - 1) / 2)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", column * (CARD_WIDTH + CARD_GAP), CARDS_TOP - rowIndex * (CARD_HEIGHT + CARD_GAP))
    card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    card:RegisterForClicks("LeftButtonUp")

    card.title = kit.CreateLabel(card, "", "GameFontNormalLarge")
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
    card.title:SetWidth(CARD_WIDTH - 60)
    card.title:SetWordWrap(false)

    card.summary = kit.CreateLabel(card, "", "GameFontHighlight")
    card.summary:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
    card.summary:SetWidth(CARD_WIDTH - 24)
    card.summary:SetWordWrap(false)

    -- One full-width line; the whole description is in the card's tooltip.
    card.description = kit.CreateLabel(card, "", "GameFontDisableSmall")
    card.description:SetPoint("TOPLEFT", card.summary, "BOTTOMLEFT", 0, -6)
    card.description:SetWidth(CARD_WIDTH - 24)
    card.description:SetWordWrap(false)

    card.open = kit.CreateButton(card, "Review", 84, 22)
    card.open:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 8)

    -- Optional second action (e.g. "Check in Auctionator").
    card.secondary = kit.CreateButton(card, "", 150, 22)
    card.secondary:SetPoint("RIGHT", card.open, "LEFT", -6, 0)
    card.secondary:Hide()

    card.remove = kit.CreateButton(card, "x", 22, 20, "danger")
    card.remove:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
    card.remove:Hide()
    return card
end

function P.BuildHomeTab(parent)
    local kit = Kit()
    parent.headline = kit.CreateLabel(parent, "", "GameFontHighlightLarge")
    parent.headline:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    parent.scanInfo = kit.CreateLabel(parent, "", "GameFontDisableSmall")
    parent.scanInfo:SetPoint("TOPLEFT", parent.headline, "BOTTOMLEFT", 0, -6)

    parent.custom = kit.CreateButton(parent, "Custom transfer", 120, 24)
    parent.custom:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    parent.custom:SetScript("OnClick", function() kit.SetTab("Transfer") end)
    parent.rescan = kit.CreateButton(parent, "Rescan", 80, 24)
    parent.rescan:SetPoint("RIGHT", parent.custom, "LEFT", -8, 0)
    parent.rescan:SetScript("OnClick", function()
        Core.ScanInventory(ns.DB.context.bankOpen and "all" or BAG_SCOPE, true)
        Core.RefreshUI()
    end)

    -- Notice strip (setup questions, What's New, tips).
    parent.notice = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    parent.notice:SetSize(CARD_WIDTH * 2 + CARD_GAP, 56)
    parent.notice:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -46)
    parent.notice:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    parent.notice:SetBackdropColor(0.12, 0.09, 0.03, 0.9)
    parent.notice:SetBackdropBorderColor(0.7, 0.55, 0.2, 0.9)
    parent.notice.text = kit.CreateLabel(parent.notice, "", "GameFontHighlight")
    parent.notice.text:SetPoint("TOPLEFT", parent.notice, "TOPLEFT", 10, -8)
    parent.notice.text:SetWidth(CARD_WIDTH * 2 - 20)
    parent.notice.buttons = {}
    for i = 1, 4 do
        local button = kit.CreateButton(parent.notice, "", 110, 20)
        if i == 1 then
            button:SetPoint("BOTTOMLEFT", parent.notice, "BOTTOMLEFT", 10, 6)
        else
            button:SetPoint("LEFT", parent.notice.buttons[i - 1], "RIGHT", 6, 0)
        end
        button:Hide()
        parent.notice.buttons[i] = button
    end

    parent.cards = {}
    for i = 1, CARDS_PER_PAGE do parent.cards[i] = CreateCard(parent, i) end

    parent.page = 1
    parent.prevPage = kit.CreateButton(parent, "<", 28, 22)
    parent.prevPage:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    parent.prevPage:SetScript("OnClick", function() parent.page = math.max(1, parent.page - 1) Core.RefreshUI() end)
    parent.pageText = kit.CreateLabel(parent, "", "GameFontDisableSmall")
    parent.pageText:SetPoint("LEFT", parent.prevPage, "RIGHT", 8, 0)
    parent.nextPage = kit.CreateButton(parent, ">", 28, 22)
    parent.nextPage:SetPoint("LEFT", parent.pageText, "RIGHT", 8, 0)
    parent.nextPage:SetScript("OnClick", function() parent.page = parent.page + 1 Core.RefreshUI() end)
end

local function StyleCard(card, state)
    if state == "ready" then
        card:SetBackdropColor(0.10, 0.08, 0.03, 0.92)
        card:SetBackdropBorderColor(0.80, 0.62, 0.18, 1)
    elseif state == "waiting" then
        card:SetBackdropColor(0.05, 0.06, 0.08, 0.88)
        card:SetBackdropBorderColor(0.35, 0.37, 0.42, 0.95)
    else
        card:SetBackdropColor(0.03, 0.03, 0.04, 0.70)
        card:SetBackdropBorderColor(0.18, 0.18, 0.20, 0.80)
    end
end

function P.RefreshHome()
    local panel = UI.frame and UI.frame.panels and UI.frame.panels.Home
    if not panel then return end
    local kit = Kit()
    local char = P.GetCurrentCharacter()
    local warband = P.GetWarbandSnapshot()
    panel.headline:SetText(ContextHeadline())
    panel.scanInfo:SetText("Bags scanned " .. FormatAge(char.lastScan.bags)
        .. "  -  Bank " .. FormatAge(char.lastScan.bank)
        .. "  -  Warband bank " .. FormatAge(warband.scannedAt))
    panel.rescan:SetEnabled(not ns.DB.context.inCombat)

    -- Notice strip
    local notices = GetHomeNotices()
    local notice = notices[1]
    panel.notice:SetShown(notice ~= nil)
    local cardsTop = notice and CARDS_TOP or -46
    if notice then
        panel.notice.text:SetText(notice.text)
        for i, button in ipairs(panel.notice.buttons) do
            local spec = notice.buttons and notice.buttons[i]
            if spec then
                button:SetText(spec.label)
                button:SetWidth(math.max(80, #spec.label * 7 + 16))
                kit.SetButtonStyle(button, spec.style or "secondary")
                button:SetScript("OnClick", spec.onClick)
                button:Show()
            else
                button:Hide()
            end
        end
    end

    -- Cards
    local cards = P.GetTaskCards()
    panel.cardData = cards
    local pages = math.max(1, math.ceil(#cards / CARDS_PER_PAGE))
    if panel.page > pages then panel.page = pages end
    local first = (panel.page - 1) * CARDS_PER_PAGE
    for i, widget in ipairs(panel.cards) do
        local card = cards[first + i]
        local column = (i - 1) % 2
        local rowIndex = math.floor((i - 1) / 2)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", panel, "TOPLEFT", column * (CARD_WIDTH + CARD_GAP), cardsTop - rowIndex * (CARD_HEIGHT + CARD_GAP))
        if card then
            widget.card = card
            widget.title:SetText(card.name)
            widget.summary:SetText(P.CardSummary(card))
            widget.description:SetText(card.description or "")
            local state = card.ready > 0 and "ready" or (card.waiting > 0 and "waiting" or "empty")
            StyleCard(widget, state)
            local routeOK, needs = P.TaskRouteAvailable(card.task)
            if routeOK then
                widget.open:SetText(card.ready > 0 and "Review" or "Open")
            else
                widget.open:SetText(needs)
            end
            widget.open:SetEnabled(routeOK and true or false)
            kit.SetButtonStyle(widget.open, (routeOK and card.ready > 0) and "primary" or "secondary")
            local name = card.name
            widget.open:SetScript("OnClick", function() P.OpenTask(name) end)
            widget:SetScript("OnClick", function() if routeOK then P.OpenTask(name) end end)
            local secondary = card.task and card.task.secondary
            local showSecondary = secondary and (not secondary.isAvailable or secondary.isAvailable())
            if showSecondary then
                local label = type(secondary.label) == "function" and secondary.label() or secondary.label
                widget.secondary:SetText(label or "")
                widget.secondary:SetScript("OnClick", function()
                    secondary.run()
                    Core.RefreshUI()
                end)
                widget.secondary:Show()
            else
                widget.secondary:Hide()
            end
            local fullDescription = card.description
            widget:SetScript("OnEnter", function(self)
                if fullDescription and fullDescription ~= "" then
                    kit.ShowTooltip(self, { name, P.CardSummary(card), fullDescription })
                end
            end)
            widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
            if card.kind == "saved" then
                widget.remove:Show()
                widget.remove:SetScript("OnClick", function()
                    P.DeleteSavedFilter(name)
                    if UI.activeSavedFilterName == name then UI.activeSavedFilterName = nil end
                    Core.RefreshUI()
                end)
            else
                widget.remove:Hide()
            end
            widget:Show()
        else
            widget.card = nil
            widget:Hide()
        end
    end
    panel.prevPage:SetShown(pages > 1)
    panel.nextPage:SetShown(pages > 1)
    panel.pageText:SetShown(pages > 1)
    panel.prevPage:SetEnabled(panel.page > 1)
    panel.nextPage:SetEnabled(panel.page < pages)
    panel.pageText:SetText("Page " .. panel.page .. " of " .. pages)
end

-- ---------------------------------------------------------------------------
-- Characters tab (roster, roles, bulk setup)
-- ---------------------------------------------------------------------------

local CHAR_ROWS = 9
local CHAR_ROW_HEIGHT = 34

local function RoleOptions()
    local options = {}
    for _, role in ipairs(P.ROLE_ORDER) do
        table.insert(options, { text = P.GetRoleLabel(role), value = role })
    end
    return options
end

function P.BuildCharactersTab(parent)
    local kit = Kit()
    parent.help = kit.CreateLabel(parent, "Roles decide who benefits from an item. Unassigned characters are ignored.", "GameFontHighlight")
    parent.help:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    parent.counts = kit.CreateLabel(parent, "", "GameFontDisableSmall")
    parent.counts:SetPoint("TOPLEFT", parent.help, "BOTTOMLEFT", 0, -6)

    parent.acceptAll = kit.CreateButton(parent, "Accept all suggestions", 170, 24, "primary")
    parent.acceptAll:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    parent.acceptAll:SetScript("OnClick", function()
        local changed = P.AcceptRoleSuggestions()
        P.Print("Set roles for " .. changed .. " character" .. (changed == 1 and "" or "s") .. ".")
        Core.RefreshUI()
    end)

    parent.note = kit.CreateLabel(parent,
        "Characters appear here after logging in once with the addon enabled. Roles can be set from any character.",
        "GameFontDisableSmall")
    parent.note:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)

    parent.listFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    parent.listFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -48)
    parent.listFrame:SetSize(806, CHAR_ROWS * CHAR_ROW_HEIGHT + 10)
    parent.listFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    parent.listFrame:SetBackdropColor(0, 0, 0, 0.2)

    parent.scrollFrame = CreateFrame("ScrollFrame", nil, parent.listFrame, "FauxScrollFrameTemplate")
    parent.scrollFrame:SetPoint("TOPLEFT", parent.listFrame, "TOPLEFT", 5, -5)
    parent.scrollFrame:SetPoint("BOTTOMRIGHT", parent.listFrame, "BOTTOMRIGHT", -29, 5)
    parent.scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, CHAR_ROW_HEIGHT, function() Core.RefreshUI() end)
    end)

    parent.rows = {}
    for i = 1, CHAR_ROWS do
        local row = CreateFrame("Frame", nil, parent.listFrame, "BackdropTemplate")
        row:SetSize(776, CHAR_ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", parent.listFrame, "TOPLEFT", 5, -5 - (i - 1) * CHAR_ROW_HEIGHT)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row:SetBackdropColor(0, 0, 0, i % 2 == 0 and 0.18 or 0.08)
        row.name = kit.CreateLabel(row, "", "GameFontHighlight")
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -4)
        row.name:SetWidth(310)
        row.name:SetWordWrap(false)
        row.facts = kit.CreateLabel(row, "", "GameFontDisableSmall")
        row.facts:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
        row.facts:SetWidth(310)
        row.facts:SetWordWrap(false)
        row.role = kit.CreateDropdown(row, 140, RoleOptions(), function(value)
            if row.character then P.SetCharacterRole(row.character.key, value) end
        end)
        row.role:SetPoint("LEFT", row, "LEFT", 330, 0)
        row.suggestion = kit.CreateLabel(row, "", "GameFontDisableSmall")
        row.suggestion:SetPoint("LEFT", row.role, "RIGHT", 10, 0)
        row.suggestion:SetWidth(220)
        row.suggestion:SetWordWrap(false)
        row.use = kit.CreateButton(row, "Use", 50, 20)
        row.use:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row:Hide()
        parent.rows[i] = row
    end
end

function P.RefreshCharacters()
    local panel = UI.frame and UI.frame.panels and UI.frame.panels.Characters
    if not panel then return end
    local kit = Kit()
    local characters = P.GetCharacters()
    local counts = P.CountByRole()
    local parts = {}
    for _, role in ipairs(P.ROLE_ORDER) do
        if counts[role] > 0 then parts[#parts + 1] = counts[role] .. " " .. P.GetRoleLabel(role) end
    end
    panel.counts:SetText(#characters .. " known character" .. (#characters == 1 and "" or "s")
        .. (#parts > 0 and (": " .. table.concat(parts, ", ")) or ""))
    panel.acceptAll:SetEnabled(counts.unassigned > 0)

    FauxScrollFrame_Update(panel.scrollFrame, #characters, CHAR_ROWS, CHAR_ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(panel.scrollFrame)
    for i, row in ipairs(panel.rows) do
        local char = characters[offset + i]
        row.character = char
        if char then
            local professions = {}
            for _, prof in ipairs(char.professions or {}) do
                if not prof.secondary then professions[#professions + 1] = prof.name end
            end
            local isCurrent = char.key == P.currentCharacterKey
            row.name:SetText((char.name or "?") .. "-" .. (char.realm or "?")
                .. (isCurrent and "  (you)" or ("  -  seen " .. FormatAge(char.lastSeen))))
            row.facts:SetText("Level " .. tostring(char.level or "?") .. " " .. (char.className or "")
                .. (#professions > 0 and ("  -  " .. table.concat(professions, ", ")) or ""))
            local role = P.GetRole(char)
            kit.SetDropdownText(row.role, P.GetRoleLabel(role))
            local suggested, reason = P.SuggestRole(char)
            if role == "unassigned" or suggested ~= role then
                row.suggestion:SetText("Suggested: " .. P.GetRoleLabel(suggested) .. " (" .. reason .. ")")
                row.use:Show()
                row.use:SetScript("OnClick", function()
                    P.SetCharacterRole(char.key, suggested)
                    Core.RefreshUI()
                end)
            else
                row.suggestion:SetText("")
                row.use:Hide()
            end
            row:Show()
        else
            row:Hide()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Bank / vendor notice (H2). Anchored to the screen, never to bank frames.
-- ---------------------------------------------------------------------------

local function EnsureNoticeFrame()
    if UI.contextNoticeFrame then return UI.contextNoticeFrame end
    local kit = Kit()
    local frame = CreateFrame("Frame", "ICantEvenRightNowNotice", UIParent, "BackdropTemplate")
    frame:SetSize(420, 36)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    frame:SetBackdropColor(0.08, 0.06, 0.02, 0.92)
    frame:SetBackdropBorderColor(0.8, 0.62, 0.18, 1)
    frame.text = kit.CreateLabel(frame, "", "GameFontHighlight")
    frame.text:SetPoint("LEFT", frame, "LEFT", 10, 0)
    frame.text:SetWidth(290)
    frame.text:SetWordWrap(false)
    frame.open = kit.CreateButton(frame, "Open", 60, 22, "primary")
    frame.open:SetPoint("RIGHT", frame, "RIGHT", -34, 0)
    frame.open:SetScript("OnClick", function()
        frame:Hide()
        if frame.secondary then
            frame.secondary.run()
            return
        end
        local name = frame.taskName
        Core.ShowHomeUI()
        local task = name and P.FindTask(name)
        if task and P.TaskRouteAvailable(task) then P.OpenTask(name) end
    end)
    frame.close = kit.CreateButton(frame, "x", 22, 22)
    frame.close:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    frame.close:SetScript("OnClick", function() frame:Hide() end)
    frame:Hide()
    UI.contextNoticeFrame = frame
    return frame
end

function P.HideContextNotice()
    if UI.contextNoticeFrame then UI.contextNoticeFrame:Hide() end
end

-- Called after a bank or vendor opens and the scan finished.
function P.OnContextOpened()
    local mode = ns.DB.ui.contextNotice or "notice"
    if mode == "off" or ns.DB.context.inCombat then return end
    if UI.frame and UI.frame:IsShown() then return end
    local card = P.GetTopReadyCard()
    if not card then return end
    if mode == "open" then
        Core.ShowHomeUI()
        return
    end
    local frame = EnsureNoticeFrame()
    frame.taskName = card.name
    frame.text:SetText(card.name .. ": " .. P.CardSummary(card))
    -- Prefer the card's direct action when it applies here (e.g. at the AH).
    local secondary = card.task and card.task.secondary
    if secondary and (not secondary.isAvailable or secondary.isAvailable()) then
        frame.secondary = secondary
        local label = type(secondary.label) == "function" and secondary.label() or secondary.label
        frame.open:SetText(label or "Open")
        frame.open:SetWidth(150)
    else
        frame.secondary = nil
        frame.open:SetText("Open")
        frame.open:SetWidth(60)
    end
    frame.text:SetWidth(420 - frame.open:GetWidth() - 60)
    frame:Show()
end

-- Recompute a shown notice (e.g. after auction prices change). Never shows
-- a hidden one: the player may have dismissed it.
function P.RefreshContextNotice()
    local frame = UI.contextNoticeFrame
    if not (frame and frame:IsShown()) then return end
    frame:Hide()
    P.OnContextOpened()
end

-- Cross-character hand-offs (Warband.lua) need both tasks and Home notices.
if P.RegisterHandoffTasks then P.RegisterHandoffTasks() end
if P.RegisterHandoffNotice then P.RegisterHandoffNotice() end
-- ---------------------------------------------------------------------------
-- Hand-off picker (W4): choose which alt an item is for.
-- ---------------------------------------------------------------------------

function P.ShowHandoffPicker(item)
    local kit = Kit()
    local frame = UI.handoffPicker
    if not frame then
        frame = CreateFrame("Frame", "ICantEvenRightNowHandoffPicker", UIParent, "BackdropTemplate")
        frame:SetSize(260, 60)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        frame.title = kit.CreateLabel(frame, "", "GameFontHighlight")
        frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
        frame.title:SetWidth(240)
        frame.buttons = {}
        for i = 1, 8 do
            local button = kit.CreateButton(frame, "", 240, 20)
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30 - (i - 1) * 22)
            button:Hide()
            frame.buttons[i] = button
        end
        frame.cancel = kit.CreateButton(frame, "Cancel", 80, 20)
        frame.cancel:SetScript("OnClick", function() frame:Hide() end)
        UI.handoffPicker = frame
    end
    local recipients = P.HandoffRecipients(item)
    frame.title:SetText(#recipients > 0 and ("Send " .. (item.name or "item") .. " to:")
        or "No other character with a matching role can use this.")
    for i, button in ipairs(frame.buttons) do
        local char = recipients[i]
        if char then
            button:SetText(char.name .. "  (" .. P.GetRoleLabel(P.GetRole(char)) .. ")")
            button:SetScript("OnClick", function()
                local ok, why = P.QueueHandoff(item, char.key)
                if ok then
                    P.Print("Marked " .. (item.name or "item") .. " for " .. char.name
                        .. ". Deposit it with \"Send to Alts\" at a bank.")
                else
                    P.Print(why)
                end
                frame:Hide()
                Core.RefreshUI()
            end)
            button:Show()
        else
            button:Hide()
        end
    end
    local rows = math.min(#recipients, #frame.buttons)
    frame.cancel:ClearAllPoints()
    frame.cancel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30 - rows * 22 - 4)
    frame:SetHeight(64 + rows * 22)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UI.frame or UIParent, "CENTER", 0, 0)
    -- The main window shares this strata at level 100; in game the picker was
    -- shown underneath it (invisible). Always draw above the window.
    frame:SetFrameLevel(((UI.frame and UI.frame:GetFrameLevel()) or 100) + 50)
    frame:Show()
    frame:Raise()
end

-- ---------------------------------------------------------------------------
-- Where is it? (W5)
-- ---------------------------------------------------------------------------

local function PlacesText(places)
    local parts = {}
    for i, place in ipairs(places) do
        if i > 4 then parts[#parts + 1] = "+" .. (#places - 4) .. " more" break end
        parts[#parts + 1] = place.label .. " " .. place.count .. " (" .. FormatAge(place.scannedAt) .. ")"
    end
    return table.concat(parts, ", ")
end

function P.WhereIsLines(query)
    query = (query or ""):lower()
    local lines = {}
    if query == "" then
        table.insert(lines, "Usage: /icanteven where <item name>")
        return lines
    end
    local byItem, order = {}, {}
    for _, snapshot in ipairs(P.AllSnapshots()) do
        for _, item in ipairs(snapshot.items) do
            if item.name and item.name:lower():find(query, 1, true) and not byItem[item.itemID] then
                byItem[item.itemID] = item.name
                table.insert(order, item.itemID)
            end
        end
    end
    if #order == 0 then
        table.insert(lines, "No scanned item matches \"" .. query .. "\". Characters appear after logging in with the addon.")
        return lines
    end
    for i, itemID in ipairs(order) do
        if i > 8 then table.insert(lines, "(" .. (#order - 8) .. " more matches; be more specific)") break end
        local total, places = P.CountAcrossAccount(itemID)
        table.insert(lines, byItem[itemID] .. ": " .. total .. " - " .. PlacesText(places))
    end
    return lines
end

-- Item tooltips anywhere in the game: "Your account: ..." (setting, on by default).
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not ns.DB or not ns.DB.ui or ns.DB.ui.whereTooltip == false then return end
        local itemID = data and data.id
        if not itemID or not tooltip or not tooltip.AddLine then return end
        local ok, total, places = pcall(P.CountAcrossAccount, itemID)
        if ok and total and total > 0 then
            tooltip:AddLine("Your account: " .. total .. " - " .. PlacesText(places), 0.6, 0.8, 1)
        end
    end)
end