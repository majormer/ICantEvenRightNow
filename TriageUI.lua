-- I Can't Even Right Now (With My Bags and Bank) — Triage screen
-- "Justify every item": one item at a time, its verdict and evidence, the
-- options that exist for it (from P.ItemChannels), a recommendation from the
-- rules in place, Wowhead links in copyable boxes, and a stored decision per
-- item (Triage.lua) that every task reads. Decisions are preferences: the
-- cards still act on selection and clicks. Spec: .local/docs/Anti_Hoard_Triage_Spec.md

local ADDON_NAME, ns = ...

local Core = ns.Core
local P    = ns.Private
local UI   = P.UI

local BAG_SCOPE  = P.BAG_SCOPE
local BANK_SCOPE = P.BANK_SCOPE

local SCOPES = {
    { key = "bank",    label = "Bank" },
    { key = "warband", label = "Warband bank" },
    { key = "bags",    label = "Bags" },
    { key = "all",     label = "Everything" },
}
P.TRIAGE_SCOPES = SCOPES

local function Kit() return P.UIKit end

-- ---------------------------------------------------------------------------
-- Queue
-- ---------------------------------------------------------------------------

local function ScopeOf(snapshot, currentKey)
    if snapshot.scope == "warband" then return "warband" end
    if snapshot.character and snapshot.character.key == currentKey then
        if snapshot.scope == BANK_SCOPE then return "bank" end
        if snapshot.scope == BAG_SCOPE then return "bags" end
    end
    return nil
end

local function LocationOrder(item)
    return (item.bagID or 0) * 1000 + (item.slot or 0)
end

-- Items of the scope without a live decision, one entry per item ID (stacks
-- grouped), in location order. `includeDecided` for Review decisions.
function P.BuildTriageQueue(scope, includeDecided)
    local currentKey = P.currentCharacterKey or P.GetCharacterKey()
    local entries, byID, order = {}, {}, { bank = 1, warband = 2, bags = 3 }
    for _, snapshot in ipairs(P.AllSnapshots()) do
        local where = ScopeOf(snapshot, currentKey)
        if where and (scope == "all" or scope == where) then
            for _, item in ipairs(snapshot.items or {}) do
                if item.itemID then
                    local decision = P.GetDecision(item.itemID)
                    local live = decision and not decision.due
                        and not (P.KeepLapsed and P.KeepLapsed(item, decision))
                        and not (P.DecisionBlocked and P.DecisionBlocked(item.itemID, decision))
                    if includeDecided or not live then
                        local key = where .. ":" .. item.itemID
                        local entry = byID[key]
                        if not entry then
                            entry = { item = item, where = where, count = 0, stacks = 0, decision = decision,
                                order = order[where] * 1e6 + LocationOrder(item) }
                            byID[key] = entry
                            entries[#entries + 1] = entry
                        end
                        entry.count = entry.count + (item.count or 1)
                        entry.stacks = entry.stacks + 1
                    end
                end
            end
        end
    end
    table.sort(entries, function(a, b) return a.order < b.order end)
    return entries
end

-- Counts for the Home card: total items in scope and how many are decided.
function P.TriageProgress(scope)
    local all = P.BuildTriageQueue(scope or "all", true)
    local decided = 0
    for _, entry in ipairs(all) do
        local decision = entry.decision
        if decision and not decision.due and not (P.KeepLapsed and P.KeepLapsed(entry.item, decision)) then
            decided = decided + 1
        end
    end
    return #all, decided
end

-- ---------------------------------------------------------------------------
-- Options and recommendation
-- ---------------------------------------------------------------------------

local KEEP_LIKE = { protected = true, keepsake = true, keep_for_alt = true, keep_event = true, keep_investment = true,
    keep_for_now = true, legendary_keepsake = true, utility_item = true, decided_keep = true, decided_carry = true,
    use_effect = true, equipment_set = true }

-- Which buttons exist for this item, and which is recommended.
-- Returns { use, sell, auction, destroy, keep, carry, defer, leave } (each
-- true/false with why in `why`), `recommended`, and `confirm` (set of
-- choices needing a second click).
function P.TriageOptions(item)
    local channels = P.ItemChannels(item)
    local explanation = P.ExplainScanned(item)
    local options = { why = {}, keep = true, defer = true, leave = true }
    options.use = channels.use == true
    options.useWhat = channels.useWhat
    options.sell = channels.vendor == true
    options.why.sell = channels.why.vendor
    local price = P.GetAuctionPrice and P.GetAuctionPrice(item)
    options.auction = channels.auction == true and price ~= nil
    options.why.auction = channels.auction and "No auction price known" or channels.why.auction
    options.auctionPrice = channels.auction and price and (P.ListingPrice(item)) or nil
    options.auctionUnconfirmed = price and price.unconfirmed or false
    options.destroy = channels.destroy == true
    options.why.destroy = channels.why.destroy
    options.carry = item.scope == BAG_SCOPE or true   -- carry means "keep in bags" wherever it is now
    options.vendorPrice = (item.sellPrice or 0) * (item.count or 1)

    -- Recommendation: rules first, then the verdict.
    local primary = explanation.primary and explanation.primary.id
    local rec
    if KEEP_LIKE[primary] then
        rec = "keep"
    elseif explanation.disposition == "free" then
        if options.auction and P.AuctionAdvice and (P.AuctionAdvice(item)) == "auction" then rec = "auction"
        elseif options.sell then rec = "sell"
        elseif options.destroy then rec = "destroy" end
    elseif options.use and (primary == "collectible_unlearned" or primary == "quest_not_started" or primary == "open_container") then
        rec = "use"
    elseif explanation.disposition == "keep" then
        rec = "keep"
    elseif options.use then
        rec = "use"
    end
    options.recommended = rec

    -- Confirm steps: destroying anything uncommon or better; selling or
    -- auctioning a legendary, keepsake, protected or set item; selling to
    -- a vendor what nets far more at auction.
    local confirm = {}
    if (item.quality or 0) >= 2 then confirm.destroy = "uncommon or better" end
    if KEEP_LIKE[primary] then
        confirm.sell = explanation.label
        confirm.auction = explanation.label
        confirm.destroy = confirm.destroy or explanation.label
    end
    if options.sell and options.auction and P.IsValueFlagged and ns.DB.ui.triageAskBeforeSellingValuable ~= false
        and P.AuctionAdvice and (P.AuctionAdvice(item, true)) == "auction" then
        local net = P.GetItemValue and (P.GetItemValue(item)) or 0
        confirm.sell = "worth about " .. P.FormatMoney(net) .. " at auction"
    end
    options.confirm = confirm
    options.explanation = explanation
    options.channels = channels
    return options
end

-- ---------------------------------------------------------------------------
-- Screen
-- ---------------------------------------------------------------------------

local CHOICE_ORDER = { "use", "sell", "auction", "destroy", "keep", "carry", "defer", "leave" }
local CHOICE_LABEL = { use = "Use / Learn", sell = "Sell", auction = "Auction", destroy = "Destroy",
    keep = "Keep", carry = "Carry", defer = "Defer", leave = "Leave" }

local state = { scope = nil, queue = {}, index = 1, done = {}, pendingConfirm = nil, started = nil }
P.TriageState = state

local frame

local function Money(copper) return P.FormatMoney and P.FormatMoney(copper or 0) or tostring(copper) end

local function SummaryText()
    local counts = {}
    for _, choice in pairs(state.done) do counts[choice] = (counts[choice] or 0) + 1 end
    local parts = {}
    for _, choice in ipairs(CHOICE_ORDER) do
        if counts[choice] then parts[#parts + 1] = counts[choice] .. " " .. choice end
    end
    return #parts > 0 and table.concat(parts, ", ") or "nothing decided yet"
end

local function CurrentEntry()
    return state.queue[state.index]
end

local function SetWowhead(box, url)
    box.url = url or ""
    box:SetText(box.url)
    box:SetShown(url ~= nil)
end

local function Render()
    if not frame then return end
    local kit = Kit()
    local entry = CurrentEntry()
    frame.scopeRow:SetShown(state.scope == nil)
    frame.itemArea:SetShown(state.scope ~= nil and entry ~= nil)
    frame.summaryArea:SetShown(state.scope ~= nil and entry == nil)
    if state.scope == nil then
        local total, decided = P.TriageProgress("all")
        frame.title:SetText("Justify every item")
        frame.progress:SetText(decided .. " of " .. total .. " decided. Pick where to start.")
        return
    end
    local total = #state.queue + (state.decidedBefore or 0)
    if not entry then
        frame.title:SetText("Done: " .. (SCOPES[1].label and state.scopeLabel or state.scope))
        frame.progress:SetText("Every item in this scope has a decision or a Leave.")
        frame.summary:SetText("This run: " .. SummaryText() .. ". The cards on Home now offer what you decided.")
        return
    end
    local item = entry.item
    local options = P.TriageOptions(item)
    local explanation = options.explanation
    -- Position by items looked at this run, so a Leave (which moves the item
    -- to the end) still advances the count.
    local looked = 0
    for _ in pairs(state.done) do looked = looked + 1 end
    frame.title:SetText(state.scopeLabel .. ": " .. math.min(looked + 1, #state.queue) .. " of " .. #state.queue)
    frame.progress:SetText("This run: " .. SummaryText())
    frame.icon:SetTexture(item.icon)
    frame.name:SetText(P.ItemDisplayName(item.name, item.link, item.itemID)
        .. (entry.count > 1 and ("  x" .. entry.count .. (entry.stacks > 1 and (" in " .. entry.stacks .. " stacks") or "")) or ""))
    local facts = {}
    facts[#facts + 1] = item.bindingScope or "?"
    if item.itemSubTypeName then facts[#facts + 1] = item.itemSubTypeName end
    if item.itemLevel and item.itemLevel > 1 then facts[#facts + 1] = "iLvl " .. item.itemLevel end
    facts[#facts + 1] = P.GetExpansionName and P.GetExpansionName(item.expansionID) or ""
    facts[#facts + 1] = item.location or entry.where
    if P.IsGearItem and P.IsGearItem(item) then facts[#facts + 1] = "hover the name to compare with what you wear" end
    if explanation.held then facts[#facts + 1] = "held " .. explanation.held end
    frame.facts:SetText(table.concat(facts, "  ·  "))
    frame.why:SetText("Why it's here: " .. (explanation.label or "?") .. (explanation.evidence and (" (" .. explanation.evidence .. ")") or ""))
    local others = {}
    for _, r in ipairs(explanation.reasons or {}) do
        if r ~= explanation.primary and P.REASONS[r.id] then others[#others + 1] = P.REASONS[r.id].label end
    end
    frame.also:SetText(#others > 0 and ("Also: " .. table.concat(others, "; ")) or "")
    frame.who:SetText(P.WhoBenefits and P.WhoBenefits(item) or "")
    -- Prices for the whole entry (every stack of this item here), with the
    -- unit price alongside when there is more than one.
    local count = entry.count or 1
    local function PriceText(each)
        local total = (each or 0) * count
        if count > 1 then return Money(total) .. " for " .. count .. " (" .. Money(each) .. " each)" end
        return Money(total)
    end
    options.vendorTotal = (item.sellPrice or 0) * count
    options.auctionTotal = options.auction and (options.auctionPrice or 0) * count or nil
    local can = {}
    can[#can + 1] = "Vendor: " .. (options.sell and PriceText(item.sellPrice) or ("no (" .. tostring(options.why.sell) .. ")"))
    can[#can + 1] = "Auction: " .. (options.auction and (PriceText(options.auctionPrice)
        .. (options.auctionUnconfirmed and ", price unconfirmed" or "")) or ("no (" .. tostring(options.why.auction) .. ")"))
    can[#can + 1] = "Destroy: " .. (options.destroy and "yes" or ("no (" .. tostring(options.why.destroy) .. ")"))
    if options.use then can[#can + 1] = "Use: " .. tostring(options.useWhat) end
    frame.can:SetText(table.concat(can, "  ·  "))
    SetWowhead(frame.wowheadItem, P.WowheadItemURL(item.itemID))
    SetWowhead(frame.wowheadQuest, item.questID and P.WowheadQuestURL(item.questID) or nil)
    frame.wowheadQuestLabel:SetShown(item.questID ~= nil)
    frame.recommended:SetText(options.recommended and ("Recommended: " .. CHOICE_LABEL[options.recommended]
        ) or "Your call: nothing recommended")
    local decision = entry.decision
    local blocked = decision and P.DecisionBlocked and P.DecisionBlocked(item.itemID, decision)
    frame.previousDecision:SetText(decision and ("Current decision: " .. decision.choice
        .. (decision.keepCount and (" (keep " .. decision.keepCount .. ")") or "")
        .. (decision.at and date and (" on " .. date("%Y-%m-%d", decision.at)) or "")
        .. (blocked and (" (not possible: " .. blocked .. ")") or "")) or "")
    -- Keep box: only when there is more than one to split.
    local splittable = (entry.count or 1) > 1
    frame.keepLabel:SetShown(splittable)
    frame.keepBox:SetShown(splittable)
    if state.keepBoxFor ~= item.itemID then
        frame.keepBox:SetText(decision and decision.keepCount and tostring(decision.keepCount) or "")
        state.keepBoxFor = item.itemID
    end
    local keepN = splittable and tonumber(frame.keepBox:GetText()) or nil
    if keepN and (keepN <= 0 or keepN >= (entry.count or 1)) then keepN = nil end
    frame.keepLabel:SetText(keepN and ("Keep " .. keepN .. " of " .. count .. ", the rest:") or ("Keep some? (of " .. count .. ")"))
    for i, choice in ipairs(CHOICE_ORDER) do
        local button = frame.buttons[choice]
        local enabled = options[choice] and true or false
        button:SetEnabled(enabled)
        local label = i .. ". " .. CHOICE_LABEL[choice]
        if choice == "sell" and options.sell then label = label .. (keepN and " the rest" or (" " .. Money(options.vendorTotal or options.vendorPrice))) end
        if choice == "auction" and options.auction then label = label .. (keepN and " the rest" or (" ~" .. Money(options.auctionTotal or options.auctionPrice))) end
        if choice == "destroy" and keepN then label = label .. " the rest" end
        if choice == "defer" then label = label .. " " .. P.TriageDeferDays() .. "d" end
        if state.pendingConfirm == choice then label = "Confirm: " .. CHOICE_LABEL[choice] end
        button:SetText(label)
        kit.SetButtonStyle(button, options.recommended == choice and "primary" or (state.pendingConfirm == choice and "danger" or "secondary"))
        button.why = options.why[choice]
    end
    frame.confirmNote:SetText(state.pendingConfirm and (CHOICE_LABEL[state.pendingConfirm] .. "? "
        .. tostring(options.confirm[state.pendingConfirm]) .. ". Click again to confirm.") or "")
    frame.prev:SetEnabled(state.index > 1)
end

local function Advance()
    state.pendingConfirm = nil
    state.index = state.index + 1
    Render()
end

-- The player chose. Confirm steps get a second click. `fromClick`: a
-- hardware event, so Use can run UseContainerItem for a bag item.
local function Choose(choice, fromClick)
    local entry = CurrentEntry()
    if not entry then return end
    local item = entry.item
    local options = P.TriageOptions(item)
    if not options[choice] then return end
    if options.confirm[choice] and state.pendingConfirm ~= choice then
        state.pendingConfirm = choice
        Render()
        return
    end
    state.pendingConfirm = nil
    if choice == "leave" then
        state.done[item.itemID] = "leave"
        -- Back to the end of the queue: looked at, not decided.
        table.remove(state.queue, state.index)
        table.insert(state.queue, entry)
        Render()
        return
    end
    local decisionChoice, note = choice, nil
    if choice == "carry" then decisionChoice, note = "keep", "carry" end
    if choice == "keep" then note = "keepsake" end
    -- "Keep N": the number in the box applies to sell/auction/destroy.
    local keepCount = frame and frame.keepBox and tonumber(frame.keepBox:GetText())
    if keepCount and (keepCount <= 0 or keepCount >= (entry.count or 1)) then keepCount = nil end
    -- Keep on a lapsed keep is an answer: it stays kept from now on.
    local previous = P.GetDecision(item.itemID)
    local reaffirmed = decisionChoice == "keep" and previous and previous.choice == "keep"
        and P.KeepLapsed and P.KeepLapsed(item, previous) or nil
    P.SetDecision(item.itemID, decisionChoice, { name = item.name, note = note, keepCount = keepCount,
        reaffirmed = reaffirmed })
    entry.decision = P.GetDecision(item.itemID)
    state.done[item.itemID] = choice
    P.Log("triage", "screen: %s -> %s", tostring(item.name), choice)
    if choice == "use" and fromClick and item.scope == BAG_SCOPE and C_Container and C_Container.UseContainerItem then
        local slotProblem = P.VerifySourceSlot and P.VerifySourceSlot(item)
        if not slotProblem then pcall(C_Container.UseContainerItem, item.bagID, item.slot) end
    end
    Advance()
    if Core.RefreshUI and UI.frame and UI.frame:IsShown() then Core.RefreshUI() end
end
P.TriageChoose = Choose

local function Previous()
    if state.index > 1 then
        state.index = state.index - 1
        state.pendingConfirm = nil
        Render()
    end
end

local function Start(scope)
    local label
    for _, s in ipairs(SCOPES) do if s.key == scope then label = s.label end end
    local total, decided = P.TriageProgress(scope)
    state.scope, state.scopeLabel = scope, label or scope
    state.queue = P.BuildTriageQueue(scope)
    state.index, state.done, state.pendingConfirm, state.keepBoxFor = 1, {}, nil, nil
    state.decidedBefore = decided
    state.started = GetTime and GetTime() or 0
    if ns.DB.ui.triageRememberScope then ns.DB.ui.triageScope = scope end
    P.Log("triage", "start %s: %d to look at, %d already decided", scope, #state.queue, decided)
    Render()
end
P.TriageStart = Start

local function Stop()
    state.scope = nil
    state.queue = {}
    state.pendingConfirm = nil
    if frame then frame:Hide() end
    if Core.RefreshUI and UI.frame and UI.frame:IsShown() then Core.RefreshUI() end
end

local function OnKey(_, key)
    if not frame or not frame:IsShown() or state.scope == nil then
        if frame then frame:SetPropagateKeyboardInput(true) end
        return
    end
    local handled = true
    local n = tonumber(key)
    if n and CHOICE_ORDER[n] then Choose(CHOICE_ORDER[n], true)
    elseif key == "BACKSPACE" then Previous()
    elseif key == "ESCAPE" then Stop()
    else handled = false end
    if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(not handled) end
end

local function Build()
    local kit = Kit()
    -- The same bordered window template as the console, so it reads as its
    -- own window on top of it (a flat dark rectangle did not).
    frame = CreateFrame("Frame", "ICantEvenTriageFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(640, 462)
    frame:SetPoint("CENTER")
    -- Above the console (in game a DIALOG frame sat behind it, like the
    -- price-first prompt did).
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:SetFrameLevel((UIParent and UIParent:GetFrameLevel() or 0) + 60)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    frame:SetMovable(true) frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    -- Enter is deliberately not a choice: it also opens chat, and a reload
    -- typed with the screen open recorded two Keeps (2026-09-27).
    frame:EnableKeyboard(true)
    frame:SetScript("OnKeyDown", OnKey)
    -- Escape closes it like any game window; a close from anywhere ends the run.
    if UISpecialFrames and tinsert then tinsert(UISpecialFrames, "ICantEvenTriageFrame") end
    frame:SetScript("OnHide", function() if state.scope ~= nil then Stop() end end)
    frame.windowTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.windowTitle:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
    frame.windowTitle:SetText("Justify every item")
    if frame.CloseButton then frame.CloseButton:SetScript("OnClick", Stop) end

    frame.title = kit.CreateLabel(frame, "", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 16, -36)
    frame.progress = kit.CreateLabel(frame, "", "GameFontDisableSmall")
    frame.progress:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -2)
    frame.close = kit.CreateButton(frame, "Stop", 70, 22)
    frame.close:SetPoint("TOPRIGHT", -14, -34)
    frame.close:SetScript("OnClick", Stop)

    -- Scope choice
    frame.scopeRow = CreateFrame("Frame", nil, frame)
    frame.scopeRow:SetPoint("TOPLEFT", 16, -92)
    frame.scopeRow:SetSize(600, 40)
    frame.scopeButtons = {}
    local x = 0
    for _, s in ipairs(SCOPES) do
        local b = kit.CreateButton(frame.scopeRow, s.label, 130, 26)
        b:SetPoint("LEFT", x, 0)
        b:SetScript("OnClick", function() Start(s.key) end)
        frame.scopeButtons[s.key] = b
        x = x + 140
    end
    frame.scopeHint = kit.CreateLabel(frame.scopeRow, "One item at a time. Every choice is a preference the cards act on; nothing moves until you click there.", "GameFontHighlightSmall")
    frame.scopeHint:SetPoint("TOPLEFT", frame.scopeRow, "BOTTOMLEFT", 0, -6)

    -- Item area
    local area = CreateFrame("Frame", nil, frame)
    area:SetPoint("TOPLEFT", 16, -84)
    area:SetPoint("BOTTOMRIGHT", -16, 14)
    frame.itemArea = area
    frame.icon = area:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(36, 36)
    frame.icon:SetPoint("TOPLEFT", 0, 0)
    frame.name = kit.CreateLabel(area, "", "GameFontNormalLarge")
    frame.name:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 8, -2)
    -- Hover the icon or the name: the game's tooltip, with what this
    -- character wears in that slot beside it (the player, on the lapsed
    -- keeps: "so I can see what I am currently wearing", 2026-09-28).
    frame.hover = CreateFrame("Button", nil, area)
    frame.hover:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", 0, 0)
    frame.hover:SetSize(420, 38)
    local function ShowItemTooltip(self)
        local item = state.queue[state.index] and state.queue[state.index].item
        if not item or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- The bag copy gives the full tooltip (gems, enchant, upgrade line);
        -- anything else goes by link.
        if item.scope == BAG_SCOPE and item.bagID and item.slot and GameTooltip.SetBagItem
            and not (P.VerifySourceSlot and P.VerifySourceSlot(item)) then
            GameTooltip:SetBagItem(item.bagID, item.slot)
        else
            GameTooltip:SetHyperlink(item.link or ("item:" .. tostring(item.itemID)))
        end
        -- Shown first: the comparison anchors to the tooltip's edges (in
        -- game, compared before Show, the worn pieces floated to the top of
        -- the screen and read "Retrieving item information"). The worn
        -- items' data is requested, and the tooltip's own update loop calls
        -- UpdateTooltip again while hovered, so the comparison fills in.
        GameTooltip:Show()
        local slots = P.INVTYPE_TO_SLOTS and P.INVTYPE_TO_SLOTS[item.equipLoc or ""]
        for _, slot in ipairs(slots or {}) do
            local wornID = GetInventoryItemID and GetInventoryItemID("player", slot)
            if wornID and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, wornID) end
        end
        if GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem, GameTooltip) end
    end
    frame.hover:SetScript("OnEnter", ShowItemTooltip)
    frame.hover.UpdateTooltip = ShowItemTooltip   -- GameTooltip_OnUpdate re-runs it (Blizzard's bag buttons do the same)
    frame.hover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    frame.facts = kit.CreateLabel(area, "", "GameFontHighlightSmall")
    frame.facts:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -2)
    frame.facts:SetWidth(560) frame.facts:SetJustifyH("LEFT")
    frame.why = kit.CreateLabel(area, "", "GameFontNormal")
    frame.why:SetPoint("TOPLEFT", frame.icon, "BOTTOMLEFT", 0, -10)
    frame.why:SetWidth(600) frame.why:SetJustifyH("LEFT")
    frame.also = kit.CreateLabel(area, "", "GameFontDisableSmall")
    frame.also:SetPoint("TOPLEFT", frame.why, "BOTTOMLEFT", 0, -2)
    frame.also:SetWidth(600) frame.also:SetJustifyH("LEFT")
    frame.who = kit.CreateLabel(area, "", "GameFontHighlightSmall")
    frame.who:SetPoint("TOPLEFT", frame.also, "BOTTOMLEFT", 0, -2)
    frame.who:SetWidth(600) frame.who:SetJustifyH("LEFT")
    frame.can = kit.CreateLabel(area, "", "GameFontHighlightSmall")
    frame.can:SetPoint("TOPLEFT", frame.who, "BOTTOMLEFT", 0, -6)
    frame.can:SetWidth(600) frame.can:SetJustifyH("LEFT")

    local function WowheadBox(label, anchor)
        local caption = kit.CreateLabel(area, label, "GameFontDisableSmall")
        caption:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
        local box = CreateFrame("EditBox", nil, area, "InputBoxTemplate")
        box:SetSize(300, 20)
        box:SetPoint("LEFT", caption, "RIGHT", 10, 0)
        box:SetAutoFocus(false)
        box:SetScript("OnEditFocusGained", function(self) if self.HighlightText then self:HighlightText() end end)
        box:SetScript("OnTextChanged", function(self)
            if self.url and self:GetText() ~= self.url then self:SetText(self.url) end   -- read-only
        end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        return box, caption
    end
    frame.wowheadItem, frame.wowheadItemLabel = WowheadBox("Wowhead (Ctrl+C to copy):", frame.can)
    frame.wowheadQuest, frame.wowheadQuestLabel = WowheadBox("Quest:", frame.wowheadItemLabel)

    -- The choice block is pinned to the bottom so the buttons never move
    -- between items, however long the explanation above them is.
    frame.recommended = kit.CreateLabel(area, "", "GameFontNormal")
    frame.recommended:SetPoint("BOTTOMLEFT", 0, 118)
    frame.previousDecision = kit.CreateLabel(area, "", "GameFontDisableSmall")
    frame.previousDecision:SetPoint("LEFT", frame.recommended, "RIGHT", 12, 0)
    -- "Keep N" box, right of the recommendation line: a number here turns
    -- Sell/Auction/Destroy into "the rest" (the Phoenix Oil case: keep 60).
    frame.keepBox = CreateFrame("EditBox", nil, area, "InputBoxTemplate")
    frame.keepBox:SetSize(48, 20)
    frame.keepBox:SetPoint("BOTTOMRIGHT", 0, 116)
    frame.keepBox:SetAutoFocus(false)
    if frame.keepBox.SetNumeric then frame.keepBox:SetNumeric(true) end
    frame.keepBox:SetScript("OnTextChanged", function(_, userInput) if userInput ~= false then Render() end end)
    frame.keepBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.keepBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.keepLabel = kit.CreateLabel(area, "", "GameFontHighlightSmall")
    frame.keepLabel:SetPoint("RIGHT", frame.keepBox, "LEFT", -6, 0)

    frame.buttons = {}
    local row1 = CreateFrame("Frame", nil, area) row1:SetSize(600, 26)
    row1:SetPoint("BOTTOMLEFT", 0, 84)
    local row2 = CreateFrame("Frame", nil, area) row2:SetSize(600, 26)
    row2:SetPoint("BOTTOMLEFT", 0, 52)
    for i, choice in ipairs(CHOICE_ORDER) do
        local parent = i <= 4 and row1 or row2
        local b = kit.CreateButton(parent, CHOICE_LABEL[choice], 146, 24)
        b:SetPoint("LEFT", ((i - 1) % 4) * 152, 0)
        b:SetScript("OnClick", function() Choose(choice, true) end)
        b:SetScript("OnEnter", function(self)
            if not self:IsEnabled() and self.why then kit.ShowTooltip(self, { CHOICE_LABEL[choice], self.why }) end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame.buttons[choice] = b
    end
    frame.confirmNote = kit.CreateLabel(area, "", "GameFontNormalSmall")
    frame.confirmNote:SetPoint("BOTTOMLEFT", 0, 32)
    frame.confirmNote:SetWidth(600) frame.confirmNote:SetJustifyH("LEFT")

    frame.prev = kit.CreateButton(area, "< Previous (Backspace)", 150, 22)
    frame.prev:SetPoint("BOTTOMLEFT", 0, 0)
    frame.prev:SetScript("OnClick", Previous)
    frame.keys = kit.CreateLabel(area, "Keys: 1-8 choose, Backspace = previous, Esc = stop", "GameFontDisableSmall")
    frame.keys:SetPoint("BOTTOMRIGHT", 0, 4)

    -- Summary
    frame.summaryArea = CreateFrame("Frame", nil, frame)
    frame.summaryArea:SetPoint("TOPLEFT", 16, -92)
    frame.summaryArea:SetSize(600, 120)
    frame.summary = kit.CreateLabel(frame.summaryArea, "", "GameFontHighlight")
    frame.summary:SetPoint("TOPLEFT", 0, 0)
    frame.summary:SetWidth(600) frame.summary:SetJustifyH("LEFT")
    frame.summaryHome = kit.CreateButton(frame.summaryArea, "Go to Home", 120, 24, "primary")
    frame.summaryHome:SetPoint("TOPLEFT", frame.summary, "BOTTOMLEFT", 0, -12)
    frame.summaryHome:SetScript("OnClick", function() Stop() if Core.ShowHomeUI then Core.ShowHomeUI() end end)
    frame.summaryAgain = kit.CreateButton(frame.summaryArea, "Another scope", 120, 24)
    frame.summaryAgain:SetPoint("LEFT", frame.summaryHome, "RIGHT", 8, 0)
    frame.summaryAgain:SetScript("OnClick", function() state.scope = nil Render() end)
    frame:Hide()
    return frame
end

function P.ShowTriage(scope)
    if not CreateFrame then return nil end
    if not frame then Build() end
    if scope then Start(scope)
    elseif ns.DB.ui.triageRememberScope and ns.DB.ui.triageScope then Start(ns.DB.ui.triageScope)
    else state.scope = nil end
    frame:Show()
    Render()
    return frame
end
P.TriageFrame = function() return frame end

-- Home card.
if P.RegisterTask then
    P.RegisterTask({
        name = "Justify every item",
        description = "Look at every item once and decide: sell, auction, keep, destroy, defer. The cards then act on it.",
        count = function()
            local total, decided = P.TriageProgress("all")
            if total == 0 then return 0, nil, 0, "Nothing scanned yet" end
            local left = total - decided
            if left == 0 then return 0, nil, 0, "Every item has a decision" end
            return left, nil, 0, decided .. " of " .. total .. " decided"
        end,
        open = function() P.ShowTriage() end,
        openLabel = "Start",
    })
end
