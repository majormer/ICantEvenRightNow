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
local CONSOLE_WIDTH = 860
local CONSOLE_HEIGHT = 560

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
local FormatMoney               = P.FormatMoney
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
local GetArmorTypeFilterLabel   = P.GetArmorTypeFilterLabel
local GetUpgradeFilterOptions   = P.GetUpgradeFilterOptions
local GetSavedFiltersOptions    = P.GetSavedFiltersOptions
local GetQuickWorkflowOptions   = P.GetQuickWorkflowOptions
local FindQuickWorkflow         = P.FindQuickWorkflow
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

local TRANSFER_SORT_OPTIONS = {
    { text = "Name", value = "Name" },
    { text = "Status", value = "Status" },
    { text = "Item Level", value = "Item Level" },
    { text = "Vendor Value", value = "Vendor Value" },
    { text = "Expansion", value = "Expansion" },
    { text = "Binding", value = "Binding" },
}

-- ===========================================================================
-- Widget factories
-- ===========================================================================

local BUTTON_STYLES = {
    secondary = {
        normal = { 0.08, 0.09, 0.11, 0.96 }, hover = { 0.15, 0.16, 0.19, 0.98 },
        pressed = { 0.04, 0.05, 0.07, 1 }, border = { 0.32, 0.34, 0.38, 0.95 },
        hoverBorder = { 0.68, 0.55, 0.22, 1 }, text = { 0.88, 0.83, 0.70, 1 },
    },
    primary = {
        normal = { 0.30, 0.20, 0.04, 0.98 }, hover = { 0.44, 0.30, 0.06, 1 },
        pressed = { 0.20, 0.12, 0.02, 1 }, border = { 0.82, 0.62, 0.16, 1 },
        hoverBorder = { 1.0, 0.82, 0.28, 1 }, text = { 1.0, 0.91, 0.48, 1 },
    },
    danger = {
        normal = { 0.20, 0.05, 0.05, 0.96 }, hover = { 0.34, 0.07, 0.07, 1 },
        pressed = { 0.12, 0.02, 0.02, 1 }, border = { 0.55, 0.16, 0.14, 1 },
        hoverBorder = { 0.90, 0.28, 0.22, 1 }, text = { 0.95, 0.72, 0.64, 1 },
    },
    chip = {
        normal = { 0.10, 0.11, 0.13, 0.96 }, hover = { 0.17, 0.18, 0.21, 1 },
        pressed = { 0.05, 0.06, 0.08, 1 }, border = { 0.48, 0.39, 0.16, 0.95 },
        hoverBorder = { 0.80, 0.62, 0.20, 1 }, text = { 0.96, 0.82, 0.40, 1 },
    },
}

local function ApplyButtonVisual(button, state)
    local style = BUTTON_STYLES[button.buttonStyle or "secondary"] or BUTTON_STYLES.secondary
    local colors = style.normal
    local border = style.border
    local textColor = style.text
    if not button:IsEnabled() then
        colors = { 0.04, 0.04, 0.05, 0.60 }
        border = { 0.18, 0.18, 0.19, 0.65 }
        textColor = { 0.42, 0.42, 0.43, 1 }
    elseif state == "hover" then
        colors = style.hover
        border = style.hoverBorder
    elseif state == "pressed" then
        colors = style.pressed
    end
    button:SetBackdropColor(colors[1], colors[2], colors[3], colors[4])
    button:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    local fontString = button:GetFontString()
    if fontString then
        fontString:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4])
    end
end

local function SetButtonStyle(button, styleName)
    button.buttonStyle = BUTTON_STYLES[styleName] and styleName or "secondary"
    ApplyButtonVisual(button)
end

local function CreateButton(parent, text, width, height, styleName)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 110, height or 24)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    label:SetJustifyH("CENTER")
    button:SetFontString(label)
    button:SetText(text or "")
    button:RegisterForClicks("LeftButtonUp")
    button:HookScript("OnEnter", function(self) ApplyButtonVisual(self, "hover") end)
    button:HookScript("OnLeave", function(self) ApplyButtonVisual(self) end)
    button:HookScript("OnMouseDown", function(self) ApplyButtonVisual(self, "pressed") end)
    button:HookScript("OnMouseUp", function(self)
        ApplyButtonVisual(self, self:IsMouseOver() and "hover" or nil)
    end)
    button:HookScript("OnEnable", function(self) ApplyButtonVisual(self) end)
    button:HookScript("OnDisable", function(self) ApplyButtonVisual(self) end)
    SetButtonStyle(button, styleName or "secondary")
    return button
end

local TAB_ACTIVE_BG = { 0.08, 0.07, 0.06, 0.95 }
local TAB_INACTIVE_BG = { 0.16, 0.02, 0.02, 0.9 }
local TAB_HOVER_BG = { 0.24, 0.04, 0.04, 0.95 }
local TAB_ACTIVE_TEXT = { 1.0, 0.88, 0.25 }
local TAB_INACTIVE_TEXT = { 0.75, 0.64, 0.34 }
local TAB_ACTIVE_BORDER = { 0.95, 0.75, 0.25, 0.95 }
local TAB_INACTIVE_BORDER = { 0.35, 0.25, 0.18, 0.9 }

local function ApplyTabBackdrop(tab, bg, border)
    tab:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    tab:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
end

local function SetTabVisual(tab, active, hovered)
    if not tab then return end
    tab.active = active and true or false
    if active then
        ApplyTabBackdrop(tab, TAB_ACTIVE_BG, TAB_ACTIVE_BORDER)
        tab.text:SetTextColor(TAB_ACTIVE_TEXT[1], TAB_ACTIVE_TEXT[2], TAB_ACTIVE_TEXT[3], 1)
        tab:SetHeight(30)
    else
        ApplyTabBackdrop(tab, hovered and TAB_HOVER_BG or TAB_INACTIVE_BG, TAB_INACTIVE_BORDER)
        tab.text:SetTextColor(TAB_INACTIVE_TEXT[1], TAB_INACTIVE_TEXT[2], TAB_INACTIVE_TEXT[3], 1)
        tab:SetHeight(26)
    end
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

local function CreateTabButton(parent, text, width, onClick)
    local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tab:SetSize(width or 100, 26)
    tab:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 0 },
    })
    tab:RegisterForClicks("LeftButtonUp")
    tab.text = CreateLabel(tab, text, "GameFontNormalSmall")
    tab.text:SetPoint("CENTER", tab, "CENTER", 0, 1)
    tab.text:SetJustifyH("CENTER")
    tab:SetScript("OnClick", function()
        if not tab.active then
            onClick()
        end
    end)
    tab:SetScript("OnEnter", function(self) SetTabVisual(self, self.active, true) end)
    tab:SetScript("OnLeave", function(self) SetTabVisual(self, self.active, false) end)
    SetTabVisual(tab, false, false)
    return tab
end

local function CloseOpenDropdown(exceptDropdown)
    if UI.openDropdown and UI.openDropdown ~= exceptDropdown and UI.openDropdown.menu then
        UI.openDropdown.menu:Hide()
    end
    if not exceptDropdown then
        UI.openDropdown = nil
    end
end

local function ToggleDropdownMenu(dropdown)
    local menu = dropdown.menu
    local shouldShow = not menu:IsShown()
    CloseOpenDropdown(dropdown)
    if shouldShow then
        UI.openDropdown = dropdown
        menu:Show()
    else
        menu:Hide()
        if UI.openDropdown == dropdown then
            UI.openDropdown = nil
        end
    end
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
            if UI.openDropdown == dropdown then UI.openDropdown = nil end
            Core.RefreshUI()
        end)
        dropdown.items[index] = item
    end

    dropdown:SetScript("OnClick", function()
        ToggleDropdownMenu(dropdown)
    end)
    dropdown:SetScript("OnHide", function()
        menu:Hide()
        if UI.openDropdown == dropdown then UI.openDropdown = nil end
    end)

    local function OptionsEqual(left, right)
        if left == right then return true end
        if not left or not right or #left ~= #right then return false end
        for index, leftOption in ipairs(left) do
            local rightOption = right[index]
            if not rightOption or leftOption.text ~= rightOption.text or leftOption.value ~= rightOption.value then
                return false
            end
        end
        return true
    end

    -- Replace all options in an existing dropdown, rebuilding its menu items in place.
    function dropdown:SetOptions(newOptions)
        newOptions = newOptions or {}
        if OptionsEqual(self.options, newOptions) then return false end
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
                if UI.openDropdown == dropdown then UI.openDropdown = nil end
                Core.RefreshUI()
            end)
            self.items[index] = item
        end
        return true
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
        ToggleDropdownMenu(dropdown)
    end)
    dropdown:SetScript("OnHide", function()
        menu:Hide()
        if UI.openDropdown == dropdown then UI.openDropdown = nil end
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

local function AddIfPresent(parts, value)
    if value and value ~= "" then
        table.insert(parts, value)
    end
end

local function GetItemGearSummary(item)
    if not item or not item.equipLoc or item.equipLoc == "" then return nil end
    local parts = {}
    if item.itemLevel and item.itemLevel > 0 then
        table.insert(parts, "iLvl " .. tostring(item.itemLevel))
    end
    AddIfPresent(parts, item.itemSubTypeName)
    return #parts > 0 and table.concat(parts, " ") or nil
end

local function BuildTransferRowDetail(plan, source, dest)
    local item = plan.item
    local status
    if plan.blocked then
        status = "Blocked: " .. plan.blocked
    elseif dest == "Vendor" then
        local stackValue = (item.sellPrice or 0) * (item.count or 1)
        status = "Ready to sell" .. (stackValue > 0 and (" for " .. FormatMoney(stackValue)) or "")
        if P.IsValueFlagged and P.IsValueFlagged(item, "Vendor") then
            local net = P.GetItemValue(item)
            status = status .. "  -  worth ~" .. FormatMoney(net) .. " at auction"
        end
    elseif dest == "Bags" then
        status = "Ready to withdraw to Bags"
    elseif dest == P.STORAGE_WARBAND_ROUTED then
        local route = P.RouteToWarbandTab(item)
        status = "Ready to deposit to Warband: " .. (route and route.reason or "?")
        local entry = P.HandoffQueuedFromMe and P.HandoffQueuedFromMe(item.itemID)
        local recipient = entry and P.GetCharacter(entry.to)
        local benefits = recipient and ("For " .. recipient.name) or (P.WhoBenefits and P.WhoBenefits(item))
        if benefits then status = status .. "  -  " .. benefits end
    elseif source == "Bags" then
        status = "Ready to deposit to " .. GetStorageDisplayName(dest)
    else
        status = "Ready to move to " .. GetStorageDisplayName(dest)
    end
    local meta = {}
    if (item.count or 1) > 1 then
        table.insert(meta, "x" .. tostring(item.count))
    end
    if P.ExplainScanned then
        AddIfPresent(meta, P.ReasonShortText(P.ExplainScanned(item)))
    end
    AddIfPresent(meta, item.bindingScope)
    AddIfPresent(meta, GetItemGearSummary(item))
    AddIfPresent(meta, item.expansionName)
    return #meta > 0 and (status .. "  |  " .. table.concat(meta, "  |  ")) or status
end

local NeedsBankStorage = P.NeedsBankStorage

-- Editing a loaded task keeps its name and marks it "(modified)".
local function ClearActiveWorkflowState()
    if UI.activeQuickWorkflowName or UI.activeSavedFilterName then
        UI.activeTaskModified = true
    end
end

-- Forget the loaded task entirely (route no longer matches any task).
local function ForgetActiveTask()
    UI.activeQuickWorkflowName = nil
    UI.activeSavedFilterName = nil
    UI.activeTaskModified = false
end

local function ApplyTransferWorkflow(workflow, panel, savedName)
    if not workflow then return end
    ApplySavedFilter(workflow, "Transfer")
    UI.transferSelected = {}
    UI.activeTaskPredicate = nil
    UI.activeSavedFilterName = savedName
    UI.activeQuickWorkflowName = savedName and nil or workflow.name
    UI.activeTaskModified = false

    local routeNeedsBank = NeedsBankStorage(workflow.source) or NeedsBankStorage(workflow.dest)
    local routeNeedsVendor = workflow.dest == "Vendor"
    if routeNeedsBank and not IsBankContextDetected() then
        UI.transferContextMessage = "Open the bank to use “" .. workflow.name .. "”. Filters were applied; the transfer route was left unchanged."
    elseif routeNeedsVendor and not ns.DB.context.vendorOpen then
        UI.transferContextMessage = "Visit a vendor to use “" .. workflow.name .. "”. Filters were applied; the transfer route was left unchanged."
    else
        if workflow.source then UI.transferSource = workflow.source end
        if workflow.dest and workflow.dest ~= UI.transferSource then UI.transferDest = workflow.dest end
    end

    if panel and panel.presetNameInput and savedName then
        panel.presetNameInput:SetText(savedName)
    end
    Core.RefreshTransferDropdowns()
end

local QUICK_TASK_PREFIX = "quick:"
local SAVED_TASK_PREFIX = "saved:"

local function GetTransferTaskOptions()
    local options = {}
    for _, option in ipairs(GetQuickWorkflowOptions()) do
        table.insert(options, {
            text = option.text,
            value = QUICK_TASK_PREFIX .. option.value,
        })
    end
    for _, option in ipairs(GetSavedFiltersOptions()) do
        table.insert(options, {
            text = "Saved: " .. option.text,
            value = SAVED_TASK_PREFIX .. option.value,
        })
    end
    return options
end

local function ApplyTransferTask(value, panel)
    if value:sub(1, #QUICK_TASK_PREFIX) == QUICK_TASK_PREFIX then
        local name = value:sub(#QUICK_TASK_PREFIX + 1)
        ApplyTransferWorkflow(FindQuickWorkflow(name), panel, nil)
    elseif value:sub(1, #SAVED_TASK_PREFIX) == SAVED_TASK_PREFIX then
        local name = value:sub(#SAVED_TASK_PREFIX + 1)
        ApplyTransferWorkflow(FindSavedFilter(name), panel, name)
    end
end

-- Open a task from Home: apply its route and filters, optionally pre-select
-- its safe movable items (setting, off by default), and show the review list.
function P.OpenTask(name)
    local task = P.FindTask(name)
    if not task then return false end
    local available, needs = P.TaskRouteAvailable(task)
    P.Log("task", "open %s (route %s -> %s)%s", task.name, P.GetTaskRoute(task),
        select(2, P.GetTaskRoute(task)), available and "" or (": unavailable, " .. tostring(needs)))
    if not available then
        -- Showing the review list now would use the wrong route.
        Print(task.name .. ": " .. needs:lower() .. " to review these items.")
        return false
    end
    Core.CreateUI()
    local panel = UI.frame.panels.Transfer
    if task.open then
        -- Action-only tasks (price checks) run here and stay on Home.
        task.open()
        Core.RefreshUI()
        return true
    elseif task.kind == "saved" then
        ApplyTransferWorkflow(task.preset, panel, task.name)
    else
        ApplyTransferWorkflow(task.preset, panel, nil)
        UI.activeQuickWorkflowName = task.name
    end
    UI.activeTaskPredicate = task.predicate
    if P.IsPreselectEnabled() and not task.filterOnly then P.PreselectTask(task) end
    P.UIKit.SetTab("Transfer")
    return true
end

local function BuildActiveFilterChips(filters)
    local chips = {}
    local function Add(text, clear)
        table.insert(chips, { text = text .. "  ×", clear = clear })
    end
    if not IsAllFilterValue(filters.expansion.include) then
        Add(GetExpansionFilterLabel(filters.expansion.include), function()
            SetFilterInclude("Transfer", "expansion", EXPANSION_FILTER_ALL)
        end)
    end
    if not IsAllFilterValue(filters.type.include) then
        Add(GetMultiSelectLabel(filters.type.include, "All"), function()
            SetFilterInclude("Transfer", "type", "All")
        end)
    end
    if not IsAllFilterValue(filters.bind.include) then
        Add(tostring(filters.bind.include), function()
            SetFilterInclude("Transfer", "bind", BIND_FILTER_ALL)
        end)
    end
    if filters.slot and not IsAllFilterValue(filters.slot.include) then
        Add(GetMultiSelectLabel(filters.slot.include, "All"), function()
            SetFilterSlot("Transfer", "All")
        end)
    end
    if filters.armorType and not IsAllFilterValue(filters.armorType.include) then
        Add(GetArmorTypeFilterLabel(filters.armorType.include), function()
            SetFilterArmorType("Transfer", "All")
        end)
    end
    if filters.upgrade and not IsAllFilterValue(filters.upgrade.include) then
        local label = filters.upgrade.include == "Upgrade" and "Upgrades" or tostring(filters.upgrade.include)
        Add(label, function() SetFilterUpgrade("Transfer", "All") end)
    end
    if filters.itemLevel and (filters.itemLevel.min or filters.itemLevel.max) then
        local label
        if filters.itemLevel.min and filters.itemLevel.max then
            label = "iLvl " .. filters.itemLevel.min .. "–" .. filters.itemLevel.max
        elseif filters.itemLevel.min then
            label = "iLvl ≥" .. filters.itemLevel.min
        else
            label = "iLvl ≤" .. filters.itemLevel.max
        end
        Add(label, function() SetFilterItemLevel("Transfer", "", "") end)
    end
    if filters.hideBlocked then
        Add("Actionable", function() SetFilterHideBlocked("Transfer", false) end)
    end
    return chips
end

local function SortTransferPlans(plans, sortMode)
    local function itemName(plan)
        return (plan.item.name or ""):lower()
    end
    table.sort(plans, function(a, b)
        local ai, bi = a.item, b.item
        if sortMode == "Status" and a.movable ~= b.movable then
            return a.movable
        elseif sortMode == "Item Level" and (ai.itemLevel or 0) ~= (bi.itemLevel or 0) then
            return (ai.itemLevel or 0) > (bi.itemLevel or 0)
        elseif sortMode == "Vendor Value" then
            local av = (ai.sellPrice or 0) * (ai.count or 1)
            local bv = (bi.sellPrice or 0) * (bi.count or 1)
            if av ~= bv then return av > bv end
        elseif sortMode == "Expansion" and (ai.expansionID or -1) ~= (bi.expansionID or -1) then
            return (ai.expansionID or -1) > (bi.expansionID or -1)
        elseif sortMode == "Binding" and (ai.bindingScope or "") ~= (bi.bindingScope or "") then
            return (ai.bindingScope or "") < (bi.bindingScope or "")
        end
        return itemName(a) < itemName(b)
    end)
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
    elseif tabName == "Transfer" then
        Core.ShowTransferUI()
    else
        Core.ShowHomeUI()
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
                    ToggleConsole()
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
        ToggleConsole()
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
        local LDBIcon = GetLibDBIcon()
        EnsureMinimapIconDB()
        if LDBIcon then
            if ns.DB.ui.showMinimapIcon == false then
                LDBIcon:Hide(MINIMAP_LDB_NAME)
            else
                LDBIcon:Show(MINIMAP_LDB_NAME)
            end
        end
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

-- ===========================================================================
-- SetTab / AddRule
-- ===========================================================================

local function SetTab(tabName)
    UI.activeTab = tabName
    Core.UpdateContext()
    Core.RefreshUI()
end

AddRule = function(item, ruleType)
    if ruleType == "handoff" then
        if P.ShowHandoffPicker then P.ShowHandoffPicker(item) end
        return
    end
    local keepChoice = type(ruleType) == "string" and ruleType:match("^keep:(%a+)$")
    if keepChoice then
        P.SetKeepReason(item.itemID, keepChoice, item.name, keepChoice == "investment" and 90 or nil)
        Core.RefreshUI()
        return
    end
    local rule = EnsureRule(item.itemID)
    rule.name = item.name or rule.name
    rule.createdFrom = "Transfer tab"
    if ruleType == "Protect" then
        rule.protect = true
    elseif ruleType == "Ignore" then
        rule.ignore = true
    elseif ruleType == "Never Sell" then
        rule.neverSell = true
    end
    if Core.OnRulesChanged then Core.OnRulesChanged() end
    Core.RefreshUI()
end

-- Widget helpers shared with HomeUI.lua.
P.UIKit = {
    CreateButton = CreateButton,
    CreateLabel = CreateLabel,
    CreateDropdown = CreateDropdown,
    SetDropdownText = SetDropdownText,
    SetButtonStyle = SetButtonStyle,
    ShowTooltip = ShowTooltip,
    CreateEmptyLabel = CreateEmptyLabel,
    SetEmptyLabel = SetEmptyLabel,
    CloseOpenDropdown = CloseOpenDropdown,
    SetTab = function(name) SetTab(name) end,
}

-- ===========================================================================
-- Tab builders
-- ===========================================================================

local function BuildRulesTab(parent)
    local CONTENT_WIDTH = 806
    local ROW_HEIGHT = 30
    local VISIBLE_ROWS = 10
    local LIST_INSET = 5
    local HEADER_HEIGHT = 26
    local FOOTER_HEIGHT = 42
    local LIST_FOOTER_GAP = 10
    local SCROLLBAR_RIGHT_INSET = 29
    local ROW_WIDTH = CONTENT_WIDTH - 26
    local REMOVE_WIDTH = 70
    local REMOVE_RIGHT = 4
    local ITEM_X = 10
    local RULE_X = 210
    local SOURCE_X = 410
    local SOURCE_WIDTH = ROW_WIDTH - SOURCE_X - REMOVE_WIDTH - 20

    parent.help = CreateLabel(parent, "Per-item rules override Transfer pipeline behavior. Rules take priority and are always removable.", "GameFontHighlight")
    parent.help:SetPoint("TOPLEFT", 0, 0)

    parent.listFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    parent.listFrame:SetWidth(CONTENT_WIDTH)
    parent.listFrame:SetPoint("TOPLEFT", parent.help, "BOTTOMLEFT", 0, -14)
    parent.listFrame:SetHeight(HEADER_HEIGHT + (2 * ROW_HEIGHT) + 8)
    parent.listFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    parent.listFrame:SetBackdropColor(0, 0, 0, 0.2)

    parent.itemHeader = CreateLabel(parent.listFrame, "Item", "GameFontNormalSmall")
    parent.itemHeader:SetPoint("TOPLEFT", parent.listFrame, "TOPLEFT", ITEM_X, -8)
    parent.ruleHeader = CreateLabel(parent.listFrame, "Rule type", "GameFontNormalSmall")
    parent.ruleHeader:SetPoint("TOPLEFT", parent.listFrame, "TOPLEFT", RULE_X, -8)
    parent.sourceHeader = CreateLabel(parent.listFrame, "Created from", "GameFontNormalSmall")
    parent.sourceHeader:SetPoint("TOPLEFT", parent.listFrame, "TOPLEFT", SOURCE_X, -8)
    parent.empty = CreateEmptyLabel(parent.listFrame, "No item rules yet.")

    parent.ROW_HEIGHT = ROW_HEIGHT
    parent.VISIBLE_ROWS = VISIBLE_ROWS
    parent.HEADER_HEIGHT = HEADER_HEIGHT
    parent.scrollFrame = CreateFrame("ScrollFrame", nil, parent.listFrame, "FauxScrollFrameTemplate")
    parent.scrollFrame:SetPoint("TOPLEFT", parent.listFrame, "TOPLEFT", LIST_INSET, -HEADER_HEIGHT)
    parent.scrollFrame:SetPoint("BOTTOMRIGHT", parent.listFrame, "BOTTOMRIGHT", -SCROLLBAR_RIGHT_INSET, LIST_INSET)
    parent.scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() Core.RefreshRules() end)
    end)

    parent.rows = {}
    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Frame", nil, parent.listFrame, "BackdropTemplate")
        row:SetSize(ROW_WIDTH, 28)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row:SetBackdropColor(0, 0, 0, i % 2 == 0 and 0.18 or 0.08)
        row:SetPoint("TOPLEFT", parent.listFrame, "TOPLEFT", LIST_INSET, -HEADER_HEIGHT - (i - 1) * ROW_HEIGHT)
        row.itemText = CreateLabel(row, "", "GameFontHighlightSmall")
        row.itemText:SetPoint("LEFT", row, "LEFT", ITEM_X - LIST_INSET, 0)
        row.itemText:SetWidth(RULE_X - ITEM_X - 14)
        row.itemText:SetWordWrap(false)
        row.ruleText = CreateLabel(row, "", "GameFontHighlightSmall")
        row.ruleText:SetPoint("LEFT", row, "LEFT", RULE_X - LIST_INSET, 0)
        row.ruleText:SetWidth(SOURCE_X - RULE_X - 14)
        row.ruleText:SetWordWrap(false)
        row.sourceText = CreateLabel(row, "", "GameFontHighlightSmall")
        row.sourceText:SetPoint("LEFT", row, "LEFT", SOURCE_X - LIST_INSET, 0)
        row.sourceText:SetWidth(SOURCE_WIDTH)
        row.sourceText:SetWordWrap(false)
        row.remove = CreateButton(row, "Remove", 70, 22, "danger")
        row.remove:SetPoint("RIGHT", -REMOVE_RIGHT, 0)
        parent.rows[i] = row
    end

    parent.footer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    parent.footer:SetSize(CONTENT_WIDTH, FOOTER_HEIGHT)
    parent.footer:SetPoint("TOPLEFT", parent.listFrame, "BOTTOMLEFT", 0, -LIST_FOOTER_GAP)
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
    local CONTENT_WIDTH = 806
    local ROW_HEIGHT = 19
    local COLUMN_GAP = 34
    local COLUMN_WIDTH = math.floor((CONTENT_WIDTH - COLUMN_GAP) / 2)
    local COMMAND_WIDTH = 132
    local DESC_X = 145

    parent.help = CreateLabel(parent, "Display", "GameFontHighlightLarge")
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

    parent.note = CreateLabel(parent, "Bank and vendor launchers remain disabled.", "GameFontDisableSmall")
    parent.note:SetPoint("TOPLEFT", parent.minimap, "BOTTOMLEFT", 0, -10)

    -- Workflow settings (right column).
    parent.workflowHeading = CreateLabel(parent, "Workflow", "GameFontHighlightLarge")
    parent.workflowHeading:SetPoint("TOPLEFT", parent, "TOPLEFT", 420, 0)
    parent.workflowChecks = {}
    local function AddCheck(key, label, tooltip, anchor)
        local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, anchor == parent.workflowHeading and -18 or -4)
        check.settingKey = key
        check.label = CreateLabel(parent, label, "GameFontHighlightSmall")
        check.label:SetPoint("LEFT", check, "RIGHT", -2, 0)
        check:SetScript("OnClick", function(self)
            ns.DB.ui[key] = self:GetChecked() and true or false
            Core.RefreshUI()
        end)
        check:SetScript("OnEnter", function(self) ShowTooltip(self, tooltip) end)
        check:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(parent.workflowChecks, check)
        return check
    end
    local preselect = AddCheck("preselectQuickTasks", "Pre-select items when opening a task",
        { "Pre-select items", "Opening a task checks its movable items for you.",
          "You still review the list and click the action. Blocked items and",
          "items flagged as worth keeping are never pre-selected." }, parent.workflowHeading)
    local grouping = AddCheck("groupIdenticalRows", "Group identical items into one row",
        { "Group identical items", "Stacks of the same item share one row." }, preselect)
    local compact = AddCheck("compactRows", "Compact rows (more items per screen)",
        { "Compact rows", "Shows 9 single-line rows instead of 6 detailed ones." }, grouping)
    local whereTip = AddCheck("whereTooltip", "Show where items are in item tooltips",
        { "Where is it?", "Item tooltips list how many your characters and Warband bank hold." }, compact)
    local auctionCurrent = AddCheck("auctionIncludeCurrent", "Include current-expansion items in Auction Candidates",
        { "Auction current-expansion items", "For players who farm and sell current materials.",
          "Items a crafter or played character uses, protected items,",
          "and keepsakes are still left out." }, whereTip)
    local betterBags = AddCheck("betterBagsCategories", "Show categories in BetterBags",
        { "BetterBags categories", "Protected, Never Sell, Sell Candidates, For the Warband, Old Content,",
          "and Waiting for You appear as BetterBags categories. Display only." }, auctionCurrent)
    betterBags:SetScript("OnClick", function(self)
        if P.SetBetterBagsCategories then P.SetBetterBagsCategories(self:GetChecked()) end
        Core.RefreshUI()
    end)
    local tips = AddCheck("tipsEnabled", "Show first-time tips",
        { "Tips", "Short tips the first time you use each feature. Seen once per account." }, betterBags)
    parent.resetTips = CreateButton(parent, "Show tips again", 120, 20)
    parent.resetTips:SetPoint("LEFT", tips.label, "RIGHT", 10, 0)
    parent.resetTips:SetScript("OnClick", function()
        if P.ResetTips then P.ResetTips() end
        UI.transferTip = nil
        Print("Tips will show again.")
    end)
    local logging = AddCheck("enhancedLogging", "Enhanced logging (for troubleshooting)",
        { "Enhanced logging", "Records scans, context changes, tasks, moves, sales, and errors",
          "into your saved data (last " .. (P.LOG_MAX_LINES or 2000) .. " lines).",
          "View with /icanteven log; clear with /icanteven log clear." }, tips)
    logging:SetScript("OnClick", function(self)
        P.SetLogging(self:GetChecked())
        Core.RefreshUI()
    end)
    parent.noticeLabel = CreateLabel(parent, "At a bank, vendor, or AH:", "GameFontHighlightSmall")
    parent.noticeLabel:SetPoint("TOPLEFT", logging, "BOTTOMLEFT", 4, -12)
    parent.noticeMode = CreateDropdown(parent, 170, {
        { text = "Show a small notice", value = "notice" },
        { text = "Open the console", value = "open" },
        { text = "Do nothing", value = "off" },
    }, function(value) ns.DB.ui.contextNotice = value end)
    parent.noticeMode:SetPoint("LEFT", parent.noticeLabel, "RIGHT", 8, 0)

    parent.refresh = CreateButton(parent, "Check launcher", 116)
    parent.refresh:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -32)
    parent.refresh:SetScript("OnClick", function()
        Core.PrintQuickAccessStatus()
        Core.RefreshUI()
    end)

    parent.status = CreateLabel(parent, "", "GameFontDisableSmall")
    parent.status:SetPoint("TOPLEFT", parent.note, "BOTTOMLEFT", 0, -12)
    parent.status:SetWidth(680)

    parent.commandsToggle = CreateButton(parent, "Show command reference", 176)
    parent.commandsToggle:SetPoint("TOPLEFT", parent.status, "BOTTOMLEFT", 0, -22)
    parent.commandsToggle:SetScript("OnClick", function()
        UI.settingsCommandHelpOpen = not UI.settingsCommandHelpOpen
        Core.RefreshUI()
    end)

    parent.commandFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    parent.commandFrame:SetSize(CONTENT_WIDTH, 268)
    parent.commandFrame:SetPoint("TOPLEFT", parent.commandsToggle, "BOTTOMLEFT", 0, -10)
    parent.commandFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    parent.commandFrame:SetBackdropColor(0, 0, 0, 0.18)
    parent.commandFrame:Hide()

    local commandGroups = {
        {
            title = "Workflows",
            x = 12,
            commands = {
                { "/icanteven", "Open Home (task cards)." },
                { "/icanteven transfer", "Open Transfer." },
                { "/icanteven why [all]", "Why items are kept." },
                { "/icanteven scan bags", "Scan bag contents." },
                { "/icanteven scan bank", "Scan bank contents." },
                { "/icanteven scan all", "Scan bags and bank." },
                { "/icanteven dump <exp>", "Bags to bank preset." },
                { "/icanteven recall <exp>", "Bank to bags preset." },
                { "/icanteven vendor", "Bags to vendor preset." },
                { "/icanteven organize", "Bank to bags preset." },
            },
        },
        {
            title = "Views and Diagnostics",
            x = 12 + COLUMN_WIDTH + COLUMN_GAP,
            commands = {
                { "/icanteven characters", "Roles for your characters." },
                { "/icanteven rules", "Open Rules." },
                { "/icanteven migration", "Show the upgrade report." },
                { "/icanteven settings", "Open Settings." },
                { "/icanteven minimap", "Toggle minimap launcher." },
                { "/icanteven buttons", "Print launcher status." },
                { "/icanteven bankdiag", "Print bank IDs." },
                { "/icanteven ctx", "Print context state." },
                { "/icanteven errors", "Show logged errors." },
                { "/icanteven clearerrors", "Clear logged errors." },
            },
        },
    }

    parent.commandRows = {}
    for _, group in ipairs(commandGroups) do
        local title = CreateLabel(parent.commandFrame, group.title, "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", parent.commandFrame, "TOPLEFT", group.x, -10)
        for index, entry in ipairs(group.commands) do
            local y = -32 - (index - 1) * ROW_HEIGHT
            local command = CreateLabel(parent.commandFrame, entry[1], "GameFontHighlightSmall")
            command:SetPoint("TOPLEFT", parent.commandFrame, "TOPLEFT", group.x, y)
            command:SetWidth(COMMAND_WIDTH)
            command:SetWordWrap(false)
            local description = CreateLabel(parent.commandFrame, entry[2], "GameFontDisableSmall")
            description:SetPoint("TOPLEFT", parent.commandFrame, "TOPLEFT", group.x + DESC_X, y)
            description:SetWidth(COLUMN_WIDTH - DESC_X)
            description:SetWordWrap(false)
            table.insert(parent.commandRows, { command = command, description = description })
        end
    end
end

local function BuildTransferTab(parent)
    local CONTENT_WIDTH = 806
    local ROW_HEIGHT = 24
    local CONTROL_GAP = 6
    local FOOTER_HEIGHT = 54
    local LIST_FOOTER_GAP = 10
    local LIST_INSET = 5
    local SCROLLBAR_RIGHT_INSET = 29
    local ROW_WIDTH = CONTENT_WIDTH - 26
    local ROW_BODY_GAP = 12
    local ROW_RULE_WIDTH = 70
    local ROW_ACTION_WIDTH = 74
    local ROW_RULE_RIGHT = 4
    local ROW_ACTION_RIGHT = ROW_RULE_RIGHT + ROW_RULE_WIDTH + ROW_BODY_GAP
    local ROW_TEXT_WIDTH = ROW_WIDTH - 232
    local TASK_Y = 0
    local REFINE_Y = -38
    local DRAWER_ROW_1_Y = -76
    local DRAWER_ROW_2_Y = -110
    local LIST_TOP_COLLAPSED_Y = -78
    local LIST_TOP_EXPANDED_Y = -150

    parent.LIST_TOP_COLLAPSED_Y = LIST_TOP_COLLAPSED_Y
    parent.LIST_TOP_EXPANDED_Y = LIST_TOP_EXPANDED_Y

    parent.contextNotice = CreateContextNotice(parent)
    parent.contextNotice:SetWidth(390)

    -- The default view is task-first: one task picker, a readable route, and
    -- the two controls needed most often while reviewing results.
    parent.homeButton = CreateButton(parent, "< Home", 70)
    parent.homeButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, TASK_Y)
    parent.homeButton:SetScript("OnClick", function() SetTab("Home") end)

    parent.taskTitle = CreateLabel(parent, "", "GameFontHighlight")
    parent.taskTitle:SetPoint("LEFT", parent.homeButton, "RIGHT", 12, 0)
    parent.taskTitle:SetWidth(250)
    parent.taskTitle:SetWordWrap(false)

    parent.routeSummary = CreateLabel(parent, "", "GameFontDisableSmall")
    parent.routeSummary:SetPoint("LEFT", parent.taskTitle, "RIGHT", 10, 0)
    parent.routeSummary:SetWidth(260)
    parent.routeSummary:SetWordWrap(false)

    parent.customizeToggle = CreateButton(parent, "Customize", 92)
    parent.customizeToggle:SetPoint("TOPRIGHT", parent, "TOPLEFT", CONTENT_WIDTH - 104, TASK_Y)
    parent.customizeToggle:SetScript("OnClick", function()
        CloseOpenDropdown()
        UI.transferCustomizeOpen = not UI.transferCustomizeOpen
        if UI.transferCustomizeOpen then
            EnsureTabFilters("Transfer").advancedEnabled = false
        end
        Core.RefreshUI()
    end)

    parent.rescan = CreateButton(parent, "Rescan", 96)
    parent.rescan:SetPoint("TOPRIGHT", parent, "TOPLEFT", CONTENT_WIDTH, TASK_Y)
    parent.rescan:SetScript("OnClick", function()
        Core.ScanInventory(IsBankContextDetected() and "all" or BAG_SCOPE)
    end)

    parent.searchLabel = CreateLabel(parent, "Search", "GameFontHighlightSmall")
    parent.searchLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, REFINE_Y - 5)

    parent.search = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    parent.search:SetSize(300, ROW_HEIGHT)
    parent.search:SetAutoFocus(false)
    parent.search:SetPoint("TOPLEFT", parent, "TOPLEFT", 46, REFINE_Y)
    -- Only typing counts: in game, text set by code (opening a task) also
    -- fires OnTextChanged, sometimes after the refresh guard is cleared, and
    -- marked every opened task "(modified)".
    parent.search:SetScript("OnTextChanged", function(self, userInput)
        if UI.refreshingTransferControls or not userInput then return end
        SetFilterSearch("Transfer", self:GetText())
        ClearActiveWorkflowState()
        Core.RefreshUI()
    end)

    parent.filtersToggle = CreateButton(parent, "Filters", 100)
    parent.filtersToggle:SetPoint("LEFT", parent.search, "RIGHT", 12, 0)
    parent.filtersToggle:SetScript("OnClick", function()
        CloseOpenDropdown()
        local filters = EnsureTabFilters("Transfer")
        filters.advancedEnabled = not filters.advancedEnabled
        if filters.advancedEnabled then
            UI.transferCustomizeOpen = false
        end
        Core.RefreshUI()
    end)
    parent.filtersToggle:SetScript("OnEnter", function(self)
        ShowTooltip(self, { "Filter items", BuildFilterSummary("Transfer") })
    end)
    parent.filtersToggle:SetScript("OnLeave", function() GameTooltip:Hide() end)

    parent.filterChips = {}
    for index = 1, 3 do
        local chip = CreateButton(parent, "", 96, 22, "chip")
        chip:SetPoint("LEFT", index == 1 and parent.filtersToggle or parent.filterChips[index - 1], "RIGHT", CONTROL_GAP, 0)
        chip:SetScript("OnClick", function(self)
            if self.clearFilter then
                self.clearFilter()
                ClearActiveWorkflowState()
            elseif self.showAllFilters then
                UI.transferCustomizeOpen = false
                EnsureTabFilters("Transfer").advancedEnabled = true
            end
            Core.RefreshUI()
        end)
        chip:Hide()
        parent.filterChips[index] = chip
    end

    -- Customize drawer: route editing and saved-workflow management.
    parent.fromLabel = CreateLabel(parent, "From", "GameFontHighlightSmall")
    parent.fromLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, DRAWER_ROW_1_Y - 5)

    parent.sourceDropdown = CreateDropdown(parent, 200, GetTransferSourceOptions(), function(value)
        UI.transferSource = value
        UI.transferSelected = {}
        ClearActiveWorkflowState()
        if UI.transferDest == value then
            for _, opt in ipairs(GetTransferDestOptions()) do
                if opt.value ~= value then
                    UI.transferDest = opt.value
                    break
                end
            end
        end
    end)
    parent.sourceDropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", 38, DRAWER_ROW_1_Y)

    parent.flowArrow = CreateLabel(parent, "->", "GameFontDisableSmall")
    parent.flowArrow:SetPoint("LEFT", parent.sourceDropdown, "RIGHT", 10, 0)

    parent.toLabel = CreateLabel(parent, "To", "GameFontHighlightSmall")
    parent.toLabel:SetPoint("LEFT", parent.flowArrow, "RIGHT", 10, 0)

    parent.destDropdown = CreateDropdown(parent, 200, GetTransferDestOptions(), function(value)
        if value == UI.transferSource then return end
        UI.transferDest = value
        UI.transferSelected = {}
        ClearActiveWorkflowState()
    end)
    parent.destDropdown:SetPoint("LEFT", parent.toLabel, "RIGHT", 8, 0)

    parent.swapRoute = CreateButton(parent, "Swap", 62)
    parent.swapRoute:SetPoint("LEFT", parent.destDropdown, "RIGHT", CONTROL_GAP, 0)
    parent.swapRoute:SetScript("OnClick", function()
        if UI.transferDest == "Vendor" then return end
        UI.transferSource, UI.transferDest = UI.transferDest, UI.transferSource
        UI.transferSelected = {}
        ClearActiveWorkflowState()
        Core.RefreshTransferDropdowns()
        Core.RefreshUI()
    end)

    -- Save as task (H6): saves the whole current state as a Home card.
    parent.presetNameLabel = CreateLabel(parent, "Save as task", "GameFontHighlightSmall")
    parent.presetNameLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, DRAWER_ROW_2_Y - 5)

    parent.presetNameInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    parent.presetNameInput:SetSize(220, ROW_HEIGHT)
    parent.presetNameInput:SetAutoFocus(false)
    parent.presetNameInput:SetMaxLetters(48)
    parent.presetNameInput:SetPoint("TOPLEFT", parent, "TOPLEFT", 86, DRAWER_ROW_2_Y)

    parent.savePreset = CreateButton(parent, "Save task", 80)
    parent.savePreset:SetPoint("LEFT", parent.presetNameInput, "RIGHT", CONTROL_GAP, 0)
    parent.savePreset:SetScript("OnClick", function()
        local name = parent.presetNameInput:GetText()
        if name and name ~= "" then
            SaveFilter(name, "Transfer")
            UI.activeSavedFilterName = name
            UI.activeQuickWorkflowName = nil
            UI.activeTaskModified = false
            UI.transferContextMessage = "Saved \"" .. name .. "\". It's on Home now."
            Core.RefreshUI()
        end
    end)

    parent.customControls = {
        parent.fromLabel, parent.sourceDropdown, parent.flowArrow, parent.toLabel,
        parent.destDropdown, parent.swapRoute,
        parent.presetNameLabel, parent.presetNameInput, parent.savePreset,
    }

    -- Filter drawer: categorical filters on the first row, refinement and sort
    -- on the second. It is mutually exclusive with the Customize drawer.
    parent.expansionFilter = CreateDropdown(parent, 145, GetExpansionOptions(), function(value)
        SetFilterInclude("Transfer", "expansion", value)
        ClearActiveWorkflowState()
    end)
    parent.expansionFilter:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, DRAWER_ROW_1_Y)

    parent.typeFilter = CreateMultiSelectDropdown(parent, 105, GetTypeFilterOptions(), function(value)
        SetFilterInclude("Transfer", "type", value)
        ClearActiveWorkflowState()
    end)
    parent.typeFilter:SetPoint("LEFT", parent.expansionFilter, "RIGHT", CONTROL_GAP, 0)

    parent.bindFilter = CreateDropdown(parent, 105, GetBindFilterOptions(), function(value)
        SetFilterInclude("Transfer", "bind", value)
        ClearActiveWorkflowState()
    end)
    parent.bindFilter:SetPoint("LEFT", parent.typeFilter, "RIGHT", CONTROL_GAP, 0)

    parent.slotFilter = CreateMultiSelectDropdown(parent, 105, GetSlotFilterOptions(), function(value)
        SetFilterSlot("Transfer", value)
        ClearActiveWorkflowState()
    end)
    parent.slotFilter:SetPoint("LEFT", parent.bindFilter, "RIGHT", CONTROL_GAP, 0)

    parent.armorTypeFilter = CreateDropdown(parent, 90, GetArmorTypeFilterOptions(), function(value)
        SetFilterArmorType("Transfer", value)
        ClearActiveWorkflowState()
    end)
    parent.armorTypeFilter:SetPoint("LEFT", parent.slotFilter, "RIGHT", CONTROL_GAP, 0)

    parent.upgradeFilter = CreateDropdown(parent, 90, GetUpgradeFilterOptions(), function(value)
        SetFilterUpgrade("Transfer", value)
        ClearActiveWorkflowState()
    end)
    parent.upgradeFilter:SetPoint("LEFT", parent.armorTypeFilter, "RIGHT", CONTROL_GAP, 0)

    parent.ilvlLabel = CreateLabel(parent, "iLvl:", "GameFontHighlightSmall")
    parent.ilvlLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, DRAWER_ROW_2_Y - 5)

    parent.ilvlMin = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    parent.ilvlMin:SetSize(46, ROW_HEIGHT)
    parent.ilvlMin:SetAutoFocus(false)
    parent.ilvlMin:SetMaxLetters(5)
    parent.ilvlMin:SetNumeric(true)
    parent.ilvlMin:SetPoint("LEFT", parent.ilvlLabel, "RIGHT", 8, 0)
    parent.ilvlMin:SetScript("OnTextChanged", function(self, userInput)
        if UI.refreshingTransferControls or not userInput then return end
        SetFilterItemLevel("Transfer", self:GetText(), parent.ilvlMax:GetText())
        ClearActiveWorkflowState()
        Core.RefreshUI()
    end)

    parent.ilvlSep = CreateLabel(parent, "–", "GameFontHighlightSmall")
    parent.ilvlSep:SetPoint("LEFT", parent.ilvlMin, "RIGHT", 4, 0)

    parent.ilvlMax = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    parent.ilvlMax:SetSize(46, ROW_HEIGHT)
    parent.ilvlMax:SetAutoFocus(false)
    parent.ilvlMax:SetMaxLetters(5)
    parent.ilvlMax:SetNumeric(true)
    parent.ilvlMax:SetPoint("LEFT", parent.ilvlSep, "RIGHT", 4, 0)
    parent.ilvlMax:SetScript("OnTextChanged", function(self, userInput)
        if UI.refreshingTransferControls or not userInput then return end
        SetFilterItemLevel("Transfer", parent.ilvlMin:GetText(), self:GetText())
        ClearActiveWorkflowState()
        Core.RefreshUI()
    end)

    parent.actionableOnly = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    parent.actionableOnly:SetPoint("LEFT", parent.ilvlMax, "RIGHT", 20, 0)
    parent.actionableOnlyLabel = CreateLabel(parent, "Actionable only", "GameFontHighlightSmall")
    parent.actionableOnlyLabel:SetPoint("LEFT", parent.actionableOnly, "RIGHT", -2, 0)
    parent.actionableOnly:SetScript("OnClick", function(self)
        SetFilterHideBlocked("Transfer", self:GetChecked())
        ClearActiveWorkflowState()
        Core.RefreshUI()
    end)

    parent.sortDropdown = CreateDropdown(parent, 124, TRANSFER_SORT_OPTIONS, function(value)
        ns.DB.ui.transferSort = value
        ClearActiveWorkflowState()
    end)
    parent.sortDropdown:SetPoint("LEFT", parent.actionableOnlyLabel, "RIGHT", 20, 0)

    parent.clearFilters = CreateButton(parent, "Reset filters", 100)
    parent.clearFilters:SetPoint("TOPRIGHT", parent, "TOPLEFT", CONTENT_WIDTH, DRAWER_ROW_2_Y)
    parent.clearFilters:SetScript("OnClick", function()
        ResetTabFilters("Transfer")
        ClearActiveWorkflowState()
        Core.RefreshUI()
    end)

    parent.filterControls = {
        parent.expansionFilter, parent.typeFilter, parent.bindFilter,
        parent.slotFilter, parent.armorTypeFilter, parent.upgradeFilter,
        parent.ilvlLabel, parent.ilvlMin, parent.ilvlSep, parent.ilvlMax,
        parent.actionableOnly, parent.actionableOnlyLabel, parent.sortDropdown,
        parent.clearFilters,
    }

    parent.listFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    parent.listFrame:SetWidth(CONTENT_WIDTH)
    parent.listFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, LIST_TOP_COLLAPSED_Y)
    parent.listFrame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, FOOTER_HEIGHT + LIST_FOOTER_GAP)
    parent.listFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    parent.listFrame:SetBackdropColor(0, 0, 0, 0.2)
    parent.contextNotice:ClearAllPoints()
    parent.contextNotice:SetPoint("BOTTOMRIGHT", parent.listFrame, "TOPRIGHT", 0, 4)
    parent.empty = CreateEmptyLabel(parent.listFrame, "No transfer candidates.")
    parent.empty:ClearAllPoints()
    parent.empty:SetPoint("CENTER", parent.listFrame, "CENTER", 0, 15)
    parent.empty:SetWidth(500)
    parent.emptyAction = CreateButton(parent.listFrame, "", 128, 24)
    parent.emptyAction:SetPoint("TOP", parent.empty, "BOTTOM", 0, -12)
    parent.emptyAction:SetScript("OnClick", function(self)
        if self.mode == "scan" then
            Core.ScanInventory(self.scanScope or BAG_SCOPE)
        elseif self.mode == "clear" then
            ResetTabFilters("Transfer")
            ClearActiveWorkflowState()
            Core.RefreshUI()
        elseif self.mode == "blocked" then
            SetFilterHideBlocked("Transfer", false)
            ClearActiveWorkflowState()
            Core.RefreshUI()
        elseif self.mode == "home" then
            Core.ShowHomeUI()
        end
    end)
    parent.emptyAction:Hide()

    -- Scrollable list using FauxScrollFrame
    -- Normal rows: 6 x 42px with a detail line. Compact rows: 9 x 28px.
    parent.ROW_HEIGHT = 42
    parent.VISIBLE_ROWS = 6
    parent.MAX_ROWS = 9
    parent.LIST_INSET = LIST_INSET
    local ROW_HEIGHT = parent.ROW_HEIGHT
    parent.scrollFrame = CreateFrame("ScrollFrame", nil, parent.listFrame, "FauxScrollFrameTemplate")
    parent.scrollFrame:SetPoint("TOPLEFT",     parent.listFrame, "TOPLEFT",     LIST_INSET,   -LIST_INSET)
    parent.scrollFrame:SetPoint("BOTTOMRIGHT", parent.listFrame, "BOTTOMRIGHT", -SCROLLBAR_RIGHT_INSET,  LIST_INSET)
    parent.scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, parent.ROW_HEIGHT, function() Core.RefreshUI() end)
    end)

    parent.rows = {}
    for i = 1, parent.MAX_ROWS do
        local row = CreateFrame("Button", nil, parent.listFrame, "BackdropTemplate")
        row:SetSize(ROW_WIDTH, 40)
        row:RegisterForClicks("LeftButtonUp")
        row.baseAlpha = i % 2 == 0 and 0.18 or 0.08
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row:SetBackdropColor(0, 0, 0, row.baseAlpha)
        row:SetPoint("TOPLEFT", parent.listFrame, "TOPLEFT", LIST_INSET, -LIST_INSET - (i - 1) * ROW_HEIGHT)
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetPoint("LEFT", 0, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", row.check, "RIGHT", -2, 0)
        row.nameText = CreateLabel(row, "", "GameFontHighlightSmall")
        row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -4)
        row.nameText:SetWidth(ROW_TEXT_WIDTH)
        row.nameText:SetWordWrap(false)
        row.detailText = CreateLabel(row, "", "GameFontDisableSmall")
        row.detailText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -2)
        row.detailText:SetWidth(ROW_TEXT_WIDTH)
        row.detailText:SetWordWrap(false)
        row.action = CreateButton(row, "Move", ROW_ACTION_WIDTH, 22)
        row.action:SetPoint("RIGHT", row, "RIGHT", -ROW_ACTION_RIGHT, 0)
        row.rule = CreateButton(row, "+Rule", ROW_RULE_WIDTH, 22)
        row.rule:SetPoint("RIGHT", row, "RIGHT", -ROW_RULE_RIGHT, 0)
        -- Only live rule types: Protect / Ignore / Never Sell
        row.ruleMenu = CreateRowRuleMenu(row, 150, {
            { text = "Protect",    ruleType = "Protect" },
            { text = "Ignore",     ruleType = "Ignore" },
            { text = "Never Sell", ruleType = "Never Sell" },
            { text = "Keepsake",   ruleType = "keep:keepsake" },
            { text = "Keep for an alt", ruleType = "keep:alt" },
            { text = "Keep for an event", ruleType = "keep:event" },
            { text = "Investment (90 days)", ruleType = "keep:investment" },
            { text = "Send to an alt...", ruleType = "handoff" },
        })
        parent.rows[i] = row
        row:Hide()
    end

    parent.footer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    parent.footer:SetSize(CONTENT_WIDTH, FOOTER_HEIGHT)
    parent.footer:SetPoint("BOTTOMLEFT", 0, 0)
    parent.footer:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })

    parent.itemCount = CreateLabel(parent.footer, "", "GameFontHighlightSmall")
    parent.itemCount:SetPoint("LEFT", parent.footer, "LEFT", 8, 0)
    parent.itemCount:SetWidth(350)
    parent.itemCount:SetJustifyH("LEFT")

    parent.execute = CreateButton(parent, "Select items first", 180, 26, "primary")
    parent.execute:SetParent(parent.footer)
    parent.execute:SetPoint("RIGHT", parent.footer, "RIGHT", -8, 0)
    parent.execute:SetScript("OnClick", function() Core.ExecuteTransferSelected() end)

    parent.clearSel = CreateButton(parent, "Clear Selection", 104)
    parent.clearSel:SetParent(parent.footer)
    parent.clearSel:SetPoint("RIGHT", parent.execute, "LEFT", -8, 0)
    parent.clearSel:SetScript("OnClick", function()
        UI.transferSelected = {}
        Core.RefreshUI()
    end)

    parent.selectAll = CreateButton(parent, "Select Movable", 116)
    parent.selectAll:SetParent(parent.footer)
    parent.selectAll:SetPoint("RIGHT", parent.clearSel, "LEFT", -8, 0)
    parent.selectAll:SetScript("OnClick", function()
        for _, plan in ipairs(UI.transferVisible or {}) do
            if plan.movable then
                UI.transferSelected[plan.key] = true
            end
        end
        Core.RefreshUI()
    end)
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
    local resetMessages = {}
    if not isValidValue(sourceOpts, UI.transferSource) then
        table.insert(resetMessages, "source")
        UI.transferSource = defaultSource
        UI.transferSelected = {}
    end
    if not isValidValue(destOpts, UI.transferDest) or UI.transferDest == UI.transferSource then
        table.insert(resetMessages, "destination")
        -- Pick first dest that isn't the source
        for _, opt in ipairs(destOpts) do
            if opt.value ~= UI.transferSource then
                UI.transferDest = opt.value
                break
            end
        end
        UI.transferSelected = {}
    end
    if #resetMessages > 0 then
        ClearActiveWorkflowState()
        UI.transferContextMessage = "Transfer " .. table.concat(resetMessages, " and ") .. " reset because the previous option is no longer available."
    end
end

function Core.RefreshTransfer()
    return P.WithEvaluationCache(Core.RefreshTransferUncached)
end

function Core.RefreshTransferUncached()
    local panel = UI.frame.panels.Transfer
    local source = UI.transferSource or "Bags"
    local dest = UI.transferDest or STORAGE_PRIVATE_BANK
    local filters = EnsureTabFilters("Transfer")

    local needsBank = NeedsBankStorage(source) or NeedsBankStorage(dest)
    local noticeText
    if dest == "Vendor" and not ns.DB.context.vendorOpen then
        noticeText = "Vendor is not open: sell actions are unavailable."
    elseif needsBank and not IsBankContextDetected() then
        noticeText = "Bank is not open: transfer actions are unavailable."
    end
    if UI.transferContextMessage then
        noticeText = noticeText and (noticeText .. " " .. UI.transferContextMessage) or UI.transferContextMessage
        UI.transferContextMessage = nil
    end
    if P.TransferTipFor and not noticeText then
        noticeText = P.TransferTipFor(source, dest, #GetAllDecisions() > 0)
    end
    SetContextNotice(panel.contextNotice, noticeText)

    SetDropdownText(panel.sourceDropdown, GetStorageDisplayName(source))
    SetDropdownText(panel.destDropdown, GetStorageDisplayName(dest))
    panel.swapRoute:SetEnabled(dest ~= "Vendor" and not ns.DB.context.inCombat)

    local taskName = UI.activeQuickWorkflowName or UI.activeSavedFilterName
    panel.taskTitle:SetText(taskName and (taskName .. (UI.activeTaskModified and " (modified)" or "")) or "Custom transfer")
    panel.routeSummary:SetText(GetStorageDisplayName(source) .. "  ->  " .. GetStorageDisplayName(dest))
    panel.rescan:SetText(IsBankContextDetected() and "Rescan all" or "Scan bags")
    panel.rescan:SetEnabled(not ns.DB.context.inCombat)
    SetDropdownText(panel.expansionFilter, "Expansion: " .. GetExpansionFilterLabel(filters.expansion.include))
    SetMultiDropdownValue(panel.typeFilter, filters.type.include)
    SetDropdownText(panel.typeFilter, "Type: " .. GetMultiSelectLabel(filters.type.include, "All"))
    SetDropdownText(panel.bindFilter, "Binding: " .. tostring(filters.bind.include or BIND_FILTER_ALL))
    SetMultiDropdownValue(panel.slotFilter, filters.slot and filters.slot.include or "All")
    SetDropdownText(panel.slotFilter, "Slot: " .. GetMultiSelectLabel(filters.slot and filters.slot.include or "All", "All"))
    local upgradeVal = filters.upgrade and filters.upgrade.include or "All"
    SetDropdownText(panel.upgradeFilter, upgradeVal == "All" and "Upgrade: All" or upgradeVal)
    local armorTypeVal = filters.armorType and filters.armorType.include or "All"
    SetDropdownText(panel.armorTypeFilter, "Armor: " .. GetArmorTypeFilterLabel(armorTypeVal))
    panel.actionableOnly:SetChecked(filters.hideBlocked)

    local filterChips = BuildActiveFilterChips(filters)
    local activeFilterCount = #filterChips
    panel.filtersToggle:SetText(activeFilterCount > 0 and ("Filters (" .. activeFilterCount .. ")") or "Filters")
    local filtersExpanded = filters.advancedEnabled and true or false
    local customizeExpanded = UI.transferCustomizeOpen and true or false
    SetButtonStyle(panel.filtersToggle, filtersExpanded and "primary" or "secondary")
    SetButtonStyle(panel.customizeToggle, customizeExpanded and "primary" or "secondary")
    panel.customizeToggle:SetText(customizeExpanded and "Done" or "Customize")
    for _, control in ipairs(panel.filterControls or {}) do control:SetShown(filtersExpanded) end
    for _, control in ipairs(panel.customControls or {}) do control:SetShown(customizeExpanded) end

    local visibleChipCount = math.min(#filterChips, 3)
    for index, chip in ipairs(panel.filterChips or {}) do
        chip.clearFilter = nil
        chip.showAllFilters = nil
        if index <= visibleChipCount then
            local definition = filterChips[index]
            local isMore = #filterChips > 3 and index == 3
            chip:ClearAllPoints()
            chip:SetPoint("LEFT", index == 1 and panel.filtersToggle or panel.filterChips[index - 1], "RIGHT", 6, 0)
            if isMore then
                chip:SetText("+" .. (#filterChips - 2) .. " more")
                chip:SetWidth(82)
                chip.showAllFilters = true
            else
                chip:SetText(definition.text)
                chip:SetWidth(math.min(110, math.max(76, #definition.text * 6 + 22)))
                chip.clearFilter = definition.clear
            end
            chip:Show()
        else
            chip:Hide()
        end
    end

    local drawerExpanded = filtersExpanded or customizeExpanded
    panel.listFrame:ClearAllPoints()
    panel.listFrame:SetWidth(806)
    panel.listFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0,
        drawerExpanded and panel.LIST_TOP_EXPANDED_Y or panel.LIST_TOP_COLLAPSED_Y)
    panel.listFrame:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 64)

    local searchText = filters.name.includeText or ""
    UI.refreshingTransferControls = true
    if panel.search:GetText() ~= searchText then
        panel.search:SetText(searchText)
    end
    local ilvlMinVal = filters.itemLevel and filters.itemLevel.min
    local ilvlMaxVal = filters.itemLevel and filters.itemLevel.max
    local ilvlMinStr = ilvlMinVal and tostring(ilvlMinVal) or ""
    local ilvlMaxStr = ilvlMaxVal and tostring(ilvlMaxVal) or ""
    if panel.ilvlMin:GetText() ~= ilvlMinStr then panel.ilvlMin:SetText(ilvlMinStr) end
    if panel.ilvlMax:GetText() ~= ilvlMaxStr then panel.ilvlMax:SetText(ilvlMaxStr) end
    UI.refreshingTransferControls = false
    local sortMode = ns.DB.ui.transferSort or "Name"
    SetDropdownText(panel.sortDropdown, "Sort: " .. sortMode)
    panel.clearFilters:SetEnabled(activeFilterCount > 0 or searchText ~= "")

    local allCandidates = GetTransferCandidates(source, dest)
    local matched = {}
    local visible = {}
    for _, plan in ipairs(allCandidates) do
        if PlanMatchesTabFilters(plan, "Transfer")
            and (not UI.activeTaskPredicate or UI.activeTaskPredicate(plan.item)) then
            table.insert(matched, plan)
            if not filters.hideBlocked or plan.movable then
                table.insert(visible, plan)
            end
        end
    end
    SortTransferPlans(visible, sortMode)
    UI.transferVisible = visible

    -- Group identical items (same item, same status) into one row (H4).
    local displayRows = {}
    local groupIndex = {}
    local grouping = ns.DB.ui.groupIdenticalRows ~= false
    for _, plan in ipairs(visible) do
        local groupKey = grouping and (tostring(plan.item.itemID) .. ":" .. tostring(plan.movable) .. ":" .. tostring(plan.blocked or ""))
        local row = groupKey and groupIndex[groupKey]
        if row then
            table.insert(row.plans, plan)
            row.total = row.total + (plan.item.count or 1)
        else
            row = { plans = { plan }, plan = plan, total = plan.item.count or 1 }
            table.insert(displayRows, row)
            if groupKey then groupIndex[groupKey] = row end
        end
    end
    UI.transferRows = displayRows

    local movableCount = 0
    for _, plan in ipairs(matched) do
        if plan.movable then movableCount = movableCount + 1 end
    end

    local lastScan = P.GetLastScan(source == "Bags" and BAG_SCOPE or BANK_SCOPE)
    local emptyMsg
    local emptyActionMode
    local emptyActionText
    local emptyScanScope
    if #allCandidates == 0 and (lastScan or 0) == 0 then
        emptyMsg = "No scan data for " .. GetStorageDisplayName(source) .. "."
        emptyActionMode = "scan"
        emptyScanScope = source == "Bags" and BAG_SCOPE or BANK_SCOPE
        emptyActionText = source == "Bags" and "Scan bags" or "Scan bank"
    elseif #matched == 0 and (UI.activeQuickWorkflowName or UI.activeSavedFilterName) and not UI.activeTaskModified then
        -- An opened task with nothing left is finished, not over-filtered.
        local taskName = UI.activeQuickWorkflowName or UI.activeSavedFilterName
        emptyMsg = taskName == "Pull Bank Upgrades" and "No bank upgrades found."
            or ("All done: nothing left for “" .. taskName .. "”.")
        emptyActionMode = "home"
        emptyActionText = "Back to Home"
    elseif #allCandidates == 0 then
        emptyMsg = "No items were found in " .. GetStorageDisplayName(source) .. "."
    elseif #matched == 0 then
        emptyMsg = "No items match the active filters."
        emptyActionMode = "clear"
        emptyActionText = "Clear filters"
    elseif #visible == 0 and filters.hideBlocked then
        emptyMsg = "All matching items are currently blocked."
        emptyActionMode = "blocked"
        emptyActionText = "Show blocked items"
    else
        emptyMsg = "No transfer candidates."
    end
    SetEmptyLabel(panel.empty, #visible == 0, emptyMsg)
    panel.emptyAction.mode = emptyActionMode
    panel.emptyAction.scanScope = emptyScanScope
    panel.emptyAction:SetText(emptyActionText or "")
    panel.emptyAction:SetShown(#visible == 0 and emptyActionMode ~= nil)

    local selectedCount = 0
    local selectedVendorValue = 0
    for _, plan in ipairs(visible) do
        if UI.transferSelected[plan.key] then
            selectedCount = selectedCount + 1
            selectedVendorValue = selectedVendorValue
                + ((plan.item.sellPrice or 0) * (plan.item.count or 1))
        end
    end

    local actionLabel
    local batch = P.VENDOR_BATCH_SIZE or 12
    if selectedCount == 0 then
        actionLabel = "Select items first"
    elseif dest == "Vendor" and selectedCount > batch then
        actionLabel = "Sell " .. batch .. " of " .. selectedCount
    elseif dest == "Vendor" then
        actionLabel = "Sell " .. selectedCount .. " (" .. FormatMoney(selectedVendorValue) .. ")"
    elseif dest == "Bags" then
        actionLabel = "Withdraw " .. selectedCount
    elseif source == "Bags" then
        actionLabel = "Deposit " .. selectedCount
    else
        actionLabel = "Move " .. selectedCount
    end
    panel.execute:SetText(actionLabel)
    panel.execute:SetEnabled(not ns.DB.context.inCombat and selectedCount > 0)
    panel.clearSel:SetEnabled(selectedCount > 0)
    panel.clearSel:SetShown(selectedCount > 0)
    panel.selectAll:SetEnabled(movableCount > 0)
    panel.selectAll:SetShown(movableCount > 0)
    panel.selectAll:ClearAllPoints()
    panel.selectAll:SetPoint("RIGHT", selectedCount > 0 and panel.clearSel or panel.execute, "LEFT", -8, 0)

    local compact = ns.DB.ui.compactRows and true or false
    panel.ROW_HEIGHT = compact and 28 or 42
    panel.VISIBLE_ROWS = compact and panel.MAX_ROWS or 6
    for i, row in ipairs(panel.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.listFrame, "TOPLEFT", panel.LIST_INSET, -panel.LIST_INSET - (i - 1) * panel.ROW_HEIGHT)
        row:SetHeight(compact and 26 or 40)
        row.detailText:SetShown(not compact)
    end

    FauxScrollFrame_Update(panel.scrollFrame, #displayRows, panel.VISIBLE_ROWS, panel.ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(panel.scrollFrame)
    local startIndex = offset + 1

    local statusSuffix = UI.inventoryStatus and ("  |  " .. UI.inventoryStatus) or ""
    panel.itemCount:SetText(#allCandidates .. " source  •  " .. #matched .. " matching  •  "
        .. movableCount .. " movable  •  " .. selectedCount .. " selected" .. statusSuffix)

    for i, row in ipairs(panel.rows) do
        local display = i <= panel.VISIBLE_ROWS and displayRows[startIndex + i - 1] or nil
        local plan = display and display.plan
        if plan then
            local item = plan.item
            local members = display.plans
            local isSelected = plan.movable
            for _, member in ipairs(members) do
                if not UI.transferSelected[member.key] then isSelected = false break end
            end
            isSelected = isSelected and true or false
            row:Show()
            row.plan = plan
            row.icon:SetTexture(item.icon)
            row.check:SetEnabled(plan.movable)
            row.check:SetChecked(isSelected)
            if isSelected then
                row:SetBackdropColor(0.08, 0.28, 0.42, 0.72)
            elseif plan.blocked then
                row:SetBackdropColor(0.28, 0.04, 0.04, 0.28)
            else
                row:SetBackdropColor(0, 0, 0, row.baseAlpha or 0.08)
            end
            local function SetMembersSelected(selected)
                for _, member in ipairs(members) do
                    UI.transferSelected[member.key] = selected and true or nil
                end
            end
            row.check:SetScript("OnClick", function(self)
                SetMembersSelected(self:GetChecked())
                Core.RefreshUI()
            end)
            row:SetScript("OnClick", function()
                if not plan.movable then return end
                SetMembersSelected(not isSelected)
                Core.RefreshUI()
            end)
            local name = P.ItemDisplayName(item.name, item.link, item.itemID)
            if #members > 1 then
                name = name .. "  x" .. display.total .. " in " .. #members .. " stacks"
            end
            if compact and plan.blocked then name = name .. "  -  Blocked: " .. plan.blocked end
            row.nameText:SetText(name)
            local detailPlan = plan
            if #members > 1 then
                detailPlan = { item = setmetatable({ count = display.total }, { __index = item }),
                    blocked = plan.blocked, movable = plan.movable }
            end
            row.detailText:SetText(BuildTransferRowDetail(detailPlan, source, dest))
            local actionText
            if dest == "Vendor" then
                actionText = "Sell"
            elseif dest == "Bags" then
                actionText = "Withdraw"
            elseif source == "Bags" then
                actionText = "Deposit"
            else
                actionText = "Move"
            end
            row.action:SetText(actionText)
            row.action:SetEnabled(plan.movable)
            row.action:SetScript("OnClick", function()
                -- Acts on every stack in the row; vendor sales stop at one buyback batch.
                local limit = dest == "Vendor" and (P.VENDOR_BATCH_SIZE or 12) or #members
                for index = 1, math.min(limit, #members) do
                    Core.ExecuteTransferOne(members[index])
                end
            end)
            row.rule:SetScript("OnClick", function() ToggleRowRuleMenu(row, item) end)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(item.link or ("item:" .. item.itemID))
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("From: " .. source, 1, 1, 1)
                GameTooltip:AddLine("To: " .. dest, 1, 1, 1)
                if item.reason then
                    GameTooltip:AddLine("Classification: " .. item.reason, 0.75, 0.85, 1)
                end
                GameTooltip:AddLine("Expansion: " .. (item.expansionName or "Unknown"), 1, 1, 1)
                GameTooltip:AddLine("Type: " .. (item.typeTag or "Unknown"), 1, 1, 1)
                if item.itemSubTypeName then
                    GameTooltip:AddLine("Subtype: " .. item.itemSubTypeName, 1, 1, 1)
                end
                if item.bindingScope then
                    GameTooltip:AddLine("Binding: " .. item.bindingScope, 1, 1, 1)
                end
                if item.itemLevel and item.itemLevel > 0 then
                    GameTooltip:AddLine("Item Level: " .. tostring(item.itemLevel), 1, 1, 1)
                end
                if item.location then
                    GameTooltip:AddLine("Location: " .. item.location, 1, 1, 1)
                end
                if dest == "Vendor" then
                    local stackValue = (item.sellPrice or 0) * (item.count or 1)
                    GameTooltip:AddLine("Vendor value: " .. FormatMoney(stackValue), 1, 1, 1)
                end
                if plan.blocked then
                    GameTooltip:AddLine("Blocked: " .. plan.blocked, 1, 0.35, 0.35)
                end
                if P.ExplainScanned then
                    local explanation = P.ExplainScanned(item)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Why it's here: " .. explanation.label, 1, 0.82, 0.3)
                    if explanation.evidence then GameTooltip:AddLine(explanation.evidence, 0.8, 0.8, 0.8) end
                    if explanation.held then GameTooltip:AddLine("Held " .. explanation.held, 0.8, 0.8, 0.8) end
                    for _, other in ipairs(explanation.reasons) do
                        if other ~= explanation.primary and P.REASONS[other.id] then
                            GameTooltip:AddLine("Also: " .. P.REASONS[other.id].label, 0.65, 0.65, 0.65)
                        end
                    end
                    local loss = P.LossText(item, explanation)
                    if loss then GameTooltip:AddLine("If it goes: " .. loss, 0.6, 0.9, 0.6) end
                    local benefits = P.WhoBenefits and P.WhoBenefits(item)
                    if benefits then GameTooltip:AddLine("Who benefits: " .. benefits, 0.6, 0.8, 1) end
                end
                if P.ValueTooltipLines then
                    for _, line in ipairs(P.ValueTooltipLines(item)) do
                        GameTooltip:AddLine(line, 0.9, 0.8, 0.5)
                    end
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            row.plan = nil
            row:SetScript("OnClick", nil)
            row:SetBackdropColor(0, 0, 0, row.baseAlpha or 0.08)
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
        if rule.keepReason then
            for _, choice in ipairs(P.KEEP_REASON_CHOICES or {}) do
                if choice.value == rule.keepReason then table.insert(flags, choice.label) end
            end
        end
        if #flags > 0 then
            local resolvedName = nameLookup[itemID] or rule.name
            local createdFrom = rule.createdFrom or ""
            if not resolvedName and GetItemInfo then
                resolvedName = GetItemInfo(itemID)
            end
            if not resolvedName and createdFrom ~= "" and createdFrom ~= "Rules tab" and createdFrom ~= "Transfer tab" then
                resolvedName = createdFrom
                createdFrom = "Legacy rule"
            end
            table.insert(entries, {
                itemID = itemID,
                ruleType = table.concat(flags, ", "),
                createdFrom = createdFrom,
                name = resolvedName or ("Item #" .. tostring(itemID)),
            })
        end
    end
    table.sort(entries, function(a, b) return (a.name or "") < (b.name or "") end)

    local rows = panel.rows or {}
    local visibleRows = panel.VISIBLE_ROWS or #rows
    local rowHeight = panel.ROW_HEIGHT or 30
    local count = #entries
    local renderedRows = math.max(2, math.min(count, visibleRows))
    panel.listFrame:SetHeight((panel.HEADER_HEIGHT or 26) + renderedRows * rowHeight + 8)
    FauxScrollFrame_Update(panel.scrollFrame, #entries, visibleRows, rowHeight)
    local offset = FauxScrollFrame_GetOffset(panel.scrollFrame)
    for i, row in ipairs(rows) do
        local e = entries[offset + i]
        if e then
            row.itemText:SetText(e.name or "")
            row.ruleText:SetText(e.ruleType or "")
            row.sourceText:SetText(e.createdFrom or "")
            row.remove:SetScript("OnClick", function()
                ns.DB.rules.items[e.itemID] = nil
                if Core.OnRulesChanged then Core.OnRulesChanged() end
                Core.RefreshRules()
            end)
            row:Show()
        else
            row.itemText:SetText("")
            row.ruleText:SetText("")
            row.sourceText:SetText("")
            row.remove:SetScript("OnClick", nil)
            row:Hide()
        end
    end

    SetEmptyLabel(panel.empty, count == 0, "No item rules yet.")
    if panel.countText then
        panel.countText:SetText(count .. " rule" .. (count == 1 and "" or "s") .. " total")
    end
end

function Core.RefreshSettings()
    if not UI.frame then return end
    local panel = UI.frame.panels and UI.frame.panels.Settings
    if not panel then return end
    if panel.minimap then
        panel.minimap:SetChecked(ns.DB and ns.DB.ui and ns.DB.ui.showMinimapIcon ~= false)
    end
    for _, check in ipairs(panel.workflowChecks or {}) do
        local value = ns.DB.ui[check.settingKey]
        if check.settingKey == "groupIdenticalRows" or check.settingKey == "whereTooltip"
            or check.settingKey == "tipsEnabled" then
            value = value ~= false
        end
        check:SetChecked(value and true or false)
    end
    if panel.noticeMode then
        local labels = { notice = "Show a small notice", open = "Open the console", off = "Do nothing" }
        SetDropdownText(panel.noticeMode, labels[ns.DB.ui.contextNotice or "notice"] or labels.notice)
    end
    if panel.status then
        local mode = UI.minimapIconRegistered and "LibDBIcon" or "fallback"
        panel.status:SetText("Minimap launcher: " .. (ns.DB.ui.showMinimapIcon ~= false and "shown" or "hidden") .. " (" .. mode .. ")")
    end
    if panel.commandsToggle and panel.commandFrame then
        local expanded = UI.settingsCommandHelpOpen and true or false
        panel.commandsToggle:SetText(expanded and "Hide command reference" or "Show command reference")
        SetButtonStyle(panel.commandsToggle, expanded and "primary" or "secondary")
        panel.commandFrame:SetShown(expanded)
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
            SetTabVisual(tabBtn, tabName == tab, false)
        end
    end
    if tab == "Home" then
        if P.RefreshHome then P.RefreshHome() end
    elseif tab == "Characters" then
        if P.RefreshCharacters then P.RefreshCharacters() end
    elseif tab == "Transfer" then
        Core.RefreshTransfer()
    elseif tab == "Rules" then
        Core.RefreshRules()
    elseif tab == "Settings" then
        Core.RefreshSettings()
    end
end

-- ===========================================================================
-- Core.CreateUI
-- ===========================================================================

function Core.CreateUI()
    if UI.frame then return end

    local frame = CreateFrame("Frame", "ICantEvenRightNowFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(CONSOLE_WIDTH, CONSOLE_HEIGHT)
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
        local tab = CreateTabButton(frame, name, (name == "Transfer" or name == "Characters") and 104 or 92, function() SetTab(name) end)
        tab:SetFrameLevel(frame:GetFrameLevel() + 8)
        tab:SetPoint("TOPLEFT", previous or frame, previous and "TOPRIGHT" or "TOPLEFT", previous and 2 or 14, previous and 0 or -36)
        UI.tabs[name] = tab
        previous = tab

        local panel = CreatePanel(frame)
        frame.panels[name] = panel
        if name == "Home" then
            P.BuildHomeTab(panel)
        elseif name == "Characters" then
            P.BuildCharactersTab(panel)
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
    if P.HideContextNotice then P.HideContextNotice() end
    UI.activeTab = tab
    UI.frame:Show()
    -- Rescan on open: saved scans can be from an earlier session, and bags
    -- are not tracked while the console is hidden. The scan refreshes the UI.
    Core.ScanInventory("all", true)
end

function Core.ShowHomeUI()     ShowAndRefresh("Home")     end
function Core.ShowSummaryUI()  ShowAndRefresh("Home")     end
function Core.ShowCharactersUI() ShowAndRefresh("Characters") end
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
