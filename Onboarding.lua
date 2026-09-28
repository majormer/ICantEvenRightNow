-- I Can't Even Right Now (With My Bags and Bank) — Onboarding
-- No required setup; at most one question per character; every answer makes
-- the next character easier. This file adds the Home notices that make that
-- true over time: What's New for upgraders, first-time tips, a welcome back
-- for returning characters, the max-level role check, and the Warband tab
-- settings hint. Every notice is dismissible and never blocks anything.

local ADDON_NAME, ns = ...

local Core = ns.Core
local P    = ns.Private

local UI = P.UI
local DAY = 24 * 3600
local WELCOME_BACK_DAYS = 7
local VERSION = "0.6.0"

local function Now() return time and time() or 0 end

-- ---------------------------------------------------------------------------
-- Tips (O5): shown once per account, when their moment happens.
-- ---------------------------------------------------------------------------

local TIPS = {
    first_bank    = "Tip: tasks find items for you. Open one, review the list, then click Deposit. Nothing moves without your click.",
    first_review  = "Tip: blocked rows say why. Use +Rule > Protect to keep an item untouched for good.",
    first_vendor  = "Tip: selling happens 12 at a time, so every sale stays in the vendor's buyback.",
    first_warband = "Tip: items go to the Warband tab whose Blizzard settings match them.",
}
P.TIPS = TIPS

local function TipsEnabled()
    return ns.DB.ui.tipsEnabled ~= false
end

-- Returns the tip text the first time it is asked for (per account), else nil.
function P.ConsumeTip(id)
    if not TipsEnabled() or not TIPS[id] then return nil end
    ns.DB.tipsSeen = ns.DB.tipsSeen or {}
    if ns.DB.tipsSeen[id] then return nil end
    ns.DB.tipsSeen[id] = Now()
    return TIPS[id]
end

function P.ResetTips()
    ns.DB.tipsSeen = {}
end

-- The first-bank tip is a Home notice until dismissed.
P.RegisterHomeNotice(function()
    if not TipsEnabled() or not ns.DB.context.bankOpen then return nil end
    ns.DB.tipsSeen = ns.DB.tipsSeen or {}
    if ns.DB.tipsSeen.first_bank then return nil end
    return {
        id = "tip-first-bank", priority = 30, text = TIPS.first_bank,
        buttons = { { label = "Got it", onClick = function()
            ns.DB.tipsSeen.first_bank = Now()
            Core.RefreshUI()
        end } },
    }
end)

-- Transfer view tips: picked once per moment and kept for this session.
function P.TransferTipFor(source, dest, hasRows)
    if UI.transferTip then return UI.transferTip end
    local tip
    if dest == "Vendor" then
        tip = P.ConsumeTip("first_vendor")
    elseif dest == P.STORAGE_WARBAND_ROUTED then
        tip = P.ConsumeTip("first_warband")
    elseif hasRows then
        tip = P.ConsumeTip("first_review")
    end
    UI.transferTip = tip
    return tip
end

-- ---------------------------------------------------------------------------
-- What's New in 0.6.0 (O5 + M3): once, for players upgrading from earlier.
-- ---------------------------------------------------------------------------

local WHATS_NEW = {
    "Home: every task is a card with a live count; click one to review and act.",
    "Characters: give each character a role so the addon knows who benefits.",
    "Warband: each tab is a destination, and \"Deposit to Warband\" follows your tabs' settings.",
    "Why is this here?: rows and /icanteven why explain why items are kept.",
    "Alts: send items to a specific character; they see \"Waiting for You\".",
    "Selling stops at 12 per click so every sale stays in buyback.",
}
P.WHATS_NEW = WHATS_NEW

local function IsUpgrader()
    return ns.DB.migrationReports ~= nil and #ns.DB.migrationReports > 0
end

P.RegisterHomeNotice(function()
    if not IsUpgrader() or (ns.DB.whatsNewSeen == VERSION) then return nil end
    local report = P.LatestMigrationReport()
    local ported = report and report.ported or {}
    local attention = report and ((#(report.notPorted or {})) + (#(report.converted or {}))) or 0
    local text = "What's new in " .. VERSION .. ": tasks are cards on Home, roles on the Characters tab, "
        .. "Warband tab routing, and \"Why is this here?\". Your settings carried over ("
        .. (ported.rules or 0) .. " rules, " .. (ported.tasks or 0) .. " saved tasks)."
    if attention > 0 then
        text = text .. " " .. attention .. " note" .. (attention == 1 and "" or "s") .. " about the upgrade."
    end
    return {
        id = "whats-new", priority = 10, text = text,
        buttons = {
            { label = "Details", onClick = function()
                P.Print("What's new in " .. VERSION .. ":")
                for _, line in ipairs(WHATS_NEW) do P.Print("  " .. line) end
                for _, line in ipairs(P.MigrationReportLines(report)) do P.Print(line) end
            end },
            { label = "Got it", style = "primary", onClick = function()
                ns.DB.whatsNewSeen = VERSION
                if report then report.seen = true end
                Core.RefreshUI()
            end },
        },
    }
end)

-- ---------------------------------------------------------------------------
-- Welcome back (O3 day 30) and the max-level role check.
-- ---------------------------------------------------------------------------

-- Called by Characters.lua before lastSeen is refreshed.
function P.NoteReturn(char, previousSeen)
    if previousSeen and (Now() - previousSeen) >= WELCOME_BACK_DAYS * DAY then
        char.returnedFrom = previousSeen
        char.welcomeBackDismissed = nil
    end
end

P.RegisterHomeNotice(function()
    local char = P.GetCurrentCharacter()
    if not char.returnedFrom or char.welcomeBackDismissed then return nil end
    local days = math.floor((Now() - char.returnedFrom) / DAY)
    local parts = { "Welcome back after " .. days .. " days." }
    local waiting = P.GetHandoffs and #P.GetHandoffs(function(e)
        return e.to == char.key and e.state == "deposited"
    end) or 0
    if waiting > 0 then parts[#parts + 1] = waiting .. " item" .. (waiting == 1 and " is" or "s are") .. " waiting for you." end
    if (char.lastScan.bank or 0) > 0 then
        parts[#parts + 1] = "Your bank list is " .. math.floor((Now() - char.lastScan.bank) / DAY) .. " days old; visit a bank to refresh it."
    end
    return {
        id = "welcome-back", priority = 15, text = table.concat(parts, " "),
        buttons = { { label = "OK", onClick = function()
            char.welcomeBackDismissed = true
            Core.RefreshUI()
        end } },
    }
end)

P.RegisterHomeNotice(function()
    local char = P.GetCurrentCharacter()
    if P.GetRole(char) ~= "leveling" or char.maxLevelPromptDismissed then return nil end
    if (char.level or 0) < P.GetMaxPlayerLevel() then return nil end
    return {
        id = "max-level", priority = 16,
        text = (char.name or "This character") .. " reached max level. Switch from Leveling to Main / Active?",
        buttons = {
            { label = "Switch to Main", style = "primary", onClick = function()
                P.SetCharacterRole(char.key, "main")
                Core.RefreshUI()
            end },
            { label = "Keep Leveling", onClick = function()
                char.maxLevelPromptDismissed = true
                Core.RefreshUI()
            end },
        },
    }
end)

-- ---------------------------------------------------------------------------
-- In-context opt-ins (O4)
-- ---------------------------------------------------------------------------

P.RegisterHomeNotice(function()
    if not ns.DB.context.bankOpen or ns.DB.ui.warbandSettingsHintDismissed then return nil end
    if not P.WarbandTabsHaveNoSettings() then return nil end
    return {
        id = "warband-settings", priority = 75,
        text = "Your Warband tabs have no \"assign to\" settings. Set them in the bank's tab settings and "
            .. "\"Deposit to Warband\" will sort items into the right tab. The addon never changes them for you.",
        buttons = { { label = "Got it", onClick = function()
            ns.DB.ui.warbandSettingsHintDismissed = true
            Core.RefreshUI()
        end } },
    }
end)
