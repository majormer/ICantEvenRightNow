-- I Can't Even Right Now (With My Bags and Bank) Debug Module
-- Provides debugging utilities and diagnostic output

local ns = select(2, ...)
ns.Debug = {}

-- Debug flag
local DEBUG_MODE = false

-- Enable/disable debug mode
function ns.Debug.SetDebug(enabled)
    DEBUG_MODE = enabled
end

-- Debug print function
function ns.Debug.Print(...)
    if DEBUG_MODE then
        print("|cFF00FF00ICantEvenRightNow Debug:|r", ...)
    end
end

-- Dump table contents for debugging
function ns.Debug.DumpTable(t, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)
    
    for k, v in pairs(t) do
        if type(v) == "table" then
            ns.Debug.Print(prefix .. tostring(k) .. " = {")
            ns.Debug.DumpTable(v, indent + 1)
            ns.Debug.Print(prefix .. "}")
        else
            ns.Debug.Print(prefix .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

-- Run full diagnostic dump
function ns.Debug.RunDiagnosticDump()
    ns.Debug.Print("=== ICantEvenRightNow Diagnostic Dump ===")
    ns.Debug.Print("Addon Version: " .. GetAddOnMetadata("ICantEvenRightNow", "Version"))
    ns.Debug.Print("Game Version: " .. GetBuildInfo())
    ns.Debug.Print("Player Name: " .. UnitName("player"))
    ns.Debug.Print("Player Class: " .. UnitClass("player"))
    
    if ns.Data and ns.Data.DefaultDB then
        ns.Debug.Print("Database structure verified")
    else
        ns.Debug.Print("ERROR: Database structure not initialized")
    end
    
    ns.Debug.Print("=== End Diagnostic Dump ===")
end
