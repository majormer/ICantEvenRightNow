-- I Can't Even Right Now (With My Bags and Bank) — Triage (decisions)
-- The anti-hoard model: one stored decision per item ("sell", "auction",
-- "destroy", "keep", "use", "defer") that every task reads. A decision is a
-- preference, never an action: the cards still act on selection and clicks.
-- The screen that asks for decisions comes in a later sitting; this file is
-- the store, the reasons it feeds, and two commands for offline triage
-- (export the classified inventory, feed decisions back). Neither command is
-- documented for players: they exist so the player and an assistant can go
-- through the bank outside the game (spec: .local/docs/Anti_Hoard_Triage_Spec.md).

local ADDON_NAME, ns = ...

local Core = ns.Core
local P    = ns.Private

local DAY = 24 * 3600
local DEFAULT_DEFER_DAYS = 30

local CHOICES = { sell = true, auction = true, destroy = true, keep = true, use = true, defer = true }
P.DECISION_CHOICES = CHOICES

local function Now() return time and time() or 0 end

local function Store()
    ns.DB.decisions = ns.DB.decisions or {}
    return ns.DB.decisions
end

function P.TriageDeferDays()
    local ui = ns.DB and ns.DB.ui
    local days = ui and tonumber(ui.triageDeferDays)
    return days and days > 0 and days or DEFAULT_DEFER_DAYS
end

-- Record a decision. opts: { reason, note, days (defer), name }.
-- Returns the stored record, or nil and a message.
function P.SetDecision(itemID, choice, opts)
    itemID = tonumber(itemID)
    if not itemID then return nil, "No item." end
    if not CHOICES[choice] then return nil, "Unknown choice: " .. tostring(choice) end
    opts = opts or {}
    local record = { choice = choice, at = Now(), by = P.currentCharacterKey, name = opts.name,
        reason = opts.reason, note = opts.note }
    if choice == "defer" then
        record.until_ = Now() + (tonumber(opts.days) or P.TriageDeferDays()) * DAY
    end
    Store()[itemID] = record
    P.Log("triage", "decision %s: %s (%s)%s", tostring(itemID), choice, tostring(opts.name),
        record.until_ and (" until " .. (date and date("%Y-%m-%d", record.until_) or record.until_)) or "")
    return record
end

function P.ClearDecision(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end
    local had = Store()[itemID] ~= nil
    Store()[itemID] = nil
    return had
end

-- The decision for an item, or nil. A defer that has run out is returned
-- with `due = true` so the item comes back for a fresh look.
function P.GetDecision(itemID)
    if not (ns.DB and itemID) then return nil end
    local record = Store()[itemID]
    if not record then return nil end
    if record.choice == "defer" and record.until_ and Now() >= record.until_ then
        record.due = true
    end
    return record
end

-- Items that left the account (sold, listed, destroyed) drop their outward
-- decision; keep/use/defer stay in case the item comes back.
function P.SweepDecisions()
    if not (ns.DB and ns.DB.decisions and P.CountAcrossAccount) then return 0 end
    local dropped = 0
    for itemID, record in pairs(ns.DB.decisions) do
        if record.choice == "sell" or record.choice == "auction" or record.choice == "destroy" then
            local total = P.CountAcrossAccount(itemID)
            if (total or 0) == 0 then
                ns.DB.decisions[itemID] = nil
                dropped = dropped + 1
            end
        end
    end
    if dropped > 0 then P.Log("triage", "%d decision(s) dropped: the items are gone", dropped) end
    return dropped
end

-- Counts for Home: decided / undecided per scope, and decided-out totals.
function P.DecisionSummary()
    local summary = { sell = 0, auction = 0, destroy = 0, keep = 0, use = 0, defer = 0, due = 0 }
    for _, record in pairs(Store()) do
        summary[record.choice] = (summary[record.choice] or 0) + 1
        if record.due then summary.due = summary.due + 1 end
    end
    return summary
end

-- ---------------------------------------------------------------------------
-- Offline triage: export and feed-back (not documented for players)
-- ---------------------------------------------------------------------------

-- Wowhead links for the screen and the export.
function P.WowheadItemURL(itemID) return "https://www.wowhead.com/item=" .. tostring(itemID) end
function P.WowheadQuestURL(questID) return "https://www.wowhead.com/quest=" .. tostring(questID) end

local function ExportRecord(item, snapshotScope)
    local explanation = P.ExplainScanned(item)
    local reasons = {}
    for _, r in ipairs(explanation.reasons or {}) do
        reasons[#reasons + 1] = { id = r.id, evidence = r.evidence }
    end
    local channels = P.ItemChannels and P.ItemChannels(item) or {}
    local price = P.GetAuctionPrice and P.GetAuctionPrice(item)
    local decision = P.GetDecision(item.itemID)
    local record = {
        itemID = item.itemID, name = item.name, count = item.count or 1, location = item.location,
        scope = snapshotScope, storageKind = item.storageKind,
        quality = item.quality, itemLevel = item.itemLevel, requiredLevel = item.requiredLevel,
        classID = item.classID, subclassID = item.subclassID, itemType = item.itemTypeName, itemSubType = item.itemSubTypeName,
        expansionID = item.expansionID, expansion = P.GetExpansionName and P.GetExpansionName(item.expansionID),
        binding = item.bindingScope, sellPrice = item.sellPrice,
        questID = item.questID, questActive = item.questActive or nil, questCompleted = item.questCompleted or nil,
        disposition = explanation.disposition, primary = explanation.primary and explanation.primary.id,
        label = explanation.label, evidence = explanation.evidence, held = explanation.held,
        reasons = reasons,
        channels = { vendor = channels.vendor, auction = channels.auction, mail = channels.mail, trade = channels.trade,
            warbandBank = channels.warbandBank, destroy = channels.destroy, use = channels.use, why = channels.why },
        auctionPrice = price and price.price, priceSource = price and P.FormatPriceSource and P.FormatPriceSource(price),
        listingPrice = P.ListingPrice and (P.ListingPrice(item)) or nil,
        decision = decision and { choice = decision.choice, at = decision.at, until_ = decision.until_, note = decision.note } or nil,
        wowhead = P.WowheadItemURL(item.itemID),
        wowheadQuest = item.questID and P.WowheadQuestURL(item.questID) or nil,
    }
    if P.WhoBenefits then record.whoBenefits = P.WhoBenefits(item) end
    return record
end

-- /icanteven export [bank|warband|bags|all]: writes ns.DB.export (saved on
-- reload or logout) with every item of the scope and how the addon reads it.
function P.ExportInventory(scopeWord)
    scopeWord = (scopeWord or "all"):lower()
    if scopeWord == "" then scopeWord = "all" end
    local currentKey = P.currentCharacterKey or P.GetCharacterKey()
    local items = {}
    local function include(snapshotScope, list)
        for _, item in ipairs(list or {}) do items[#items + 1] = ExportRecord(item, snapshotScope) end
    end
    local run = function()
        for _, snapshot in ipairs(P.AllSnapshots()) do
            local mine = snapshot.character and snapshot.character.key == currentKey
            if snapshot.scope == "warband" and (scopeWord == "all" or scopeWord == "warband") then
                include("warband", snapshot.items)
            elseif mine and snapshot.scope == P.BANK_SCOPE and (scopeWord == "all" or scopeWord == "bank") then
                include("bank", snapshot.items)
            elseif mine and snapshot.scope == P.BAG_SCOPE and (scopeWord == "all" or scopeWord == "bags") then
                include("bags", snapshot.items)
            end
        end
    end
    if P.WithEvaluationCache then P.WithEvaluationCache(run) else run() end
    ns.DB.export = { at = Now(), scope = scopeWord, character = currentKey, version = P.ADDON_VERSION, items = items }
    P.Log("triage", "export: %d item(s), scope %s", #items, scopeWord)
    return #items
end

-- /icanteven decide <itemID> <choice> [days|note]
function P.DecideCommand(args)
    local itemID, choice, rest = (args or ""):match("^(%d+)%s+(%a+)%s*(.-)$")
    if not itemID then
        return "Usage: /icanteven decide <itemID> sell|auction|destroy|keep|use|defer|clear [days or note]"
    end
    choice = choice:lower()
    if choice == "clear" then
        return P.ClearDecision(itemID) and ("Decision cleared for item " .. itemID .. ".") or ("No decision for item " .. itemID .. ".")
    end
    local name
    local total, _ = P.CountAcrossAccount and P.CountAcrossAccount(tonumber(itemID))
    for _, snapshot in ipairs(P.AllSnapshots()) do
        for _, item in ipairs(snapshot.items or {}) do
            if item.itemID == tonumber(itemID) then name = item.name break end
        end
        if name then break end
    end
    local days = choice == "defer" and tonumber(rest) or nil
    local record, err = P.SetDecision(itemID, choice, { name = name, days = days, note = (not days and rest ~= "") and rest or nil })
    if not record then return err end
    if Core.RefreshUI and P.UI and P.UI.frame and P.UI.frame:IsShown() then Core.RefreshUI() end
    return "Decided: " .. (name or ("item " .. itemID)) .. " -> " .. choice
        .. (record.until_ and (" until " .. (date and date("%Y-%m-%d", record.until_) or "")) or "")
        .. ((total or 0) == 0 and " (not in your scans yet)" or "")
end

-- Many decisions at once: one per line, "<itemID> <choice> [note]" (a
-- leading "/icanteven decide " is ignored, so exported lines paste as-is;
-- text after "--" is a comment). Returns applied, skipped, and messages.
function P.ApplyDecisionLines(text)
    local applied, skipped, messages = 0, 0, {}
    for raw in tostring(text or ""):gmatch("[^\r\n]+") do
        local line = raw:gsub("%-%-.*$", ""):gsub("^%s*/icanteven%s+decide%s+", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then
            local result = P.DecideCommand(line)
            if result:sub(1, 8) == "Decided:" or result:sub(1, 8) == "Decision" then
                applied = applied + 1
            else
                skipped = skipped + 1
                if #messages < 5 then messages[#messages + 1] = raw .. " -> " .. result end
            end
        end
    end
    P.Log("triage", "applied %d decision line(s), %d skipped", applied, skipped)
    return applied, skipped, messages
end

-- /icanteven decisions: a box to paste decision lines into (Ctrl+V works in
-- WoW edit boxes), then Apply. Undocumented, like the commands it serves.
local pasteBox
function P.ShowDecisionPasteBox()
    if not CreateFrame then return nil end
    if not pasteBox then
        local frame = CreateFrame("Frame", "ICantEvenDecisionPasteBox", UIParent, "BackdropTemplate")
        frame:SetSize(560, 360)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(true) frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        if frame.SetBackdrop then
            frame:SetBackdrop({ bgFile = "Interface\DialogFrame\UI-DialogBox-Background", edgeFile = "Interface\DialogFrame\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
        end
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -16)
        title:SetText("Paste decisions (one per line: itemID choice [note]), then Apply")
        local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 20, -40)
        scroll:SetPoint("BOTTOMRIGHT", -40, 50)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(490)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(edit)
        frame.edit = edit
        local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status:SetPoint("BOTTOMLEFT", 20, 22)
        frame.status = status
        local apply = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        apply:SetSize(100, 24) apply:SetPoint("BOTTOMRIGHT", -20, 16) apply:SetText("Apply")
        apply:SetScript("OnClick", function()
            local applied, skipped, messages = P.ApplyDecisionLines(edit:GetText())
            status:SetText(applied .. " applied, " .. skipped .. " skipped" .. (#messages > 0 and (": " .. messages[1]) or ""))
            for _, m in ipairs(messages) do P.Print(m) end
            if applied > 0 then edit:SetText("") end
            if Core.RefreshUI then Core.RefreshUI() end
        end)
        local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        close:SetSize(80, 24) close:SetPoint("RIGHT", apply, "LEFT", -8, 0) close:SetText("Close")
        close:SetScript("OnClick", function() frame:Hide() end)
        pasteBox = frame
    end
    pasteBox:Show()
    pasteBox.edit:SetFocus()
    return pasteBox
end
