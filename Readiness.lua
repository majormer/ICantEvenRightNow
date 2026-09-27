-- I Can't Even Right Now (With My Bags and Bank) — Readiness
-- Stable results instead of live-changing ones. After a reload or when a
-- bank, vendor or auction house opens, the addon first waits for the data
-- its verdicts depend on (item info, gear stats, appearance collection), at
-- most SETTLE_LIMIT seconds. Meanwhile Home, the notice and task lists say
-- "Getting ready..." and show no counts or actions. After that, numbers only
-- change because of something the player did; data arriving late is flagged
-- ("Rescan to include them") instead of changing what's on screen.
-- Player's rule (2026-09-26): don't show counts that change as data trickles in.

local ADDON_NAME, ns = ...

local P = ns.Private

-- Below the 10 s per-item limit in Reasons.lua, so items still waiting are
-- counted as "couldn't be checked" instead of silently judged without stats.
local SETTLE_LIMIT = 8
local TICK = 0.5

local state = { settling = false, pending = 0, startedAt = 0, noticeWanted = false, lateData = false, unresolved = 0 }
P.ReadinessState = state

local function Now() return GetTime and GetTime() or 0 end

-- Why an item's verdict could still change (nil when it can't): its details
-- or stats are loading (ItemData.lua), or the scan hasn't described it yet.
local function PendingReason(item)
    if not item or not item.itemID then return nil end
    local state = P.ItemDataState(item)
    if state == "loading" then return "item details" end
    if state ~= "ready" then return nil end
    if item.classID == nil then return "the next scan" end
    if item.bindingPending then return "binding" end
    if P.IsGearItem and P.IsGearItem(item) and P.RolesAssigned and P.RolesAssigned()
        and P.ItemTooltipFacts and P.ItemTooltipFacts(item).state == "loading" then
        return "tooltip"
    end
    if P.IsGearItem and P.IsGearItem(item) and P.RolesAssigned and P.RolesAssigned()
        and P.GearDetailsState and P.GearDetailsState(item) == "pending" then
        return "stats"
    end
    return nil
end

function P.ItemDataPending(item)
    local why = PendingReason(item)
    return why ~= nil, why
end

-- Pending, or given up on: counted as "couldn't be checked".
local function UnresolvedReason(item)
    local why = PendingReason(item)
    if why then return why end
    if P.ItemDataState(item) == "failed" then return "item details (gave up)" end
    if P.IsGearItem and P.IsGearItem(item) and P.RolesAssigned and P.RolesAssigned()
        and P.GearDetailsState and P.GearDetailsState(item) == "failed" then
        return "stats (gave up)"
    end
    return nil
end

-- Items this character can act on here: bags, bank, and the Warband bank.
local function RelevantItems()
    local list = {}
    local currentKey = P.currentCharacterKey
    for _, snapshot in ipairs(P.AllSnapshots and P.AllSnapshots() or {}) do
        local relevant = snapshot.scope == "warband" or (snapshot.character and snapshot.character.key == currentKey)
        if relevant then
            for _, item in ipairs(snapshot.items or {}) do list[#list + 1] = item end
        end
    end
    return list
end

local function CountPending()
    local n = 0
    for _, item in ipairs(RelevantItems()) do
        if P.ItemDataPending(item) then n = n + 1 end
    end
    return n
end

function P.IsSettling() return state.settling end

-- One line for headers and footers, or nil when there's nothing to say.
function P.ReadinessText()
    if state.settling then
        if state.pending == 0 then return "Getting ready..." end
        return "Getting ready... checking " .. state.pending .. " item" .. (state.pending == 1 and "" or "s")
    end
    if state.lateData then
        return "Some item details arrived after checking: Rescan to include them"
    end
    if state.unresolved > 0 then
        return state.unresolved .. " item" .. (state.unresolved == 1 and "" or "s") .. " couldn't be checked"
    end
    return nil
end

local function Refresh()
    if P.UI.frame and P.UI.frame:IsShown() and ns.Core.RefreshUI then ns.Core.RefreshUI() end
end

-- Update only the lines that say how far along it is (no recount of cards
-- or lists: those stay "Getting ready..." until Finish).
local function UpdateTexts()
    if P.RefreshHomeHeader then pcall(P.RefreshHomeHeader) end
    if P.RefreshTransferFooter then pcall(P.RefreshTransferFooter) end
    if state.noticeWanted and P.ShowGettingReadyNotice then pcall(P.ShowGettingReadyNotice, P.ReadinessText()) end
end

local function Finish()
    state.settling = false
    local unresolved = {}
    for _, item in ipairs(RelevantItems()) do
        local why = UnresolvedReason(item)
        if why then unresolved[#unresolved + 1] = { item = item, why = why } end
    end
    state.unresolved = #unresolved
    P.Log("ready", "settled after %.1fs (%s): %d item(s) could not be checked",
        Now() - state.startedAt, tostring(state.reason), state.unresolved)
    for _, entry in ipairs(unresolved) do
        P.Log("ready", "  not checked: %s (%s): waiting for %s",
            tostring(entry.item.name), tostring(entry.item.itemID), entry.why)
    end
    Refresh()
    if state.noticeWanted then
        state.noticeWanted = false
        if P.ShowContextNotice then pcall(P.ShowContextNotice) end
    end
end

local ticking = false
local function Tick()
    if not state.settling then ticking = false return end
    state.pending = CountPending()
    if state.pending == 0 or Now() - state.startedAt >= SETTLE_LIMIT then
        ticking = false
        Finish()
        return
    end
    UpdateTexts()
    C_Timer.After(TICK, Tick)
end

-- Start (or restart) the getting-ready phase. `wantsNotice`: show the
-- bank/vendor/AH notice once settled.
function P.BeginSettling(reason, wantsNotice)
    state.settling = true
    state.startedAt = Now()
    state.reason = reason
    state.lateData = false
    state.unresolved = 0
    if wantsNotice then state.noticeWanted = true end
    -- Ask for everything up front.
    if P.PrefetchGearDetails then pcall(P.PrefetchGearDetails) end
    state.pending = CountPending()
    P.Log("ready", "getting ready (%s): %d item(s) to check", tostring(reason), state.pending)
    Refresh()
    UpdateTexts()
    if not ticking then
        ticking = true
        if C_Timer then C_Timer.After(0, Tick) else Tick() end
    end
end

-- Data arrived for an item after settling: flag it instead of changing the screen.
function P.NoteLateData()
    if state.settling or state.lateData then return end
    state.lateData = true
    P.Log("ready", "item details arrived after checking: flagged for Rescan")
    if P.RefreshHomeHeader then pcall(P.RefreshHomeHeader) end
    if P.RefreshTransferFooter then pcall(P.RefreshTransferFooter) end
end

-- The player asked to include late data (Rescan).
function P.ClearLateData()
    state.lateData = false
    state.unresolved = 0
    if P.RetryFailedItemData then P.RetryFailedItemData() end
end
