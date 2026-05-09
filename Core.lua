-- I Can't Even Right Now (With My Bags and Bank) — Core
-- Bootstrap: event dispatch, context tracking, slash commands, error logging.
-- All logic lives in: Shared.lua, Evaluator.lua, Filter.lua, Scanner.lua, Transfer.lua, UI.lua

local ADDON_NAME, ns = ...

ns.Core = ns.Core or {}
ns.DB   = ns.DB   or {}

local Core  = ns.Core
local Data  = ns.Data
local Debug = ns.Debug
local P     = ns.Private

local UI = P.UI

local BAG_SCOPE          = P.BAG_SCOPE
local BANK_SCOPE         = P.BANK_SCOPE
local STORAGE_ALL_BANK_TABS = P.STORAGE_ALL_BANK_TABS
local BANK_FRAME_NAMES   = P.BANK_FRAME_NAMES
local BANK_FRAME_PATTERNS = P.BANK_FRAME_PATTERNS
local PRIVATE_BANK_IDS   = P.PRIVATE_BANK_IDS
local REAGENT_BANK_IDS   = P.REAGENT_BANK_IDS
local WARBAND_BANK_IDS   = P.WARBAND_BANK_IDS

local Print                      = P.Print
local SafeCopyDefaults           = P.SafeCopyDefaults
local MigrateLegacyTabFilters    = P.MigrateLegacyTabFilters
local SeedDefaultSavedFilters    = P.SeedDefaultSavedFilters
local NormalizeLegacyBankStorageKinds = P.NormalizeLegacyBankStorageKinds
local RefreshBankTabData         = P.RefreshBankTabData
local IsBankContextDetected      = P.IsBankContextDetected
local IsBankInteractionType      = P.IsBankInteractionType
local IsPlayerBankInteractionActive = P.IsPlayerBankInteractionActive
local IsBankViewableByAPI        = P.IsBankViewableByAPI
local IsBankStorageAccessible    = P.IsBankStorageAccessible
local GetShownGlobalFrame        = P.GetShownGlobalFrame
local GetShownNamedFrameByPattern = P.GetShownNamedFrameByPattern
local IsGlobalFrameShown         = P.IsGlobalFrameShown
local ScheduleQuickAccessRefresh = P.ScheduleQuickAccessRefresh

-- ===========================================================================
-- Core.UpdateContext
-- Reads game state and updates ns.DB.context flags.
-- ===========================================================================

function Core.UpdateContext()
    local context = ns.DB.context
    context.bankOpen = UI.bankContextOpen or IsBankContextDetected()
    context.reagentBankOpen = IsGlobalFrameShown("ReagentBankFrame")
    context.vendorOpen = UI.vendorContextOpen or (IsGlobalFrameShown("MerchantFrame") and not UI.vendorContextClosed)
    context.auctionHouseOpen = IsGlobalFrameShown("AuctionHouseFrame")
    context.mailboxOpen = IsGlobalFrameShown("MailFrame")
    context.inCombat = InCombatLockdown() and true or false
    if context.bankOpen then
        UI.hadBankContext = true
    end
    if context.vendorOpen then
        UI.hadVendorContext = true
    end
end

-- ===========================================================================
-- Core.LogError + error handler
-- ===========================================================================

local ERROR_LOG_MAX = 50

function Core.LogError(msg)
    if not ns.DB then return end
    if not ns.DB.errorLog then ns.DB.errorLog = {} end
    local log = ns.DB.errorLog
    table.insert(log, { time = date("%Y-%m-%d %H:%M:%S"), msg = tostring(msg) })
    while #log > ERROR_LOG_MAX do table.remove(log, 1) end
end

do
    local _prevHandler = geterrorhandler()
    seterrorhandler(function(errMsg)
        if type(errMsg) == "string" and errMsg:find(ADDON_NAME, 1, true) then
            Core.LogError(errMsg)
        end
        if _prevHandler then return _prevHandler(errMsg) end
    end)
end

-- ===========================================================================
-- Slash commands
-- ===========================================================================

local function ToggleQuickAccessSetting(key, label)
    ns.DB.ui[key] = not ns.DB.ui[key]
    Core.UpdateQuickAccessButtons()
    Print(label .. ": " .. (ns.DB.ui[key] and "shown" or "hidden"))
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
    elseif cmd == "transfer" then
        Core.ShowTransferUI()
    elseif cmd == "move" then
        UI.transferSource = "Bags"
        UI.transferDest = STORAGE_ALL_BANK_TABS
        Core.ShowMoveUI()
    elseif cmd == "dump" then
        UI.transferSource = "Bags"
        UI.transferDest = STORAGE_ALL_BANK_TABS
        Core.SetExpansionFilterFromText(arg1)
        Core.ShowMoveUI()
    elseif cmd == "recall" then
        UI.transferSource = STORAGE_ALL_BANK_TABS
        UI.transferDest = "Bags"
        Core.SetExpansionFilterFromText(arg1)
        Core.ShowMoveUI()
    elseif cmd == "organize" or cmd == "organizer" then
        UI.transferSource = STORAGE_ALL_BANK_TABS
        UI.transferDest = "Bags"
        Core.ShowOrganizeUI()
    elseif cmd == "vendor" or cmd == "sell" then
        UI.transferSource = "Bags"
        UI.transferDest = "Vendor"
        Core.ShowVendorUI()
    elseif cmd == "settings" or cmd == "options" then
        Core.CreateUI()
        UI.activeTab = "Settings"
        UI.frame:Show()
        Core.RefreshUI()
    elseif cmd == "rules" or cmd == "config" or cmd == "protect" then
        Core.CreateUI()
        UI.activeTab = "Rules"
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
        if C_Container and C_Container.GetContainerNumFreeSlots then
            local parts = {}
            local allIDs = {}
            for _, ids in ipairs({ PRIVATE_BANK_IDS, REAGENT_BANK_IDS, WARBAND_BANK_IDS }) do
                for _, bagID in ipairs(ids or {}) do table.insert(allIDs, bagID) end
            end
            for _, bagID in ipairs(allIDs) do
                local ok, free = pcall(C_Container.GetContainerNumFreeSlots, bagID)
                table.insert(parts, tostring(bagID) .. "=" .. tostring(ok and free or "err"))
            end
            Print("FreeSlots: " .. table.concat(parts, ", "))
        end
        Print("=== ctx end ===")
    elseif cmd == "debug" then
        Debug.SetDebug(not Debug.IsDebugEnabled())
        Print("Debug mode: " .. (Debug.IsDebugEnabled() and "ON" or "OFF"))
    elseif cmd == "diag" then
        Debug.RunDiagnosticDump()
    elseif cmd == "errors" then
        local log = ns.DB and ns.DB.errorLog
        if not log or #log == 0 then
            Print("No errors logged for " .. ADDON_NAME .. ".")
        else
            Print(#log .. " error(s) logged (most recent first):")
            local start = math.max(1, #log - 9)
            for i = #log, start, -1 do
                local e = log[i]
                Print("[" .. (e.time or "?") .. "] " .. (e.msg or "?"))
            end
            if #log > 10 then
                Print("(showing 10 most recent of " .. #log .. " total; /icanteven clearerrors to wipe)")
            end
        end
    elseif cmd == "clearerrors" then
        if ns.DB then ns.DB.errorLog = {} end
        Print("Error log cleared.")
    else
        Print("Commands: /icanteven, scan [bags|bank|all], summary, transfer, move, dump, recall, organize, vendor, rules, settings, minimap, buttons, bankdiag, debug, diag, errors, clearerrors")
    end
end

-- ===========================================================================
-- Core.OnAddonLoaded
-- ===========================================================================

function Core.OnAddonLoaded()
    ICantEvenRightNowDB = SafeCopyDefaults(Data.DefaultDB, ICantEvenRightNowDB)
    ns.DB = ICantEvenRightNowDB
    MigrateLegacyTabFilters()
    SeedDefaultSavedFilters()
    ns.DB.ui.showBankButton = false
    ns.DB.ui.showVendorButton = false
    NormalizeLegacyBankStorageKinds(ns.DB.scans.bank)
    Core.RegisterSlashCommands()
    Core.UpdateContext()
    Core.UpdateQuickAccessButtons()
    ScheduleQuickAccessRefresh()
    Print("Loaded. Type /icanteven to open the cleanup console.")
end

-- ===========================================================================
-- Event frame
-- ===========================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("BANKFRAME_CLOSED")
eventFrame:RegisterEvent("BANK_TAB_SETTINGS_UPDATED")
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
        return
    end

    if not ns.DB or not ns.DB.context then return end

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

    -- Refresh dropdowns whenever bank or vendor context changes
    if bankContextOpened or bankContextClosed or vendorContextOpened or vendorContextClosed then
        Core.RefreshTransferDropdowns()
    end

    if ((bankContextClosed and UI.hadBankContext) or (vendorContextClosed and UI.hadVendorContext)) and UI.frame and UI.frame:IsShown() then
        UI.frame:Hide()
    end

    if bankContextClosed then UI.hadBankContext = false end
    if vendorContextClosed then UI.hadVendorContext = false end

    if bankContextOpened then
        RefreshBankTabData()
        Core.RefreshTransferDropdowns()
        pcall(Core.ScanInventory, "all", true)
    end

    if event == "BANK_TAB_SETTINGS_UPDATED" then
        RefreshBankTabData()
        Core.RefreshUI()
    end

    ScheduleQuickAccessRefresh()
end)
