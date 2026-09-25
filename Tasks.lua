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
    return false
end
P.IsShareableItem = IsShareable

local TASK_EXTRAS = {
    ["Deposit Old Items"] = { description = "Old-expansion items from your bags into the bank." },
    ["Pull Bank Upgrades"] = { description = "Gear in the bank that beats what you're wearing." },
    ["Pull Auctionable BoEs"] = { description = "Bind-on-equip gear to list on the auction house." },
    ["Sell Old Consumables"] = { description = "Potions, food, and flasks from past expansions." },
    ["Deposit to Warband"] = {
        description = "Items your other characters can use, sorted into Warband tabs by their settings.",
        predicate = IsShareable,
    },
    ["Consolidate Warbound Gear"] = { description = "Warbound gear from the character bank into the Warband bank." },
}

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
        table.insert(tasks, { name = option.value, kind = "quick", preset = preset,
            description = extra.description, predicate = extra.predicate })
    end
    for _, task in ipairs(EXTRA_TASKS) do
        if not task.isAvailable or task.isAvailable() then
            table.insert(tasks, { name = task.name, kind = "extra", preset = task.preset,
                description = task.description, predicate = task.predicate, count = task.count, open = task.open,
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

-- Evaluate a task into card data.
local function EvaluateTask(task)
    local card = {
        name = task.name, kind = task.kind, description = task.description, valueMode = task.valueMode,
        ready = 0, waiting = 0, value = 0, needs = nil, task = task, filterOnly = task.filterOnly,
    }
    if task.filterOnly then
        -- no count: the route is chosen when the filters are applied
    elseif task.count then
        local ready, needs, value, summary = task.count()
        card.ready, card.needs, card.value, card.summaryText = ready or 0, needs, value or 0, summary
    else
        for _, plan in ipairs(TaskPlans(task)) do
            local item = plan.item
            local stackValue = (item.sellPrice or 0) * (item.count or 1)
            if task.valueMode == "auction" and P.GetItemValue then stackValue = (P.GetItemValue(item)) end
            if plan.movable then
                card.ready = card.ready + 1
                card.value = card.value + stackValue
            elseif CONTEXT_BLOCKS[plan.blocked or ""] then
                card.waiting = card.waiting + 1
                card.value = card.value + stackValue
                card.needs = card.needs or CONTEXT_BLOCKS[plan.blocked]
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
        if card.waiting > 0 then return 2 end
        return 3
    end
    table.sort(cards, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    return cards
end

-- The card to mention in the bank/vendor notice: the biggest ready card.
function P.GetTopReadyCard()
    for _, card in ipairs(P.GetTaskCards()) do
        if card.ready > 0 then return card end
        break
    end
    return nil
end

-- One-line card summary: "23 ready (4g 12s)" / "12 waiting: Visit a bank".
function P.CardSummary(card)
    if card.filterOnly then return "Filter preset (no route)" end
    if card.summaryText then return card.summaryText end
    local money = card.value > 0
        and (" (" .. (card.valueMode == "auction" and "~" or "") .. P.FormatMoney(card.value)
            .. (card.valueMode == "auction" and " at auction" or "") .. ")") or ""
    if card.ready > 0 then
        local extra = card.waiting > 0 and (", " .. card.waiting .. " more elsewhere") or ""
        return card.ready .. " ready" .. money .. extra
    elseif card.waiting > 0 then
        return card.waiting .. " waiting: " .. (card.needs or "change location")
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
            if plan.dest == "Vendor" and explanation.disposition == "keep" then safe = false end
        end
        if safe then UI.transferSelected[plan.key] = true end
    end
end

function P.IsPreselectEnabled()
    return ns.DB and ns.DB.ui and ns.DB.ui.preselectQuickTasks == true
end

-- Reason-driven tasks live in Reasons.lua; register them now that tasks exist.
if P.RegisterReasonTasks then P.RegisterReasonTasks() end
