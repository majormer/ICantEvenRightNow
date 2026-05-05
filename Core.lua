-- I Can't Even Right Now (With My Bags and Bank) Core Module
-- Main addon logic, event handlers, scanning, decisions, movement, and UI.

local ADDON_NAME, ns = ...

ns.Core = {}
ns.DB = {}

local Core = ns.Core
local Data = ns.Data
local Debug = ns.Debug

local CContainer = C_Container
local UI = {
    frame = nil,
    tabs = {},
    activeTab = "Summary",
    rows = {},
    ruleRows = {},
    selected = {},
    visible = {},
    page = 1,
    pageSize = 10,
}

local BAG_SCOPE = "bags"
local BANK_SCOPE = "bank"

local BAG_IDS = { 0, 1, 2, 3, 4 }
local BANK_IDS = { -1, 5, 6, 7, 8, 9, 10, 11, -3 }
local GROUP_ORDER = {
    "Unknown / needs review",
    "Recommended bank candidates",
    "Recommended recall candidates",
    "Obsolete consumables",
    "Old BoEs",
    "Protected / blocked",
    "Ignored",
}

local function Print(msg)
    print("|cFF66CCFFICantEvenRightNow:|r " .. tostring(msg))
end

local function SafeCopyDefaults(defaults, target)
    target = target or {}
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = SafeCopyDefaults(value, target[key])
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

local function IsBankBag(bagID)
    if bagID == -1 or bagID == -3 then
        return true
    end
    return bagID >= 5 and bagID <= 11
end

local function GetExpansionName(expansionID)
    local expansion = expansionID and Data.Expansions[expansionID]
    return expansion and expansion.name or "Unknown"
end

local function FormatTimestamp(timestamp)
    if not timestamp or timestamp == 0 then
        return "Never"
    end
    return date("%Y-%m-%d %H:%M", timestamp)
end

local function LocationKey(item)
    return table.concat({ item.scope or "?", tostring(item.bagID), tostring(item.slot), tostring(item.itemID) }, ":")
end

local function FindCuratedItem(itemID)
    for _, tableByExpansion in pairs(Data.CuratedItems) do
        if tableByExpansion[itemID] then
            return tableByExpansion[itemID]
        end
    end
    return nil
end

local function EnsureRule(itemID)
    ns.DB.rules.items[itemID] = ns.DB.rules.items[itemID] or {
        protect = false,
        neverMove = false,
        neverSell = false,
        ignore = false,
        expansionOverride = nil,
        actionOverride = nil,
        notes = nil,
        createdFrom = "Rules tab",
    }
    return ns.DB.rules.items[itemID]
end

local function GetItemType(item)
    if item.rule and item.rule.typeOverride then
        return item.rule.typeOverride
    end
    if item.curated and item.curated.type then
        return item.curated.type
    end
    if item.classID == 0 then
        return Data.ItemTypes.CONSUMABLE
    elseif item.classID == 7 then
        return Data.ItemTypes.PROFESSION
    elseif item.classID == 12 then
        return Data.ItemTypes.QUEST
    elseif item.bindType == 2 and (item.classID == 2 or item.classID == 4) then
        return Data.ItemTypes.BOE
    elseif item.classID == 2 or item.classID == 4 then
        return Data.ItemTypes.EQUIPMENT
    end
    return Data.ItemTypes.UNKNOWN
end

local function IsCurrentExpansion(expansionID)
    return not expansionID or expansionID >= Data.CurrentExpansionID
end

local function IsOldExpansion(expansionID)
    return expansionID and expansionID > 0 and expansionID < Data.CurrentExpansionID
end

local function InferExpansionOverride(item)
    local name = (item.name or ""):lower()
    local subtype = (item.itemSubTypeName or ""):lower()

    if name:find("primordial stone", 1, true) or subtype:find("primordial stone", 1, true) then
        return 10, "Dragonflight Primordial Stone"
    end

    return nil, nil
end

local function SetBankOrRecallDecision(item, bankGroup, bankReason, recallReason)
    if item.scope == BANK_SCOPE then
        return "Recommended recall candidates", Data.Recommendations.RECALL, Data.Actions.RECALL, recallReason or bankReason
    end
    return bankGroup, Data.Recommendations.BANK, Data.Actions.BANK, bankReason
end

local function BuildDecision(item)
    local rule = ns.DB.rules.items[item.itemID]
    item.rule = rule
    item.curated = FindCuratedItem(item.itemID)

    local expansionID = rule and rule.expansionOverride or item.expansionID
    if item.curated and item.curated.expansion then
        expansionID = expansionID or item.curated.expansion
    end
    local inferredExpansionID, inferredReason = InferExpansionOverride(item)
    if inferredExpansionID then
        expansionID = inferredExpansionID
    end

    local itemType = GetItemType(item)
    local blocked = {}
    local group = "Unknown / needs review"
    local recommendation = Data.Recommendations.REVIEW
    local action = Data.Actions.REVIEW
    local reason = "Needs player review before moving"

    if rule and rule.ignore then
        group = "Ignored"
        recommendation = Data.Recommendations.IGNORED
        action = Data.Actions.NONE
        reason = "Ignored by item rule"
        table.insert(blocked, "Ignored")
    elseif rule and (rule.protect or rule.neverMove) then
        group = "Protected / blocked"
        recommendation = Data.Recommendations.PROTECTED
        action = Data.Actions.NONE
        reason = rule.protect and "Protected by item rule" or "Never move rule"
        table.insert(blocked, reason)
    elseif item.isBound and (item.classID == 2 or item.classID == 4) then
        group = "Protected / blocked"
        recommendation = Data.Recommendations.BLOCKED
        action = Data.Actions.NONE
        reason = "Soulbound equipment is blocked by default"
        table.insert(blocked, "Soulbound equipment")
    elseif itemType == Data.ItemTypes.QUEST then
        group = "Protected / blocked"
        recommendation = Data.Recommendations.BLOCKED
        action = Data.Actions.NONE
        reason = "Quest items are blocked by default"
        table.insert(blocked, "Quest item")
    elseif rule and rule.actionOverride then
        action = rule.actionOverride
        recommendation = action == Data.Actions.BANK and Data.Recommendations.BANK or Data.Recommendations.RECALL
        group = action == Data.Actions.BANK and "Recommended bank candidates" or "Recommended recall candidates"
        reason = "Action override rule"
    elseif item.curated and item.curated.action == Data.Actions.BANK then
        group, recommendation, action, reason = SetBankOrRecallDecision(
            item,
            "Recommended bank candidates",
            item.curated.reason or "Curated old-content table",
            "Curated item is available to recall from bank"
        )
    elseif itemType == Data.ItemTypes.CONSUMABLE and IsOldExpansion(expansionID) then
        group, recommendation, action, reason = SetBankOrRecallDecision(
            item,
            "Obsolete consumables",
            "Old expansion consumable",
            "Old expansion consumable is available to recall from bank"
        )
    elseif itemType == Data.ItemTypes.BOE and IsOldExpansion(expansionID) then
        group = "Old BoEs"
        recommendation = Data.Recommendations.REVIEW
        action = Data.Actions.REVIEW
        reason = "Old BoE, review before moving"
    elseif itemType == Data.ItemTypes.PROFESSION and IsOldExpansion(expansionID) then
        group, recommendation, action, reason = SetBankOrRecallDecision(
            item,
            "Recommended bank candidates",
            "Old expansion material",
            "Old expansion material is available to recall from bank"
        )
    elseif item.scope == BANK_SCOPE
        and expansionID
        and IsCurrentExpansion(expansionID)
        and (itemType == Data.ItemTypes.PROFESSION or itemType == Data.ItemTypes.CONSUMABLE or itemType == Data.ItemTypes.CURRENCY_LIKE) then
        group = "Recommended recall candidates"
        recommendation = Data.Recommendations.RECALL
        action = Data.Actions.RECALL
        reason = "Current expansion item is available to recall from bank"
    elseif IsCurrentExpansion(expansionID) then
        group = "Protected / blocked"
        recommendation = Data.Recommendations.BLOCKED
        action = Data.Actions.NONE
        reason = inferredReason and (inferredReason .. " is blocked by default") or "Current or unknown expansion is blocked by default"
        table.insert(blocked, "Current or unknown expansion")
    end

    local eligibleForBankMove = action == Data.Actions.BANK
        and item.scope == BAG_SCOPE
        and ns.DB.context.bankOpen
        and not ns.DB.context.inCombat
        and #blocked == 0

    local eligibleForRecall = action == Data.Actions.RECALL
        and item.scope == BANK_SCOPE
        and ns.DB.context.bankOpen
        and not ns.DB.context.inCombat
        and #blocked == 0

    item.expansionID = expansionID
    item.expansionName = GetExpansionName(expansionID)
    item.typeTag = itemType
    item.recommendation = recommendation
    item.recommendedAction = action
    item.reason = reason
    item.group = group
    item.blockedReasons = blocked
    item.eligibleForBankMove = eligibleForBankMove
    item.eligibleForRecall = eligibleForRecall
    item.ruleStatus = rule and "custom" or "none"
    item.key = LocationKey(item)

    return item
end

local function GetAllDecisions()
    local decisions = {}
    for _, item in ipairs(ns.DB.scans.bags or {}) do
        table.insert(decisions, BuildDecision(item))
    end
    for _, item in ipairs(ns.DB.scans.bank or {}) do
        table.insert(decisions, BuildDecision(item))
    end
    return decisions
end

local function MatchesFilter(item)
    local ui = ns.DB.ui
    if ui.mode == "Dump to Bank" and item.scope ~= BAG_SCOPE then
        return false
    elseif ui.mode == "Recall from Bank" and item.scope ~= BANK_SCOPE then
        return false
    end
    if ui.recommendedOnly then
        if ui.mode == "Dump to Bank" and item.recommendedAction ~= Data.Actions.BANK then
            return false
        elseif ui.mode == "Recall from Bank" and item.recommendedAction ~= Data.Actions.RECALL then
            return false
        elseif item.recommendedAction == Data.Actions.NONE or item.recommendedAction == Data.Actions.REVIEW then
            return false
        end
    end
    if ui.expansionFilter and ui.expansionFilter ~= 0 and item.expansionID ~= ui.expansionFilter then
        return false
    end
    if ui.typeFilter and ui.typeFilter ~= "All" and item.typeTag ~= ui.typeFilter then
        return false
    end
    if ui.locationFilter == "Bags" and item.scope ~= BAG_SCOPE then
        return false
    elseif ui.locationFilter == "Bank" and item.scope ~= BANK_SCOPE then
        return false
    end
    local search = ui.search and ui.search:lower() or ""
    if search ~= "" then
        local haystack = table.concat({
            item.name or "",
            tostring(item.itemID or ""),
            item.expansionName or "",
            item.typeTag or "",
            item.reason or "",
        }, " "):lower()
        return haystack:find(search, 1, true) ~= nil
    end
    return true
end

local function SortDecisions(a, b)
    local ai, bi = 99, 99
    for index, group in ipairs(GROUP_ORDER) do
        if a.group == group then ai = index end
        if b.group == group then bi = index end
    end
    if ai ~= bi then
        return ai < bi
    end
    return (a.name or "") < (b.name or "")
end

local function CreateButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 110, height or 24)
    button:SetText(text)
    return button
end

local function CreateLabel(parent, text, size)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetText(text or "")
    label:SetJustifyH("LEFT")
    if size then
        label:SetFontObject(size)
    end
    return label
end

local function CreateDropdown(parent, width, options, onSelect)
    local dropdown = CreateButton(parent, "", width or 140, 24)
    dropdown.options = options
    dropdown.onSelect = onSelect

    local menu = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(parent:GetFrameLevel() + 40)
    menu:SetSize(width or 140, #options * 22 + 8)
    menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    menu:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    menu:Hide()
    dropdown.menu = menu

    dropdown.items = {}
    for index, option in ipairs(options) do
        local item = CreateButton(menu, option.text, (width or 140) - 8, 20)
        item:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (index - 1) * 22)
        item:SetScript("OnClick", function()
            onSelect(option.value)
            menu:Hide()
            Core.RefreshUI()
        end)
        dropdown.items[index] = item
    end

    dropdown:SetScript("OnClick", function()
        menu:SetShown(not menu:IsShown())
    end)
    dropdown:SetScript("OnHide", function()
        menu:Hide()
    end)

    return dropdown
end

local function SetDropdownText(dropdown, label)
    dropdown:SetText(label .. " |TInterface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up:10:10:0:0|t")
end

local function GetExpansionOptions()
    local options = {
        { text = "All expansions", value = 0 },
    }
    for expansionID = 1, Data.CurrentExpansionID do
        local expansion = Data.Expansions[expansionID]
        if expansion then
            table.insert(options, { text = expansion.name, value = expansionID })
        end
    end
    return options
end

local function CreatePanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetFrameLevel(parent:GetFrameLevel() + 5)
    panel:SetPoint("TOPLEFT", 14, -64)
    panel:SetPoint("BOTTOMRIGHT", -14, 14)
    return panel
end

local function RaiseConsole()
    if not UI.frame then
        return
    end
    UI.frame:SetFrameStrata("FULLSCREEN_DIALOG")
    UI.frame:SetFrameLevel(100)
    UI.frame:Raise()
end

function Core.UpdateContext()
    local context = ns.DB.context
    context.bankOpen = BankFrame and BankFrame:IsShown() or false
    context.reagentBankOpen = ReagentBankFrame and ReagentBankFrame:IsShown() or false
    context.vendorOpen = MerchantFrame and MerchantFrame:IsShown() or false
    context.auctionHouseOpen = AuctionHouseFrame and AuctionHouseFrame:IsShown() or false
    context.mailboxOpen = MailFrame and MailFrame:IsShown() or false
    context.inCombat = InCombatLockdown() and true or false
end

local function ScanContainerBag(bagID, scope, output)
    local numSlots = CContainer.GetContainerNumSlots(bagID) or 0
    for slot = 1, numSlots do
        local info = CContainer.GetContainerItemInfo(bagID, slot)
        local itemID = CContainer.GetContainerItemID(bagID, slot)
        if info and itemID then
            local name, link, quality, itemLevel, requiredLevel, itemTypeName, itemSubTypeName, maxStack, equipLoc, icon, sellPrice, classID, subclassID, bindType, expansionID = GetItemInfo(itemID)
            table.insert(output, {
                itemID = itemID,
                name = name or info.itemName or ("Item " .. itemID),
                link = link,
                icon = icon or info.iconFileID,
                quality = quality or info.quality,
                count = info.stackCount or 1,
                bagID = bagID,
                slot = slot,
                scope = scope,
                location = scope == BAG_SCOPE and ("Bag " .. bagID .. " Slot " .. slot) or ("Bank " .. bagID .. " Slot " .. slot),
                classID = classID,
                subclassID = subclassID,
                bindType = bindType,
                equipLoc = equipLoc,
                itemLevel = itemLevel,
                requiredLevel = requiredLevel,
                itemTypeName = itemTypeName,
                itemSubTypeName = itemSubTypeName,
                maxStack = maxStack,
                sellPrice = sellPrice,
                expansionID = expansionID,
                isBound = info.isBound and true or false,
            })
        end
    end
end

function Core.ScanInventory(scope, quiet)
    Core.UpdateContext()
    scope = (scope and scope:lower()) or BAG_SCOPE

    local scanBags = scope == "" or scope == BAG_SCOPE or scope == "all"
    local scanBank = scope == BANK_SCOPE or scope == "all"

    if scanBank and not ns.DB.context.bankOpen then
        if not quiet then
            Print("Open the bank before scanning bank contents.")
        end
        scanBank = false
    end

    if scanBags then
        local bagItems = {}
        for _, bagID in ipairs(BAG_IDS) do
            ScanContainerBag(bagID, BAG_SCOPE, bagItems)
        end
        ns.DB.scans.bags = bagItems
        ns.DB.lastScan.bags = time()
        if not quiet then
            Print("Scanned bags: " .. #bagItems .. " item stacks.")
        end
    end

    if scanBank then
        local bankItems = {}
        for _, bagID in ipairs(BANK_IDS) do
            ScanContainerBag(bagID, BANK_SCOPE, bankItems)
        end
        ns.DB.scans.bank = bankItems
        ns.DB.lastScan.bank = time()
        if not quiet then
            Print("Scanned bank: " .. #bankItems .. " item stacks.")
        end
    end

    if UI.frame and UI.frame:IsShown() then
        Core.RefreshUI()
    end
end

function Core.ScheduleRescanAfterMove()
    local delays = { 0.25, 0.8, 1.6 }
    for _, delay in ipairs(delays) do
        C_Timer.After(delay, function()
            Core.ScanInventory("all", true)
        end)
    end
end

local function GetContextText()
    if ns.DB.context.inCombat then
        return "In combat"
    elseif ns.DB.context.vendorOpen then
        return "Vendor open"
    elseif ns.DB.context.bankOpen then
        return "Bank open"
    end
    return "Bags only"
end

local function CountSummary()
    local counts = {
        oldBags = 0,
        oldBank = 0,
        bankCandidates = 0,
        recallCandidates = 0,
        consumables = 0,
        boes = 0,
        unknown = 0,
        protected = 0,
    }
    for _, item in ipairs(GetAllDecisions()) do
        if IsOldExpansion(item.expansionID) and item.scope == BAG_SCOPE then
            counts.oldBags = counts.oldBags + 1
        elseif IsOldExpansion(item.expansionID) and item.scope == BANK_SCOPE then
            counts.oldBank = counts.oldBank + 1
        end
        if item.recommendation == Data.Recommendations.BANK then
            counts.bankCandidates = counts.bankCandidates + 1
        elseif item.recommendation == Data.Recommendations.RECALL then
            counts.recallCandidates = counts.recallCandidates + 1
        end
        if item.group == "Obsolete consumables" then counts.consumables = counts.consumables + 1 end
        if item.group == "Old BoEs" then counts.boes = counts.boes + 1 end
        if item.group == "Unknown / needs review" then counts.unknown = counts.unknown + 1 end
        if item.group == "Protected / blocked" then counts.protected = counts.protected + 1 end
    end
    return counts
end

local function SetTab(tabName)
    UI.activeTab = tabName
    UI.page = 1
    Core.RefreshUI()
end

local function AddRule(item, ruleType)
    local rule = EnsureRule(item.itemID)
    rule.createdFrom = item.name or "Move tab"
    if ruleType == "Protect" then
        rule.protect = true
    elseif ruleType == "Ignore" then
        rule.ignore = true
    elseif ruleType == "Always Bank" then
        rule.actionOverride = Data.Actions.BANK
    elseif ruleType == "Always Recall" then
        rule.actionOverride = Data.Actions.RECALL
    elseif ruleType == "Never Move" then
        rule.neverMove = true
    end
    Core.RefreshUI()
end

local function BuildSummaryTab(parent)
    parent.context = CreateLabel(parent, "", "GameFontHighlightLarge")
    parent.context:SetPoint("TOPLEFT", 0, 0)

    parent.lastScan = CreateLabel(parent, "")
    parent.lastScan:SetPoint("TOPLEFT", parent.context, "BOTTOMLEFT", 0, -10)

    parent.scanBags = CreateButton(parent, "Scan Bags")
    parent.scanBags:SetPoint("TOPLEFT", parent.lastScan, "BOTTOMLEFT", 0, -14)
    parent.scanBags:SetScript("OnClick", function() Core.ScanInventory(BAG_SCOPE) end)

    parent.scanBank = CreateButton(parent, "Scan Bank")
    parent.scanBank:SetPoint("LEFT", parent.scanBags, "RIGHT", 8, 0)
    parent.scanBank:SetScript("OnClick", function() Core.ScanInventory(BANK_SCOPE) end)

    parent.openMove = CreateButton(parent, "Open Move Tab")
    parent.openMove:SetPoint("LEFT", parent.scanBank, "RIGHT", 8, 0)
    parent.openMove:SetScript("OnClick", function() SetTab("Move") end)

    parent.cards = {}
    for i = 1, 8 do
        local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        card:SetSize(168, 48)
        card:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        card.title = CreateLabel(card, "", "GameFontNormalSmall")
        card.title:SetPoint("TOPLEFT", 8, -7)
        card.value = CreateLabel(card, "", "GameFontHighlightLarge")
        card.value:SetPoint("BOTTOMLEFT", 8, 7)
        card:SetPoint("TOPLEFT", parent.scanBags, "BOTTOMLEFT", ((i - 1) % 4) * 176, -18 - math.floor((i - 1) / 4) * 56)
        parent.cards[i] = card
    end
end

local function BuildMoveTab(parent)
    parent.modeBank = CreateButton(parent, "Dump to Bank", 120)
    parent.modeBank:SetPoint("TOPLEFT", 0, 0)
    parent.modeBank:SetScript("OnClick", function()
        ns.DB.ui.mode = "Dump to Bank"
        Core.RefreshUI()
    end)

    parent.modeRecall = CreateButton(parent, "Recall from Bank", 130)
    parent.modeRecall:SetPoint("LEFT", parent.modeBank, "RIGHT", 8, 0)
    parent.modeRecall:SetScript("OnClick", function()
        ns.DB.ui.mode = "Recall from Bank"
        Core.RefreshUI()
    end)

    parent.expansionFilter = CreateDropdown(parent, 170, GetExpansionOptions(), function(value)
        ns.DB.ui.expansionFilter = value
        UI.page = 1
    end)
    parent.expansionFilter:SetPoint("TOPLEFT", parent.modeBank, "BOTTOMLEFT", 0, -10)

    parent.typeFilter = CreateDropdown(parent, 150, {
        { text = "All", value = "All" },
        { text = Data.ItemTypes.REPUTATION, value = Data.ItemTypes.REPUTATION },
        { text = Data.ItemTypes.QUEST, value = Data.ItemTypes.QUEST },
        { text = Data.ItemTypes.PROFESSION, value = Data.ItemTypes.PROFESSION },
        { text = Data.ItemTypes.CONSUMABLE, value = Data.ItemTypes.CONSUMABLE },
        { text = Data.ItemTypes.BOE, value = Data.ItemTypes.BOE },
        { text = Data.ItemTypes.UNKNOWN, value = Data.ItemTypes.UNKNOWN },
    }, function(value)
        ns.DB.ui.typeFilter = value
        UI.page = 1
    end)
    parent.typeFilter:SetPoint("LEFT", parent.expansionFilter, "RIGHT", 8, 0)

    parent.locationFilter = CreateDropdown(parent, 130, {
        { text = "All", value = "All" },
        { text = "Bags", value = "Bags" },
        { text = "Bank", value = "Bank" },
    }, function(value)
        ns.DB.ui.locationFilter = value
        UI.page = 1
    end)
    parent.locationFilter:SetPoint("LEFT", parent.typeFilter, "RIGHT", 8, 0)

    parent.recommended = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    parent.recommended:SetPoint("LEFT", parent.locationFilter, "RIGHT", 12, 0)
    parent.recommendedLabel = CreateLabel(parent, "Recommended only", "GameFontHighlightSmall")
    parent.recommendedLabel:SetPoint("LEFT", parent.recommended, "RIGHT", -2, 0)
    parent.recommended:SetScript("OnClick", function(self)
        ns.DB.ui.recommendedOnly = self:GetChecked() and true or false
        UI.page = 1
        Core.RefreshUI()
    end)

    parent.search = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    parent.search:SetSize(170, 24)
    parent.search:SetAutoFocus(false)
    parent.search:SetPoint("TOPLEFT", parent.expansionFilter, "BOTTOMLEFT", 6, -10)
    parent.search:SetScript("OnTextChanged", function(self)
        ns.DB.ui.search = self:GetText() or ""
        UI.page = 1
        Core.RefreshUI()
    end)

    parent.headers = CreateLabel(parent, "Item                         Count  Expansion       Type        Location          Action          Rule", "GameFontNormalSmall")
    parent.headers:SetPoint("TOPLEFT", parent.search, "BOTTOMLEFT", -6, -12)

    parent.listFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    parent.listFrame:SetSize(720, 306)
    parent.listFrame:SetPoint("TOPLEFT", parent.headers, "BOTTOMLEFT", 0, -4)
    parent.listFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    parent.listFrame:SetBackdropColor(0, 0, 0, 0.2)

    parent.rows = {}
    for i = 1, UI.pageSize do
        local row = CreateFrame("Button", nil, parent.listFrame, "BackdropTemplate")
        row:SetSize(710, 28)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row:SetBackdropColor(0, 0, 0, i % 2 == 0 and 0.18 or 0.08)
        row:SetPoint("TOPLEFT", parent.listFrame, "TOPLEFT", 5, -5 - (i - 1) * 30)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetPoint("LEFT", 0, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", row.check, "RIGHT", -2, 0)
        row.text = CreateLabel(row, "", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.text:SetWidth(420)
        row.text:SetWordWrap(false)
        row.bank = CreateButton(row, "Bank", 50, 22)
        row.bank:SetPoint("RIGHT", row, "RIGHT", -180, 0)
        row.recall = CreateButton(row, "Recall", 56, 22)
        row.recall:SetPoint("RIGHT", row, "RIGHT", -120, 0)
        row.protect = CreateButton(row, "Protect", 58, 22)
        row.protect:SetPoint("RIGHT", row, "RIGHT", -60, 0)
        row.ignore = CreateButton(row, "Ignore", 56, 22)
        row.ignore:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        parent.rows[i] = row
    end

    parent.footer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    parent.footer:SetSize(720, 54)
    parent.footer:SetPoint("BOTTOMLEFT", 0, 0)
    parent.footer:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })

    parent.selectRecommended = CreateButton(parent, "Select Recommended", 140)
    parent.selectRecommended:SetParent(parent.footer)
    parent.selectRecommended:SetPoint("TOPLEFT", parent.footer, "TOPLEFT", 8, -7)
    parent.selectRecommended:SetScript("OnClick", function() Core.SelectRecommended() end)

    parent.selectVisible = CreateButton(parent, "Select Visible", 110)
    parent.selectVisible:SetParent(parent.footer)
    parent.selectVisible:SetPoint("LEFT", parent.selectRecommended, "RIGHT", 8, 0)
    parent.selectVisible:SetScript("OnClick", function() Core.SelectVisible() end)

    parent.clear = CreateButton(parent, "Clear Selection", 120)
    parent.clear:SetParent(parent.footer)
    parent.clear:SetPoint("LEFT", parent.selectVisible, "RIGHT", 8, 0)
    parent.clear:SetScript("OnClick", function()
        UI.selected = {}
        Core.RefreshUI()
    end)

    parent.move = CreateButton(parent, "Move Selected", 120)
    parent.move:SetParent(parent.footer)
    parent.move:SetPoint("LEFT", parent.clear, "RIGHT", 8, 0)
    parent.move:SetScript("OnClick", function() Core.MoveSelected() end)

    parent.prev = CreateButton(parent, "Prev", 60)
    parent.prev:SetParent(parent.footer)
    parent.prev:SetPoint("TOPLEFT", parent.footer, "TOPLEFT", 8, -29)
    parent.prev:SetScript("OnClick", function()
        UI.page = math.max(1, UI.page - 1)
        Core.RefreshUI()
    end)

    parent.next = CreateButton(parent, "Next", 60)
    parent.next:SetParent(parent.footer)
    parent.next:SetPoint("LEFT", parent.prev, "RIGHT", 6, 0)
    parent.next:SetScript("OnClick", function()
        UI.page = UI.page + 1
        Core.RefreshUI()
    end)

    parent.pageText = CreateLabel(parent, "", "GameFontHighlightSmall")
    parent.pageText:SetParent(parent.footer)
    parent.pageText:SetPoint("LEFT", parent.next, "RIGHT", 8, 0)
end

local function BuildRulesTab(parent)
    parent.help = CreateLabel(parent, "Item-ID rules created from Move rows. Rules are conservative and removable.", "GameFontHighlight")
    parent.help:SetPoint("TOPLEFT", 0, 0)
    parent.headers = CreateLabel(parent, "Item                         Rule type                         Created from", "GameFontNormalSmall")
    parent.headers:SetPoint("TOPLEFT", parent.help, "BOTTOMLEFT", 0, -14)
    parent.rows = {}
    for i = 1, 13 do
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(700, 28)
        row:SetPoint("TOPLEFT", parent.headers, "BOTTOMLEFT", 0, -4 - (i - 1) * 30)
        row.text = CreateLabel(row, "", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 0, 0)
        row.text:SetWidth(560)
        row.remove = CreateButton(row, "Remove", 70, 22)
        row.remove:SetPoint("RIGHT", 0, 0)
        parent.rows[i] = row
    end
end

function Core.CreateUI()
    if UI.frame then
        return
    end

    local frame = CreateFrame("Frame", "ICantEvenRightNowFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(780, 560)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnMouseDown", RaiseConsole)
    frame:SetScript("OnShow", RaiseConsole)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
    frame.title:SetText("I Can't Even Right Now")

    frame.panels = {}
    local previous
    for _, name in ipairs({ "Summary", "Move", "Rules" }) do
        local tab = CreateButton(frame, name, 92, 24)
        tab:SetPoint("TOPLEFT", previous or frame, previous and "TOPRIGHT" or "TOPLEFT", previous and 4 or 14, previous and 0 or -34)
        tab:SetScript("OnClick", function() SetTab(name) end)
        UI.tabs[name] = tab
        previous = tab

        local panel = CreatePanel(frame)
        frame.panels[name] = panel
        if name == "Summary" then
            BuildSummaryTab(panel)
        elseif name == "Move" then
            BuildMoveTab(panel)
        else
            BuildRulesTab(panel)
        end
    end

    UI.frame = frame
end

function Core.RefreshSummary()
    local panel = UI.frame.panels.Summary
    local counts = CountSummary()
    panel.context:SetText("Context: " .. GetContextText())
    panel.lastScan:SetText("Last scan: Bags " .. FormatTimestamp(ns.DB.lastScan.bags) .. " | Bank " .. FormatTimestamp(ns.DB.lastScan.bank))
    panel.scanBank:SetEnabled(ns.DB.context.bankOpen and not ns.DB.context.inCombat)

    local cards = {
        { "Old-content items in bags", counts.oldBags },
        { "Old-content items in bank", counts.oldBank },
        { "Bank candidates", counts.bankCandidates },
        { "Recall candidates", counts.recallCandidates },
        { "Obsolete consumables", counts.consumables },
        { "Old BoEs", counts.boes },
        { "Unknown/review items", counts.unknown },
        { "Protected items", counts.protected },
    }
    for index, cardData in ipairs(cards) do
        panel.cards[index].title:SetText(cardData[1])
        panel.cards[index].value:SetText(cardData[2])
    end
end

function Core.GetFilteredVisible()
    local filtered = {}
    for _, item in ipairs(GetAllDecisions()) do
        if MatchesFilter(item) then
            table.insert(filtered, item)
        end
    end
    table.sort(filtered, SortDecisions)
    return filtered
end

function Core.RefreshMove()
    local panel = UI.frame.panels.Move
    local ui = ns.DB.ui
    local filtered = Core.GetFilteredVisible()
    UI.visible = filtered

    panel.modeBank:SetText(ui.mode == "Dump to Bank" and "[Dump to Bank]" or "Dump to Bank")
    panel.modeRecall:SetText(ui.mode == "Recall from Bank" and "[Recall from Bank]" or "Recall from Bank")
    SetDropdownText(panel.expansionFilter, "Expansion: " .. (ui.expansionFilter == 0 and "All expansions" or GetExpansionName(ui.expansionFilter)))
    SetDropdownText(panel.typeFilter, "Type: " .. ui.typeFilter)
    SetDropdownText(panel.locationFilter, "Location: " .. ui.locationFilter)
    panel.recommended:SetChecked(ui.recommendedOnly)
    if panel.search:GetText() ~= ui.search then
        panel.search:SetText(ui.search or "")
    end

    local maxPage = math.max(1, math.ceil(#filtered / UI.pageSize))
    UI.page = math.min(UI.page, maxPage)
    local startIndex = (UI.page - 1) * UI.pageSize + 1
    local selectedCount = 0
    for _, selected in pairs(UI.selected) do
        if selected then
            selectedCount = selectedCount + 1
        end
    end
    panel.pageText:SetText("Page " .. UI.page .. "/" .. maxPage .. " (" .. #filtered .. " visible, " .. selectedCount .. " selected)")
    panel.move:SetText(ui.mode == "Recall from Bank" and "Recall Selected" or "Bank Selected")
    panel.move:SetEnabled(ns.DB.context.bankOpen and not ns.DB.context.inCombat)

    for i, row in ipairs(panel.rows) do
        local item = filtered[startIndex + i - 1]
        if item then
            row:Show()
            row.item = item
            row.icon:SetTexture(item.icon)
            row.check:SetChecked(UI.selected[item.key] and true or false)
            row.check:SetScript("OnClick", function(self)
                UI.selected[item.key] = self:GetChecked() and true or nil
            end)
            local line = string.format("%-28s x%-3d  %-14s %-11s %-16s %-14s %s",
                item.name or ("Item " .. item.itemID),
                item.count or 1,
                item.expansionName or "Unknown",
                item.typeTag or "Unknown",
                item.location or "",
                item.recommendedAction or "Review",
                item.ruleStatus or "none")
            row.text:SetText(line)
            row.bank:SetScript("OnClick", function() AddRule(item, "Always Bank") end)
            row.recall:SetScript("OnClick", function() AddRule(item, "Always Recall") end)
            row.protect:SetScript("OnClick", function() AddRule(item, "Protect") end)
            row.ignore:SetScript("OnClick", function() AddRule(item, "Ignore") end)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(item.link or ("item:" .. item.itemID))
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Expansion: " .. (item.expansionName or "Unknown"), 1, 1, 1)
                GameTooltip:AddLine("Source: " .. (item.curated and "CuratedTable" or "Item API/defaults"), 1, 1, 1)
                GameTooltip:AddLine("Reason: " .. (item.reason or "Review"), 1, 1, 1)
                if #item.blockedReasons > 0 then
                    GameTooltip:AddLine("Blocked by: " .. table.concat(item.blockedReasons, ", "), 1, 0.35, 0.35)
                end
                GameTooltip:AddLine("Actions: Protect, Ignore, Bank/Recall override via rules", 0.7, 0.85, 1)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            row.item = nil
            row:Hide()
        end
    end
end

function Core.RefreshRules()
    local panel = UI.frame.panels.Rules
    local rows = {}
    for itemID, rule in pairs(ns.DB.rules.items or {}) do
        table.insert(rows, { itemID = itemID, rule = rule })
    end
    table.sort(rows, function(a, b) return tonumber(a.itemID) < tonumber(b.itemID) end)

    for i, row in ipairs(panel.rows) do
        local data = rows[i]
        if data then
            row:Show()
            local rule = data.rule
            local types = {}
            if rule.protect then table.insert(types, "Protect this item") end
            if rule.neverMove then table.insert(types, "Never move this item") end
            if rule.neverSell then table.insert(types, "Never sell this item") end
            if rule.ignore then table.insert(types, "Ignore this item") end
            if rule.expansionOverride then table.insert(types, "Override expansion: " .. GetExpansionName(rule.expansionOverride)) end
            if rule.actionOverride then table.insert(types, "Override action: " .. rule.actionOverride) end
            if #types == 0 then table.insert(types, "Empty rule") end
            local name = GetItemInfo(data.itemID) or ("Item " .. data.itemID)
            row.text:SetText(name .. " (" .. data.itemID .. ")    " .. table.concat(types, ", ") .. "    " .. (rule.createdFrom or "Unknown"))
            row.remove:SetScript("OnClick", function()
                ns.DB.rules.items[data.itemID] = nil
                Core.RefreshUI()
            end)
        else
            row:Hide()
        end
    end
end

function Core.RefreshUI()
    if not UI.frame then
        return
    end
    Core.UpdateContext()
    for name, panel in pairs(UI.frame.panels) do
        panel:SetShown(name == UI.activeTab)
        UI.tabs[name]:SetText(name == UI.activeTab and ("[" .. name .. "]") or name)
    end
    Core.RefreshSummary()
    Core.RefreshMove()
    Core.RefreshRules()
end

function Core.ShowSummaryUI()
    Core.CreateUI()
    UI.activeTab = "Summary"
    UI.frame:Show()
    Core.RefreshUI()
end

function Core.ShowMoveUI()
    Core.CreateUI()
    UI.activeTab = "Move"
    UI.frame:Show()
    Core.RefreshUI()
end

function Core.SetExpansionFilterFromText(text)
    text = (text or ""):lower()
    if text == "" or text == "all" or text == "old" then
        ns.DB.ui.expansionFilter = 0
        return
    end
    for expansionID, expansion in pairs(Data.Expansions) do
        if expansion.name:lower():find(text, 1, true) then
            ns.DB.ui.expansionFilter = expansionID
            return
        end
    end
    Print("Unknown expansion filter: " .. text)
end

function Core.SelectRecommended()
    UI.selected = {}
    for _, item in ipairs(UI.visible) do
        local bankOK = ns.DB.ui.mode == "Dump to Bank" and item.recommendedAction == Data.Actions.BANK and item.scope == BAG_SCOPE
        local recallOK = ns.DB.ui.mode == "Recall from Bank" and item.recommendedAction == Data.Actions.RECALL and item.scope == BANK_SCOPE
        if bankOK or recallOK then
            UI.selected[item.key] = true
        end
    end
    Core.RefreshUI()
end

function Core.SelectVisible()
    UI.selected = {}
    for _, item in ipairs(UI.visible) do
        UI.selected[item.key] = true
    end
    Core.RefreshUI()
end

local function RemoveMovedItemsFromScan(movedKeys)
    for _, scope in ipairs({ BAG_SCOPE, BANK_SCOPE }) do
        local kept = {}
        for _, item in ipairs(ns.DB.scans[scope] or {}) do
            if not movedKeys[LocationKey(item)] then
                table.insert(kept, item)
            end
        end
        ns.DB.scans[scope] = kept
    end
end

function Core.MoveSelected()
    Core.UpdateContext()
    if ns.DB.context.inCombat then
        Print("Cannot move items in combat.")
        return
    end
    if not ns.DB.context.bankOpen then
        Print("Open the bank before moving items.")
        return
    end

    local moved, blocked = 0, 0
    local movedKeys = {}
    for _, item in ipairs(GetAllDecisions()) do
        if UI.selected[item.key] then
            local canMove = ns.DB.ui.mode == "Dump to Bank" and item.eligibleForBankMove
            canMove = canMove or (ns.DB.ui.mode == "Recall from Bank" and item.eligibleForRecall)
            if canMove and CContainer.UseContainerItem then
                CContainer.UseContainerItem(item.bagID, item.slot)
                movedKeys[item.key] = true
                moved = moved + 1
            else
                blocked = blocked + 1
            end
        end
    end
    UI.selected = {}
    RemoveMovedItemsFromScan(movedKeys)
    Core.RefreshUI()
    Print("Move run complete: " .. moved .. " moved, " .. blocked .. " blocked.")
    Core.ScheduleRescanAfterMove()
end

function Core.RegisterSlashCommands()
    SLASH_ICANTEVEN1 = "/icanteven"
    SLASH_ICANTEVEN2 = "/icant"
    SlashCmdList["ICANTEVEN"] = function(msg)
        Core.HandleSlashCommand(msg)
    end
end

function Core.HandleSlashCommand(msg)
    local cmd, arg1 = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" then
        Core.ShowSummaryUI()
    elseif cmd == "scan" then
        Core.ScanInventory(arg1)
    elseif cmd == "summary" then
        Core.ShowSummaryUI()
    elseif cmd == "move" then
        Core.ShowMoveUI()
    elseif cmd == "dump" then
        ns.DB.ui.mode = "Dump to Bank"
        Core.SetExpansionFilterFromText(arg1)
        Core.ShowMoveUI()
    elseif cmd == "recall" then
        ns.DB.ui.mode = "Recall from Bank"
        Core.SetExpansionFilterFromText(arg1)
        Core.ShowMoveUI()
    elseif cmd == "rules" or cmd == "config" or cmd == "protect" then
        Core.CreateUI()
        UI.activeTab = "Rules"
        UI.frame:Show()
        Core.RefreshUI()
    elseif cmd == "debug" then
        Debug.SetDebug(not Debug.IsDebugEnabled())
        Print("Debug mode: " .. (Debug.IsDebugEnabled() and "ON" or "OFF"))
    elseif cmd == "diag" then
        Debug.RunDiagnosticDump()
    else
        Print("Commands: /icanteven, scan [bags|bank|all], summary, move, rules, debug, diag")
    end
end

function Core.OnAddonLoaded()
    ICantEvenRightNowDB = SafeCopyDefaults(Data.DefaultDB, ICantEvenRightNowDB)
    ns.DB = ICantEvenRightNowDB
    Core.RegisterSlashCommands()
    Core.UpdateContext()
    Print("Loaded. Type /icanteven to open the cleanup console.")
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("BANKFRAME_CLOSED")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("MERCHANT_CLOSED")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
eventFrame:RegisterEvent("MAIL_SHOW")
eventFrame:RegisterEvent("MAIL_CLOSED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == ADDON_NAME then
            Core.OnAddonLoaded()
        end
    elseif ns.DB and ns.DB.context then
        Core.UpdateContext()
        if UI.frame and UI.frame:IsShown() then
            Core.RefreshUI()
        end
    end
end)
