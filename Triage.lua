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
        reason = opts.reason, note = opts.note, reaffirmed = opts.reaffirmed or nil }
    if choice == "defer" then
        record.until_ = Now() + (tonumber(opts.days) or P.TriageDeferDays()) * DAY
    end
    -- "Keep N, the rest go": only an outward choice can have a kept share.
    local keepCount = tonumber(opts.keepCount)
    if keepCount and keepCount > 0 and (choice == "sell" or choice == "auction" or choice == "destroy") then
        record.keepCount = math.floor(keepCount)
    end
    Store()[itemID] = record
    P.InvalidateDecisionSurplus()
    P.Log("triage", "decision %s: %s (%s)%s", tostring(itemID), choice, tostring(opts.name),
        record.until_ and (" until " .. (date and date("%Y-%m-%d", record.until_) or record.until_)) or "")
    return record
end

function P.ClearDecision(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end
    local had = Store()[itemID] ~= nil
    Store()[itemID] = nil
    P.InvalidateDecisionSurplus()
    return had
end

-- ---------------------------------------------------------------------------
-- Quantity decisions: "keep N, the rest go"
-- A decision is per item, but the player keeps 60 Phoenix Oil and auctions
-- the rest, or keeps one of five duplicate trinkets and sells four. The
-- kept share is the first N units in this order: highest item level first,
-- then bags before the character bank before the Warband bank, then larger
-- stacks first. A stack that straddles the boundary is kept whole. Every
-- other stack is "surplus" and carries the outward decision.
-- ---------------------------------------------------------------------------
-- Stackables keep the bags copies (60 oils to carry); gear keeps the banked
-- copy (the Warband bank is where the alts reach it) and lets the bag copy go.
local SCOPE_ORDER = { bags = 0, bank = 1, warband = 2 }
local GEAR_SCOPE_ORDER = { warband = 0, bank = 1, bags = 2 }
local surplusCache = {}

function P.InvalidateDecisionSurplus() surplusCache = {} end

-- One key per stack: the item's GUID when the scanner recorded one (it
-- follows the item across moves, so a kept copy stays kept after a deposit
-- or a pull), else the location. `owner` is written by the scanner
-- (character key, or "warband"); older scans without it key on "".
function P.StackKey(item)
    if item.guid then return item.guid end
    return tostring(item.owner or "") .. "|" .. tostring(item.scope or "") .. "|" .. tostring(item.bagID or "") .. "|" .. tostring(item.slot or "")
end

function P.DecisionSurplus(itemID)
    local cached = surplusCache[itemID]
    if cached then return cached end
    local record = Store()[itemID]
    local surplus = {}
    if record and record.keepCount and P.AllSnapshots then
        local stacks = {}
        for _, snapshot in ipairs(P.AllSnapshots()) do
            for _, item in ipairs(snapshot.items or {}) do
                if item.itemID == itemID then stacks[#stacks + 1] = item end
            end
        end
        -- Stacks kept last time stay kept (record.keptKeys): otherwise a
        -- surplus copy pulled into the bags would outrank the copy it was
        -- meant to lose to (bags before banks) and the two would swap places
        -- on every scan (seen in game with Winged Terror Gloves, 2026-09-28).
        local keptBefore = record.keptKeys or {}
        table.sort(stacks, function(a, b)
            local la, lb = a.itemLevel or 0, b.itemLevel or 0
            if la ~= lb then return la > lb end
            local ka, kb = keptBefore[P.StackKey(a)] and 0 or 1, keptBefore[P.StackKey(b)] and 0 or 1
            if ka ~= kb then return ka < kb end
            local order = ((a.maxStack or 1) <= 1) and GEAR_SCOPE_ORDER or SCOPE_ORDER
            local sa, sb = order[a.scope] or 3, order[b.scope] or 3
            if sa ~= sb then return sa < sb end
            local ca, cb = a.count or 1, b.count or 1
            if ca ~= cb then return ca > cb end
            return P.StackKey(a) < P.StackKey(b)
        end)
        local kept, keptKeys = 0, {}
        for _, stack in ipairs(stacks) do
            if kept < record.keepCount then
                kept = kept + (stack.count or 1)
                keptKeys[P.StackKey(stack)] = true
            else
                surplus[P.StackKey(stack)] = true
            end
        end
        if #stacks > 0 then record.keptKeys = keptKeys end
    end
    surplusCache[itemID] = surplus
    return surplus
end

-- The decision as it applies to this particular stack: a kept share reads as
-- a keep ("kept copy"); a surplus stack carries the outward choice.
function P.EffectiveDecision(item)
    if not (item and item.itemID) then return nil end
    local record = P.GetDecision(item.itemID)
    if not record or not record.keepCount then return record end
    if P.DecisionSurplus(item.itemID)[P.StackKey(item)] then return record end
    return { choice = "keep", keptCopy = true, keepCount = record.keepCount, restChoice = record.choice,
        at = record.at, by = record.by, name = record.name, note = record.note }
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

-- A decision the game has refused: sell when a merchant won't buy it, auction
-- when the auction house refused it. Returns the reason text, or nil.
function P.DecisionBlocked(itemID, record)
    record = record or P.GetDecision(itemID)
    if not record then return nil end
    if record.choice == "sell" and P.MerchantRefused and P.MerchantRefused(itemID) then
        return "vendors won't buy it"
    end
    if record.choice == "auction" and P.AuctionRefused and P.AuctionRefused(itemID) then
        local refusal = P.AuctionRefused(itemID)
        return "the auction house refused it" .. (refusal and refusal.reason and (": " .. tostring(refusal.reason)) or "")
    end
    return nil
end

-- Items that left the account (sold, listed, destroyed) drop their outward
-- decision; keep/use/defer stay in case the item comes back.
-- An item is "gone" only when two scans at least this far apart both miss it.
-- Right after a bank pull the moved stacks are in neither snapshot for a few
-- seconds (the bank scan no longer has them, the bag slots are still locked),
-- and one sweep in that window dropped 40 destroy decisions (2026-09-28).
local MISSING_GRACE_SECONDS = 120

function P.SweepDecisions()
    if not (ns.DB and ns.DB.decisions and P.CountAcrossAccount) then return 0 end
    local dropped, now = 0, Now()
    for itemID, record in pairs(ns.DB.decisions) do
        if record.choice == "sell" or record.choice == "auction" or record.choice == "destroy" then
            local total = P.CountAcrossAccount(itemID)
            if (total or 0) > 0 then
                record.missingSince = nil
            elseif not record.missingSince then
                record.missingSince = now
            elseif now - record.missingSince >= MISSING_GRACE_SECONDS then
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
        return "Usage: /icanteven decide <itemID> sell|auction|destroy|keep|carry|use|defer|clear [keep <n>] [days or note]"
    end
    choice = choice:lower()
    -- "carry" is the triage screen's "keep it in your bags": a keep with the
    -- note "carry" (in game, 5 pasted carry lines answered "Unknown choice").
    local carry = choice == "carry"
    if carry then choice, rest = "keep", "carry" end
    if choice == "clear" then
        return P.ClearDecision(itemID) and ("Decision cleared for item " .. itemID .. ".") or ("No decision for item " .. itemID .. ".")
    end
    local name, found
    local total, _ = P.CountAcrossAccount and P.CountAcrossAccount(tonumber(itemID))
    for _, snapshot in ipairs(P.AllSnapshots()) do
        for _, item in ipairs(snapshot.items or {}) do
            if item.itemID == tonumber(itemID) then name, found = item.name, item break end
        end
        if name then break end
    end
    -- Keeping a lapsed keep again is an answer: it stays kept from now on.
    local previous = P.GetDecision(tonumber(itemID))
    local reaffirmed = choice == "keep" and previous and previous.choice == "keep" and found
        and P.KeepLapsed and P.KeepLapsed(found, previous) or nil
    local days = choice == "defer" and tonumber(rest) or nil
    -- "<choice> keep <n> [note]": keep n units, the rest follow the choice.
    local keepCount, afterKeep = rest:match("^keep%s+(%d+)%s*(.-)$")
    if keepCount then rest = afterKeep end
    local record, err = P.SetDecision(itemID, choice, { name = name, days = days, keepCount = keepCount,
        note = (not days and rest ~= "") and rest or nil, reaffirmed = reaffirmed })
    if not record then return err end
    if Core.RefreshUI and P.UI and P.UI.frame and P.UI.frame:IsShown() then Core.RefreshUI() end
    return "Decided: " .. (name or ("item " .. itemID)) .. " -> " .. (carry and "carry (keep it in your bags)" or choice)
        .. (record.keepCount and (" (keep " .. record.keepCount .. ", the rest " .. choice .. ")") or "")
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
        local frame = CreateFrame("Frame", "ICantEvenDecisionPasteBox", UIParent)
        frame:SetSize(560, 360)
        -- A plain dark background: BackdropTemplate drew nothing in game.
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if bg.SetColorTexture then bg:SetColorTexture(0.05, 0.05, 0.05, 0.95) end
        frame:SetPoint("CENTER")
        -- Above the console (a DIALOG frame sat behind it, 2026-09-28).
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        if frame.SetToplevel then frame:SetToplevel(true) end
        frame:SetFrameLevel((UIParent and UIParent:GetFrameLevel() or 0) + 60)
        frame:SetMovable(true) frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
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
        edit:SetHeight(270)   -- a multiline box has no height until it has text; give it one so clicks land
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(edit)
        -- A click anywhere in the box focuses the edit box (then Ctrl+V pastes).
        scroll:EnableMouse(true)
        scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
        frame:SetScript("OnMouseDown", function() edit:SetFocus() end)
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
