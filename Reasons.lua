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
    keep_for_now         = { disposition = "keep",   label = "You're keeping it for now" },
    quest_active         = { disposition = "keep",   label = "Quest in progress" },
    collectible_unlearned = { disposition = "keep",  label = "Collectible not learned yet" },
    appearance_uncollected = { disposition = "keep", label = "Appearance not collected yet" },
    used_by_crafter      = { disposition = "keep",   label = "Material one of your crafters uses" },
    usable_gear          = { disposition = "keep",   label = "Gear one of your played characters can use" },
    equipment_set        = { disposition = "keep",   label = "In a saved equipment set" },
    current_expansion    = { disposition = "keep",   label = "From the current expansion" },
    -- free
    appearance_collected = { disposition = "free",   label = "Appearance already collected" },
    collectible_learned  = { disposition = "free",   label = "Collectible already learned" },
    quest_done           = { disposition = "free",   label = "Starts a quest you already completed" },
    junk                 = { disposition = "free",   label = "Junk (grey item)" },
    old_consumable       = { disposition = "free",   label = "Consumable from a past expansion" },
    unused_material      = { disposition = "free",   label = "Material no crafter on your account uses" },
    unused_gear          = { disposition = "free",   label = "Gear none of your played characters can use" },
    set_replaced         = { disposition = "free",   label = "Old class set: replaced by the set you wear" },
    outgrown_no_upgrade  = { disposition = "free",   label = "Below what you wear, and it can't be upgraded" },
    -- Outranks the other free reasons: selling isn't an option, so say what is.
    vendor_refused       = { disposition = "free",   label = "No vendor buys it: destroy it or keep it", rank = 1.9 },
    -- Same, when it has an auction price (in game the refused soup sold for ~19s there).
    vendor_refused_auction = { disposition = "free", label = "No vendor buys it: sell it at the auction house or keep it", rank = 1.9 },
    -- review
    -- A due investment reminder outranks free reasons: the player asked to be asked.
    investment_due       = { disposition = "review", label = "Your investment reminder is due", pinned = true },
    quest_not_started    = { disposition = "review", label = "Starts a quest you haven't done" },
    possible_keepsake    = { disposition = "review", label = "Possibly a keepsake" },
    -- Outranks the "can go" reasons: in game eight Legion Legendaries and a
    -- BfA Legendary cloak were offered as "below what you wear".
    legendary_keepsake   = { disposition = "review", label = "Legendary: many players keep these", rank = 1.8 },
    long_untouched       = { disposition = "review", label = "Untouched for over a year" },
    roles_needed         = { disposition = "review", label = "Assign character roles to see who can use this" },
    outgrown_gear        = { disposition = "review", label = "Gear that isn't an upgrade for anyone" },
    situational_gear     = { disposition = "review", label = "Max-level trinket or weapon: check before selling" },
    set_completes        = { disposition = "review", label = "Completes a set bonus: your call" },
    -- info
    quest_item           = { disposition = "info",   label = "Quest item" },
    unexplained          = { disposition = "info",   label = "No clear reason found" },
    details_loading      = { disposition = "info",   label = "Checking item details..." },
    details_unavailable  = { disposition = "info",   label = "Item details didn't load: Rescan to try again" },
}
P.REASONS = REASONS

local KEEP_REASON_BY_CHOICE = {
    keepsake = "keepsake", alt = "keep_for_alt", event = "keep_event", investment = "keep_investment",
    fornow = "keep_for_now",
}
P.KEEP_REASON_CHOICES = {
    { value = "keepsake",   label = "Keepsake" },
    { value = "alt",        label = "For an alt" },
    { value = "event",      label = "For an event" },
    { value = "investment", label = "Investment" },
    { value = "fornow",     label = "For now" },
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

-- Appearance collection: true/false, or nil when the item has no appearance
-- (or its details aren't in yet: see ItemData.lua).
local function AppearanceCollected(item)
    return (P.ItemAppearance(item))
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

-- Weapon proficiencies by weapon subclass (Enum.ItemWeaponSubclass), from
-- warcraft.wiki.gg "Proficiency" (verified 2026-09-26). Without this, bows and
-- swords counted as upgrades for Druids and Priests and were kept (in game).
local function Classes(list)
    local set = {}
    for class in list:gmatch("%S+") do set[class] = true end
    return set
end
local WEAPON_CLASSES = {
    [0]  = Classes("DEATHKNIGHT DEMONHUNTER EVOKER HUNTER MONK PALADIN ROGUE SHAMAN WARRIOR"),        -- 1H axe
    [1]  = Classes("DEATHKNIGHT EVOKER HUNTER PALADIN SHAMAN WARRIOR"),                              -- 2H axe
    [2]  = Classes("HUNTER ROGUE WARRIOR"),                                                           -- bow
    [3]  = Classes("HUNTER ROGUE WARRIOR"),                                                           -- gun
    [4]  = Classes("DEATHKNIGHT DRUID EVOKER MONK PALADIN PRIEST ROGUE SHAMAN WARRIOR"),             -- 1H mace
    [5]  = Classes("DEATHKNIGHT DRUID EVOKER PALADIN SHAMAN WARRIOR"),                               -- 2H mace
    [6]  = Classes("DEATHKNIGHT DRUID HUNTER MONK PALADIN WARRIOR"),                                 -- polearm
    [7]  = Classes("DEATHKNIGHT DEMONHUNTER EVOKER HUNTER MAGE MONK PALADIN ROGUE WARLOCK WARRIOR"), -- 1H sword
    [8]  = Classes("DEATHKNIGHT EVOKER HUNTER PALADIN WARRIOR"),                                     -- 2H sword
    [9]  = Classes("DEMONHUNTER"),                                                                    -- warglaive
    [10] = Classes("DRUID EVOKER HUNTER MAGE MONK PRIEST SHAMAN WARLOCK WARRIOR"),                   -- staff
    [13] = Classes("DEMONHUNTER DRUID EVOKER HUNTER MONK ROGUE SHAMAN WARRIOR"),                     -- fist
    [15] = Classes("DRUID EVOKER HUNTER MAGE PRIEST ROGUE SHAMAN WARLOCK WARRIOR"),                  -- dagger
    [18] = Classes("HUNTER ROGUE WARRIOR"),                                                           -- crossbow
    [19] = Classes("MAGE PRIEST WARLOCK"),                                                            -- wand
}
P.WEAPON_CLASSES = WEAPON_CLASSES

-- Primary stats each class can use (any spec). A Strength trinket is no use
-- to a Priest.
local CLASS_STATS = {
    DEATHKNIGHT = { STRENGTH = true }, WARRIOR = { STRENGTH = true },
    PALADIN = { STRENGTH = true, INTELLECT = true },
    DEMONHUNTER = { AGILITY = true }, HUNTER = { AGILITY = true }, ROGUE = { AGILITY = true },
    DRUID = { AGILITY = true, INTELLECT = true }, MONK = { AGILITY = true, INTELLECT = true },
    SHAMAN = { AGILITY = true, INTELLECT = true },
    EVOKER = { INTELLECT = true }, MAGE = { INTELLECT = true }, PRIEST = { INTELLECT = true },
    WARLOCK = { INTELLECT = true },
}

-- The item's primary stats as a set (STRENGTH/AGILITY/INTELLECT), or nil
-- when unknown or it has none, plus "pending" while its details are loading
-- or "failed" when they didn't load (ItemData.lua). Combined keys
-- (ITEM_MOD_AGILITY_INTELLECT_SHORT) count for each stat they name.
local primarySets = setmetatable({}, { __mode = "k" })   -- by stat table

local function PrimaryStats(item)
    if not item.itemID then return nil end
    local stats, state = P.ItemStats(item)
    if state == "loading" then return nil, "pending" end
    if not stats then return nil, state == "failed" and "failed" or nil end
    local cached = primarySets[stats]
    if cached ~= nil then return cached or nil end
    local set, any = {}, false
    for key in pairs(stats) do
        if type(key) == "string" and key:find("^ITEM_MOD_") then
            for _, stat in ipairs({ "STRENGTH", "AGILITY", "INTELLECT" }) do
                if key:find(stat, 1, true) then set[stat] = true any = true end
            end
        end
    end
    primarySets[stats] = any and set or false
    return any and set or nil
end

-- True while a gear item's stats are still loading (no verdict yet).
function P.GearDetailsPending(item)
    local _, state = PrimaryStats(item)
    return state == "pending"
end

-- "pending", "failed", or nil when the gear's details are in.
function P.GearDetailsState(item)
    local _, state = PrimaryStats(item)
    return state
end

-- Ask for the details of this character's items and the Warband bank's
-- (not every character's snapshot: 456 items in game), so they are usually
-- loaded before the player opens a task (called at a bank/vendor).
function P.PrefetchGearDetails()
    local currentKey = P.currentCharacterKey
    for _, snapshot in ipairs(P.AllSnapshots and P.AllSnapshots() or {}) do
        local relevant = snapshot.scope == "warband" or (snapshot.character and snapshot.character.key == currentKey)
        for _, item in ipairs(relevant and snapshot.items or {}) do
            if (item.classID == 2 or item.classID == 4) and item.equipLoc and item.equipLoc ~= "" then
                PrimaryStats(item)
            else
                P.ItemDataState(item)
            end
        end
    end
end

-- Can this character wear the item at all (armor type, shields, weapon type,
-- primary stat, level)?
local function CanCharacterUse(char, item, levelLimited)
    local class = char.classFile or ""
    if item.classID == 2 and item.subclassID and WEAPON_CLASSES[item.subclassID] and class ~= "" then
        if not WEAPON_CLASSES[item.subclassID][class] then return false end
    end
    if (item.classID == 2 or item.classID == 4) and CLASS_STATS[class] then
        local stats = PrimaryStats(item)
        if stats then
            local usable = false
            for stat in pairs(stats) do
                if CLASS_STATS[class][stat] then usable = true break end
            end
            if not usable then return false end
        end
    end
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

-- Trinkets, weapons, off-hands and shields that need max level: their value
-- depends on spec, role and content more than item level.
local SITUATIONAL_SLOTS = {
    INVTYPE_TRINKET = true, INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true, INVTYPE_SHIELD = true, INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
}
local function IsSituational(item)
    if not SITUATIONAL_SLOTS[item.equipLoc or ""] then return false end
    local maxLevel = P.GetMaxPlayerLevel and P.GetMaxPlayerLevel() or 0
    return maxLevel > 0 and (item.requiredLevel or 0) >= maxLevel
end

-- The only character who can ever use a Soulbound item (it can't be traded,
-- mailed or put in the Warband bank): its owner. In game, Soulbound pieces
-- in Finalomega's bags were kept as "Upgrade for Minormer". Nil when the item
-- can move between characters.
local function BoundOwnerKey(item, ownerKey)
    if item.isSoulbound and not item.isWarbandBound then
        return ownerKey or P.currentCharacterKey
    end
    return nil
end
P.BoundOwnerKey = BoundOwnerKey

local function GearUsers(item, ownerKey)
    local users = {}
    local only = BoundOwnerKey(item, ownerKey)
    for _, char in ipairs(P.CharactersWith("receivesGear")) do
        local levelLimited = P.GetRole(char) == "leveling"
        if (not only or char.key == only) and CanCharacterUse(char, item, levelLimited) then
            table.insert(users, char)
        end
    end
    return users
end
P.GearUsersFor = GearUsers

-- Gear-receiving characters for whom this item beats what they wear
-- (two-slot items compare against the weaker slot; empty slot = 0).
local function UpgradeUsers(item, ownerKey)
    local slots = P.INVTYPE_TO_SLOTS and P.INVTYPE_TO_SLOTS[item.equipLoc or ""]
    if not slots or not item.itemLevel or item.itemLevel <= 0 then return {} end
    local users = {}
    for _, char in ipairs(GearUsers(item, ownerKey)) do
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
P.RolesAssigned = AnyRolesAssigned

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

-- The lowest item level the character wears in the item's slot(s), or nil.
-- `skip`: slots to leave out (e.g. the ring slot already holding a set piece).
local function EquippedLevelFor(char, item, skip)
    local slots = P.INVTYPE_TO_SLOTS and P.INVTYPE_TO_SLOTS[item.equipLoc or ""]
    if not (char and slots and char.equipped) then return nil end
    local lowest
    for _, slot in ipairs(slots) do
        local level = not (skip and skip[slot]) and char.equipped[slot] or nil
        if type(level) == "number" and level > 0 and (not lowest or level < lowest) then lowest = level end
    end
    return lowest
end
P.EquippedLevelFor = EquippedLevelFor

-- Distinct slots of a set the character holds in bags and bank (plus the
-- Warband bank for pieces that aren't soulbound).
local function HeldSetSlots(char, setID)
    local slots, count = {}, 0
    for _, snapshot in ipairs(P.AllSnapshots and P.AllSnapshots() or {}) do
        local mine = snapshot.character and snapshot.character.key == char.key
        if mine or snapshot.scope == "warband" then
            for _, held in ipairs(snapshot.items or {}) do
                local fits = mine or not held.isSoulbound
                if fits and held.equipLoc and not slots[held.equipLoc] and P.ItemSetID(held) == setID then
                    slots[held.equipLoc] = true
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- The highest item level an upgradable item could reach. Midnight tracks
-- step about +3 per rank (Method: Champion 292-308, Hero 305-321, Myth
-- 318-334); +4 per remaining rank errs toward "it could still catch up".
local UPGRADE_STEP = 4
local function UpgradeCeiling(item, facts)
    if not (item.itemLevel and facts.upgradeCur and facts.upgradeMax) then return nil end
    return item.itemLevel + (facts.upgradeMax - facts.upgradeCur) * UPGRADE_STEP
end

-- Could upgrading the item make it at least as good as what any wearer has?
-- (Player's rule: a track that can't get past what you wear doesn't count.)
local function CanOutgrowWearers(item, facts, users)
    local ceiling = UpgradeCeiling(item, facts)
    if not ceiling then return true end
    for _, char in ipairs(users) do
        local worn = EquippedLevelFor(char, item)
        if not worn or ceiling > worn then return true end
    end
    return false
end

-- Set rules for gear someone can wear but that isn't an upgrade. Returns a
-- reason id and evidence, or nil when sets don't decide it.
local function SetVerdict(item, setID, facts, users)
    for _, char in ipairs(users) do
        local sets = char.equippedSets or {}
        local worn = sets[setID] and sets[setID].count or 0
        local min = facts.setMin or 2
        -- Already active: this piece adds nothing new at the lowest bonus.
        if sets[setID] and sets[setID].active and worn >= min then min = worn + 1 end
        -- A class set replaced by another class set the character wears.
        if facts.classes and (not facts.upgradable or not CanOutgrowWearers(item, facts, { char })) then
            for otherID, other in pairs(sets) do
                if otherID ~= setID and other.classSet and (other.active or other.count >= (other.min or 2)) then
                    return "set_replaced", (char.name or "?") .. " wears " .. other.count .. " pieces of "
                        .. (other.name or "a newer class set") .. (other.level and (" at " .. other.level) or "")
                        .. "; this set (" .. (facts.setName or "old set") .. ") can't be upgraded"
                end
            end
        end
        -- Would turn on a bonus that isn't active.
        if worn < min and worn + HeldSetSlots(char, setID) >= min then
            -- The piece would replace what's in a slot not holding this set.
            local wornLevel = EquippedLevelFor(char, item, sets[setID] and sets[setID].slots)
            local cost = wornLevel and item.itemLevel and (wornLevel - item.itemLevel) or nil
            return "set_completes", "With " .. (worn > 0 and (worn .. " piece" .. (worn == 1 and "" or "s") .. " "
                .. (char.name or "?") .. " wears") or "pieces you hold") .. ", completes "
                .. (facts.setName or "a set") .. " (" .. min .. ")"
                .. (cost and cost > 0 and ("; costs " .. cost .. " item levels in that slot") or "")
        end
    end
    return nil
end

-- ctx: { locationKey = ..., owner = character record or nil }
local function ExplainItem(item, ctx)
    ctx = ctx or {}
    local reasons = {}
    local function add(id, evidence) table.insert(reasons, { id = id, evidence = evidence }) end
    local keptForNow

    local rule = ns.DB.rules and ns.DB.rules.items and ns.DB.rules.items[item.itemID]
    if type(rule) == "table" then
        if rule.protect then add("protected") end
        local keep = rule.keepReason and KEEP_REASON_BY_CHOICE[rule.keepReason]
        if keep then
            local wornNow = rule.keepReason == "fornow" and EquippedLevelFor(ctx.owner or P.GetCurrentCharacter(), item)
            if rule.keepReason == "investment" and rule.keepUntil and Now() >= rule.keepUntil then
                add("investment_due", "Keep holding it, or let it go")
            elseif rule.keepReason == "fornow" and rule.keepAtLevel and wornNow and wornNow > rule.keepAtLevel then
                -- Kept "for now"; the slot got better since: ask again (player's rule).
                keptForNow = "You kept it for now at " .. rule.keepAtLevel .. "; you now wear " .. wornNow .. ". "
            else
                add(keep, rule.keepReason == "fornow" and rule.keepAtLevel
                    and ("Until you wear better than " .. rule.keepAtLevel .. " in that slot") or nil)
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

    if IsGear(item) and P.EquipmentSetsWith then
        for _, entry in ipairs(P.EquipmentSetsWith(item.itemID)) do
            add("equipment_set", "In " .. (entry.character.name or "?") .. "'s " .. table.concat(entry.sets, ", ") .. " set")
        end
    end

    local refused = P.MerchantRefused and P.MerchantRefused(item.itemID)
    if refused then
        local when = "A vendor refused it" .. (refused.at and date and (" on " .. date("%Y-%m-%d", refused.at)) or "") .. ". "
        local price = P.CanBeAuctioned and P.CanBeAuctioned(item) and P.GetAuctionPrice and P.GetAuctionPrice(item)
        if price and not price.unconfirmed then
            add("vendor_refused_auction", when .. "It sells for about " .. P.FormatMoney(price.price)
                .. " at the auction house (" .. P.FormatPriceSource(price) .. ").")
        else
            add("vendor_refused", when .. "To destroy it: drag it out of your bag, drop it on the game world, and confirm.")
        end
    end

    local detailsState = IsGear(item) and AnyRolesAssigned() and P.GearDetailsState(item) or nil
    if IsGear(item) and item.levelPending then detailsState = "pending" end
    local gearPending = detailsState ~= nil
    if detailsState == "pending" then
        -- No verdict until the stats are in; the list shows it as checking.
        add("details_loading")
    elseif detailsState == "failed" then
        -- Never judge gear without its stats (a guess made weapons look usable).
        add("details_unavailable")
    end

    -- Item level 1 "gear" is a curiosity, not equipment (in game: Noble's
    -- Signet Ring, a Warbound Eversong treasure with "+1 Nobility", read as
    -- "below what you wear").
    local curiosity = IsGear(item) and item.itemLevel and item.itemLevel <= 1
    if curiosity then
        add("possible_keepsake", "Item level 1: usually a treasure, quest curiosity or cosmetic, not real gear")
    end

    if IsGear(item) and not gearPending and not curiosity then
        local collected = AppearanceCollected(item)
        if collected == false then
            add("appearance_uncollected", "Equip it once to collect the appearance; then it can go")
        end
        if AnyRolesAssigned() then
            local ownerKey = ctx.owner and ctx.owner.key or nil
            local users = GearUsers(item, ownerKey)
            local upgrades = UpgradeUsers(item, ownerKey)
            if #upgrades > 0 then
                local labels = {}
                for _, char in ipairs(upgrades) do
                    labels[#labels + 1] = char.name .. " (" .. P.GetRoleLabel(P.GetRole(char)) .. ")"
                end
                add("usable_gear", "Upgrade for " .. Names(labels))
            elseif #users > 0 then
                local facts = P.ItemTooltipFacts and P.ItemTooltipFacts(item) or { state = "unknown" }
                local setID = P.ItemSetID and P.ItemSetID(item)
                local setReason, setEvidence
                if setID and facts.state == "ready" then setReason, setEvidence = SetVerdict(item, setID, facts, users) end
                if setReason then
                    add(setReason, (setReason ~= "set_completes" and keptForNow or "") .. setEvidence)
                elseif IsSituational(item) then
                    -- Item level is a weak test for these: an on-use effect or a
                    -- spec, role or content fit can matter more (player's point).
                    add("situational_gear", "Wearable by " .. Names(users, "name")
                        .. "; trinkets and weapons can matter for a spec, role, or dungeon vs. raid")
                elseif facts.state == "ready" and not SITUATIONAL_SLOTS[item.equipLoc or ""]
                    and (not facts.upgradable or not CanOutgrowWearers(item, facts, users)) then
                    -- (Trinkets and weapons stay the player's call at any level.)
                    -- Worse than what everyone wears and it can't get better
                    -- (no upgrade track): it can go (player's rule).
                    local ceiling = facts.upgradable and UpgradeCeiling(item, facts)
                    add("outgrown_no_upgrade", (keptForNow or "") .. "Wearable by " .. Names(users, "name")
                        .. ", but below what they wear"
                        .. (ceiling and ("; even fully upgraded (" .. facts.upgradeTrack .. " " .. facts.upgradeCur .. "/"
                            .. facts.upgradeMax .. ") it would reach about " .. ceiling)
                            or ", and it can't be upgraded"))
                else
                    -- Wearable but worse, and it can still be upgraded (or its
                    -- tooltip isn't in yet): the player decides.
                    add("outgrown_gear", "Wearable by " .. Names(users, "name") .. ", but not an upgrade"
                        .. (facts.upgradable and ("; can be upgraded (" .. facts.upgradeTrack .. " "
                            .. facts.upgradeCur .. "/" .. facts.upgradeMax .. ")") or ""))
                end
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

    if (item.quality or 0) >= 5 and (item.quality or 0) ~= 7 then
        -- Legendary (5) and Artifact (6); heirlooms (7) are handled elsewhere.
        add("legendary_keepsake", "Usually can't be earned again; keep it for the memory or the look, or let it go")
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
    local judgedAsGear = IsGear(item) and AnyRolesAssigned()   -- includes gear still loading
    if not hasKeep and not judgedAsGear and item.quality ~= 0 and item.expansionID
        and not P.IsOldExpansion(item.expansionID) then
        add("current_expansion")
    end

    if #reasons == 0 then add("unexplained") end

    -- Primary: keep > free > review > info.
    local order = { keep = 1, free = 2, review = 3, info = 4 }
    local function rank(id)
        local def = REASONS[id]
        return def.rank or (def.pinned and 1.5) or order[def.disposition]
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
function P.SetKeepReason(itemID, choice, itemName, remindAfterDays, item)
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
    -- "For now": ask again once the slot holds something better than today.
    rule.keepAtLevel = (choice == "fornow" and item) and EquippedLevelFor(P.GetCurrentCharacter(), item) or nil
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
-- One line per item for the enhanced log (/icanteven why items): where it is,
-- item level, binding, and the primary reason with its evidence. Too long for
-- chat; meant for reading from the saved file.
function P.WhyItemLines(scope)
    local currentKey = P.currentCharacterKey or P.GetCharacterKey()
    local lines = {}
    for _, snapshot in ipairs(P.AllSnapshots()) do
        local char = snapshot.character
        local include = scope == "all" or snapshot.scope == "warband" or (char and char.key == currentKey)
        if include then
            local label = snapshot.scope == "warband" and "Warband" or ((char and char.name or "?") .. " " .. snapshot.scope)
            local locationKey = snapshot.scope == "warband" and "warband" or LocationKeyFor(snapshot.scope, char and char.key)
            for _, item in ipairs(snapshot.items) do
                if P.GetItemType and not item.typeTag then item.typeTag = P.GetItemType(item) end
                local explanation = ExplainItem(item, { locationKey = locationKey, owner = char })
                local evidence = {}
                for _, r in ipairs(explanation.reasons or {}) do
                    evidence[#evidence + 1] = r.id .. (r.evidence and (":" .. r.evidence) or "")
                end
                lines[#lines + 1] = string.format("%s | %s x%d | q%s ilvl %s req %s | %s | %s | %s",
                    label, tostring(item.name), item.count or 1, tostring(item.quality), tostring(item.itemLevel),
                    tostring(item.requiredLevel), tostring(item.bindingScope), explanation.disposition,
                    table.concat(evidence, "; "))
            end
        end
    end
    return lines
end

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
    -- A vendor price no vendor pays isn't what letting it go costs.
    if ids.vendor_refused or ids.vendor_refused_auction then value = 0 end
    if P.GetItemValue then
        local best, source = P.GetItemValue(item)
        if best and best > value and source ~= "vendor" then
            parts[#parts + 1] = "Worth about " .. P.FormatMoney(best) .. " (" .. source .. ")."
        elseif value > 0 then
            parts[#parts + 1] = "Worth " .. P.FormatMoney(value) .. " at a vendor."
        elseif ids.vendor_refused then
            parts[#parts + 1] = "Vendors won't buy it."
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
    if P.MerchantRefused and P.MerchantRefused(item.itemID) then return false end
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
    -- The same for the Warband bank: in game it held 32 "Can go" stacks while
    -- the character-bank task (which doesn't read the Warband bank) showed 3.
    P.RegisterTask({
        name = "Pull Warband Items That Can Go",
        description = "Warband bank items you can let go of, into your bags to sell.",
        preset = { name = "Pull Warband Items That Can Go", source = P.STORAGE_WARBAND_BANK, dest = "Bags",
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