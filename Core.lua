-- I Can't Even Right Now (With My Bags and Bank) Core Module
-- Main addon logic, event handlers, and UI management

local ADDON_NAME, ns = ...

-- Initialize namespace
ns.Core = {}
ns.DB = {}

-- Local references
local Data = ns.Data
local Debug = ns.Debug

-- Frame for event handling
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

-- Event handler
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == ADDON_NAME then
            ns.Core.OnAddonLoaded()
        end
    end
end)

-- Initialize addon on load
function ns.Core.OnAddonLoaded()
    -- Initialize saved variables
    if not ICantEvenRightNowDB then
        ICantEvenRightNowDB = CopyTable(Data.DefaultDB)
    end
    ns.DB = ICantEvenRightNowDB
    
    Debug.Print("I Can't Even Right Now (With My Bags and Bank) loaded successfully")
    
    -- Register slash commands
    ns.Core.RegisterSlashCommands()
end

-- Register slash commands
function ns.Core.RegisterSlashCommands()
    SLASH_ICANTEVEN1 = "/icanteven"
    SlashCmdList["ICANTEVEN"] = function(msg)
        ns.Core.HandleSlashCommand(msg)
    end
end

-- Handle slash command input
function ns.Core.HandleSlashCommand(msg)
    local cmd, arg1 = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    
    if cmd == "scan" then
        -- Scan bags/bank
        ns.Core.ScanInventory(arg1)
    elseif cmd == "summary" then
        -- Show summary UI
        ns.Core.ShowSummaryUI()
    elseif cmd == "debug" then
        -- Toggle debug mode
        Debug.SetDebug(not DEBUG_MODE)
        print("ICantEvenRightNow debug mode: " .. (DEBUG_MODE and "ON" or "OFF"))
    elseif cmd == "diag" then
        -- Run diagnostic
        Debug.RunDiagnosticDump()
    else
        -- Show help
        print("|cFF00FF00ICantEvenRightNow Commands:|r")
        print("  /icanteven scan [bags|bank] - Scan inventory")
        print("  /icanteven summary - Show summary UI")
        print("  /icanteven debug - Toggle debug mode")
        print("  /icanteven diag - Run diagnostic dump")
    end
end

-- Scan inventory (placeholder)
function ns.Core.ScanInventory(scope)
    Debug.Print("Scanning " .. (scope or "bags"))
    -- TODO: Implement inventory scanning logic
    print("Inventory scan not yet implemented")
end

-- Show summary UI (placeholder)
function ns.Core.ShowSummaryUI()
    Debug.Print("Showing summary UI")
    -- TODO: Implement summary UI
    print("Summary UI not yet implemented")
end

-- Update context (placeholder)
function ns.Core.UpdateContext()
    -- TODO: Implement context detection
    ns.DB.context.bankOpen = IsBankOpen()
    ns.DB.context.inCombat = InCombatLockdown()
end
