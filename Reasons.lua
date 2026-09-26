-- I Can't Even Right Now (With My Bags and Bank) — "Why Is This Here?"
-- Explains why each item is being kept, before anything suggests parting
-- with it. Detectors read only the scan record plus account-wide facts
-- (roster, collections), so they work for other characters' snapshots too.
--
-- Each detected reason has a disposition:
--   keep   a real reason to hold the item (the addon stops suggesting it)
--   free   the item can go without losing anything
--   review the player should decide (the addon cannot know)
--   info   context only
-- The primary reason is the first keep reason, else the first free reason,
-- else the first review reason. Keep always wins, so a detector can never
-- talk the player out of something they need.

local ADDON_NAME, ns = ...

local Core = ns.Core
local Data = ns.Data
local P    = ns.Private

local BAG_SCOPE  = P.BAG_SCOPE
local BANK_SCOPE = P.BANK_SCOPE

local DAY = 24 * 3600

-- Consumable subclasses that are used up (potions, elixirs, flasks, food,
-- bandages, runes). Devices (0), scrolls (4), enhancements (6), and "Other" (8)
-- include reusable tools and event tokens, so they are never called free.
local SPENT_CONSUMABLE_SUBCLASSES = { [1] = true, [2] = true, [3] = true, [5] = true, [7] = true, [9] = true }
local LONG_UNTOUCHED_DAYS = 365

-- ---------------------------------------------------------------------------
-- Reason catalogue
-- ---------------------------------------------------------------------------

local REASONS = {
    -- keep
    protected            = { disposition = "keep",   label = "Protected by your rule" },
    keepsake             = { disposition = "keep",   label = "You marked it as a keepsake" },
    keep_for_alt         = { disposition = "keep",   label = "You're keeping it for an alt" },
    keep_event           = { disposition = "keep",   label = "You're keeping it for an event" },
    keep_investment      = { disposition = "keep",   label = "You're holding it as an investment" },
    quest_active         = { disposition = "keep",   label = "Quest in progress" },
    collectible_unlearned = { disposition = "keep",  label = "Collectible not learned yet" },
    appearance_uncollected = { disposition = "keep", label = "Appearance not collected yet" },
    used_by_crafter      = { disposition = "keep",   label = "Material one of your crafters uses" },
    usable_gear          = { disposition = "keep",   label = "Gear one of your played characters can use" },
    current_expansion    = { disposition = "keep",   label = "From the current expansion" },
    -- free
    appearance_collected = { disposition = "free",   label = "Appearance already collected" },
    collectible_learned  = { disposition = "free",   label = "Collectible already learned" },
    quest_done           = { disposition = "free",   label = "Starts a quest you already completed" },
    junk                 = { disposition = "free",   label = "Junk (grey item)" },
    old_consumable       = { disposition = "free",   label = "Consumable from a past expansion" },
    unused_material      = { disposition = "free",   label = "Material no crafter on your account uses" },
    unused_gear          = { disposition = "free",   label = "Gear none of your played characters can use" },
    -- review
    -- A due investment reminder outranks free reasons: the player asked to be asked.
    investment_due       = { disposition = "review", label = "Your investment reminder is due", pinned = true },
    quest_not_started    = { disposition = "review", label = "Starts a quest you haven't done" },
    possible_keepsake    = { disposition = "review", label = "Possibly a keepsake" },
    long_untouched       = { disposition = "review", label = "Untouched for over a year" },
    roles_needed         = { disposition = "review", label = "Assign character roles to see who can use this" },
    outgrown_gear        = { disposition = "review", label = "Gear that isn't an upgrade for anyone" },
    -- info
    quest_item           = { disposition = "info",   label = "Quest item" },
    unexplained          = { disposition = "info",   label = "No clear reason found" },
}
P.REASONS = REASONS

local KEEP_REASON_BY_CHOICE = {
    keepsake = "keepsake", alt = "keep_for_alt", event = "keep_event", investment = "keep_investment",
}
P.KEEP_REASON_CHOICES = {
    { value = "keepsake",   label = "Keepsake" },
    { value = "alt",        label = "For an alt" },
    { value = "event",      label = "For an event" },
    { value = "investment", label = "Investment" },
}

-- ---------------------------------------------------------------------------
-- Time held (Y3)
-- ---------------------------------------------------------------------------

local function Now() return time and time() or 0 end

-- "char:<Name-Realm>:bags", "char:<Name-Realm>:bank", or "warband".
local function LocationKeyFor(scope, characterKey)
    if scope == "warband" then return "warband" end
    characterKey = characterKey or P.currentCharacterKey or P.GetCharacterKey()
    return "char:" .. characterKey .. ":" .. (scope == BAG_SCOPE and "bags" or "bank")
end
P.LocationKeyFor = LocationKeyFor

-- Records the first date each itemID was seen in a location. Items that left
-- the location are forgotten, so "never moved" restarts when they return.
local function RecordTimeHeld(locationKey, items)
    ns.DB.timeHeld = ns.DB.timeHeld or {}
    local entry = ns.DB.timeHeld[locationKey]
    if not entry then
        entry = { since = Now(), items = {} }
        ns.DB.timeHeld[locationKey] = entry
    end
    local present = {}
    for _, item in ipairs(items or {}) do
        if item.itemID then
            present[item.itemID] = true
            if not entry.items[item.itemID] then entry.items[item.itemID] = Now() end
        end
    end
    for itemID in pairs(entry.items) do
        if not present[itemID] then entry.items[itemID] = nil end
    end
end
P.RecordTimeHeld = RecordTimeHeld

-- Returns firstSeen, isLowerBound (tracking began then, so it may be older).
local function GetTimeHeld(locationKey, itemID)
    local entry = ns.DB.timeHeld and ns.DB.timeHeld[locationKey]
    local firstSeen = entry and entry.items[itemID]
    if not firstSeen then return nil end
    return firstSeen, firstSeen <= entry.since
end
P.GetTimeHeld = GetTimeHeld

local function FormatHeld(firstSeen, isLowerBound)
    local days = math.floor((Now() - firstSeen) / DAY)
    local text
    if days < 1 then
        text = "today"
    elseif days < 60 then
        text = days .. " day" .. (days == 1 and "" or "s")
    else
        text = "since " .. (date and date("%B %Y", firstSeen) or tostring(firstSeen))
    end
    if isLowerBound and days >= 1 then
        return days < 60 and ("at least " .. text) or ("at least " .. text)
    end
    return text
end
P.FormatHeld = FormatHeld

-- ---------------------------------------------------------------------------
-- Account facts used by detectors
-- ---------------------------------------------------------------------------

local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e, f, g, h, i, j, k, l, m
end

-- Appearance collection: true/false, or nil when the item has no appearance.
local function AppearanceCollected(item)
    if not C_TransmogCollection then return nil end
    local _, sourceID = SafeCall(C_TransmogCollection.GetItemInfo, item.link or item.itemID)
    if not sourceID then return nil end
    return SafeCall(C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance, sourceID) and true or false
end
P.IsAppearanceCollected = AppearanceCollected

-- Collectible learned state: "toy"|"mount"|"pet", learned (bool); nil if not a collectible.
local function CollectibleState(item)
    local itemID = item.itemID
    if C_ToyBox and SafeCall(C_ToyBox.GetToyInfo, itemID) then
        return "toy", SafeCall(PlayerHasToy, itemID) and true or false
    end
    if C_MountJournal and C_MountJournal.GetMountFromItem then
        local mountID = SafeCall(C_MountJournal.GetMountFromItem, itemID)
        if mountID then
            local isCollected = select(11, SafeCall(C_MountJournal.GetMountInfoByID, mountID))
            return "mount", isCollected and true or false
        end
    end
    if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local speciesID = select(13, SafeCall(C_PetJournal.GetPetInfoByItemID, itemID))
        if speciesID then
            local collected = SafeCall(C_PetJournal.GetNumCollectedInfo, speciesID) or 0
            return "pet", collected > 0
        end
    end
    return nil
end
P.GetCollectibleState = CollectibleState

-- Professions (with trade-goods subclasses) of characters that receive materials.
local function CraftersFor(item)
    if item.classID ~= 7 then return nil end
    local users = {}
    for _, char in ipairs(P.CharactersWith("receivesMaterials")) do
        for _, prof in ipairs(char.professions or {}) do
            local subclasses = Data.ProfessionSubclasses and Data.ProfessionSubclasses[prof.skillLine]
            if subclasses then
                for _, subclassID in ipairs(subclasses) do
                    if subclassID == item.subclassID then
                        table.insert(users, { character = char, profession = prof.name })
                        break
                    end
                end
            end
        end
    end
    return users
end
P.CraftersFor = CraftersFor

local function IsGear(item)
    return (item.classID == 2 or item.classID == 4) and item.equipLoc and item.equipLoc ~= ""
        and item.equipLoc ~= "INVTYPE_NON_EQUIP" and item.equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
end
P.IsGearItem = IsGear

local SHIELD_CLASSES = { PALADIN = true, SHAMAN = true, WARRIOR = true }

-- Can this character wear the item at all (armor type, shields, level)?
local function CanCharacterUse(char, item, levelLimited)
    if item.classID == 4 then
        local sub = item.subclassID
        if sub == 6 then
            if not SHIELD_CLASSES[char.classFile or ""] then return false end
        elseif sub and sub >= 1 and sub <= 4 and item.equipLoc ~= "INVTYPE_CLOAK" then
            if char.armorSubclass and sub ~= char.armorSubclass then return false end
        end
    end
    if levelLimited and (item.requiredLevel or 0) > (char.level or 0) then return false end
    return true
end
P.CanCharacterUse = CanCharacterUse

local function GearUsers(item)
    local users = {}
    for _, char in ipairs(P.CharactersWith("receivesGear")) do
        local levelLimited = P.GetRole(char) == "leveling"
        if CanCharacterUse(char, item, levelLimited) then table.insert(users, char) end
    end
    return users
end
P.GearUsersFor = GearUsers

-- Gear-receiving characters for whom this item beats what they wear
-- (two-slot items compare against the weaker slot; empty slot = 0).
local function UpgradeUsers(item)
    local slots = P.INVTYPE_TO_SLOTS and P.INVTYPE_TO_SLOTS[item.equipLoc or ""]
    if not slots or not item.itemLevel or item.itemLevel <= 0 then return {} end
    local users = {}
    for _, char in ipairs(GearUsers(item)) do
        -- Unknown equipment (never read, or read before the gear loaded) is
        -- not an upgrade target; fall back to the equipped average if known.
        -- Saves from before this fix hold 0 for every slot: also unknown.
        local known = false
        for _, level in pairs(char.equipped or {}) do
            if type(level) == "number" and level > 0 then known = true break end
        end
        if known or (char.averageItemLevel or 0) > 0 then
            local lowest
            for _, slot in ipairs(slots) do
                local level = known and (char.equipped[slot] or 0) or char.averageItemLevel
                if known and level == 0 and (char.averageItemLevel or 0) > 0 and char.equipped[slot] == 0 then
                    level = char.averageItemLevel -- a stored 0 means "not loaded", not "empty"
                end
                if not lowest or level < lowest then lowest = level end
            end
            if item.itemLevel > (lowest or 0) then table.insert(users, char) end
        end
    end
    return users
end
P.UpgradeUsersFor = UpgradeUsers

local function AnyRolesAssigned()
    local counts = P.CountByRole()
    return (counts.main + counts.leveling + counts.crafter + counts.utility) > 0
end

-- ---------------------------------------------------------------------------
-- Detection
-- ---------------------------------------------------------------------------

local function Names(list, field)
    local names = {}
    for i, entry in ipairs(list) do
        if i > 3 then names[#names + 1] = "and " .. (#list - 3) .. " more" break end
        names[#names + 1] = field and entry[field] or entry
    end
    return table.concat(names, ", ")
end

-- ctx: { locationKey = ..., owner = character record or nil }
local function ExplainItem(item, ctx)
    ctx = ctx or {}
    local reasons = {}
    local function add(id, evidence) table.insert(reasons, { id = id, evidence = evidence }) end

    local rule = ns.DB.rules and ns.DB.rules.items and ns.DB.rules.items[item.itemID]
    if type(rule) == "table" then
        if rule.protect then add("protected") end
        local keep = rule.keepReason and KEEP_REASON_BY_CHOICE[rule.keepReason]
        if keep then
            if rule.keepReason == "investment" and rule.keepUntil and Now() >= rule.keepUntil then
                add("investment_due", "Keep holding it, or let it go")
            else
                add(keep)
            end
        end
    end

    -- Quests (status captured for the owning character at scan time).
    if item.questID then
        if item.questActive then
            add("quest_active")
        elseif item.questCompleted then
            add("quest_done", "Quest already completed by the character holding it")
        else
            local expansion = P.GetExpansionName(item.expansionID)
            add("quest_not_started", expansion ~= "Unknown" and ("A " .. expansion .. " quest") or nil)
        end
    elseif item.isQuestItem or item.classID == 12 then
        add("quest_item")
    end

    local kind, learned = CollectibleState(item)
    if kind then
        if learned then add("collectible_learned", "This " .. kind .. " is already in your collection")
        else add("collectible_unlearned", "Use it to add the " .. kind .. " to your collection") end
    end

    if IsGear(item) then
        local collected = AppearanceCollected(item)
        if collected == false then add("appearance_uncollected") end
        if AnyRolesAssigned() then
            local users = GearUsers(item)
            local upgrades = UpgradeUsers(item)
            if #upgrades > 0 then
                local labels = {}
                for _, char in ipairs(upgrades) do
                    labels[#labels + 1] = char.name .. " (" .. P.GetRoleLabel(P.GetRole(char)) .. ")"
                end
                add("usable_gear", "Upgrade for " .. Names(labels))
            elseif #users > 0 then
                -- Wearable but worse than what everyone wears (maybe an off-spec
                -- or transmog piece): the player decides, the addon doesn't keep it.
                add("outgrown_gear", "Wearable by " .. Names(users, "name") .. ", but not an upgrade")
            elseif collected then
                add("appearance_collected", "You keep the appearance; none of your played characters wear this")
            else
                add("unused_gear", "None of your played characters can wear it")
            end
        else
            -- Without roles the addon cannot tell whether a character still
            -- wears this, so it never calls gear free to go.
            add("roles_needed", collected and "Appearance already collected" or nil)
        end
    end

    if item.classID == 7 then
        if AnyRolesAssigned() then
            local users = CraftersFor(item)
            if users and #users > 0 then
                local labels = {}
                for _, u in ipairs(users) do labels[#labels + 1] = u.character.name .. " (" .. u.profession .. ")" end
                add("used_by_crafter", "Used by " .. Names(labels))
            else
                add("unused_material", "No character with a crafting role has a profession that uses it")
            end
        else
            add("roles_needed")
        end
    end

    if item.quality == 0 then add("junk") end
    if item.classID == 0 and SPENT_CONSUMABLE_SUBCLASSES[item.subclassID or -1] and P.IsOldExpansion(item.expansionID) then
        add("old_consumable", "From " .. P.GetExpansionName(item.expansionID))
    end

    if (item.quality or 0) >= 5 and (item.sellPrice or 0) == 0 then
        add("possible_keepsake", "Legendary or rarer with no vendor price")
    end

    if ctx.locationKey then
        local firstSeen, lowerBound = GetTimeHeld(ctx.locationKey, item.itemID)
        if firstSeen then
            ctx.heldText = FormatHeld(firstSeen, lowerBound)
            if Now() - firstSeen >= LONG_UNTOUCHED_DAYS * DAY then
                add("long_untouched", "Held " .. ctx.heldText .. ", never moved")
            end
        end
    end

    -- Current-expansion content is protected by default elsewhere in the addon.
    local hasKeep = false
    for _, r in ipairs(reasons) do
        if REASONS[r.id].disposition == "keep" then hasKeep = true break end
    end
    -- Gear is judged by who it upgrades once roles are set, not by expansion.
    local judgedAsGear = IsGear(item) and AnyRolesAssigned()
    if not hasKeep and not judgedAsGear and item.quality ~= 0 and item.expansionID
        and not P.IsOldExpansion(item.expansionID) then
        add("current_expansion")
    end

    if #reasons == 0 then add("unexplained") end

    -- Primary: keep > free > review > info.
    local order = { keep = 1, free = 2, review = 3, info = 4 }
    local function rank(id)
        local def = REASONS[id]
        return def.pinned and 1.5 or order[def.disposition]
    end
    local primary
    for _, r in ipairs(reasons) do
        if not primary or rank(r.id) < rank(primary.id) then primary = r end
    end
    return {
        primary = primary,
        reasons = reasons,
        disposition = REASONS[primary.id].disposition,
        label = REASONS[primary.id].label,
        evidence = primary.evidence,
        held = ctx.heldText,
    }
end
P.ExplainItem = ExplainItem

-- Player-assigned keep reasons (Y4). choice = nil clears it.
function P.SetKeepReason(itemID, choice, itemName, remindAfterDays)
    ns.DB.rules = ns.DB.rules or { items = {} }
    ns.DB.rules.items = ns.DB.rules.items or {}
    local rule = ns.DB.rules.items[itemID]
    if not rule then
        if not choice then return end
        rule = { protect = false, neverSell = false, ignore = false, createdFrom = "Why is this here?" }
        ns.DB.rules.items[itemID] = rule
    end
    rule.name = rule.name or itemName
    rule.keepReason = choice
    rule.keepUntil = (choice == "investment" and remindAfterDays) and (Now() + remindAfterDays * DAY) or nil
    if Core.OnRulesChanged then Core.OnRulesChanged() end
end

-- ---------------------------------------------------------------------------
-- Report (Y1)
-- ---------------------------------------------------------------------------

local function ItemValue(item)
    if P.GetItemValue then return P.GetItemValue(item) end
    return (item.sellPrice or 0) * (item.count or 1), "vendor"
end

-- scope: "current" (this character's bags + bank, and the Warband bank) or "all".
function P.BuildWhyReport(scope)
    local currentKey = P.currentCharacterKey or P.GetCharacterKey()
    local groups, total = {}, 0
    local sources = {}
    for _, snapshot in ipairs(P.AllSnapshots()) do
        local char = snapshot.character
        local include = scope == "all" or snapshot.scope == "warband" or (char and char.key == currentKey)
        if include then
            local locationKey = snapshot.scope == "warband" and "warband" or LocationKeyFor(snapshot.scope, char and char.key)
            table.insert(sources, { label = snapshot.scope == "warband" and "Warband bank"
                or ((char and char.name or "?") .. " " .. snapshot.scope), scannedAt = snapshot.scannedAt,
                count = #snapshot.items })
            for _, item in ipairs(snapshot.items) do
                if P.GetItemType and not item.typeTag then item.typeTag = P.GetItemType(item) end
                local explanation = ExplainItem(item, { locationKey = locationKey, owner = char })
                local id = explanation.primary.id
                local group = groups[id]
                if not group then
                    group = { id = id, label = explanation.label, disposition = explanation.disposition,
                        count = 0, value = 0, examples = {} }
                    groups[id] = group
                end
                group.count = group.count + 1
                group.value = group.value + (ItemValue(item) or 0)
                if #group.examples < 3 then table.insert(group.examples, item.name or ("Item " .. item.itemID)) end
                total = total + 1
            end
        end
    end
    local list = {}
    for _, group in pairs(groups) do table.insert(list, group) end
    local order = { free = 1, review = 2, keep = 3, info = 4 }
    table.sort(list, function(a, b)
        if a.disposition ~= b.disposition then return order[a.disposition] < order[b.disposition] end
        if a.count ~= b.count then return a.count > b.count end
        return a.label < b.label
    end)
    return { groups = list, total = total, sources = sources }
end

function P.WhyReportLines(scope)
    local report = P.BuildWhyReport(scope)
    local lines = {}
    table.insert(lines, "Why is this here? " .. report.total .. " stacks"
        .. (scope == "all" and " across all known characters" or " (this character and the Warband bank)") .. ".")
    if report.total == 0 then
        table.insert(lines, "No scan data yet. Open your bags, or visit a bank, then try again.")
        return lines
    end
    local headings = { free = "Can go", review = "Your call", keep = "Worth keeping", info = "Other" }
    local lastDisposition
    for _, group in ipairs(report.groups) do
        if group.disposition ~= lastDisposition then
            table.insert(lines, headings[group.disposition] .. ":")
            lastDisposition = group.disposition
        end
        table.insert(lines, string.format("  %s: %d (%s) e.g. %s", group.label, group.count,
            P.FormatMoney(group.value), table.concat(group.examples, ", ")))
    end
    for _, source in ipairs(report.sources) do
        if (source.scannedAt or 0) == 0 and source.count == 0 then
            -- skip empty, never-scanned sources
        elseif (source.scannedAt or 0) > 0 and (Now() - source.scannedAt) > 7 * DAY then
            table.insert(lines, "Note: " .. source.label .. " was last scanned "
                .. math.floor((Now() - source.scannedAt) / DAY) .. " days ago.")
        end
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- UI helpers (Y4)
-- ---------------------------------------------------------------------------

-- Explain a scanned record using the location it came from (for time held).
function P.ExplainScanned(item)
    local cache = P.evaluationCache and P.evaluationCache.explanations
    if cache and cache[item] then return cache[item] end
    local explanation = P.ExplainScannedUncached(item)
    if cache then cache[item] = explanation end
    return explanation
end

function P.ExplainScannedUncached(item)
    local locationKey
    if item.storageKind == P.STORAGE_WARBAND_BANK then
        locationKey = "warband"
    elseif item.scope == BAG_SCOPE or item.scope == BANK_SCOPE then
        locationKey = LocationKeyFor(item.scope)
    end
    return ExplainItem(item, { locationKey = locationKey })
end

local DISPOSITION_PREFIX = { free = "Can go", review = "Your call", keep = "Keep", info = "" }

-- Short label for list rows: "Can go: Appearance already collected".
function P.ReasonShortText(explanation)
    if not explanation then return nil end
    if explanation.primary.id == "unexplained" then return nil end
    local prefix = DISPOSITION_PREFIX[explanation.disposition] or ""
    return (prefix ~= "" and (prefix .. ": ") or "") .. explanation.label
end

-- What letting the item go would cost, in plain words.
function P.LossText(item, explanation)
    local parts = {}
    local ids = {}
    for _, r in ipairs(explanation.reasons) do ids[r.id] = true end
    if ids.appearance_collected then parts[#parts + 1] = "You keep the appearance." end
    if ids.collectible_learned then parts[#parts + 1] = "It stays in your collection." end
    if ids.quest_done then parts[#parts + 1] = "The quest is already done." end
    local value = (item.sellPrice or 0) * (item.count or 1)
    if P.GetItemValue then
        local best, source = P.GetItemValue(item)
        if best and best > value and source ~= "vendor" then
            parts[#parts + 1] = "Worth about " .. P.FormatMoney(best) .. " (" .. source .. ")."
        elseif value > 0 then
            parts[#parts + 1] = "Worth " .. P.FormatMoney(value) .. " at a vendor."
        end
    elseif value > 0 then
        parts[#parts + 1] = "Worth " .. P.FormatMoney(value) .. " at a vendor."
    end
    if ids.unused_gear or ids.unused_material then
        parts[#parts + 1] = "Nothing on your account uses it."
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " ")
end

-- Items the "can go" tasks act on: free to go and sellable at a vendor.
local function CanGoAndSellable(item)
    if (item.sellPrice or 0) <= 0 then return false end
    if P.IsValueFlagged and P.IsValueFlagged(item, "Vendor") then return false end
    local explanation = P.ExplainScanned(item)
    return explanation.disposition == "free"
end
P.CanGoAndSellable = CanGoAndSellable

-- Reason-driven tasks (registered once Tasks.lua is loaded).
function P.RegisterReasonTasks()
    if not P.RegisterTask then return end
    P.RegisterTask({
        name = "Pull Items That Can Go",
        description = "Bank items you can let go of without losing anything, into your bags to sell.",
        preset = { name = "Pull Items That Can Go", source = P.STORAGE_ALL_BANK_TABS, dest = "Bags",
            expansion = 0, bind = "All", type = "All", slot = "All", armorType = "All", upgrade = "All",
            hideBlocked = true, sort = "Vendor Value" },
        predicate = CanGoAndSellable,
    })
    P.RegisterTask({
        name = "Sell Items That Can Go",
        description = "Junk, collected appearances, learned collectibles, and spent consumables.",
        preset = { name = "Sell Items That Can Go", source = "Bags", dest = "Vendor",
            expansion = 0, bind = "All", type = "All", slot = "All", armorType = "All", upgrade = "All",
            hideBlocked = true, sort = "Vendor Value" },
        predicate = CanGoAndSellable,
    })
end
-- One line naming who benefits from an item, or nil (W6).
function P.WhoBenefits(item)
    if P.IsGearItem(item) then
        local upgrades = UpgradeUsers(item)
        if #upgrades > 0 then
            local labels = {}
            for _, char in ipairs(upgrades) do
                labels[#labels + 1] = char.name .. " (" .. P.GetRoleLabel(P.GetRole(char)) .. ")"
            end
            return "Upgrade for " .. Names(labels)
        end
        local users = GearUsers(item)
        if #users > 0 then return "Can be worn by " .. Names(users, "name") end
    end
    if item.classID == 7 then
        local users = CraftersFor(item) or {}
        if #users > 0 then
            local labels = {}
            for _, u in ipairs(users) do labels[#labels + 1] = u.character.name .. " (" .. u.profession .. ")" end
            return "Used by " .. Names(labels)
        end
    end
    if item.isWarbandBound then return "Warbound: any of your characters can use it" end
    return nil
end