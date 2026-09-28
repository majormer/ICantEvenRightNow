-- I Can't Even Right Now (With My Bags and Bank) — Tasks
-- The model behind the Home screen: every quick task and saved task becomes a
-- card with a live count, value, and availability for the current context.
-- Counting never changes the player's Transfer filters or sort.

local ADDON_NAME, ns = ...

local Core = ns.Core
local Data = ns.Data
local P    = ns.Private

local UI = P.UI

local STORAGE_ALL_BANK_TABS = P.STORAGE_ALL_BANK_TABS
local SCRATCH_TAB = "__taskCount"

-- Block reasons that only mean "go somewhere first"; such items still count
-- as waiting work on a card.
local CONTEXT_BLOCKS = {
    ["Bank is not open"] = "Visit a bank",
    ["Vendor is not open"] = "Visit a vendor",
    ["Auction house is not open"] = "Visit the auction house",
    ["In combat"] = "Leave combat",
}

-- ---------------------------------------------------------------------------
-- Built-in task extras: descriptions and item predicates
-- ---------------------------------------------------------------------------

-- Items another character benefits from sharing (the Warband principle):
-- Warbound items, unbound BoE gear, and materials a different character's
-- crafting role uses. Everyday items this character uses stay out.
local function IsShareable(item)
    if item.accountBankAllowed == false then return false end
    if item.isWarbandBound or item.bindingScope == "Warbound" or item.bindingScope == "Warbound Until Equipped" then
        return true
    end
    if item.bindingScope == "BoE" and (item.classID == 2 or item.classID == 4) and not item.isBound then
        return true
    end
    if item.classID == 7 and P.CraftersFor then
        local currentKey = P.currentCharacterKey
        for _, use in ipairs(P.CraftersFor(item) or {}) do
            if use.character.key ~= currentKey then return true end
        end
    end
    -- Housing items: the house belongs to the whole account (in game,
    -- Kiosk's 30 housing dyes, kept "in Warband" by the player, were never
    -- offered: they are unbound and neither gear nor a material).
    if item.classID == 20 then return true end
    -- A Utility character (bank or auction alt) keeps nothing for itself:
    -- whatever it keeps belongs where the others can reach it.
    local char = P.GetCurrentCharacter and P.GetCurrentCharacter()
    if char and P.GetRole and P.GetRole(char) == "utility" and item.accountBankAllowed ~= false then
        return true
    end
    return false
end
P.IsShareableItem = IsShareable

-- Would Deposit to Warband take this item (a Warband tab exists, another
-- character benefits, the addon keeps it, and it isn't this character's
-- upgrade or own current supplies)? Read through TASK_EXTRAS at call time.
function P.WantsWarbandBank(item)
    if P.WarbandTabsPurchased and P.WarbandTabsPurchased() == 0 then return false end
    local extra = P.TASK_EXTRAS and P.TASK_EXTRAS["Deposit to Warband"]
    return extra and extra.predicate and extra.predicate(item) and true or false
end

-- Items headed out of storage don't get banked: auction candidates (in game,
-- right after pulling them this offered to deposit them again), "Can go"
-- items (Pull Items That Can Go takes them back out), and items for a quest
-- in progress (offered for the bank once).
local function IsHeadedOut(item)
    if P.IsAuctionCandidate and P.IsAuctionCandidate(item) then return true end
    if not P.ExplainScanned then return false end
    local explanation = P.ExplainScanned(item)
    for _, reason in ipairs(explanation.reasons or {}) do
        if reason.id == "quest_active" then return true end
        -- Needs the player's attention first (a refused or run-out decision):
        -- depositing it would hide the question (8 refused legendaries, 2026-09-28).
        if reason.id == "decision_blocked" or reason.id == "decision_due" or reason.id == "decision_lapsed" then return true end
        -- Stays in the bags (utility items the player uses: Jeeves).
        local def = P.REASONS and P.REASONS[reason.id]
        if def and def.bags then return true end
    end
    return explanation.disposition == "free"
end
P.IsHeadedOut = IsHeadedOut

local TASK_EXTRAS = {
    ["Deposit Old Items"] = {
        description = "Old-expansion items from your bags into the bank.",
        -- Nothing Deposit to Warband wants: in game (Dorftastic, 2026-09-28)
        -- both cards offered the same crafting materials and alt gear, one
        -- to the character bank, the other to the Warband bank.
        predicate = function(item)
            if IsHeadedOut(item) then return false end
            -- Never gear this character should equip: in game (Gnomurcy,
            -- 2026-09-28) it banked two upgrades that Pull Bank Upgrades
            -- then offered straight back.
            if P.IsUpgradeForPlayer and P.IsUpgradeForPlayer(item) then return false end
            return not (P.WantsWarbandBank and P.WantsWarbandBank(item))
        end,
    },
    ["Pull Bank Upgrades"] = {
        description = "Gear in your bank or the Warband bank that beats what you're wearing.",
        -- Reads whichever bank holds more upgrades. In game, Minormer's Home
        -- said "Nothing to do" while the Warband bank held 14 pieces his main
        -- had parked there for him: the preset only read the character bank.
        presetFor = function(preset)
            local warband = P.WithPresetSource(preset, P.STORAGE_WARBAND_BANK)
            local inBank = #P.GetTaskPlans({ preset = preset })
            local inWarband = #P.GetTaskPlans({ preset = warband })
            if inWarband > inBank then return warband end
            return preset
        end,
    },
    ["Pull Auctionable BoEs"] = {
        description = "Bind-on-equip gear to list on the auction house.",
        -- Only BoEs that can go: in game (Glowheart, 2026-09-28) it pulled
        -- back a "your call" greatsword Deposit Old Items had just banked.
        predicate = function(item)
            local channels = P.ItemChannels and P.ItemChannels(item)
            if channels and not channels.auction then return false end
            if P.IsAuctionCandidate and P.IsAuctionCandidate(item) then return true end
            return P.ExplainScanned and P.ExplainScanned(item).disposition == "free" or false
        end,
    },
    ["Sell Old Consumables"] = {
        description = "Potions, food, and flasks from past expansions.",
        -- Never an item the addon says to keep (in game it offered Swapblaster,
        -- a utility gadget that shares the consumable item class).
        predicate = function(item)
            if not P.ExplainScanned then return true end
            return P.ExplainScanned(item).disposition ~= "keep"
        end,
    },
    ["Deposit to Warband"] = {
        description = "Items your other characters can use, sorted into Warband tabs by their settings.",
        -- Only items worth keeping: in game this also offered appearance-
        -- collected gear nobody can use, which moves clutter instead of
        -- clearing it. "Can go" and "Your call" items stay out.
        predicate = function(item)
            if not IsShareable(item) then return false end
            -- Never gear this character should equip: in game, Minormer's 16
            -- freshly withdrawn upgrades were offered straight back.
            if P.IsUpgradeForPlayer and P.IsUpgradeForPlayer(item) then return false end
            -- Nor a played character's own supplies: current-expansion
            -- consumables stay in the bags of a Main or Leveling character
            -- (in game it offered Minormer's 25 Potent Healing Potions; the
            -- player: "I agree on the healing potions", 2026-09-28).
            if item.classID == 0 and P.IsCurrentExpansion and P.IsCurrentExpansion(item.expansionID) then
                local role = P.GetCurrentCharacter and P.GetRole and P.GetRole(P.GetCurrentCharacter())
                if role == "main" or role == "leveling" then return false end
            end
            if not P.ExplainScanned then return true end
            return P.ExplainScanned(item).disposition == "keep"
        end,
    },
    ["Move Materials to Warband"] = {
        description = "Materials your crafters use, from the character bank into the Warband bank where they can reach them.",
        predicate = function(item)
            if item.classID ~= 7 or not IsShareable(item) then return false end
            if not P.ExplainScanned then return true end
            return P.ExplainScanned(item).disposition == "keep"
        end,
    },
    ["Consolidate Warbound Items"] = {
        description = "Warbound items from the character bank into the Warband bank, where every character reaches them.",
        -- Gear, tokens, pet charms, cosmetics (the player, 2026-09-28: Trial
        -- of Style tokens belong where any character can spend them).
        -- Materials stay with Move Materials to Warband (in game this card
        -- listed Warbound lumber twice), and nothing headed out (it offered
        -- 46 "Can go" pieces for the Warband bank).
        predicate = function(item)
            return item.classID ~= 7 and not IsHeadedOut(item)
        end,
    },
}

-- A copy of a preset that reads another source (the preset tables are shared).
function P.WithPresetSource(preset, source)
    local copy = {}
    for k, v in pairs(preset) do copy[k] = v end
    copy.source = source
    return copy
end

P.TASK_EXTRAS = TASK_EXTRAS

-- Other modules (Reasons, Value, Warband queue) register extra built-in tasks.
local EXTRA_TASKS = {}
function P.RegisterTask(task)
    for i, existing in ipairs(EXTRA_TASKS) do
        if existing.name == task.name then EXTRA_TASKS[i] = task return end
    end
    table.insert(EXTRA_TASKS, task)
end

-- ---------------------------------------------------------------------------
-- Task list
-- ---------------------------------------------------------------------------

-- All tasks: { name, kind = "quick"|"saved"|"extra", preset, description, predicate }
local function GetAllTasks()
    local tasks = {}
    for _, option in ipairs(P.GetQuickWorkflowOptions()) do
        local preset = P.FindQuickWorkflow(option.value)
        local extra = TASK_EXTRAS[option.value] or {}
        if preset and extra.presetFor then preset = extra.presetFor(preset) end
        table.insert(tasks, { name = option.value, kind = "quick", preset = preset,
            description = extra.description, predicate = extra.predicate })
    end
    for _, task in ipairs(EXTRA_TASKS) do
        if not task.isAvailable or task.isAvailable() then
            -- presetFor: a task can pick its route now (e.g. which bank holds its items).
            local description = task.description
            if type(description) == "function" then description = description() end
            table.insert(tasks, { name = task.name, kind = "extra",
                preset = task.presetFor and task.presetFor() or task.preset,
                description = description, predicate = task.predicate, count = task.count, open = task.open,
                secondary = task.secondary, valueMode = task.valueMode })
        end
    end
    for _, preset in ipairs(P.GetSavedFilters()) do
        -- Presets from 0.4/0.5 saved filters only (no route). They apply to
        -- whatever route is chosen, so they get no count of their own.
        local filterOnly = preset.source == nil and preset.dest == nil
        table.insert(tasks, { name = preset.name, kind = "saved", preset = preset, filterOnly = filterOnly,
            description = filterOnly and "Filters only: applies to the route you choose in Transfer."
                or (preset.imported and "Imported from an earlier version." or "Your saved task.") })
    end
    return tasks
end
P.GetAllTasks = GetAllTasks

function P.FindTask(name)
    for _, task in ipairs(GetAllTasks()) do
        if task.name == name then return task end
    end
    return nil
end

local function TaskRoute(task)
    local preset = task.preset or {}
    return preset.source or "Bags", preset.dest or STORAGE_ALL_BANK_TABS
end
P.GetTaskRoute = TaskRoute

-- Can this task's review list be shown here? Returns ok, whatToDo.
function P.TaskRouteAvailable(task)
    if not task or task.filterOnly or task.open then return true end
    local source, dest = TaskRoute(task)
    local context = ns.DB.context
    if (P.IsWarbandStorage(source) or P.IsWarbandStorage(dest)) and P.WarbandTabsPurchased() == 0 then
        return false, "Buy a Warband tab"
    end
    if (P.NeedsBankStorage(source) or P.NeedsBankStorage(dest)) and not context.bankOpen then
        return false, "Visit a bank"
    end
    if dest == "Vendor" and not context.vendorOpen then
        return false, "Visit a vendor"
    end
    if dest == P.STORAGE_AUCTION_HOUSE and not context.auctionHouseOpen then
        return false, "Visit the auction house"
    end
    return true
end

-- Returns the matching plans for a task without touching the Transfer filters.
local function TaskPlans(task)
    if task.count then return {} end
    local preset = task.preset
    if not preset then return {} end
    local source, dest = TaskRoute(task)
    local savedSort = ns.DB.ui.transferSort
    ns.DB.ui.tabFilters[SCRATCH_TAB] = nil
    P.ApplySavedFilter(preset, SCRATCH_TAB)
    ns.DB.ui.transferSort = savedSort
    local matched = {}
    local candidates
    local cache = P.evaluationCache
    if cache then
        local routeKey = tostring(source) .. "->" .. tostring(dest)
        candidates = cache.routes[routeKey]
        if not candidates then
            candidates = P.GetTransferCandidates(source, dest)
            cache.routes[routeKey] = candidates
        end
    else
        candidates = P.GetTransferCandidates(source, dest)
    end
    for _, plan in ipairs(candidates) do
        if P.PlanMatchesTabFilters(plan, SCRATCH_TAB) and (not task.predicate or task.predicate(plan.item)) then
            table.insert(matched, plan)
        end
    end
    ns.DB.ui.tabFilters[SCRATCH_TAB] = nil
    return matched
end
P.GetTaskPlans = TaskPlans

-- What frees Warband bank space, in the player's words, most useful first.
-- In game (Finalomega, 2026-09-28) a full Warband bank advised "pull items
-- that can go", but nothing in it could go: the pull list was empty while
-- 31 items waited there for Kiosk to auction. Returns ways, canPull.
function P.WarbandRoomWays()
    local ways = {}
    local pullTask = P.FindTask("Pull Warband Items That Can Go")
    local canPull = pullTask and #TaskPlans(pullTask) > 0 or false
    if canPull then ways[#ways + 1] = "pull out items that can go" end
    local target = P.AuctionCharacter and P.AuctionCharacter()
    if target and target.key ~= P.currentCharacterKey and P.GetHandoffs then
        local waiting = #P.GetHandoffs(function(e) return e.to == target.key and e.state == "deposited" end)
        if waiting > 0 then
            ways[#ways + 1] = "have " .. target.name .. " collect the " .. waiting .. " item"
                .. (waiting == 1 and "" or "s") .. " waiting to be auctioned"
        end
    end
    local bought = P.WarbandTabsPurchased and P.WarbandTabsPurchased()
    if bought and bought < 5 then
        ways[#ways + 1] = "buy another Warband tab at a banker (" .. bought .. " of 5 bought)"
    end
    return ways, canPull
end

-- Evaluate a task into card data.
local function EvaluateTask(task)
    local card = {
        name = task.name, kind = task.kind, description = task.description, valueMode = task.valueMode,
        ready = 0, waiting = 0, value = 0, needs = nil, task = task, filterOnly = task.filterOnly,
    }
    if task.filterOnly then
        -- no count: the route is chosen when the filters are applied
    elseif task.count then
        local ready, needs, value, summary, bankWork = task.count()
        card.ready, card.needs, card.value, card.summaryText = ready or 0, needs, value or 0, summary
        card.bankWork = bankWork
    else
        for _, plan in ipairs(TaskPlans(task)) do
            local item = plan.item
            local stackValue = (item.sellPrice or 0) * (item.count or 1)
            if task.valueMode == "auction" and P.GetItemValue then stackValue = (P.GetItemValue(item)) end
            -- Selling something worth far more at auction isn't "ready" (in
            -- game Sell Old Consumables counted a 25s item worth ~24g at auction).
            local worthMore = plan.movable and plan.dest == "Vendor" and P.IsValueFlagged
                and P.IsValueFlagged(item, "Vendor")
            local needsPrice = not worthMore and plan.movable and plan.dest == "Vendor" and P.NeedsPriceCheck
                and P.NeedsPriceCheck(item)
            if worthMore then
                card.worthMore = (card.worthMore or 0) + 1
            elseif needsPrice then
                card.needsPrice = (card.needsPrice or 0) + 1
            elseif plan.movable then
                card.ready = card.ready + 1
                card.value = card.value + stackValue
            elseif CONTEXT_BLOCKS[plan.blocked or ""] then
                card.waiting = card.waiting + 1
                card.value = card.value + stackValue
                card.needs = card.needs or CONTEXT_BLOCKS[plan.blocked]
            elseif plan.blocked and task.predicate and (task.kind == "extra"
                or plan.blocked:find("No empty slots", 1, true)
                or (P.WARBAND_ASSIGNED_FULL and plan.blocked:sub(1, #P.WARBAND_ASSIGNED_FULL) == P.WARBAND_ASSIGNED_FULL)) then
                -- (Also any task whose destination is full: in game "Deposit
                -- to Warband" said "Nothing to do right now" with the Warband
                -- bank full and an item waiting.)
                -- Items the player asked for (e.g. marked for an alt) but that
                -- can't move: say why instead of "Nothing to do" (in game: a
                -- full Warband tab hid a queued hand-off).
                card.blocked = (card.blocked or 0) + 1
                card.blockedReason = card.blockedReason or plan.blocked
            end
        end
    end
    card.total = card.ready + card.waiting
    card.available = card.ready > 0
    return card
end
P.EvaluateTask = EvaluateTask

-- Cards for the Home screen, most useful first: ready now (largest first),
-- then waiting on a context, then empty tasks.
-- A cache shared by every card in one refresh: one candidate list per route
-- and one explanation per item, instead of recomputing them for each card.
local function WithEvaluationCache(fn)
    local outer = P.evaluationCache
    if not outer then
        P.evaluationCache = { routes = {}, explanations = setmetatable({}, { __mode = "k" }) }
    end
    local ok, result = pcall(fn)
    if not outer then P.evaluationCache = nil end
    if not ok then error(result, 0) end
    return result
end
P.WithEvaluationCache = WithEvaluationCache

function P.GetTaskCards()
    local cards = {}
    WithEvaluationCache(function()
        for _, task in ipairs(GetAllTasks()) do
            local ok, card = pcall(EvaluateTask, task)
            if ok then table.insert(cards, card) end
        end
    end)
    local function rank(card)
        if card.ready > 0 then return 1 end
        if card.waiting > 0 or (card.blocked or 0) > 0 then return 2 end
        return 3
    end
    -- At a bank, pulls come before deposits: they free the space deposits
    -- need (in game a deposit filled the Warband bank right before a pull).
    local atBank = ns.DB.context.bankOpen
    local function step(card)
        if not atBank or card.ready == 0 then return 0 end
        -- Counted tasks (Auction Candidates) have bank work only while
        -- items are still in a bank; otherwise they wait for the next stop.
        if card.task and card.task.count then return (card.bankWork or 0) > 0 and 1 or 3 end
        local source, dest = TaskRoute(card.task or {})
        if dest == "Bags" and P.NeedsBankStorage(source) then return 1 end
        return 2
    end
    table.sort(cards, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        local sa, sb = step(a), step(b)
        if sa ~= sb then return sa < sb end
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    return cards
end

-- Free slots in the bags, and in the Warband bank's tabs (nil when unknown).
function P.FreeBagSlots()
    local free = 0
    for _, bagID in ipairs(P.NORMAL_BAG_IDS or {}) do
        free = free + (C_Container.GetContainerNumFreeSlots and C_Container.GetContainerNumFreeSlots(bagID) or 0)
    end
    return free
end

function P.FreeWarbandSlots()
    if not ns.DB.context.bankOpen then return nil end
    local free, any = 0, false
    for _, tab in ipairs(P.GetWarbandTabs and P.GetWarbandTabs() or {}) do
        any = true
        free = free + (C_Container.GetContainerNumFreeSlots and C_Container.GetContainerNumFreeSlots(tab.bagID) or 0)
    end
    return any and free or nil
end

-- One line for Home: where to go next and why, in the order that avoids
-- shuffling (bank -> auction house -> vendor). Current stop marked "here".
function P.TripPlan(cards)
    local bank, vendor = 0, 0
    for _, card in ipairs(cards or {}) do
        if not card.filterOnly and card.task and not card.task.open and (card.ready + card.waiting) > 0 then
            local source, dest = TaskRoute(card.task)
            if card.task.count then
                if (card.bankWork or 0) > 0 then bank = bank + 1 end
            elseif P.NeedsBankStorage(source) or P.NeedsBankStorage(dest) then
                bank = bank + 1
            elseif dest == "Vendor" then
                vendor = math.max(vendor, card.ready + card.waiting)
            end
        end
    end
    local auction = 0
    -- With an auction character elsewhere, auctionables go to the bank for
    -- it; the auction house is that character's stop, not this one's.
    if P.AuctionCandidateItems and not (P.AuctionHandoffTarget and P.AuctionHandoffTarget()) then
        for _, item in ipairs(P.AuctionCandidateItems()) do
            if item.scope == P.BAG_SCOPE then auction = auction + 1 end
        end
    end
    local context = ns.DB.context
    local stops = {}
    local function add(here, label, count, unit)
        if count > 0 then
            stops[#stops + 1] = (here and "here: " or "") .. label .. " (" .. count .. " " .. unit .. ")"
        end
    end
    add(context.bankOpen, "bank", bank, bank == 1 and "task" or "tasks")
    add(context.auctionHouseOpen, "auction house", auction, "to list")
    add(context.vendorOpen, "vendor", vendor, "to sell")
    if #stops == 0 then return nil end
    return "Trip: " .. table.concat(stops, "  ->  ")
end

-- The card to mention in the bank/vendor notice: the biggest ready card.
function P.GetTopReadyCard()
    local cards = P.GetTaskCards()
    -- At the auction house, the auction cards are the relevant ones.
    if ns.DB.context.auctionHouseOpen then
        for _, card in ipairs(cards) do
            if card.ready > 0 and card.valueMode == "auction" then return card end
        end
        for _, card in ipairs(cards) do
            local isPriceCheck = card.name == "Check Prices in Auctionator" or card.name == "Price My Items"
            if isPriceCheck and card.ready > 0 then return card end
        end
        return nil
    end
    -- At a vendor, the ready selling task with the most items comes first
    -- (in game the notice showed Auction Candidates, then Sell Old
    -- Consumables with 5 while Sell Items That Can Go had 9).
    if ns.DB.context.vendorOpen then
        local best
        for _, card in ipairs(cards) do
            local _, dest = TaskRoute(card.task or {})
            if card.ready > 0 and not card.task.count and dest == "Vendor"
                and (not best or card.ready > best.ready) then
                best = card
            end
        end
        -- Nothing to sell: no notice (an auction or bank task isn't what a
        -- vendor visit is for; in game Auction Candidates showed again).
        return best
    end
    -- At a bank, the first task with bank work (in game the notice named
    -- Auction Candidates after every candidate was already in the bags).
    if ns.DB.context.bankOpen then
        for _, card in ipairs(cards) do
            if card.ready > 0 and not card.filterOnly and card.task and not card.task.open then
                local source, dest = TaskRoute(card.task)
                local bankWork
                if card.task.count then
                    bankWork = (card.bankWork or 0) > 0
                else
                    bankWork = P.NeedsBankStorage(source) or P.NeedsBankStorage(dest)
                end
                if bankWork then return card end
            end
        end
        return nil
    end
    for _, card in ipairs(cards) do
        if card.ready > 0 then return card end
        break
    end
    return nil
end

-- One-line card summary: "23 ready (4g 12s)" / "12 waiting: Visit a bank".
function P.CardSummary(card)
    if card.filterOnly then return "Filter preset (no route)" end
    if P.IsSettling and P.IsSettling() then return "Getting ready..." end
    if card.task and not card.task.count and not card.task.open then
        local source, dest = TaskRoute(card.task)
        if (P.IsWarbandStorage(source) or P.IsWarbandStorage(dest)) and P.WarbandTabsPurchased() == 0 then
            return "No Warband bank tab yet: the first costs 1,000g at any banker"
        end
    end
    if card.summaryText then return card.summaryText end
    local money = card.value > 0
        and (" (" .. (card.valueMode == "auction" and "~" or "") .. P.FormatMoney(card.value)
            .. (card.valueMode == "auction" and " at auction" or "") .. ")") or ""
    local worthMore = (card.worthMore or 0) > 0
        and (card.worthMore .. " worth more at auction") or nil
    local needsPrice = (card.needsPrice or 0) > 0
        and (card.needsPrice .. " to price at the auction house first") or nil
    if needsPrice then worthMore = worthMore and (worthMore .. ", " .. needsPrice) or needsPrice end
    if card.ready > 0 then
        local extra = card.waiting > 0 and (", " .. card.waiting .. " more elsewhere") or ""
        local source, dest = TaskRoute(card.task or {})
        if P.IsWarbandStorage(dest) then
            local free = P.FreeWarbandSlots()
            if free and free < card.ready then
                local ways = P.WarbandRoomWays()
                extra = extra .. "; Warband bank has " .. free .. " free" .. (ways[1] and (": " .. ways[1] .. " first") or "")
            end
        elseif dest == "Bags" and P.NeedsBankStorage(source) then
            local free = P.FreeBagSlots()
            if free < card.ready then
                extra = extra .. "; bags have " .. free .. " free: sell at a vendor first"
            end
        end
        return card.ready .. " ready" .. money .. extra .. (worthMore and (", " .. worthMore) or "")
    elseif card.waiting > 0 then
        return card.waiting .. " waiting: " .. (card.needs or "change location")
    elseif (card.blocked or 0) > 0 then
        local reason = tostring(card.blockedReason)
        local _, dest = TaskRoute(card.task or {})
        if P.IsWarbandStorage(dest) and (reason:find("No empty slots", 1, true)
            or (P.WARBAND_ASSIGNED_FULL and reason:sub(1, #P.WARBAND_ASSIGNED_FULL) == P.WARBAND_ASSIGNED_FULL)) then
            reason = "Warband bank full"
        end
        return card.blocked .. " blocked: " .. reason
    elseif worthMore then
        return worthMore .. ((card.worthMore or 0) > 0 and ": see Auction Candidates" or "")
    end
    return "Nothing to do right now"
end

-- ---------------------------------------------------------------------------
-- Opening a task
-- ---------------------------------------------------------------------------

-- Pre-select every movable item of the task that is safe to pre-select.
-- Never selects blocked items or items flagged as worth keeping.
function P.PreselectTask(task)
    UI.transferSelected = {}
    for _, plan in ipairs(TaskPlans(task)) do
        local safe = plan.movable
        if safe and P.ExplainItem then
            local explanation = P.ExplainItem(plan.item, {})
            if P.IsValueFlagged and P.IsValueFlagged(plan.item, plan.dest) then safe = false end
            if plan.dest == "Vendor" and P.NeedsPriceCheck and P.NeedsPriceCheck(plan.item) then safe = false end
            -- Selling: only items that can clearly go. "Your call" items
            -- (situational trinkets, outgrown gear) are never pre-selected.
            if plan.dest == "Vendor" and explanation.disposition ~= "free" then safe = false end
            -- Destroying: only what the player decided (it can't be undone).
            if plan.dest == P.STORAGE_DESTROY and not (P.DecidedToDestroy and P.DecidedToDestroy(plan.item)) then
                safe = false
            end
        end
        if safe then UI.transferSelected[plan.key] = true end
    end
end

function P.IsPreselectEnabled()
    return ns.DB and ns.DB.ui and ns.DB.ui.preselectQuickTasks == true
end

-- Reason-driven tasks live in Reasons.lua; register them now that tasks exist.
if P.RegisterReasonTasks then P.RegisterReasonTasks() end
