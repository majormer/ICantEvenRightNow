-- I Can't Even Right Now (With My Bags and Bank) Core Module
-- Main addon logic, event handlers, scanning, decisions, movement, and UI.

local ADDON_NAME, ns = ...

ns.Core = {}
ns.DB = {}

local Core = ns.Core
local Data = ns.Data
local Debug = ns.Debug
local DISPLAY_NAME = "I Can't Even Right Now (With My Bags and Bank)"
local ICON_TEXTURE = "Interface\\AddOns\\ICantEvenRightNow\\ICantEvenRightNow.png"

local CContainer = C_Container
local TAB_ORDER = { "Summary", "Move", "Organize", "Vendor", "Rules", "Settings" }
local UI = {
    frame = nil,
    minimapButton = nil,
    minimapDataObject = nil,
    minimapIconRegistered = false,
    bankButton = nil,
    vendorButton = nil,
    tabs = {},
    activeTab = "Summary",
    rows = {},
    ruleRows = {},
    selected = {},
    organizeSelected = {},
    organizeVisible = {},
    vendorSelected = {},
    vendorVisible = {},
    visible = {},
    bankContextOpen = false,
    bankContextClosed = false,
    vendorContextOpen = false,
    vendorContextClosed = false,
    hadBankContext = false,
    hadVendorContext = false,
    page = 1,
    pageSize = 6,
}

local BAG_SCOPE = "bags"
local BANK_SCOPE = "bank"
local EXPANSION_FILTER_ALL = 0
local EXPANSION_FILTER_NOT_CURRENT = -1
local EXPANSION_FILTER_UNKNOWN = -2
local ORGANIZE_PAGE_SIZE = 6
local VENDOR_PAGE_SIZE = 6
local STORAGE_BAGS = "Bags"
local STORAGE_PRIVATE_BANK = "Private Bank"
local STORAGE_REAGENT_BANK = "Reagent Bank"
local STORAGE_WARBAND_BANK = "Warband Bank"
local TYPE_FILTER_REAGENT = "Reagent"
local TYPE_FILTER_BOE = "BoE"
local TYPE_FILTER_WUE = "WuE"
local TYPE_FILTER_VENDOR_SELLABLE = "Vendor Sellable"
local BIND_FILTER_ALL = "All"
local BIND_FILTER_BOE = "BoE"
local BIND_FILTER_WUE = "WuE"
local BIND_FILTER_SOULBOUND = "Soulbound"
local BIND_FILTER_WARBAND = "Warbound"
local BIND_FILTER_BOP = "BoP"
local VENDOR_ACTION_RECALL = "Recall to Bags"
local VENDOR_ACTION_SELL = "Sell at Vendor"
local MINIMAP_LDB_NAME = "ICantEvenRightNow"
local BANK_FRAME_NAMES = {
    "BetterBagsBagBank",
    "BagnonFramebank",
    "BagnonFrameBank",
    "CombuctorFramebank",
    "CombuctorFrameBank",
    "LiteBagBankPanel",
    "InventorianBankFrame",
    "BankFrame",
    "BankPanelFrame",
    "BankPanel",
    "BankPanelContainerFrame",
    "AccountBankPanel",
    "AccountBankFrame",
    "AccountBankPanelFrame",
    "WarbandBankFrame",
    "WarbandBankPanel",
    "WarbandBankPanelFrame",
    "BetterBagsBankFrame",
    "BetterBags_BankFrame",
    "BetterBagsBank",
}
local BANK_FRAME_PATTERNS = {
    "betterbagsbagbank",
    "bank",
    "bagnonframebank",
    "combuctorframebank",
    "litebagbank",
    "inventorianbank",
    "bankpanel",
    "accountbank",
    "warbandbank",
    "adibagsbank",
    "sortedbank",
}
local MYTHIC_KEYSTONE_ITEM_IDS = {
    [138019] = true,
    [158923] = true,
    [180653] = true,
}

local function AppendBagID(list, bagID)
    if type(bagID) == "number" then
        table.insert(list, bagID)
    end
end

local function AppendNamedBagID(list, bagIndex, ...)
    if not bagIndex then
        return
    end
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        AppendBagID(list, rawget(bagIndex, key))
    end
end

local function UniqueBagIDs(list)
    local seen = {}
    local unique = {}
    for _, bagID in ipairs(list or {}) do
        if type(bagID) == "number" and not seen[bagID] then
            seen[bagID] = true
            table.insert(unique, bagID)
        end
    end
    return unique
end

local function BuildBackpackIDs()
    local bagIndex = Enum and Enum.BagIndex
    if bagIndex and bagIndex.Backpack then
        local list = {}
        AppendBagID(list, bagIndex.Backpack)
        AppendBagID(list, bagIndex.Bag_1)
        AppendBagID(list, bagIndex.Bag_2)
        AppendBagID(list, bagIndex.Bag_3)
        AppendBagID(list, bagIndex.Bag_4)
        AppendBagID(list, rawget(bagIndex, "ReagentBag"))
        AppendBagID(list, rawget(bagIndex, "Reagentbag"))
        return list
    end
    return { 0, 1, 2, 3, 4 }
end

local function BuildNormalBackpackIDs()
    local bagIndex = Enum and Enum.BagIndex
    if bagIndex and bagIndex.Backpack then
        local list = {}
        AppendBagID(list, bagIndex.Backpack)
        AppendBagID(list, bagIndex.Bag_1)
        AppendBagID(list, bagIndex.Bag_2)
        AppendBagID(list, bagIndex.Bag_3)
        AppendBagID(list, bagIndex.Bag_4)
        return list
    end
    return { 0, 1, 2, 3, 4 }
end

local function BuildPrivateBankIDs()
    local bagIndex = Enum and Enum.BagIndex
    if bagIndex then
        local list = {}
        AppendNamedBagID(list, bagIndex,
            "CharacterBankTab_1", "CharacterBankTab_2", "CharacterBankTab_3",
            "CharacterBankTab_4", "CharacterBankTab_5", "CharacterBankTab_6")

        -- Legacy naming seen in older clients/docs.
        AppendNamedBagID(list, bagIndex,
            "BankBag_1", "BankBag_2", "BankBag_3", "BankBag_4", "BankBag_5", "BankBag_6", "BankBag_7",
            "Bankbag_1", "Bankbag_2", "Bankbag_3", "Bankbag_4", "Bankbag_5", "Bankbag_6", "Bankbag_7")

        if #list == 0 then
            -- Prefer explicit tab IDs over Characterbanktab because that value can
            -- represent an aggregate/current tab in modern UI flows.
            local reagentBagID = rawget(bagIndex, "ReagentBag")
            if reagentBagID == 5 then
                list = { 6, 7, 8, 9, 10, 11 }
            else
                list = { 5, 6, 7, 8, 9, 10, 11 }
            end
        end
        return UniqueBagIDs(list)
    end
    return { -1, 5, 6, 7, 8, 9, 10, 11 }
end

local function BuildReagentBankIDs()
    local bagIndex = Enum and Enum.BagIndex
    local list = {}
    if bagIndex then
        AppendNamedBagID(list, bagIndex, "Reagentbank", "ReagentBank")

        local hasModernAccountAggregate = rawget(bagIndex, "Accountbanktab") == -3
        local hasModernAccountTabs = rawget(bagIndex, "AccountBankTab_1") ~= nil
        if #list == 0 and not (hasModernAccountAggregate or hasModernAccountTabs) then
            -- Legacy fallback: reagent bank container used -3 prior to modern account bank IDs.
            AppendBagID(list, -3)
        end
    else
        AppendBagID(list, -3)
    end
    return UniqueBagIDs(list)
end

local function BuildWarbandBankIDs()
    local bagIndex = Enum and Enum.BagIndex
    local list = {}
    if bagIndex then
        AppendBagID(list, bagIndex.AccountBankTab_1)
        AppendBagID(list, bagIndex.AccountBankTab_2)
        AppendBagID(list, bagIndex.AccountBankTab_3)
        AppendBagID(list, bagIndex.AccountBankTab_4)
        AppendBagID(list, bagIndex.AccountBankTab_5)
    end
    return list
end

-- Scanner functions moved to modules/Scanner.lua
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
    for _, item in ipairs(GetAllDecisions() or {}) do
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
    Core.UpdateContext()
    Core.RefreshUI()
    Core.ScheduleDeferredUIRefresh()
end

function AddRule(item, ruleType)
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
    elseif ruleType == "Never Sell" then
        rule.neverSell = true
    end
    Core.RefreshUI()
end

-- UI building moved to modules/UI.lua
-- UI Refresh functions moved to modules/UI.lua
function Core.ShowSummaryUI()
    Core.CreateUI()
    UI.activeTab = "Summary"
    UI.frame:Show()
    Core.RefreshUI()
end

function Core.ScheduleDeferredUIRefresh()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, function()
            if ns.DB and ns.DB.context and UI.frame and UI.frame:IsShown() then
                Core.UpdateContext()
                Core.RefreshUI()
            end
        end)
        C_Timer.After(1.0, function()
            if ns.DB and ns.DB.context and UI.frame and UI.frame:IsShown() then
                Core.UpdateContext()
                Core.RefreshUI()
            end
        end)
    end
end

function Core.ShowMoveUI()
    Core.CreateUI()
    UI.activeTab = "Move"
    UI.frame:Show()
    Core.RefreshUI()
    Core.ScheduleDeferredUIRefresh()
end

function Core.ShowOrganizeUI()
    Core.CreateUI()
    UI.activeTab = "Organize"
    UI.frame:Show()
    Core.RefreshUI()
    Core.ScheduleDeferredUIRefresh()
end

function Core.ShowVendorUI()
    Core.CreateUI()
    UI.activeTab = "Vendor"
    UI.frame:Show()
    Core.RefreshUI()
    Core.ScheduleDeferredUIRefresh()
end

-- Action functions moved to modules/Actions.lua
function Core.RegisterSlashCommands()
    SLASH_ICANTEVEN1 = "/icanteven"
    SLASH_ICANTEVEN2 = "/icant"
    SlashCmdList["ICANTEVEN"] = function(msg)
        Core.HandleSlashCommand(msg)
    end
end

local function ToggleQuickAccessSetting(key, label)
    ns.DB.ui[key] = not ns.DB.ui[key]
    Core.UpdateQuickAccessButtons()
    Print(label .. ": " .. (ns.DB.ui[key] and "shown" or "hidden"))
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
    elseif cmd == "organize" or cmd == "organizer" then
        Core.ShowOrganizeUI()
    elseif cmd == "vendor" or cmd == "sell" then
        Core.ShowVendorUI()
    elseif cmd == "settings" or cmd == "options" then
        Core.CreateUI()
        UI.activeTab = "Settings"
        UI.frame:Show()
        Core.RefreshUI()
    elseif cmd == "minimap" then
        ToggleQuickAccessSetting("showMinimapIcon", "Minimap button")
    elseif cmd == "bankbutton" then
        Print("Bank launcher is disabled in this version.")
    elseif cmd == "vendorbutton" then
        Print("Vendor launcher is disabled in this version.")
    elseif cmd == "buttons" or cmd == "quickaccess" then
        Core.PrintQuickAccessStatus()
    elseif cmd == "bankdiag" or cmd == "bankids" then
        Core.PrintBankContainerDiagnostics()
    elseif cmd == "ctx" then
        Core.UpdateContext()
        Print("=== ctx diagnostic ===")
        Print("UI.bankContextOpen=" .. tostring(UI.bankContextOpen))
        Print("IsPlayerBankInteractionActive=" .. tostring(IsPlayerBankInteractionActive()))
        Print("IsBankViewableByAPI=" .. tostring(IsBankViewableByAPI()))
        Print("IsBankStorageAccessible=" .. tostring(IsBankStorageAccessible()))
        local frameResult = GetShownGlobalFrame(BANK_FRAME_NAMES) or GetShownNamedFrameByPattern(BANK_FRAME_PATTERNS)
        Print("FrameDetected=" .. tostring(frameResult ~= nil) .. " (" .. tostring(frameResult) .. ")")
        Print("IsBankContextDetected=" .. tostring(IsBankContextDetected()))
        Print("context.bankOpen=" .. tostring(ns.DB.context.bankOpen))
        if CContainer and CContainer.GetContainerNumFreeSlots then
            local parts = {}
            local allIDs = {}
            for _, ids in ipairs({ PRIVATE_BANK_IDS, REAGENT_BANK_IDS, WARBAND_BANK_IDS }) do
                for _, bagID in ipairs(ids or {}) do table.insert(allIDs, bagID) end
            end
            for _, bagID in ipairs(allIDs) do
                local ok, free = pcall(CContainer.GetContainerNumFreeSlots, bagID)
                table.insert(parts, tostring(bagID) .. "=" .. tostring(ok and free or "err"))
            end
            Print("FreeSlots: " .. table.concat(parts, ", "))
        end
        Print("=== ctx end ===")
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
        Print("Commands: /icanteven, scan [bags|bank|all], summary, move, organize, vendor, rules, settings, minimap, buttons, bankdiag, debug, diag")
    end
end

function Core.OnAddonLoaded()
    ICantEvenRightNowDB = SafeCopyDefaults(Data.DefaultDB, ICantEvenRightNowDB)
    ns.DB = ICantEvenRightNowDB
    MigrateLegacyTabFilters()
    ns.DB.ui.showBankButton = false
    ns.DB.ui.showVendorButton = false
    NormalizeLegacyBankStorageKinds(ns.DB.scans.bank)
    Core.RegisterSlashCommands()
    Core.UpdateContext()
    Core.UpdateQuickAccessButtons()
    ScheduleQuickAccessRefresh()
    Print("Loaded. Type /icanteven to open the cleanup console.")
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("BANKFRAME_CLOSED")
eventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
eventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
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
        elseif ns.DB and addonName and addonName:lower():find("betterbags", 1, true) then
            ScheduleQuickAccessRefresh()
        end
    elseif ns.DB and ns.DB.context then
        local interactionType = ...
        local bankInteraction = IsBankInteractionType(interactionType)
        local bankContextOpened = event == "BANKFRAME_OPENED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and bankInteraction)
        local bankContextClosed = event == "BANKFRAME_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and bankInteraction)
        local vendorContextOpened = event == "MERCHANT_SHOW"
        local vendorContextClosed = event == "MERCHANT_CLOSED"

        if bankContextOpened then
            UI.bankContextOpen = true
            UI.bankContextClosed = false
            UI.hadBankContext = true
        elseif bankContextClosed then
            UI.bankContextOpen = false
            UI.bankContextClosed = true
        end

        if vendorContextOpened then
            UI.vendorContextOpen = true
            UI.vendorContextClosed = false
            UI.hadVendorContext = true
        elseif vendorContextClosed then
            UI.vendorContextOpen = false
            UI.vendorContextClosed = true
        end

        Core.UpdateContext()
        if ((bankContextClosed and UI.hadBankContext) or (vendorContextClosed and UI.hadVendorContext)) and UI.frame and UI.frame:IsShown() then
            UI.frame:Hide()
        end
        if bankContextClosed then
            UI.hadBankContext = false
        end
        if vendorContextClosed then
            UI.hadVendorContext = false
        end
        if bankContextOpened then
            pcall(Core.ScanInventory, "all", true)
        end
        ScheduleQuickAccessRefresh()
    end
end)
