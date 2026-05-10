-- I Can't Even Right Now (With My Bags and Bank) — UI
-- All UI construction, refresh logic, and quick access buttons.

local ADDON_NAME, ns = ...

local Core = ns.Core
local Data = ns.Data
local P    = ns.Private

local BAG_SCOPE  = P.BAG_SCOPE
local BANK_SCOPE = P.BANK_SCOPE

local STORAGE_PRIVATE_BANK   = P.STORAGE_PRIVATE_BANK
local STORAGE_REAGENT_BANK   = P.STORAGE_REAGENT_BANK
local STORAGE_WARBAND_BANK   = P.STORAGE_WARBAND_BANK
local STORAGE_ALL_BANK_TABS  = P.STORAGE_ALL_BANK_TABS
local BANK_TAB_PREFIX        = P.BANK_TAB_PREFIX
local TAB_ORDER              = P.TAB_ORDER
local EXPANSION_FILTER_ALL   = P.EXPANSION_FILTER_ALL
local EXPANSION_FILTER_NOT_CURRENT = P.EXPANSION_FILTER_NOT_CURRENT
local EXPANSION_FILTER_UNKNOWN     = P.EXPANSION_FILTER_UNKNOWN
local BIND_FILTER_ALL        = P.BIND_FILTER_ALL
local BANK_FRAME_NAMES       = P.BANK_FRAME_NAMES
local BANK_FRAME_PATTERNS    = P.BANK_FRAME_PATTERNS

local UI = P.UI

local DISPLAY_NAME  = "I Can't Even Right Now"
local ICON_TEXTURE  = "Interface\\AddOns\\ICantEvenRightNow\\ICantEvenRightNow_icon.tga"
local MINIMAP_LDB_NAME = "ICantEvenRightNow"

local GetStorageDisplayName     = P.GetStorageDisplayName
local GetTransferSourceOptions  = P.GetTransferSourceOptions
local GetTransferDestOptions    = P.GetTransferDestOptions
local IsBankContextDetected     = P.IsBankContextDetected
local GetShownGlobalFrame       = P.GetShownGlobalFrame
local GetShownNamedFrameByPattern = P.GetShownNamedFrameByPattern
local IsPlayerBankInteractionActive = P.IsPlayerBankInteractionActive
local IsBankViewableByAPI       = P.IsBankViewableByAPI
local IsBankStorageAccessible   = P.IsBankStorageAccessible
local FormatTimestamp           = P.FormatTimestamp
local Print                     = P.Print
local SlotKey                   = P.SlotKey

local EnsureTabFilters          = P.EnsureTabFilters
local IsAllFilterValue          = P.IsAllFilterValue
local GetMultiSelectLabel       = P.GetMultiSelectLabel
local GetExpansionFilterLabel   = P.GetExpansionFilterLabel
local BuildFilterSummary        = P.BuildFilterSummary
local IsVendorSellable          = P.IsVendorSellable
local PlanMatchesTabFilters     = P.PlanMatchesTabFilters
local MatchesTabFilters         = P.MatchesTabFilters
local SetFilterInclude          = P.SetFilterInclude
local SetFilterSearch           = P.SetFilterSearch
local SetFilterHideBlocked      = P.SetFilterHideBlocked
local SetFilterItemLevel        = P.SetFilterItemLevel
local SetFilterSlot             = P.SetFilterSlot
local SetFilterArmorType        = P.SetFilterArmorType
local SetFilterUpgrade          = P.SetFilterUpgrade
local ResetTabFilters           = P.ResetTabFilters
local GetTypeFilterOptions      = P.GetTypeFilterOptions
local GetBindFilterOptions      = P.GetBindFilterOptions
local GetExpansionOptions       = P.GetExpansionOptions
local GetSlotFilterOptions      = P.GetSlotFilterOptions
local GetArmorTypeFilterOptions = P.GetArmorTypeFilterOptions
local GetUpgradeFilterOptions   = P.GetUpgradeFilterOptions
local GetSavedFiltersOptions    = P.GetSavedFiltersOptions
local FindSavedFilter           = P.FindSavedFilter
local ApplySavedFilter          = P.ApplySavedFilter
local SaveFilter                = P.SaveFilter
local DeleteSavedFilter         = P.DeleteSavedFilter

local GetTransferCandidates     = P.GetTransferCandidates
local GetTransferBlockReason    = P.GetTransferBlockReason
local GetAllDecisions           = P.GetAllDecisions
local EnsureRule                = P.EnsureRule
local IsOldExpansion            = P.IsOldExpansion
local GetCharacterProfessionSubclasses = P.GetCharacterProfessionSubclasses

local NORMAL_BAG_IDS   = P.NORMAL_BAG_IDS
local PRIVATE_BANK_IDS = P.PRIVATE_BANK_IDS
local REAGENT_BANK_IDS = P.REAGENT_BANK_IDS
local WARBAND_BANK_IDS = P.WARBAND_BANK_IDS

local RefreshBankTabData = P.RefreshBankTabData

local CContainer = C_Container

-- ===========================================================================
-- Widget factories
-- ===========================================================================

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

    -- Replace all options in an existing dropdown, rebuilding its menu items in place.
    function dropdown:SetOptions(newOptions)
        for _, existing in ipairs(self.items) do
            existing:Hide()
            existing:SetParent(nil)
        end
        self.items = {}
        self.options = newOptions
        menu:SetSize(width or 140, #newOptions * 22 + 8)
        for index, option in ipairs(newOptions) do
            local item = CreateButton(menu, option.text, (width or 140) - 8, 20)
            item:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (index - 1) * 22)
            item:SetScript("OnClick", function()
                onSelect(option.value)
                menu:Hide()
                Core.RefreshUI()
            end)
            self.items[index] = item
        end
    end

    return dropdown
end

local function UpdateMultiDropdownItems(dropdown)
    local selected = dropdown.selected or {}
    local isEmpty = true
    for _ in pairs(selected) do isEmpty = false; break end
    for _, item in ipairs(dropdown.items) do
        local opt = item.option
        local isAll = IsAllFilterValue(opt.value)
        local isSelected = not isAll and selected[opt.value]
        if isSelected or (isAll and isEmpty) then
            item:SetNormalFontObject("GameFontNormalSmall")
        else
            item:SetNormalFontObject("GameFontDisableSmall")
        end
    end
end

local function SetMultiDropdownValue(dropdown, value)
    if IsAllFilterValue(value) or type(value) ~= "table" then
        dropdown.selected = {}
    else
        dropdown.selected = {}
        for k, v in pairs(value) do
            dropdown.selected[k] = v
        end
    end
    UpdateMultiDropdownItems(dropdown)
end

local function CreateMultiSelectDropdown(parent, width, options, onSelect)
    local dropdown = CreateButton(parent, "", width or 140, 24)
    dropdown.options = options
    dropdown.selected = {}
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
        item.option = option
        item:SetScript("OnClick", function()
            if IsAllFilterValue(option.value) then
                dropdown.selected = {}
                onSelect("All")
            else
                if dropdown.selected[option.value] then
                    dropdown.selected[option.value] = nil
                else
                    dropdown.selected[option.value] = true
                end
                local count = 0
                for _ in pairs(dropdown.selected) do count = count + 1 end
                if count == 0 then
                    onSelect("All")
                else
                    onSelect(dropdown.selected)
                end
            end
            UpdateMultiDropdownItems(dropdown)
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

-- ===========================================================================
-- Panel helpers
-- ===========================================================================

local function CreatePanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetFrameLevel(parent:GetFrameLevel() + 5)
    panel:SetPoint("TOPLEFT", 14, -72)
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

local AddRule  -- forward declaration; defined below

local function ShowTooltip(owner, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    for index, line in ipairs(lines) do
        if index == 1 then
            GameTooltip:AddLine(line, 1, 1, 1)
        else
            GameTooltip:AddLine(line, 0.75, 0.85, 1)
        end
    end
    GameTooltip:Show()
end

local function CreateEmptyLabel(parent, text)
    local label = CreateLabel(parent, text, "GameFontDisableLarge")
    label:SetPoint("CENTER", parent, "CENTER", 0, 0)
    label:SetJustifyH("CENTER")
    label:Hide()
    return label
end

local function SetEmptyLabel(label, isEmpty, text)
    if not label then return end
    if text then label:SetText(text) end
    label:SetShown(isEmpty and true or false)
end

local function CreateContextNotice(parent)
    local label = CreateLabel(parent, "", "GameFontDisableSmall")
    label:SetPoint("TOPRIGHT", 0, 0)
    label:SetWidth(250)
    label:SetJustifyH("RIGHT")
    label:Hide()
    return label
end

local function SetContextNotice(label, text)
    if not label then return end
    label:SetText(text or "")
    label:SetShown(text and text ~= "")
end

-- ===========================================================================
-- Tab visual state
-- ===========================================================================

local function GetTabAvailability(tabName)
    if tabName == "Move" then
        if ns.DB.context.bankOpen then return true, nil end
        return false, "Open the bank to move selected rows."
    elseif tabName == "Organize" then
        if ns.DB.context.bankOpen then return true, nil end
        return false, "Open the bank to organize storage."
    elseif tabName == "Vendor" then
        if ns.DB.context.vendorOpen then return true, nil end
        return false, "Open a vendor to sell selected rows."
    end
    return true, nil
end

local function ApplyTabVisualState(tab, tabName, isActive)
    local isAvailable, reason = GetTabAvailability(tabName)
    tab:SetText(tabName)
    tab:SetEnabled(true)
    tab:SetAlpha(isActive and 1 or (isAvailable and 0.82 or 0.55))
    if isActive and tab.LockHighlight then
        tab:LockHighlight()
    elseif tab.UnlockHighlight then
        tab:UnlockHighlight()
    end
    local fontString = tab:GetFontString()
    if fontString and fontString.SetTextColor then
        if isActive then
            fontString:SetTextColor(1, 0.86, 0.1)
        elseif not isAvailable then
            fontString:SetTextColor(0.95, 0.55, 0.25)
        else
            fontString:SetTextColor(0.9, 0.82, 0.55)
        end
    end
    tab.availabilityReason = reason
end

-- ===========================================================================
-- Row rule menu
-- Only Protect / Ignore / Never Sell — dead entries (Always Bank, Always Recall,
-- Never Move) have been removed.
-- ===========================================================================

local function CreateRowRuleMenu(parent, width, options)
    local menu = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(parent:GetFrameLevel() + 30)
    menu:SetSize(width or 100, #options * 22 + 8)
    menu:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    menu:Hide()

    menu.buttons = {}
    for index, option in ipairs(options) do
        local button = CreateButton(menu, option.text, (width or 100) - 8, 20)
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (index - 1) * 22)
        button:SetScript("OnClick", function()
            if menu.item then
                AddRule(menu.item, option.ruleType)
            end
            menu:Hide()
        end)
        menu.buttons[index] = button
    end

    return menu
end

local function ToggleRowRuleMenu(row, item)
    if not row.ruleMenu then return end
    row.ruleMenu.item = item
    row.ruleMenu:ClearAllPoints()
    row.ruleMenu:SetPoint("TOPRIGHT", row.rule, "BOTTOMRIGHT", 0, -2)
    row.ruleMenu:SetShown(not row.ruleMenu:IsShown())
end

-- ===========================================================================
-- Console toggle
-- ===========================================================================

local function ToggleConsole(tabName)
    if UI.frame and UI.frame:IsShown() and (not tabName or UI.activeTab == tabName) then
        UI.frame:Hide()
        return
    end
    if tabName == "Organize" then
        Core.ShowOrganizeUI()
    elseif tabName == "Vendor" then
        Core.ShowVendorUI()
    elseif tabName == "Move" then
        Core.ShowMoveUI()
    else
        Core.ShowSummaryUI()
    end
end

-- ===========================================================================
-- Icon button
-- ===========================================================================

local function CreateIconButton(name, parent, size, tooltipLines, onClick)
    local button = CreateFrame("Button", name, parent)
    button:SetSize(size or 28, size or 28)
    button:RegisterForClicks("LeftButtonUp")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 3, -3)
    button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    button.icon:SetTexture(ICON_TEXTURE)

    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetPoint("TOPLEFT")
    button.border:SetPoint("BOTTOMRIGHT")
    button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self) ShowTooltip(self, tooltipLines) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

-- ===========================================================================
-- Minimap / quick access buttons
-- ===========================================================================

local function GetLibDBIcon()
    return LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true) or nil
end

local function GetLibDataBroker()
    return LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true) or nil
end

local function EnsureMinimapIconDB()
    ns.DB.ui.minimapIcon = ns.DB.ui.minimapIcon or {
        hide = ns.DB.ui.showMinimapIcon == false,
        minimapPos = 220,
        lock = false,
    }
    ns.DB.ui.minimapIcon.hide = ns.DB.ui.showMinimapIcon == false
    return ns.DB.ui.minimapIcon
end

local function CreateStandardMinimapButton()
    local LDB = GetLibDataBroker()
    local LDBIcon = GetLibDBIcon()
    if not LDB or not LDBIcon then
        return false
    end

    if not UI.minimapDataObject then
        UI.minimapDataObject = LDB:NewDataObject(MINIMAP_LDB_NAME, {
            type = "launcher",
            text = DISPLAY_NAME,
            icon = ICON_TEXTURE,
            OnClick = function(_, button)
                if button == "RightButton" then
                    Core.CreateUI()
                    UI.activeTab = "Settings"
                    UI.frame:Show()
                    Core.RefreshUI()
                else
                    ToggleConsole("Summary")
                end
            end,
            OnTooltipShow = function(tooltip)
                if not tooltip or not tooltip.AddLine then return end
                tooltip:AddLine(DISPLAY_NAME, 1, 1, 1)
                tooltip:AddLine(" ")
                tooltip:AddLine("Left-click to open the cleanup console.", 0.75, 0.85, 1)
                tooltip:AddLine("Right-click for settings.", 0.75, 0.85, 1)
            end,
        })
    end

    local minimapIconDB = EnsureMinimapIconDB()
    if not UI.minimapIconRegistered then
        LDBIcon:Register(MINIMAP_LDB_NAME, UI.minimapDataObject, minimapIconDB)
        UI.minimapIconRegistered = true
    end

    if ns.DB.ui.showMinimapIcon == false then
        LDBIcon:Hide(MINIMAP_LDB_NAME)
    else
        LDBIcon:Show(MINIMAP_LDB_NAME)
    end
    if UI.minimapButton then
        UI.minimapButton:Hide()
    end
    return true
end

local function GetStandardMinimapButton()
    local LDBIcon = GetLibDBIcon()
    if LDBIcon and UI.minimapIconRegistered and LDBIcon.GetMinimapButton then
        return LDBIcon:GetMinimapButton(MINIMAP_LDB_NAME)
    end
    return nil
end

local function CreateMinimapButton()
    if CreateStandardMinimapButton() then
        return
    end
    if UI.minimapButton or not Minimap then
        return
    end

    local button = CreateIconButton("ICantEvenRightNowMinimapButton", Minimap, 32, {
        DISPLAY_NAME,
        "Click to open or close the cleanup console.",
        "Use /icanteven minimap to hide this button.",
    }, function()
        ToggleConsole("Summary")
    end)
    button:SetFrameStrata("FULLSCREEN_DIALOG")
    button:SetFrameLevel(80)
    UI.minimapButton = button
end

local function PositionMinimapButton()
    if not UI.minimapButton then return end
    UI.minimapButton:ClearAllPoints()
    UI.minimapButton:SetPoint("CENTER", Minimap, "CENTER", 56, -56)
end

local function PositionFrameButton(button, parent)
    button:SetParent(UIParent)
    button:SetFrameStrata("FULLSCREEN_DIALOG")
    button:SetFrameLevel(math.max((parent:GetFrameLevel() or 1) + 80, 90))
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -34, -30)
end

-- Bank/vendor frame launchers are intentionally disabled; kept for future use.
local function CreateBankButton(parent)
    if UI.bankButton then
        PositionFrameButton(UI.bankButton, parent)
        return
    end
    UI.bankButton = CreateIconButton("ICantEvenRightNowBankButton", UIParent, 28, {
        DISPLAY_NAME, "Open the bank organizer.", "Use /icanteven bankbutton to hide this button.",
    }, function() Core.ShowOrganizeUI() end)
    PositionFrameButton(UI.bankButton, parent)
end

local function CreateVendorButton(parent)
    if UI.vendorButton then
        PositionFrameButton(UI.vendorButton, parent)
        return
    end
    UI.vendorButton = CreateIconButton("ICantEvenRightNowVendorButton", UIParent, 28, {
        DISPLAY_NAME, "Open vendor review.", "Use /icanteven vendorbutton to hide this button.",
    }, function() Core.ShowVendorUI() end)
    PositionFrameButton(UI.vendorButton, parent)
end

function Core.UpdateQuickAccessButtons()
    if not ns.DB or not ns.DB.ui then return end

    CreateMinimapButton()
    if UI.minimapIconRegistered then
        EnsureMinimapIconDB()
    elseif UI.minimapButton then
        PositionMinimapButton()
        UI.minimapButton:SetShown(ns.DB.ui.showMinimapIcon ~= false)
    end

    -- Bank/vendor launchers are intentionally disabled.
    if UI.bankButton then UI.bankButton:Hide() end
    if UI.vendorButton then UI.vendorButton:Hide() end
end

function Core.PrintQuickAccessStatus()
    Core.UpdateContext()
    Core.UpdateQuickAccessButtons()
    local minimapButton = GetStandardMinimapButton() or UI.minimapButton
    local minimapMode = UI.minimapIconRegistered and "LibDBIcon" or "fallback"
    Print("Quick access: minimap " .. tostring(ns.DB.ui.showMinimapIcon ~= false)
        .. " / " .. minimapMode .. " button " .. tostring(minimapButton and minimapButton:IsShown())
        .. "; bank launcher disabled; vendor launcher disabled")
end

local ScheduleQuickAccessRefresh  -- forward declared; defined below

-- ===========================================================================
-- Summary helpers
-- ===========================================================================

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
        totalBags = 0,
        totalBank = 0,
        totalWarband = 0,
        oldInBags = 0,
        oldInBank = 0,
        unclassified = 0,
        itemRules = 0,
    }
    for _, item in ipairs(GetAllDecisions() or {}) do
        if item.scope == BAG_SCOPE then
            counts.totalBags = counts.totalBags + 1
        elseif item.storageKind == STORAGE_WARBAND_BANK then
            counts.totalWarband = counts.totalWarband + 1
        else
            counts.totalBank = counts.totalBank + 1
        end
        if IsOldExpansion(item.expansionID) then
            if item.scope == BAG_SCOPE then
                counts.oldInBags = counts.oldInBags + 1
            elseif item.scope == BANK_SCOPE then
                counts.oldInBank = counts.oldInBank + 1
            end
        end
        if item.reason == "Unclassified" then
            counts.unclassified = counts.unclassified + 1
        end
    end
    local rules = ns.DB and ns.DB.rules and ns.DB.rules.items or {}
    for _, rule in pairs(rules) do
        if rule.protect or rule.ignore or rule.neverSell then
            counts.itemRules = counts.itemRules + 1
        end
    end
    return counts
end

-- ===========================================================================
-- SetTab / AddRule
-- ===========================================================================

local function SetTab(tabName)
    UI.activeTab = tabName
    Core.UpdateContext()
    Core.RefreshUI()
end

AddRule = function(item, ruleType)
    local rule = EnsureRule(item.itemID)
    rule.createdFrom = item.name or "Transfer tab"
    if ruleType == "Protect" then
        rule.protect = true
    elseif ruleType == "Ignore" then
        rule.ignore = true
    elseif ruleType == "Never Sell" then
        rule.neverSell = true
    end
    Core.RefreshUI()
end

-- ===========================================================================
-- Tab builders
-- ===========================================================================

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

    parent.openTransfer = CreateButton(parent, "Open Transfer Tab")
    parent.openTransfer:SetPoint("LEFT", parent.scanBank, "RIGHT", 8, 0)
    parent.openTransfer:SetScript("OnClick", function() SetTab("Transfer") end)

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

local function BuildRulesTab(parent)
    parent.help = CreateLabel(parent, "Per-item rules override Transfer pipeline behavior. Rules take priority and are always removable.", "GameFontHighlight")
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

local function BuildTransferTab(parent)
    parent.contextNotice = CreateContextNotice(parent)

    parent.fromLabel = CreateLabel(parent, "From:", "GameFontHighlightSmall")
    parent.fromLabel:SetPoint("TOPLEFT", 0, 0)

    parent.sourceDropdown = CreateDropdown(parent, 155, GetTransferSourceOptions(), function(value)
        UI.transferSource = value
        UI.transferSelected = {}
        if UI.transferDest == value then
            for _, opt in ipairs(GetTransferDestOptions()) do
                if opt.value ~= value then
                    UI.transferDest = opt.value
                    break
                end
            end
        end
        Core.RefreshUI()
    end)
    parent.sourceDropdown:SetPoint("LEFT", parent.fromLabel, "RIGHT", 6, 0)

    parent.toLabel = CreateLabel(parent, "To:", "GameFontHighlightSmall")
    parent.toLabel:SetPoint("LEFT", parent.sourceDropdown, "RIGHT", 16, 0)

    parent.destDropdown = CreateDropdown(parent, 155, GetTransferDestOptions(), function(value)
        if value == UI.transferSource then return end
        UI.transferDest = value
        UI.transferSelected = {}
        Core.RefreshUI()
    end)
    parent.destDropdown:SetPoint("LEFT", parent.toLabel, "RIGHT", 6, 0)

    parent.scanBags = CreateButton(parent, "Scan Bags", 90)
    parent.scanBags:SetPoint("LEFT", parent.destDropdown, "RIGHT", 16, 0)
    parent.scanBags:SetScript("OnClick", function() Core.ScanInventory(BAG_SCOPE) end)

    parent.scanBank = CreateButton(parent, "Scan Bank", 90)
    parent.scanBank:SetPoint("LEFT", parent.scanBags, "RIGHT", 8, 0)
    parent.scanBank:SetScript("OnClick", function() Core.ScanInventory(BANK_SCOPE) end)

    -- Presets row: load / save / remove named filter combinations
    parent.presetsLabel = CreateLabel(parent, "Preset:", "GameFontHighlightSmall")
    parent.presetsLabel:SetPoint("TOPLEFT", parent.fromLabel, "BOTTOMLEFT", 0, -16)

    parent.presetsDropdown = CreateDropdown(parent, 190, GetSavedFiltersOptions(), function(name)
        local preset = FindSavedFilter(name)
        if not preset then return end
        ApplySavedFilter(preset, "Transfer")
        if parent.presetNameInput:GetText() ~= name then
            parent.presetNameInput:SetText(name)
        end
        Core.RefreshUI()
    end)
    parent.presetsDropdown:SetPoint("LEFT", parent.presetsLabel, "RIGHT", 6, 0)

    parent.presetNameInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    parent.presetNameInput:SetSize(148, 24)
    parent.presetNameInput:SetAutoFocus(false)
    parent.presetNameInput:SetMaxLetters(48)
    parent.presetNameInput:SetPoint("LEFT", parent.presetsDropdown, "RIGHT", 10, 0)

    parent.savePreset = CreateButton(parent, "Save", 58)
    parent.savePreset:SetPoint("LEFT", parent.presetNameInput, "RIGHT", 6, 0)
    parent.savePreset:SetScript("OnClick", function()
        local name = parent.presetNameInput:GetText()
        if name and name ~= "" then
            SaveFilter(name, "Transfer")
            Core.RefreshUI()
        end
    end)

    parent.deletePreset = CreateButton(parent, "Remove", 68)
    parent.deletePreset:SetPoint("LEFT", parent.savePreset, "RIGHT", 6, 0)
    parent.deletePreset:SetScript("OnClick", function()
        local name = parent.presetNameInput:GetText()
        if name and name ~= "" then
            DeleteSavedFilter(name)
            parent.presetNameInput:SetText("")
            Core.RefreshUI()
        end
    end)

    -- Filter row 1: expansion / type / binding / slot dropdowns
    parent.expansionFilter = CreateDropdown(parent, 155, GetExpansionOptions(), function(value)
        SetFilterInclude("Transfer", "expansion", value)
    end)
    parent.expansionFilter:SetPoint("TOPLEFT", parent.presetsLabel, "BOTTOMLEFT", 0, -12)

    parent.typeFilter = CreateMultiSelectDropdown(parent, 120, GetTypeFilterOptions(), function(value)
        SetFilterInclude("Transfer", "type", value)
    end)
    parent.typeFilter:SetPoint("LEFT", parent.expansionFilter, "RIGHT", 6, 0)

    parent.bindFilter = CreateDropdown(parent, 110, GetBindFilterOptions(), function(value)
        SetFilterInclude("Transfer", "bind", value)
    end)
    parent.bindFilter:SetPoint("LEFT", parent.typeFilter, "RIGHT", 6, 0)

    parent.slotFilter = CreateMultiSelectDropdown(parent, 110, GetSlotFilterOptions(), function(value)
        SetFilterSlot("Transfer", value)
    end)
    parent.slotFilter:SetPoint("LEFT", parent.bindFilter, "RIGHT", 6, 0)

    parent.upgradeFilter = CreateDropdown(parent, 100, GetUpgradeFilterOptions(), function(value)
        SetFilterUpgrade("Transfer", value)
    end)
    parent.upgradeFilter:SetPoint("LEFT", parent.slotFilter, "RIGHT", 6, 0)

    parent.armorTypeFilter = CreateDropdown(parent, 88, GetArmorTypeFilterOptions(), function(value)
        SetFilterArmorType("Transfer", value)
    end)
    parent.armorTypeFilter:SetPoint("LEFT", parent.upgradeFilter, "RIGHT", 6, 0)

    -- Filter row 2: search / ilvl range / actionable toggle / clear
    parent.searchLabel = CreateLabel(parent, "Search", "GameFontHighlightSmall")
    parent.searchLabel:SetPoint("TOPLEFT", parent.expansionFilter, "BOTTOMLEFT", 6, -16)

    parent.search = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    parent.search:SetSize(180, 24)
    parent.search:SetAutoFocus(false)
    parent.search:SetPoint("LEFT", parent.searchLabel, "RIGHT", 6, 0)
    parent.search:SetScript("OnTextChanged", function(self)
        SetFilterSearch("Transfer", self:GetText())
        Core.RefreshUI()
    end)

    parent.ilvlLabel = CreateLabel(parent, "iLvl:", "GameFontHighlightSmall")
    parent.ilvlLabel:SetPoint("LEFT", parent.search, "RIGHT", 12, 0)

    parent.ilvlMin = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    parent.ilvlMin:SetSize(52, 24)
    parent.ilvlMin:SetAutoFocus(false)
    parent.ilvlMin:SetMaxLetters(5)
    parent.ilvlMin:SetNumeric(true)
    parent.ilvlMin:SetPoint("LEFT", parent.ilvlLabel, "RIGHT", 6, 0)
    parent.ilvlMin:SetScript("OnTextChanged", function(self)
        SetFilterItemLevel("Transfer", self:GetText(), parent.ilvlMax:GetText())
        Core.RefreshUI()
    end)

    parent.ilvlSep = CreateLabel(parent, "–", "GameFontHighlightSmall")
    parent.ilvlSep:SetPoint("LEFT", parent.ilvlMin, "RIGHT", 4, 0)

    parent.ilvlMax = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    parent.ilvlMax:SetSize(52, 24)
    parent.ilvlMax:SetAutoFocus(false)
    parent.ilvlMax:SetMaxLetters(5)
    parent.ilvlMax:SetNumeric(true)
    parent.ilvlMax:SetPoint("LEFT", parent.ilvlSep, "RIGHT", 4, 0)
    parent.ilvlMax:SetScript("OnTextChanged", function(self)
        SetFilterItemLevel("Transfer", parent.ilvlMin:GetText(), self:GetText())
        Core.RefreshUI()
    end)

    parent.actionableOnly = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    parent.actionableOnly:SetPoint("LEFT", parent.ilvlMax, "RIGHT", 16, 0)
    parent.actionableOnlyLabel = CreateLabel(parent, "Actionable only", "GameFontHighlightSmall")
    parent.actionableOnlyLabel:SetPoint("LEFT", parent.actionableOnly, "RIGHT", -2, 0)
    parent.actionableOnly:SetScript("OnClick", function(self)
        SetFilterHideBlocked("Transfer", self:GetChecked())
        Core.RefreshUI()
    end)

    parent.clearFilters = CreateButton(parent, "Clear Filters", 100)
    parent.clearFilters:SetPoint("LEFT", parent.actionableOnlyLabel, "RIGHT", 10, 0)
    parent.clearFilters:SetScript("OnClick", function()
        ResetTabFilters("Transfer")
        Core.RefreshUI()
    end)

    parent.listFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    parent.listFrame:SetWidth(706)
    parent.listFrame:SetPoint("TOPLEFT", parent.searchLabel, "BOTTOMLEFT", -6, -10)
    parent.listFrame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 54)
    parent.listFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    parent.listFrame:SetBackdropColor(0, 0, 0, 0.2)
    parent.empty = CreateEmptyLabel(parent.listFrame, "No transfer candidates.")

    -- Scrollable list using FauxScrollFrame
    parent.ROW_HEIGHT = 42
    parent.VISIBLE_ROWS = 8
    local ROW_HEIGHT = parent.ROW_HEIGHT
    local VISIBLE_ROWS = parent.VISIBLE_ROWS
    parent.scrollFrame = CreateFrame("ScrollFrame", nil, parent.listFrame, "FauxScrollFrameTemplate")
    parent.scrollFrame:SetPoint("TOPLEFT",     parent.listFrame, "TOPLEFT",     5,   -5)
    parent.scrollFrame:SetPoint("BOTTOMRIGHT", parent.listFrame, "BOTTOMRIGHT", -29,  5)
    parent.scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() Core.RefreshUI() end)
    end)

    parent.rows = {}
    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Button", nil, parent.listFrame, "BackdropTemplate")
        row:SetSize(680, 40)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row:SetBackdropColor(0, 0, 0, i % 2 == 0 and 0.18 or 0.08)
        row:SetPoint("TOPLEFT", parent.listFrame, "TOPLEFT", 5, -5 - (i - 1) * ROW_HEIGHT)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetPoint("LEFT", 0, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", row.check, "RIGHT", -2, 0)
        row.nameText = CreateLabel(row, "", "GameFontHighlightSmall")
        row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -4)
        row.nameText:SetWidth(440)
        row.nameText:SetWordWrap(false)
        row.detailText = CreateLabel(row, "", "GameFontDisableSmall")
        row.detailText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -2)
        row.detailText:SetWidth(440)
        row.detailText:SetWordWrap(false)
        row.action = CreateButton(row, "Move", 60, 22)
        row.action:SetPoint("RIGHT", row, "RIGHT", -86, 0)
        row.rule = CreateButton(row, "+Rule", 70, 22)
        row.rule:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        -- Only live rule types: Protect / Ignore / Never Sell
        row.ruleMenu = CreateRowRuleMenu(row, 104, {
            { text = "Protect",    ruleType = "Protect" },
            { text = "Ignore",     ruleType = "Ignore" },
            { text = "Never Sell", ruleType = "Never Sell" },
        })
        parent.rows[i] = row
        row:Hide()
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

    parent.selectAll = CreateButton(parent, "Select Movable", 120)
    parent.selectAll:SetParent(parent.footer)
    parent.selectAll:SetPoint("TOPLEFT", parent.footer, "TOPLEFT", 8, -7)
    parent.selectAll:SetScript("OnClick", function()
        for _, plan in ipairs(UI.transferVisible or {}) do
            if plan.movable then
                UI.transferSelected[plan.key] = true
            end
        end
        Core.RefreshUI()
    end)

    parent.selectPage = CreateButton(parent, "Select Visible", 110)
    parent.selectPage:SetParent(parent.footer)
    parent.selectPage:SetPoint("LEFT", parent.selectAll, "RIGHT", 8, 0)
    parent.selectPage:SetScript("OnClick", function()
        local vis = UI.transferVisible or {}
        local offset = FauxScrollFrame_GetOffset(parent.scrollFrame)
        for i = offset + 1, math.min(offset + VISIBLE_ROWS, #vis) do
            local plan = vis[i]
            if plan and plan.movable then
                UI.transferSelected[plan.key] = true
            end
        end
        Core.RefreshUI()
    end)

    parent.clearSel = CreateButton(parent, "Clear Selection", 120)
    parent.clearSel:SetParent(parent.footer)
    parent.clearSel:SetPoint("LEFT", parent.selectPage, "RIGHT", 8, 0)
    parent.clearSel:SetScript("OnClick", function()
        UI.transferSelected = {}
        Core.RefreshUI()
    end)

    parent.selectAllItems = CreateButton(parent, "Select All", 90)
    parent.selectAllItems:SetParent(parent.footer)
    parent.selectAllItems:SetPoint("LEFT", parent.clearSel, "RIGHT", 8, 0)
    parent.selectAllItems:SetScript("OnClick", function()
        for _, plan in ipairs(UI.transferVisible or {}) do
            UI.transferSelected[plan.key] = true
        end
        Core.RefreshUI()
    end)

    parent.execute = CreateButton(parent, "Transfer Selected", 130)
    parent.execute:SetParent(parent.footer)
    parent.execute:SetPoint("LEFT", parent.selectAllItems, "RIGHT", 8, 0)
    parent.execute:SetScript("OnClick", function() Core.ExecuteTransferSelected() end)

    parent.itemCount = CreateLabel(parent, "", "GameFontHighlightSmall")
    parent.itemCount:SetParent(parent.footer)
    parent.itemCount:SetPoint("LEFT", parent.execute, "RIGHT", 12, 0)
    parent.itemCount:SetWidth(260)
end

-- ===========================================================================
-- Refresh functions
-- ===========================================================================

function Core.RefreshTransferDropdowns()
    if not UI.frame then return end
    local panel = UI.frame.panels and UI.frame.panels.Transfer
    if not panel then return end
    local sourceOpts = GetTransferSourceOptions()
    local destOpts = GetTransferDestOptions()
    if panel.sourceDropdown and panel.sourceDropdown.SetOptions then
        panel.sourceDropdown:SetOptions(sourceOpts)
    end
    if panel.destDropdown and panel.destDropdown.SetOptions then
        panel.destDropdown:SetOptions(destOpts)
    end
    -- Validate current source/dest are still available; reset if stale
    local function isValidValue(opts, value)
        for _, opt in ipairs(opts) do
            if opt.value == value then return true end
        end
        return false
    end
    local defaultSource = "Bags"
    local defaultDest = sourceOpts[2] and sourceOpts[2].value or defaultSource
    if not isValidValue(sourceOpts, UI.transferSource) then
        UI.transferSource = defaultSource
        UI.transferSelected = {}
    end
    if not isValidValue(destOpts, UI.transferDest) or UI.transferDest == UI.transferSource then
        -- Pick first dest that isn't the source
        for _, opt in ipairs(destOpts) do
            if opt.value ~= UI.transferSource then
                UI.transferDest = opt.value
                break
            end
        end
        UI.transferSelected = {}
    end
end

function Core.RefreshSummary()
    local panel = UI.frame.panels.Summary
    local counts = CountSummary()
    panel.context:SetText("Context: " .. GetContextText())
    panel.lastScan:SetText("Last scan: Bags " .. FormatTimestamp(ns.DB.lastScan.bags) .. " | Bank " .. FormatTimestamp(ns.DB.lastScan.bank))
    panel.scanBank:SetEnabled((UI.bankContextOpen or IsBankContextDetected()) and not ns.DB.context.inCombat)

    local cards = {
        { "Items in bags",        counts.totalBags },
        { "Items in bank",        counts.totalBank },
        { "Old-content in bags",  counts.oldInBags },
        { "Old-content in bank",  counts.oldInBank },
        { "Warband bank items",   counts.totalWarband },
        { "Item rules",           counts.itemRules },
        { "Unclassified items",   counts.unclassified },
        { "Last scan: bags",      FormatTimestamp(ns.DB.lastScan and ns.DB.lastScan.bags) },
    }
    for index, cardData in ipairs(cards) do
        panel.cards[index].title:SetText(cardData[1])
        panel.cards[index].value:SetText(tostring(cardData[2]))
    end
end

function Core.RefreshTransfer()
    local panel = UI.frame.panels.Transfer
    local source = UI.transferSource or "Bags"
    local dest = UI.transferDest or STORAGE_PRIVATE_BANK
    local filters = EnsureTabFilters("Transfer")

    local function NeedsBankStorage(s)
        return s ~= "Bags" and s ~= "Vendor"
            and (s == STORAGE_PRIVATE_BANK or s == STORAGE_REAGENT_BANK
                 or s == STORAGE_WARBAND_BANK or s == STORAGE_ALL_BANK_TABS
                 or (s and s:sub(1, #BANK_TAB_PREFIX) == BANK_TAB_PREFIX))
    end
    local needsBank = NeedsBankStorage(source) or NeedsBankStorage(dest)
    local noticeText
    if dest == "Vendor" and not ns.DB.context.vendorOpen then
        noticeText = "Vendor is not open: sell actions are unavailable."
    elseif needsBank and not IsBankContextDetected() then
        noticeText = "Bank is not open: transfer actions are unavailable."
    end
    SetContextNotice(panel.contextNotice, noticeText)

    SetDropdownText(panel.sourceDropdown, "From: " .. GetStorageDisplayName(source))
    SetDropdownText(panel.destDropdown,   "To: "   .. GetStorageDisplayName(dest))
    -- Update presets dropdown options (list may have changed since the tab was built)
    local presetOpts = GetSavedFiltersOptions()
    panel.presetsDropdown:SetOptions(presetOpts)
    SetDropdownText(panel.presetsDropdown, #presetOpts > 0 and "Load preset..." or "(no presets saved)")
    local currentPresetName = panel.presetNameInput:GetText()
    local presetExists = currentPresetName ~= "" and FindSavedFilter(currentPresetName) ~= nil
    panel.deletePreset:SetEnabled(presetExists)
    SetDropdownText(panel.expansionFilter, "Expansion: " .. GetExpansionFilterLabel(filters.expansion.include))
    SetMultiDropdownValue(panel.typeFilter, filters.type.include)
    SetDropdownText(panel.typeFilter, "Type: " .. GetMultiSelectLabel(filters.type.include, "All"))
    SetDropdownText(panel.bindFilter, "Binding: " .. tostring(filters.bind.include or BIND_FILTER_ALL))
    SetMultiDropdownValue(panel.slotFilter, filters.slot and filters.slot.include or "All")
    SetDropdownText(panel.slotFilter, "Slot: " .. GetMultiSelectLabel(filters.slot and filters.slot.include or "All", "All"))
    local upgradeVal = filters.upgrade and filters.upgrade.include or "All"
    SetDropdownText(panel.upgradeFilter, upgradeVal == "All" and "Upgrade: All" or upgradeVal)
    local armorTypeVal = filters.armorType and filters.armorType.include or "All"
    local armorTypeLabelMap = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }
    local armorTypeLabel = (armorTypeVal == "All" or armorTypeVal == nil)
        and "Armor: All"
        or ("Armor: " .. (armorTypeLabelMap[armorTypeVal] or tostring(armorTypeVal)))
    SetDropdownText(panel.armorTypeFilter, armorTypeLabel)
    panel.actionableOnly:SetChecked(filters.hideBlocked)
    -- filterSummary removed; filter state is visible in the dropdown button labels
    local searchText = filters.name.includeText or ""
    if panel.search:GetText() ~= searchText then
        panel.search:SetText(searchText)
    end
    local ilvlMinVal = filters.itemLevel and filters.itemLevel.min
    local ilvlMaxVal = filters.itemLevel and filters.itemLevel.max
    local ilvlMinStr = ilvlMinVal and tostring(ilvlMinVal) or ""
    local ilvlMaxStr = ilvlMaxVal and tostring(ilvlMaxVal) or ""
    if panel.ilvlMin:GetText() ~= ilvlMinStr then panel.ilvlMin:SetText(ilvlMinStr) end
    if panel.ilvlMax:GetText() ~= ilvlMaxStr then panel.ilvlMax:SetText(ilvlMaxStr) end
    panel.scanBank:SetEnabled((UI.bankContextOpen or IsBankContextDetected()) and not ns.DB.context.inCombat)

    local allCandidates = GetTransferCandidates(source, dest)
    local visible = {}
    for _, plan in ipairs(allCandidates) do
        if (not filters.hideBlocked or plan.movable) and PlanMatchesTabFilters(plan, "Transfer") then
            table.insert(visible, plan)
        end
    end
    UI.transferVisible = visible

    local emptyMsg = #allCandidates == 0
        and ("No scanned items in " .. source .. ". Use Scan Bags or Scan Bank first.")
        or "No items match the current filters."
    SetEmptyLabel(panel.empty, #visible == 0, emptyMsg)

    local selectedCount = 0
    for _, plan in ipairs(visible) do
        if UI.transferSelected[plan.key] then
            selectedCount = selectedCount + 1
        end
    end

    local actionLabel = dest == "Vendor" and "Sell Selected" or "Transfer Selected"
    panel.execute:SetText(actionLabel)
    panel.execute:SetEnabled(not ns.DB.context.inCombat and selectedCount > 0)

    local offset = FauxScrollFrame_GetOffset(panel.scrollFrame)
    FauxScrollFrame_Update(panel.scrollFrame, #visible, panel.VISIBLE_ROWS, panel.ROW_HEIGHT)
    local startIndex = offset + 1

    panel.itemCount:SetText(#visible .. " item" .. (#visible == 1 and "" or "s") .. ", " .. selectedCount .. " selected")

    for i, row in ipairs(panel.rows) do
        local plan = visible[startIndex + i - 1]
        if plan then
            local item = plan.item
            row:Show()
            row.plan = plan
            row.icon:SetTexture(item.icon)
            row.check:SetEnabled(plan.movable)
            row.check:SetChecked(plan.movable and UI.transferSelected[plan.key] and true or false)
            row.check:SetScript("OnClick", function(self)
                UI.transferSelected[plan.key] = self:GetChecked() and true or nil
                Core.RefreshUI()
            end)
            row.nameText:SetText(item.name or ("Item " .. item.itemID))
            local statusText = plan.movable
                and (source .. " -> " .. dest)
                or ("Blocked: " .. (plan.blocked or "?"))
            row.detailText:SetText(string.format("x%d  |  %s  |  %s  |  %s  |  %s",
                item.count or 1,
                item.expansionName or "Unknown",
                item.typeTag or "Unknown",
                item.location or "",
                statusText))
            local actionText = dest == "Vendor" and "Sell" or "Move"
            row.action:SetText(actionText)
            row.action:SetEnabled(plan.movable)
            row.action:SetScript("OnClick", function()
                Core.ExecuteTransferOne(plan)
            end)
            row.rule:SetScript("OnClick", function() ToggleRowRuleMenu(row, item) end)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(item.link or ("item:" .. item.itemID))
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("From: " .. source, 1, 1, 1)
                GameTooltip:AddLine("To: " .. dest, 1, 1, 1)
                GameTooltip:AddLine("Expansion: " .. (item.expansionName or "Unknown"), 1, 1, 1)
                if plan.blocked then
                    GameTooltip:AddLine("Blocked: " .. plan.blocked, 1, 0.35, 0.35)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            row.plan = nil
            if row.ruleMenu then row.ruleMenu:Hide() end
            row:Hide()
        end
    end
end

function Core.RefreshRules()
    if not UI.frame then return end
    local panel = UI.frame.panels and UI.frame.panels.Rules
    if not panel then return end

    local ruleItems = ns.DB and ns.DB.rules and ns.DB.rules.items or {}
    local nameLookup = {}
    for _, item in ipairs(GetAllDecisions() or {}) do
        if item.itemID and item.name then nameLookup[item.itemID] = item.name end
    end
    local entries = {}
    for itemID, rule in pairs(ruleItems) do
        local flags = {}
        if rule.protect   then table.insert(flags, "Protect") end
        if rule.ignore    then table.insert(flags, "Ignore") end
        if rule.neverSell then table.insert(flags, "Never Sell") end
        if #flags > 0 then
            table.insert(entries, {
                itemID = itemID,
                ruleType = table.concat(flags, ", "),
                createdFrom = rule.createdFrom or "",
                name = nameLookup[itemID] or rule.name or ("Item #" .. tostring(itemID)),
            })
        end
    end
    table.sort(entries, function(a, b) return (a.name or "") < (b.name or "") end)

    local rows = panel.rows or {}
    for i, row in ipairs(rows) do
        local e = entries[i]
        if e then
            row.text:SetText(string.format("%-40s %-40s %s", e.name, e.ruleType, e.createdFrom))
            row.remove:SetScript("OnClick", function()
                ns.DB.rules.items[e.itemID] = nil
                Core.RefreshRules()
            end)
            row:Show()
        else
            row.text:SetText("")
            row.remove:SetScript("OnClick", nil)
            row:Hide()
        end
    end

    local count = #entries
    SetEmptyLabel(panel.empty, count == 0, "No item rules yet.")
    if panel.countText then
        panel.countText:SetText(count .. " rule" .. (count == 1 and "" or "s") .. " total")
    end
end

function Core.RefreshUI()
    if not UI.frame then return end
    local tab = UI.activeTab
    for _, tabName in ipairs(TAB_ORDER) do
        local panel = UI.frame.panels[tabName]
        if panel then
            panel:SetShown(tabName == tab)
        end
        local tabBtn = UI.tabs and UI.tabs[tabName]
        if tabBtn then
            tabBtn:SetEnabled(tabName ~= tab)
        end
    end
    if tab == "Summary" then
        Core.RefreshSummary()
    elseif tab == "Transfer" then
        Core.RefreshTransfer()
    elseif tab == "Rules" then
        Core.RefreshRules()
    end
end

-- ===========================================================================
-- Core.CreateUI
-- ===========================================================================

function Core.CreateUI()
    if UI.frame then return end

    local frame = CreateFrame("Frame", "ICantEvenRightNowFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(780, 584)
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
        elseif name == "Transfer" then
            BuildTransferTab(panel)
        elseif name == "Rules" then
            BuildRulesTab(panel)
        else
            BuildSettingsTab(panel)
        end
    end

    UI.frame = frame
end

-- ===========================================================================
-- Show helpers
-- ===========================================================================

local function ShowAndRefresh(tab)
    Core.CreateUI()
    UI.activeTab = tab
    UI.frame:Show()
    Core.RefreshUI()
end

function Core.ShowSummaryUI()  ShowAndRefresh("Summary")  end
function Core.ShowTransferUI() ShowAndRefresh("Transfer") end
function Core.ShowMoveUI()     ShowAndRefresh("Transfer") end
function Core.ShowOrganizeUI() ShowAndRefresh("Transfer") end
function Core.ShowVendorUI()   ShowAndRefresh("Transfer") end

-- ===========================================================================
-- SetExpansionFilterFromText
-- ===========================================================================

function Core.SetExpansionFilterFromText(text)
    text = (text or ""):lower()
    local function SetMoveExpansionFilter(value)
        SetFilterInclude("Transfer", "expansion", value)
    end
    if text == "" or text == "all" or text == "old" then
        SetMoveExpansionFilter(EXPANSION_FILTER_ALL)
        return
    elseif text == "unknown" or text == "unknown expansion" then
        SetMoveExpansionFilter(EXPANSION_FILTER_UNKNOWN)
        return
    elseif text == "not current" or text == "notcurrent" then
        SetMoveExpansionFilter(EXPANSION_FILTER_NOT_CURRENT)
        return
    end
    for expansionID, expansion in pairs(Data.Expansions) do
        if expansion.name:lower():find(text, 1, true) then
            SetMoveExpansionFilter(expansionID)
            return
        end
    end
    Print("Unknown expansion filter: " .. text)
end

-- ===========================================================================
-- ScheduleQuickAccessRefresh (defined here since it uses Core.RefreshUI)
-- ===========================================================================

ScheduleQuickAccessRefresh = function()
    local function RefreshQuickAccess()
        if ns.DB and ns.DB.context then
            Core.UpdateContext()
            Core.UpdateQuickAccessButtons()
            if UI.frame and UI.frame:IsShown() then
                Core.RefreshUI()
            end
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, RefreshQuickAccess)
        C_Timer.After(0.25, RefreshQuickAccess)
        C_Timer.After(1.0, RefreshQuickAccess)
        C_Timer.After(2.5, RefreshQuickAccess)
    else
        RefreshQuickAccess()
    end
end

-- Expose so Core.lua can call it from OnAddonLoaded and the event handler.
P.ScheduleQuickAccessRefresh = ScheduleQuickAccessRefresh
