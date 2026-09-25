-- I Can't Even Right Now (With My Bags and Bank) — Warband Routing
-- Sends each item to the Warband tab whose own Blizzard "assign to" settings
-- (depositFlags) match it, so routing follows choices the player already made
-- in the game's bank tab settings. Never calls C_Bank.AutoDepositItemsIntoBank:
-- that bypasses item rules and the review step.

local ADDON_NAME, ns = ...

local Data = ns.Data
local P    = ns.Private

-- Enum.BagSlotFlags (verified 2026-09-25, warcraft.wiki.gg).
local FLAG = {
    Equipment      = 0x2,
    Consumables    = 0x4,
    ProfessionGoods = 0x8,
    Junk           = 0x10,
    QuestItems     = 0x20,
    Reagents       = 0x80,
    ExpansionCurrent = 0x100,
    ExpansionLegacy  = 0x200,
}
P.BAG_SLOT_FLAG = FLAG

local CATEGORY_FLAGS = { FLAG.Equipment, FLAG.Consumables, FLAG.ProfessionGoods, FLAG.Junk, FLAG.QuestItems, FLAG.Reagents }
local CATEGORY_LABEL = {
    [FLAG.Equipment] = "Equipment", [FLAG.Consumables] = "Consumables",
    [FLAG.ProfessionGoods] = "Profession Goods", [FLAG.Junk] = "Junk",
    [FLAG.QuestItems] = "Quest Items", [FLAG.Reagents] = "Reagents",
}

local function HasFlag(flags, flag)
    return bit.band(flags or 0, flag) ~= 0
end

-- The Blizzard category an item falls into (one flag), or nil.
local function ItemCategoryFlag(item)
    if item.quality == 0 then return FLAG.Junk end
    if item.classID == 12 or item.isQuestItem then return FLAG.QuestItems end
    if item.classID == 2 or item.classID == 4 then return FLAG.Equipment end
    if item.classID == 0 then return FLAG.Consumables end
    if item.classID == 7 then return FLAG.Reagents end
    -- Recipes (9) and profession tools/equipment (19).
    if item.classID == 9 or item.classID == 19 then return FLAG.ProfessionGoods end
    return nil
end
P.ItemCategoryFlag = ItemCategoryFlag

local function TabCategoryFlags(tab)
    local list = {}
    for _, flag in ipairs(CATEGORY_FLAGS) do
        if HasFlag(tab.flags, flag) then table.insert(list, flag) end
    end
    return list
end

-- Score a tab for an item: nil if the tab's settings exclude it.
-- 3 = category and expansion both match, 2 = category matches,
-- 1 = general tab (no category settings) that allows the item's expansion.
local function ScoreTab(tab, item)
    local wantsCurrent = HasFlag(tab.flags, FLAG.ExpansionCurrent)
    local wantsLegacy = HasFlag(tab.flags, FLAG.ExpansionLegacy)
    local expansionMatch = nil
    if wantsCurrent or wantsLegacy then
        local isOld = P.IsOldExpansion(item.expansionID)
        local ok = (isOld and wantsLegacy) or ((not isOld) and wantsCurrent)
        if not ok then return nil end
        expansionMatch = true
    end
    local categories = TabCategoryFlags(tab)
    if #categories == 0 then
        return expansionMatch and 1.5 or 1, nil
    end
    local itemFlag = ItemCategoryFlag(item)
    for _, flag in ipairs(categories) do
        if flag == itemFlag then
            return expansionMatch and 3 or 2, CATEGORY_LABEL[flag]
        end
    end
    return nil
end

-- Returns { bagID, tab, reason } for the best Warband tab, or nil with a reason.
local function RouteToWarbandTab(item)
    local tabs = P.GetWarbandTabs()
    if #tabs == 0 then return nil, "No Warband tabs are known yet: visit a bank" end
    local best, bestScore, bestLabel
    for _, tab in ipairs(tabs) do
        local score, label = ScoreTab(tab, item)
        if score and (not bestScore or score > bestScore) then
            best, bestScore, bestLabel = tab, score, label
        end
    end
    if not best then return nil, "No Warband tab accepts this item (check the tabs' settings)" end
    local tabName = best.name ~= "" and best.name or ("Tab " .. tostring(best.bagID - 11))
    local reason
    if bestLabel then
        reason = tabName .. " (accepts " .. bestLabel .. ")"
    else
        reason = tabName .. " (general tab)"
    end
    return { bagID = best.bagID, tab = best, reason = reason }
end
P.RouteToWarbandTab = RouteToWarbandTab

-- True when no known Warband tab has any "assign to" settings.
function P.WarbandTabsHaveNoSettings()
    local tabs = P.GetWarbandTabs()
    if #tabs == 0 then return false end
    for _, tab in ipairs(tabs) do
        if #TabCategoryFlags(tab) > 0 or HasFlag(tab.flags, FLAG.ExpansionCurrent)
            or HasFlag(tab.flags, FLAG.ExpansionLegacy) then
            return false
        end
    end
    return true
end

-- ===========================================================================
-- Alt hand-off queue (W4)
-- Mark an item "for Alt B" on any character; it travels through the normal
-- Warband deposit; on Alt B a "Waiting for You" task collects it. The queue
-- only records intent: every move is still reviewed and clicked.
--   entry = { id, itemID, name, count, from, to, at, state = "queued" | "deposited" }
-- ===========================================================================

local HANDOFF_REMIND_DAYS = 14

local function Queue()
    ns.DB.handoff = ns.DB.handoff or { nextID = 1, entries = {} }
    return ns.DB.handoff
end

local function Now() return time and time() or 0 end

-- Characters who can receive this item, by role and usability.
function P.HandoffRecipients(item)
    local list = {}
    local currentKey = P.currentCharacterKey
    local isGear = P.IsGearItem and P.IsGearItem(item)
    local capability = isGear and "receivesGear" or "receivesMaterials"
    for _, char in ipairs(P.CharactersWith(capability)) do
        if char.key ~= currentKey then
            local ok = true
            if isGear then
                ok = P.CanCharacterUse(char, item, P.GetRole(char) == "leveling")
            end
            if ok then table.insert(list, char) end
        end
    end
    -- Materials: prefer characters whose professions use it.
    if not isGear and item.classID == 7 and P.CraftersFor then
        local users = {}
        for _, use in ipairs(P.CraftersFor(item) or {}) do users[use.character.key] = true end
        table.sort(list, function(a, b)
            if (users[a.key] or false) ~= (users[b.key] or false) then return users[a.key] and true or false end
            return a.key < b.key
        end)
    end
    return list
end

function P.QueueHandoff(item, toKey)
    if item.accountBankAllowed == false then return false, "Not eligible for Warband Bank" end
    local queue = Queue()
    for _, entry in ipairs(queue.entries) do
        if entry.itemID == item.itemID and entry.to == toKey and entry.from == P.currentCharacterKey then
            return true
        end
    end
    table.insert(queue.entries, {
        id = queue.nextID, itemID = item.itemID, name = item.name, count = item.count or 1,
        from = P.currentCharacterKey, to = toKey, at = Now(), state = "queued",
    })
    queue.nextID = queue.nextID + 1
    P.Log("handoff", "queued %s (%s) x%s from %s to %s", item.name, item.itemID, item.count or 1,
        P.currentCharacterKey, toKey)
    if P.RequestBetterBagsRefresh then P.RequestBetterBagsRefresh() end
    return true
end

function P.CancelHandoff(id)
    local queue = Queue()
    for i, entry in ipairs(queue.entries) do
        if entry.id == id then
            table.remove(queue.entries, i)
            if P.RequestBetterBagsRefresh then P.RequestBetterBagsRefresh() end
            return true
        end
    end
    return false
end

function P.GetHandoffs(filter)
    local list = {}
    for _, entry in ipairs(Queue().entries) do
        if not filter or filter(entry) then table.insert(list, entry) end
    end
    return list
end

local function QueuedFromMe(itemID)
    for _, entry in ipairs(Queue().entries) do
        if entry.itemID == itemID and entry.from == P.currentCharacterKey and entry.state == "queued" then return entry end
    end
end

local function WaitingForMe(itemID)
    for _, entry in ipairs(Queue().entries) do
        if entry.itemID == itemID and entry.to == P.currentCharacterKey and entry.state == "deposited" then return entry end
    end
end
P.HandoffQueuedFromMe = QueuedFromMe
P.HandoffWaitingForMe = WaitingForMe

-- Called after a successful move (Transfer.lua).
function P.OnItemMoved(item, dest)
    if P.IsWarbandStorage(dest) then
        local entry = QueuedFromMe(item.itemID)
        if entry then
            entry.state = "deposited"
            entry.depositedAt = Now()
        end
    elseif dest == "Bags" and item.storageKind == P.STORAGE_WARBAND_BANK then
        local entry = WaitingForMe(item.itemID)
        if entry then P.CancelHandoff(entry.id) end
    end
end

-- Drop entries whose items are gone (sold, withdrawn elsewhere). Runs after scans.
function P.CleanupHandoffs()
    local warbandIDs = {}
    for _, item in ipairs(P.GetWarbandSnapshot().items or {}) do warbandIDs[item.itemID] = true end
    local mine = {}
    for _, scope in ipairs({ P.BAG_SCOPE, P.BANK_SCOPE }) do
        for _, item in ipairs(P.GetScanList(scope)) do mine[item.itemID] = true end
    end
    local warbandScanned = (P.GetWarbandSnapshot().scannedAt or 0) > 0
    local kept = {}
    for _, entry in ipairs(Queue().entries) do
        local keep = true
        if entry.state == "deposited" and warbandScanned and not warbandIDs[entry.itemID] then
            keep = false            -- taken out of the Warband bank elsewhere
        elseif entry.state == "queued" and entry.from == P.currentCharacterKey and not mine[entry.itemID] then
            keep = false            -- sender no longer has it
        end
        if keep then table.insert(kept, entry) end
    end
    Queue().entries = kept
end

function P.RegisterHandoffTasks()
    if not P.RegisterTask then return end
    P.RegisterTask({
        name = "Send to Alts",
        description = "Items you marked for another character, into the Warband bank.",
        preset = { name = "Send to Alts", source = "Bags", dest = P.STORAGE_WARBAND_ROUTED,
            expansion = 0, bind = "All", type = "All", slot = "All", armorType = "All", upgrade = "All",
            hideBlocked = false, sort = "Name" },
        predicate = function(item) return QueuedFromMe(item.itemID) ~= nil end,
        isAvailable = function() return #P.GetHandoffs(function(e) return e.from == P.currentCharacterKey and e.state == "queued" end) > 0 end,
    })
    P.RegisterTask({
        name = "Waiting for You",
        description = "Items your other characters sent to this one through the Warband bank.",
        preset = { name = "Waiting for You", source = P.STORAGE_WARBAND_BANK, dest = "Bags",
            expansion = 0, bind = "All", type = "All", slot = "All", armorType = "All", upgrade = "All",
            hideBlocked = false, sort = "Name" },
        predicate = function(item) return WaitingForMe(item.itemID) ~= nil end,
        isAvailable = function() return #P.GetHandoffs(function(e) return e.to == P.currentCharacterKey and e.state == "deposited" end) > 0 end,
    })
end

-- Sender-side reminder for hand-offs nobody collected (registered by HomeUI.lua).
function P.RegisterHandoffNotice()
    P.RegisterHomeNotice(function()
        local stale = {}
        for _, entry in ipairs(Queue().entries) do
            if entry.from == P.currentCharacterKey and entry.state == "deposited"
                and (Now() - (entry.depositedAt or entry.at)) > HANDOFF_REMIND_DAYS * 86400 then
                table.insert(stale, entry)
            end
        end
        if #stale == 0 then return nil end
        local recipient = P.GetCharacter(stale[1].to)
        local days = math.floor((Now() - (stale[1].depositedAt or stale[1].at)) / 86400)
        return {
            id = "handoff-reminder", priority = 70,
            text = #stale .. " item" .. (#stale == 1 and " has" or "s have") .. " been waiting for "
                .. (recipient and recipient.name or "another character") .. " for " .. days .. " days.",
            buttons = { { label = "Cancel them", onClick = function()
                for _, entry in ipairs(stale) do P.CancelHandoff(entry.id) end
                ns.Core.RefreshUI()
            end } },
        }
    end)
end