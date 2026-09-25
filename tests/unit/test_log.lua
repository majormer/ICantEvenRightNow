local T = ...
local F = require("fixtures")
local I = F.ITEMS

local PLAYER = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" }

local function newGame(populate)
    return T.game({ player = PLAYER, setup = F.setup(populate or function(w) w:put(0, 1, I.JUNK, 1) end) })
end

local function logText(g) return table.concat(g:P().GetLogLines(), "\n") end

T.test("logging is off by default and records nothing", function()
    local g = newGame()
    g:Core().ScanInventory("bags", true)
    T.eq(g:db().ui.enhancedLogging, false)
    T.eq(#g:P().GetLogLines(), 0)
end)

T.test("when on, scans, context changes, and sales are recorded", function()
    local g = newGame()
    g:slash("log on")
    g:Core().ScanInventory("bags", true)
    g:openVendor()
    g:Core().ShowHomeUI()
    local P, UI = g:P(), g:UI()
    P.OpenTask("Sell Items That Can Go")
    for _, plan in ipairs(UI.transferVisible) do UI.transferSelected[plan.key] = true end
    g.world:withHardwareEvent(function() g:Core().ExecuteTransferSelected() end)
    local text = logText(g)
    T.contains(text, "[log] enhanced logging on")
    T.contains(text, "[scan] bags")
    T.contains(text, "[context] bank=false")
    T.contains(text, "vendor=true")
    T.contains(text, "[task] open Sell Items That Can Go")
    T.contains(text, "[transfer] sell Broken Tusk x1")
    T.contains(text, "[transfer] done Bags -> Vendor: 1 sold")
end)

T.test("the log is a bounded ring buffer, oldest dropped first", function()
    local g = newGame()
    local P = g:P()
    P.SetLogging(true)
    P.ClearLog()
    for i = 1, P.LOG_MAX_LINES + 5 do P.Log("test", "line %d", i) end
    local lines = P.GetLogLines()
    T.eq(#lines, P.LOG_MAX_LINES)
    T.contains(lines[1], "line 6")
    T.contains(lines[#lines], "line " .. (P.LOG_MAX_LINES + 5))
    T.eq(#P.GetLogLines(3), 3)
end)

T.test("log survives a reload and can be cleared", function()
    local g = newGame()
    g:slash("log on")
    g:P().Log("test", "keep me")
    local saved = g:logout()
    local g2 = T.game({ player = PLAYER, savedVariables = saved, setup = F.setup() })
    T.contains(logText(g2), "keep me")
    g2:slash("log clear")
    T.eq(#g2:P().GetLogLines(), 0)
end)

T.test("errors are logged, and the settings checkbox toggles logging", function()
    local g = newGame()
    g:slash("log on")
    g:Core().LogError("something broke")
    T.contains(logText(g), "[error] something broke")
    g:slash("log off")
    g:P().Log("test", "not recorded")
    T.notContains(logText(g), "not recorded")
end)

T.test("the Settings checkbox turns logging on", function()
    local g = newGame()
    g:Core().CreateUI()
    g:slash("settings")
    local check
    for _, c in ipairs(g:UI().frame.panels.Settings.workflowChecks) do
        if c.settingKey == "enhancedLogging" then check = c end
    end
    T.ok(check, "checkbox exists")
    g:click(check)
    T.eq(g:db().ui.enhancedLogging, true)
    T.contains(logText(g), "enhanced logging on")
end)
