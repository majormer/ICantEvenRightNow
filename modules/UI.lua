local _, ns = ...
local Core = ns.Core
local Data = ns.Data
local UI = ns.UI

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
    parent.help = CreateLabel(parent, "Move flow: use checkboxes for batch actions, or act on a single eligible row.", "GameFontHighlight")
    parent.help:SetPoint("TOPLEFT", 0, 0)
    parent.contextNotice = CreateContextNotice(parent)

    parent.modeBank = CreateButton(parent, "Dump to Bank", 120)
    parent.modeBank:SetPoint("TOPLEFT", parent.help, "BOTTOMLEFT", 0, -10)
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

    parent.expansionFilter = CreateDropdown(parent, 160, GetExpansionOptions(), function(value)
        SetFilterInclude("Move", "expansion", value)
    end)
    parent.expansionFilter:SetPoint("TOPLEFT", parent.modeBank, "BOTTOMLEFT", 0, -10)

    parent.typeFilter = CreateDropdown(parent, 135, GetTypeFilterOptions(), function(value)
        SetFilterInclude("Move", "type", value)
    end)
    parent.typeFilter:SetPoint("LEFT", parent.expansionFilter, "RIGHT", 8, 0)

    parent.bindFilter = CreateDropdown(parent, 115, GetBindFilterOptions(), function(value)
        SetFilterInclude("Move", "bind", value)
    end)
    parent.bindFilter:SetPoint("LEFT", parent.typeFilter, "RIGHT", 8, 0)

    parent.locationFilter = CreateDropdown(parent, 115, {
        { text = "All", value = "All" },
        { text = "Bags", value = "Bags" },
        { text = "Bank", value = "Bank" },
    }, function(value)
        SetFilterInclude("Move", "location", value)
    end)
    parent.locationFilter:SetPoint("LEFT", parent.bindFilter, "RIGHT", 8, 0)

    parent.recommended = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    parent.recommended:SetPoint("LEFT", parent.locationFilter, "RIGHT", 12, 0)
    parent.recommendedLabel = CreateLabel(parent, "Recommended only", "GameFontHighlightSmall")
    parent.recommendedLabel:SetPoint("LEFT", parent.recommended, "RIGHT", -2, 0)
    parent.recommended:SetScript("OnClick", function(self)
        ns.DB.ui.recommendedOnly = self:GetChecked() and true or false
        UI.page = 1
        Core.RefreshUI()
    end)

    parent.searchLabel = CreateLabel(parent, "Search", "GameFontHighlightSmall")
    parent.searchLabel:SetPoint("TOPLEFT", parent.expansionFilter, "BOTTOMLEFT", 6, -14)
    parent.search = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    parent.search:SetSize(170, 24)
    parent.search:SetAutoFocus(false)
    parent.search:SetPoint("LEFT", parent.searchLabel, "RIGHT", 8, 0)
    parent.search:SetScript("OnTextChanged", function(self)
        SetFilterSearch("Move", self:GetText())
        Core.RefreshUI()
    end)

    parent.actionableOnly = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    parent.actionableOnly:SetPoint("LEFT", parent.search, "RIGHT", 14, 0)
    parent.actionableOnlyLabel = CreateLabel(parent, "Actionable only", "GameFontHighlightSmall")
    parent.actionableOnlyLabel:SetPoint("LEFT", parent.actionableOnly, "RIGHT", -2, 0)
    parent.actionableOnly:SetScript("OnClick", function(self)
        SetFilterHideBlocked("Move", self:GetChecked())
        Core.RefreshUI()
    end)

    parent.clearFilters = CreateButton(parent, "Clear Filters", 100)
    parent.clearFilters:SetPoint("LEFT", parent.actionableOnlyLabel, "RIGHT", 10, 0)
    parent.clearFilters:SetScript("OnClick", function()
        ResetTabFilters("Move")
        Core.RefreshUI()
    end)

    parent.filterSummary = CreateLabel(parent, "", "GameFontDisableSmall")
    parent.filterSummary:SetPoint("TOPLEFT", parent.searchLabel, "BOTTOMLEFT", -6, -6)
    parent.filterSummary:SetWidth(700)
    parent.filterSummary:SetWordWrap(false)

    parent.listFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    parent.listFrame:SetSize(720, 264)
    parent.listFrame:SetPoint("TOPLEFT", parent.filterSummary, "BOTTOMLEFT", 0, -8)
    parent.listFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    parent.listFrame:SetBackdropColor(0, 0, 0, 0.2)
    parent.empty = CreateEmptyLabel(parent.listFrame, "No bank organization plans.")
    parent.empty = CreateEmptyLabel(parent.listFrame, "No matching move candidates.")

    parent.rows = {}
    for i = 1, UI.pageSize do
        local row = CreateFrame("Button", nil, parent.listFrame, "BackdropTemplate")
        row:SetSize(710, 40)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row:SetBackdropColor(0, 0, 0, i % 2 == 0 and 0.18 or 0.08)
        row:SetPoint("TOPLEFT", parent.listFrame, "TOPLEFT", 5, -5 - (i - 1) * 42)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetPoint("LEFT", 0, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", row.check, "RIGHT", -2, 0)
        row.nameText = CreateLabel(row, "", "GameFontHighlightSmall")
        row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -4)
        row.nameText:SetWidth(460)
        row.nameText:SetWordWrap(false)
        row.detailText = CreateLabel(row, "", "GameFontDisableSmall")
        row.detailText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -2)
        row.detailText:SetWidth(460)
        row.detailText:SetWordWrap(false)
        row.action = CreateButton(row, "Act", 60, 22)
        row.action:SetPoint("RIGHT", row, "RIGHT", -86, 0)
        row.rule = CreateButton(row, "+Rule", 70, 22)
        row.rule:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.ruleMenu = CreateRowRuleMenu(row, 104, {
            { text = "Always Bank", ruleType = "Always Bank" },
            { text = "Always Recall", ruleType = "Always Recall" },
            { text = "Protect", ruleType = "Protect" },
            { text = "Ignore", ruleType = "Ignore" },
        })
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

    parent.selectVisible = CreateButton(parent, "Select Page", 110)
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

local function BuildOrganizeTab(parent)
    parent.help = CreateLabel(parent, "Bank organizer: move selected stacks between private and Warband bank storage.", "GameFontHighlight")
    parent.help:SetPoint("TOPLEFT", 0, 0)
    parent.contextNotice = CreateContextNotice(parent)

    parent.expansionFilter = CreateDropdown(parent, 160, GetExpansionOptions(), function(value)
        SetFilterInclude("Organize", "expansion", value)
    end)
    parent.expansionFilter:SetPoint("TOPLEFT", parent.help, "BOTTOMLEFT", 0, -12)

    parent.typeFilter = CreateDropdown(parent, 135, GetTypeFilterOptions(), function(value)
        SetFilterInclude("Organize", "type", value)
    end)
    parent.typeFilter:SetPoint("LEFT", parent.expansionFilter, "RIGHT", 8, 0)

    parent.bindFilter = CreateDropdown(parent, 115, GetBindFilterOptions(), function(value)
        SetFilterInclude("Organize", "bind", value)
    end)
    parent.bindFilter:SetPoint("LEFT", parent.typeFilter, "RIGHT", 8, 0)

    parent.locationFilter = CreateDropdown(parent, 135, GetBankLocationFilterOptions(), function(value)
        SetFilterInclude("Organize", "location", value)
    end)
    parent.locationFilter:SetPoint("LEFT", parent.bindFilter, "RIGHT", 8, 0)

    parent.rescan = CreateButton(parent, "Rescan Bank", 110)
    parent.rescan:SetPoint("TOPLEFT", parent.expansionFilter, "BOTTOMLEFT", 0, -10)
    parent.rescan:SetScript("OnClick", function() Core.ScanInventory("all") end)

    parent.showAll = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    parent.showAll:SetPoint("LEFT", parent.rescan, "RIGHT", 12, 0)
    parent.showAllLabel = CreateLabel(parent, "Show already optimized", "GameFontHighlightSmall")
    parent.showAllLabel:SetPoint("LEFT", parent.showAll, "RIGHT", -2, 0)
    parent.showAll:SetScript("OnClick", function(self)
        ns.DB.ui.organizerShowAll = self:GetChecked() and true or false
        UI.page = 1
        Core.RefreshUI()
    end)

    parent.searchLabel = CreateLabel(parent, "Search", "GameFontHighlightSmall")
    parent.searchLabel:SetPoint("LEFT", parent.showAllLabel, "RIGHT", 18, 0)
    parent.search = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    parent.search:SetSize(160, 24)
    parent.search:SetAutoFocus(false)
    parent.search:SetPoint("LEFT", parent.searchLabel, "RIGHT", 8, 0)
    parent.search:SetScript("OnTextChanged", function(self)
        SetFilterSearch("Organize", self:GetText())
        Core.RefreshUI()
    end)

    parent.actionableOnly = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    parent.actionableOnly:SetPoint("LEFT", parent.search, "RIGHT", 14, 0)
    parent.actionableOnlyLabel = CreateLabel(parent, "Actionable only", "GameFontHighlightSmall")
    parent.actionableOnlyLabel:SetPoint("LEFT", parent.actionableOnly, "RIGHT", -2, 0)
    parent.actionableOnly:SetScript("OnClick", function(self)
        SetFilterHideBlocked("Organize", self:GetChecked())
        Core.RefreshUI()
    end)

    parent.clearFilters = CreateButton(parent, "Clear Filters", 100)
    parent.clearFilters:SetPoint("LEFT", parent.actionableOnlyLabel, "RIGHT", 10, 0)
    parent.clearFilters:SetScript("OnClick", function()
        ResetTabFilters("Organize")
        Core.RefreshUI()
    end)

    parent.filterSummary = CreateLabel(parent, "", "GameFontDisableSmall")
    parent.filterSummary:SetPoint("TOPLEFT", parent.rescan, "BOTTOMLEFT", 0, -8)
    parent.filterSummary:SetWidth(700)
    parent.filterSummary:SetWordWrap(false)

    parent.listFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    parent.listFrame:SetSize(720, 264)
    parent.listFrame:SetPoint("TOPLEFT", parent.filterSummary, "BOTTOMLEFT", 0, -8)
    parent.listFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    parent.listFrame:SetBackdropColor(0, 0, 0, 0.2)
    parent.empty = CreateEmptyLabel(parent.listFrame, "No organization plans.")

    parent.rows = {}
    for i = 1, ORGANIZE_PAGE_SIZE do
        local row = CreateFrame("Button", nil, parent.listFrame, "BackdropTemplate")
        row:SetSize(710, 38)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row:SetBackdropColor(0, 0, 0, i % 2 == 0 and 0.18 or 0.08)
        row:SetPoint("TOPLEFT", parent.listFrame, "TOPLEFT", 5, -5 - (i - 1) * 42)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetPoint("LEFT", 0, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", row.check, "RIGHT", -2, 0)
        row.nameText = CreateLabel(row, "", "GameFontHighlightSmall")
        row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -4)
        row.nameText:SetWidth(620)
        row.nameText:SetWordWrap(false)
        row.detailText = CreateLabel(row, "", "GameFontDisableSmall")
        row.detailText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -2)
        row.detailText:SetWidth(620)
        row.detailText:SetWordWrap(false)
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

    parent.selectMovable = CreateButton(parent, "Select Page", 110)
    parent.selectMovable:SetParent(parent.footer)
    parent.selectMovable:SetPoint("TOPLEFT", parent.footer, "TOPLEFT", 8, -7)
    parent.selectMovable:SetScript("OnClick", function() Core.SelectOrganizerMovable() end)

    parent.clear = CreateButton(parent, "Clear Selection", 120)
    parent.clear:SetParent(parent.footer)
    parent.clear:SetPoint("LEFT", parent.selectMovable, "RIGHT", 8, 0)
    parent.clear:SetScript("OnClick", function()
        UI.organizeSelected = {}
        Core.RefreshUI()
    end)

    parent.move = CreateButton(parent, "Move Selected", 120)
    parent.move:SetParent(parent.footer)
    parent.move:SetPoint("LEFT", parent.clear, "RIGHT", 8, 0)
    parent.move:SetScript("OnClick", function() Core.MoveOrganizerSelected() end)

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

local function BuildVendorTab(parent)
    parent.help = CreateLabel(parent, "Vendor flow: recall old low-value consumables from bank, then sell them at a vendor.", "GameFontHighlight")
    parent.help:SetPoint("TOPLEFT", 0, 0)
    parent.contextNotice = CreateContextNotice(parent)

    parent.rescan = CreateButton(parent, "Rescan All", 100)
    parent.rescan:SetPoint("TOPLEFT", parent.help, "BOTTOMLEFT", 0, -12)
    parent.rescan:SetScript("OnClick", function() Core.ScanInventory("all") end)

    parent.showAll = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    parent.showAll:SetPoint("LEFT", parent.rescan, "RIGHT", 12, 0)
    parent.showAllLabel = CreateLabel(parent, "Show rejected items", "GameFontHighlightSmall")
    parent.showAllLabel:SetPoint("LEFT", parent.showAll, "RIGHT", -2, 0)
    parent.showAll:SetScript("OnClick", function(self)
        ns.DB.ui.vendorShowAll = self:GetChecked() and true or false
        UI.page = 1
        Core.RefreshUI()
    end)

    parent.expansionFilter = CreateDropdown(parent, 160, GetExpansionOptions(), function(value)
        SetFilterInclude("Vendor", "expansion", value)
    end)
    parent.expansionFilter:SetPoint("TOPLEFT", parent.rescan, "BOTTOMLEFT", 0, -10)

    parent.typeFilter = CreateDropdown(parent, 135, GetTypeFilterOptions(), function(value)
        SetFilterInclude("Vendor", "type", value)
    end)
    parent.typeFilter:SetPoint("LEFT", parent.expansionFilter, "RIGHT", 8, 0)

    parent.bindFilter = CreateDropdown(parent, 115, GetBindFilterOptions(), function(value)
        SetFilterInclude("Vendor", "bind", value)
    end)
    parent.bindFilter:SetPoint("LEFT", parent.typeFilter, "RIGHT", 8, 0)

    parent.searchLabel = CreateLabel(parent, "Search", "GameFontHighlightSmall")
    parent.searchLabel:SetPoint("LEFT", parent.bindFilter, "RIGHT", 18, 0)
    parent.search = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    parent.search:SetSize(160, 24)
    parent.search:SetAutoFocus(false)
    parent.search:SetPoint("LEFT", parent.searchLabel, "RIGHT", 8, 0)
    parent.search:SetScript("OnTextChanged", function(self)
        SetFilterSearch("Vendor", self:GetText())
        Core.RefreshUI()
    end)

    parent.actionableOnly = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    parent.actionableOnly:SetPoint("LEFT", parent.search, "RIGHT", 14, 0)
    parent.actionableOnlyLabel = CreateLabel(parent, "Actionable only", "GameFontHighlightSmall")
    parent.actionableOnlyLabel:SetPoint("LEFT", parent.actionableOnly, "RIGHT", -2, 0)
    parent.actionableOnly:SetScript("OnClick", function(self)
        SetFilterHideBlocked("Vendor", self:GetChecked())
        Core.RefreshUI()
    end)

    parent.clearFilters = CreateButton(parent, "Clear Filters", 100)
    parent.clearFilters:SetPoint("LEFT", parent.actionableOnlyLabel, "RIGHT", 10, 0)
    parent.clearFilters:SetScript("OnClick", function()
        ResetTabFilters("Vendor")
        Core.RefreshUI()
    end)

    parent.context = CreateLabel(parent, "", "GameFontHighlightSmall")
    parent.context:SetPoint("TOPLEFT", parent.expansionFilter, "BOTTOMLEFT", 0, -8)

    parent.filterSummary = CreateLabel(parent, "", "GameFontDisableSmall")
    parent.filterSummary:SetPoint("TOPLEFT", parent.context, "BOTTOMLEFT", 0, -6)
    parent.filterSummary:SetWidth(700)
    parent.filterSummary:SetWordWrap(false)

    parent.listFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    parent.listFrame:SetSize(720, 264)
    parent.listFrame:SetPoint("TOPLEFT", parent.filterSummary, "BOTTOMLEFT", 0, -8)
    parent.listFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    parent.listFrame:SetBackdropColor(0, 0, 0, 0.2)
    parent.empty = CreateEmptyLabel(parent.listFrame, "No vendor plans.")

    parent.rows = {}
    for i = 1, VENDOR_PAGE_SIZE do
        local row = CreateFrame("Button", nil, parent.listFrame, "BackdropTemplate")
        row:SetSize(710, 38)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row:SetBackdropColor(0, 0, 0, i % 2 == 0 and 0.18 or 0.08)
        row:SetPoint("TOPLEFT", parent.listFrame, "TOPLEFT", 5, -5 - (i - 1) * 42)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetPoint("LEFT", 0, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", row.check, "RIGHT", -2, 0)
        row.nameText = CreateLabel(row, "", "GameFontHighlightSmall")
        row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -4)
        row.nameText:SetWidth(500)
        row.nameText:SetWordWrap(false)
        row.detailText = CreateLabel(row, "", "GameFontDisableSmall")
        row.detailText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -2)
        row.detailText:SetWidth(500)
        row.detailText:SetWordWrap(false)
        row.neverSell = CreateButton(row, "+Rule", 70, 22)
        row.neverSell:SetPoint("RIGHT", row, "RIGHT", -4, 0)
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

    parent.selectReady = CreateButton(parent, "Select Page", 110)
    parent.selectReady:SetParent(parent.footer)
    parent.selectReady:SetPoint("TOPLEFT", parent.footer, "TOPLEFT", 8, -7)
    parent.selectReady:SetScript("OnClick", function() Core.SelectVendorReady() end)

    parent.clear = CreateButton(parent, "Clear Selection", 120)
    parent.clear:SetParent(parent.footer)
    parent.clear:SetPoint("LEFT", parent.selectReady, "RIGHT", 8, 0)
    parent.clear:SetScript("OnClick", function()
        UI.vendorSelected = {}
        Core.RefreshUI()
    end)

    parent.move = CreateButton(parent, "Process Selected", 130)
    parent.move:SetParent(parent.footer)
    parent.move:SetPoint("LEFT", parent.clear, "RIGHT", 8, 0)
    parent.move:SetScript("OnClick", function() Core.ProcessVendorSelected() end)

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

    parent.listFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    parent.listFrame:SetSize(720, 394)
    parent.listFrame:SetPoint("TOPLEFT", parent.help, "BOTTOMLEFT", 0, -14)
    parent.listFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    parent.listFrame:SetBackdropColor(0, 0, 0, 0.2)

    parent.headers = CreateLabel(parent.listFrame, "Item                                      Rule type                                      Created from", "GameFontNormalSmall")
    parent.headers:SetPoint("TOPLEFT", parent.listFrame, "TOPLEFT", 10, -8)
    parent.empty = CreateEmptyLabel(parent.listFrame, "No item rules yet.")

    parent.rows = {}
    for i = 1, 12 do
        local row = CreateFrame("Frame", nil, parent.listFrame, "BackdropTemplate")
        row:SetSize(710, 28)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row:SetBackdropColor(0, 0, 0, i % 2 == 0 and 0.18 or 0.08)
        row:SetPoint("TOPLEFT", parent.listFrame, "TOPLEFT", 5, -30 - (i - 1) * 30)
        row.text = CreateLabel(row, "", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetWidth(600)
        row.remove = CreateButton(row, "Remove", 70, 22)
        row.remove:SetPoint("RIGHT", -4, 0)
        parent.rows[i] = row
    end

    parent.footer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    parent.footer:SetSize(720, 42)
    parent.footer:SetPoint("BOTTOMLEFT", 0, 0)
    parent.footer:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })

    parent.countText = CreateLabel(parent.footer, "", "GameFontHighlightSmall")
    parent.countText:SetPoint("LEFT", parent.footer, "LEFT", 8, 0)
end

local function BuildSettingsTab(parent)
    parent.help = CreateLabel(parent, "Quick access and display settings.", "GameFontHighlight")
    parent.help:SetPoint("TOPLEFT", 0, 0)

    parent.minimap = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    parent.minimap:SetPoint("TOPLEFT", parent.help, "BOTTOMLEFT", 0, -18)
    parent.minimapLabel = CreateLabel(parent, "Show minimap launcher", "GameFontHighlightSmall")
    parent.minimapLabel:SetPoint("LEFT", parent.minimap, "RIGHT", -2, 0)
    parent.minimap:SetScript("OnClick", function(self)
        ns.DB.ui.showMinimapIcon = self:GetChecked() and true or false
        Core.UpdateQuickAccessButtons()
        Core.RefreshUI()
    end)

    parent.note = CreateLabel(parent, "Bank and vendor launchers are disabled in this version.", "GameFontDisableSmall")
    parent.note:SetPoint("TOPLEFT", parent.minimap, "BOTTOMLEFT", 0, -10)

    parent.refresh = CreateButton(parent, "Refresh Launchers", 140)
    parent.refresh:SetPoint("TOPLEFT", parent.note, "BOTTOMLEFT", 0, -14)
    parent.refresh:SetScript("OnClick", function()
        Core.PrintQuickAccessStatus()
        Core.RefreshUI()
    end)

    parent.status = CreateLabel(parent, "", "GameFontDisableSmall")
    parent.status:SetPoint("TOPLEFT", parent.refresh, "BOTTOMLEFT", 0, -14)
    parent.status:SetWidth(680)
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
    frame.title:SetText(DISPLAY_NAME)

    frame.panels = {}
    local previous
    for _, name in ipairs(TAB_ORDER) do
        local tab = CreateButton(frame, name, 92, 26)
        tab:SetFrameLevel(frame:GetFrameLevel() + 8)
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
        elseif name == "Organize" then
            BuildOrganizeTab(panel)
        elseif name == "Vendor" then
            BuildVendorTab(panel)
        elseif name == "Rules" then
            BuildRulesTab(panel)
        else
            BuildSettingsTab(panel)
        end
    end

    UI.frame = frame
end


function Core.RefreshSummary()
    local panel = UI.frame.panels.Summary
    local counts = CountSummary()
    panel.context:SetText("Context: " .. GetContextText())
    panel.lastScan:SetText("Last scan: Bags " .. FormatTimestamp(ns.DB.lastScan.bags) .. " | Bank " .. FormatTimestamp(ns.DB.lastScan.bank))
    panel.scanBank:SetEnabled((UI.bankContextOpen or IsBankContextDetected()) and not ns.DB.context.inCombat)

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
    for _, item in ipairs(GetAllDecisions() or {}) do
        if MatchesMoveFilter(item) then
            table.insert(filtered, item)
        end
    end
    table.sort(filtered, SortDecisions)
    return filtered
end

local function GetMoveSearchDiagnostics(searchText)
    local searchMatches = 0
    local recommendedMatches = 0
    for _, item in ipairs(GetAllDecisions() or {}) do
        if TextMatchesSearch(searchText, {
            item.name or "",
            tostring(item.itemID or ""),
            item.expansionName or "",
            item.typeTag or "",
            item.location or "",
            item.reason or "",
        }) then
            searchMatches = searchMatches + 1
            if item.recommendedAction == Data.Actions.BANK or item.recommendedAction == Data.Actions.RECALL then
                recommendedMatches = recommendedMatches + 1
            end
        end
    end
    return searchMatches, recommendedMatches
end

function Core.RefreshMove()
    local panel = UI.frame.panels.Move
    local ui = ns.DB.ui
    local filters = EnsureTabFilters("Move")
    local filtered = Core.GetFilteredVisible()
    UI.visible = filtered
    local noticeText = (UI.bankContextOpen or IsBankContextDetected()) and "" or "Bank closed: move actions are unavailable."
    SetContextNotice(panel.contextNotice, noticeText ~= "" and noticeText or nil)

    panel.modeBank:SetText(ui.mode == "Dump to Bank" and "[Dump to Bank]" or "Dump to Bank")
    panel.modeRecall:SetText(ui.mode == "Recall from Bank" and "[Recall from Bank]" or "Recall from Bank")
    local expansionLabel = GetExpansionFilterLabel(filters.expansion.include)
    SetDropdownText(panel.expansionFilter, "Expansion: " .. expansionLabel)
    SetDropdownText(panel.typeFilter, "Type: " .. tostring(filters.type.include or "All"))
    SetDropdownText(panel.bindFilter, "Bind: " .. tostring(filters.bind.include or BIND_FILTER_ALL))
    SetDropdownText(panel.locationFilter, "Location: " .. tostring(filters.location.include or "All"))
    panel.recommended:SetChecked(ui.recommendedOnly)
    panel.actionableOnly:SetChecked(filters.hideBlocked)
    panel.filterSummary:SetText(BuildFilterSummary("Move"))
    local searchText = filters.name.includeText or ""
    if panel.search:GetText() ~= searchText then
        panel.search:SetText(searchText)
    end
    local emptyText = "No move candidates to show."
    if searchText ~= "" then
        local searchMatches, recommendedMatches = GetMoveSearchDiagnostics(searchText)
        if searchMatches == 0 then
            emptyText = "No scanned items match your search. Scan bags if the item is visible in your inventory."
        elseif ui.recommendedOnly and recommendedMatches == 0 then
            emptyText = "Items match your search, but none are recommended. Clear Recommended only to review them."
        else
            emptyText = "Items match your search, but not the current filters. Try All expansions, Type: All, and Location: All."
        end
    end
    SetEmptyLabel(panel.empty, #filtered == 0, emptyText)

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
    panel.move:SetEnabled((UI.bankContextOpen or IsBankContextDetected()) and not ns.DB.context.inCombat and selectedCount > 0)

    for i, row in ipairs(panel.rows) do
        local item = filtered[startIndex + i - 1]
        if item then
            row:Show()
            row.item = item
            row.icon:SetTexture(item.icon)
            local blockReason = GetMoveBlockReason(item)
            local moveEligible = IsMoveEligibleForCurrentMode(item) and not blockReason
            if not moveEligible then
                UI.selected[item.key] = nil
            end
            row.check:SetEnabled(moveEligible)
            row.check:SetChecked(moveEligible and UI.selected[item.key] and true or false)
            row.check:SetScript("OnClick", function(self)
                UI.selected[item.key] = self:GetChecked() and true or nil
                Core.RefreshUI()
            end)
            row.nameText:SetText(item.name or ("Item " .. item.itemID))
            local actionDetail = item.recommendedAction or "Review"
            if item.recommendedAction == Data.Actions.BANK and item.bankTargetStorage then
                actionDetail = "Bank -> " .. item.bankTargetStorage
            end
            row.detailText:SetText(string.format("x%d  |  %s  |  %s  |  %s  |  %s  |  %s",
                item.count or 1,
                item.expansionName or "Unknown",
                item.typeTag or "Unknown",
                item.location or "",
                actionDetail,
                item.ruleStatus == "custom" and "custom rule" or "no rule"))
            row.action:SetText(ui.mode == "Recall from Bank" and "Recall" or "Bank")
            row.action:SetEnabled(moveEligible)
            row.action:SetScript("OnClick", function()
                if moveEligible then
                    Core.MoveOneItem(item)
                else
                    local verb = ui.mode == "Recall from Bank" and "recall" or "bank"
                    Print("Cannot " .. verb .. " " .. (item.name or ("Item " .. item.itemID)) .. ": " .. (blockReason or "not eligible for this mode"))
                end
            end)
            row.rule:SetScript("OnClick", function() ToggleRowRuleMenu(row, item) end)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(item.link or ("item:" .. item.itemID))
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Expansion: " .. (item.expansionName or "Unknown"), 1, 1, 1)
                GameTooltip:AddLine("Source: " .. (item.curated and "CuratedTable" or "Item API/defaults"), 1, 1, 1)
                GameTooltip:AddLine("Reason: " .. (item.reason or "Review"), 1, 1, 1)
                if #item.blockedReasons > 0 then
                    local label = moveEligible and "Policy note: " or "Blocked by: "
                    GameTooltip:AddLine(label .. table.concat(item.blockedReasons, ", "), 1, 0.35, 0.35)
                elseif blockReason then
                    GameTooltip:AddLine("Cannot act: " .. blockReason, 1, 0.35, 0.35)
                end
                GameTooltip:AddLine("The row button acts on this item now.", 0.7, 0.85, 1)
                GameTooltip:AddLine("The checkbox includes this item in the footer action.", 0.7, 0.85, 1)
                GameTooltip:AddLine("+Rule creates future handling rules.", 0.7, 0.85, 1)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            row.item = nil
            if row.ruleMenu then
                row.ruleMenu:Hide()
            end
            row:Hide()
        end
    end
end

function Core.RefreshOrganizer()
    local panel = UI.frame.panels.Organize
    local filters = EnsureTabFilters("Organize")
    local noticeText = (UI.bankContextOpen or IsBankContextDetected()) and "" or "Bank closed: organization actions are unavailable."
    SetContextNotice(panel.contextNotice, noticeText ~= "" and noticeText or nil)
    SetDropdownText(panel.expansionFilter, "Expansion: " .. GetExpansionFilterLabel(filters.expansion.include))
    SetDropdownText(panel.typeFilter, "Type: " .. tostring(filters.type.include or "All"))
    SetDropdownText(panel.bindFilter, "Bind: " .. tostring(filters.bind.include or BIND_FILTER_ALL))
    SetDropdownText(panel.locationFilter, "Location: " .. tostring(filters.location.include or "All"))
    local showAll = ns.DB.ui.organizerShowAll
    local allPlans = GetOrganizationPlans(true)
    local plans = {}
    local displayableBeforeFilters = 0
    for _, plan in ipairs(allPlans) do
        if showAll or plan.needsMove then
            displayableBeforeFilters = displayableBeforeFilters + 1
        end
        if (showAll or plan.needsMove) and (not filters.hideBlocked or plan.movable) and PlanMatchesTabFilters(plan, "Organize") then
            table.insert(plans, plan)
        end
    end
    UI.organizeVisible = plans
    panel.showAll:SetChecked(showAll)
    panel.actionableOnly:SetChecked(filters.hideBlocked)
    panel.filterSummary:SetText(BuildFilterSummary("Organize"))
    local searchText = filters.name.includeText or ""
    if panel.search:GetText() ~= searchText then
        panel.search:SetText(searchText)
    end
    panel.rescan:SetEnabled((UI.bankContextOpen or IsBankContextDetected()) and not ns.DB.context.inCombat)
    local emptyText = "No bank organization plans to show."
    if searchText ~= "" then
        emptyText = "No organization plans match your search."
    elseif #allPlans == 0 then
        emptyText = "No scanned bank items. Open the bank and rescan."
    elseif displayableBeforeFilters == 0 then
        emptyText = "No bank moves needed. Enable Show already optimized to review scanned bank rows."
    elseif #plans == 0 then
        emptyText = "No organization plans match the current filters."
    end
    SetEmptyLabel(panel.empty, #plans == 0, emptyText)

    local maxPage = math.max(1, math.ceil(#plans / ORGANIZE_PAGE_SIZE))
    UI.page = math.min(UI.page, maxPage)
    local startIndex = (UI.page - 1) * ORGANIZE_PAGE_SIZE + 1
    local selectedCount = 0
    for _, selected in pairs(UI.organizeSelected) do
        if selected then
            selectedCount = selectedCount + 1
        end
    end
    panel.pageText:SetText("Page " .. UI.page .. "/" .. maxPage .. " (" .. #plans .. " plans, " .. selectedCount .. " selected)")
    panel.move:SetEnabled((UI.bankContextOpen or IsBankContextDetected()) and not ns.DB.context.inCombat and selectedCount > 0)

    for i, row in ipairs(panel.rows) do
        local plan = plans[startIndex + i - 1]
        if plan then
            local item = plan.item
            row:Show()
            row.plan = plan
            row.icon:SetTexture(item.icon)
            row.check:SetEnabled(plan.movable)
            row.check:SetChecked(plan.movable and UI.organizeSelected[plan.key] and true or false)
            row.check:SetScript("OnClick", function(self)
                UI.organizeSelected[plan.key] = self:GetChecked() and true or nil
                Core.RefreshUI()
            end)
            row.nameText:SetText(item.name or ("Item " .. item.itemID))
            row.detailText:SetText(string.format("%s -> %s  |  %s  |  %s",
                plan.currentStorage,
                plan.targetStorage,
                plan.movable and "movable" or (plan.blockedReason or "already optimized"),
                plan.reason))
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(item.link or ("item:" .. item.itemID))
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Current: " .. plan.currentStorage, 1, 1, 1)
                GameTooltip:AddLine("Recommended: " .. plan.targetStorage, 1, 1, 1)
                GameTooltip:AddLine("Reason: " .. plan.reason, 1, 1, 1)
                GameTooltip:AddLine("Binding: " .. (item.bindingScope or "Unknown"), 1, 1, 1)
                if plan.blockedReason then
                    GameTooltip:AddLine("Blocked: " .. plan.blockedReason, 1, 0.35, 0.35)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            row.plan = nil
            row:Hide()
        end
    end
end

function Core.RefreshVendor()
    local panel = UI.frame.panels.Vendor
    local filters = EnsureTabFilters("Vendor")
    local vendorNotice
    if not ns.DB.context.vendorOpen then
        vendorNotice = ns.DB.context.bankOpen and "Vendor closed: sell actions are unavailable; bank recall prep is available." or "Vendor closed: sell actions are unavailable."
    end
    SetContextNotice(panel.contextNotice, vendorNotice)
    local showRejected = ns.DB.ui.vendorShowAll or FilterIncludesValue(filters.type.include, TYPE_FILTER_VENDOR_SELLABLE)
    local plans = {}
    for _, plan in ipairs(GetVendorPlans(true)) do
        if (showRejected or plan.isCandidate) and (not filters.hideBlocked or plan.movable) and PlanMatchesTabFilters(plan, "Vendor") then
            table.insert(plans, plan)
        end
    end
    UI.vendorVisible = plans
    panel.showAll:SetChecked(ns.DB.ui.vendorShowAll)
    panel.actionableOnly:SetChecked(filters.hideBlocked)
    panel.filterSummary:SetText(BuildFilterSummary("Vendor"))
    SetDropdownText(panel.expansionFilter, "Expansion: " .. GetExpansionFilterLabel(filters.expansion.include))
    SetDropdownText(panel.typeFilter, "Type: " .. tostring(filters.type.include or "All"))
    SetDropdownText(panel.bindFilter, "Bind: " .. tostring(filters.bind.include or BIND_FILTER_ALL))
    local searchText = filters.name.includeText or ""
    if panel.search:GetText() ~= searchText then
        panel.search:SetText(searchText)
    end
    panel.context:SetText("Context: " .. GetContextText())
    SetEmptyLabel(panel.empty, #plans == 0, searchText ~= "" and "No vendor plans match your search." or "No vendor plans to show.")

    local maxPage = math.max(1, math.ceil(#plans / VENDOR_PAGE_SIZE))
    UI.page = math.min(UI.page, maxPage)
    local startIndex = (UI.page - 1) * VENDOR_PAGE_SIZE + 1
    local selectedCount = 0
    local selectedValue = 0
    for _, plan in ipairs(plans) do
        if UI.vendorSelected[plan.key] then
            selectedCount = selectedCount + 1
            if plan.action == VENDOR_ACTION_SELL then
                selectedValue = selectedValue + plan.value
            end
        end
    end

    local actionLabel = "Process Selected"
    if ns.DB.context.vendorOpen then
        actionLabel = "Sell Selected"
    elseif ns.DB.context.bankOpen then
        actionLabel = "Recall Selected"
    end
    panel.move:SetText(actionLabel)
    panel.move:SetEnabled(not ns.DB.context.inCombat and selectedCount > 0)
    panel.pageText:SetText("Page " .. UI.page .. "/" .. maxPage .. " (" .. #plans .. " plans, " .. selectedCount .. " selected, " .. FormatMoney(selectedValue) .. ")")

    for i, row in ipairs(panel.rows) do
        local plan = plans[startIndex + i - 1]
        if plan then
            local item = plan.item
            row:Show()
            row.plan = plan
            row.icon:SetTexture(item.icon)
            row.check:SetEnabled(plan.movable)
            row.check:SetChecked(plan.movable and UI.vendorSelected[plan.key] and true or false)
            row.check:SetScript("OnClick", function(self)
                UI.vendorSelected[plan.key] = self:GetChecked() and true or nil
                Core.RefreshUI()
            end)
            row.nameText:SetText(item.name or ("Item " .. item.itemID))
            row.detailText:SetText(string.format("%s  |  %s  |  %s  |  %s",
                plan.action,
                item.location or "Unknown location",
                FormatMoney(plan.value),
                plan.movable and plan.reason or (plan.blockedReason or plan.reason)))
            row.neverSell:SetScript("OnClick", function()
                AddRule(item, "Never Sell")
            end)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(item.link or ("item:" .. item.itemID))
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Vendor action: " .. plan.action, 1, 1, 1)
                GameTooltip:AddLine("Reason: " .. (plan.reason or "Review"), 1, 1, 1)
                GameTooltip:AddLine("Value: " .. FormatMoney(plan.value), 1, 1, 1)
                if plan.blockedReason then
                    GameTooltip:AddLine("Blocked: " .. plan.blockedReason, 1, 0.35, 0.35)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            row.plan = nil
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
    SetEmptyLabel(panel.empty, #rows == 0, "No item rules yet. Add rules from Move or Vendor rows when you need exceptions.")
    panel.headers:SetShown(#rows > 0)
    panel.countText:SetText(#rows .. " item rules")

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

function Core.RefreshSettings()
    local panel = UI.frame.panels.Settings
    panel.minimap:SetChecked(ns.DB.ui.showMinimapIcon ~= false)

    local minimapButton = GetStandardMinimapButton() or UI.minimapButton
    local minimapMode = UI.minimapIconRegistered and "LibDBIcon" or "fallback"
    panel.status:SetText("Minimap launcher (" .. minimapMode .. "): " .. tostring(minimapButton and minimapButton:IsShown())
    .. " | Bank launcher: disabled"
    .. " | Vendor launcher: disabled")
end

function Core.RefreshUI()
    if not UI.frame then
        return
    end
    Core.UpdateContext()
    for name, panel in pairs(UI.frame.panels) do
        panel:SetShown(name == UI.activeTab)
        ApplyTabVisualState(UI.tabs[name], name, name == UI.activeTab)
    end
    local refreshFn
    if UI.activeTab == "Summary" then
        refreshFn = Core.RefreshSummary
    elseif UI.activeTab == "Move" then
        refreshFn = Core.RefreshMove
    elseif UI.activeTab == "Organize" then
        refreshFn = Core.RefreshOrganizer
    elseif UI.activeTab == "Vendor" then
        refreshFn = Core.RefreshVendor
    elseif UI.activeTab == "Rules" then
        refreshFn = Core.RefreshRules
    elseif UI.activeTab == "Settings" then
        refreshFn = Core.RefreshSettings
    end
    if refreshFn then
        local ok, err = pcall(refreshFn)
        if not ok then
            Print("|cffff4444RefreshUI error (" .. tostring(UI.activeTab) .. "): " .. tostring(err) .. "|r")
        end
    end
end

