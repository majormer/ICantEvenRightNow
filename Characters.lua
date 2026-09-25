-- I Can't Even Right Now (With My Bags and Bank) — Characters
-- Account-wide roster: character facts, roles, role suggestions, and the
-- per-character / account inventory snapshots every other feature reads.
--
-- Roles decide "who benefits": only characters whose role receives gear or
-- materials count when the addon explains where an item is useful.
-- Unassigned characters are ignored, so an unsorted roster never floods
-- decisions. Characters are known only after logging in once with the addon.

local ADDON_NAME, ns = ...

local Core = ns.Core
local P    = ns.Private

local BAG_SCOPE  = P.BAG_SCOPE
local BANK_SCOPE = P.BANK_SCOPE

-- ---------------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------------

local ROLE_DEFS = {
    main       = { label = "Main / Active", receivesGear = true,  receivesMaterials = true,
                   description = "A character you play. Gets gear upgrades and materials for its professions." },
    leveling   = { label = "Leveling",      receivesGear = true,  receivesMaterials = true, levelLimitedGear = true,
                   description = "A character you are leveling. Gets gear it can use now and materials for its professions." },
    crafter    = { label = "Crafter",       receivesGear = false, receivesMaterials = true,
                   description = "Profession-only. Gets materials for its professions, never gear." },
    utility    = { label = "Utility",       receivesGear = false, receivesMaterials = false,
                   description = "Gold farmer, bank or auction alt. Receives nothing; its items are yours to move or sell." },
    unassigned = { label = "Unassigned",    receivesGear = false, receivesMaterials = false,
                   description = "Not sorted yet. Ignored when deciding who benefits from an item." },
}
local ROLE_ORDER = { "main", "leveling", "crafter", "utility", "unassigned" }

P.ROLE_DEFS  = ROLE_DEFS
P.ROLE_ORDER = ROLE_ORDER

-- Professions that do not make a character a "crafter" on their own.
local SECONDARY_SKILL_LINES = { [185] = true, [356] = true, [794] = true }  -- Cooking, Fishing, Archaeology

local CLASS_ARMOR = {
    DEATHKNIGHT = 4, PALADIN = 4, WARRIOR = 4,
    EVOKER = 3, HUNTER = 3, SHAMAN = 3,
    DEMONHUNTER = 2, DRUID = 2, MONK = 2, ROGUE = 2,
    MAGE = 1, PRIEST = 1, WARLOCK = 1,
}
P.CLASS_ARMOR = CLASS_ARMOR

local LEVEL_HISTORY_MAX = 6
local LEVELING_WINDOW_SECONDS = 14 * 24 * 3600
local LEARNED_PATTERN_MIN = 3

local function Now() return time and time() or 0 end

local function MaxLevel()
    local fn = GetMaxLevelForPlayerExpansion or GetMaxLevelForLatestExpansion
    local ok, level = pcall(function() return fn and fn() end)
    if ok and type(level) == "number" and level > 0 then return level end
    return 80
end
P.GetMaxPlayerLevel = MaxLevel

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------

local function Roster()
    ns.DB.characters = ns.DB.characters or {}
    return ns.DB.characters
end

local function EnsureSnapshots(char)
    char.scans = char.scans or {}
    char.scans.bags = char.scans.bags or {}
    char.scans.bank = char.scans.bank or {}
    char.lastScan = char.lastScan or {}
    char.lastScan.bags = char.lastScan.bags or 0
    char.lastScan.bank = char.lastScan.bank or 0
    return char
end

local function Warband()
    ns.DB.warband = ns.DB.warband or {}
    local warband = ns.DB.warband
    warband.items = warband.items or {}
    warband.scannedAt = warband.scannedAt or 0
    warband.tabs = warband.tabs or {}
    return warband
end
P.GetWarbandSnapshot = Warband

-- Realm names are normalized (no spaces or dashes) so "Area 52" from
-- GetRealmName and "Area52" from UnitFullName give the same key.
local function NormalizeRealm(realm)
    return (tostring(realm or ""):gsub("[%s%-]", ""))
end

local function GetCharacterKey()
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end
    name = name or (UnitName and UnitName("player")) or "Unknown"
    if not realm or realm == "" then
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "Unknown"
    end
    realm = NormalizeRealm(realm)
    if realm == "" then realm = "Unknown" end
    return name .. "-" .. realm, name, realm
end
P.GetCharacterKey = GetCharacterKey

local function ReadProfessions()
    local list = {}
    if not (GetProfessions and GetProfessionInfo) then return list end
    local slots = { GetProfessions() }
    for i = 1, 5 do
        local slot = slots[i]
        if slot then
            local name, _, skill, maxSkill, _, _, skillLine = GetProfessionInfo(slot)
            if name then
                table.insert(list, { name = name, skillLine = skillLine, skill = skill, maxSkill = maxSkill,
                    secondary = SECONDARY_SKILL_LINES[skillLine] or false })
            end
        end
    end
    return list
end

-- Equipped item level per inventory slot, for "upgrade for <alt>" hints.
local EQUIP_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local function ReadEquipped()
    if not (ItemLocation and ItemLocation.CreateFromEquipmentSlot and C_Item and C_Item.GetCurrentItemLevel) then
        return nil
    end
    local equipped = {}
    for _, slot in ipairs(EQUIP_SLOTS) do
        local ok, location = pcall(ItemLocation.CreateFromEquipmentSlot, ItemLocation, slot)
        if ok and location and location:IsValid() then
            local okLevel, level = pcall(C_Item.GetCurrentItemLevel, location)
            if okLevel and type(level) == "number" then equipped[slot] = level end
        end
    end
    return equipped
end

-- Creates or refreshes the current character's record. Safe to call often.
local function EnsureCurrentCharacter(levelOverride)
    local roster = Roster()
    local key, name, realm = GetCharacterKey()
    local char = roster[key]
    local isNew = char == nil
    if isNew then
        char = { key = key, firstSeen = Now(), levelHistory = {} }
        roster[key] = char
    end
    char.key, char.name, char.realm = key, name, realm
    if UnitClass then
        local className, classFile = UnitClass("player")
        char.className, char.classFile = className or char.className, classFile or char.classFile
    end
    char.armorSubclass = CLASS_ARMOR[char.classFile or ""] or char.armorSubclass
    local level = tonumber(levelOverride) or (UnitLevel and UnitLevel("player"))
    if type(level) == "number" and level > 0 then
        local history = char.levelHistory or {}
        local last = history[#history]
        if not last or last.level ~= level then
            table.insert(history, { at = Now(), level = level })
            while #history > LEVEL_HISTORY_MAX do table.remove(history, 1) end
        end
        char.levelHistory = history
        char.level = level
    end
    local professions = ReadProfessions()
    if #professions > 0 or isNew then char.professions = professions end
    char.equipped = ReadEquipped() or char.equipped
    if P.NoteReturn and not isNew then P.NoteReturn(char, char.lastSeen) end
    char.lastSeen = Now()
    EnsureSnapshots(char)

    -- The first character to log in after upgrading claims the old bag scan.
    local claim = ns.DB.pendingBagScanClaim
    if claim and #char.scans.bags == 0 then
        char.scans.bags = claim.items or {}
        char.lastScan.bags = claim.scannedAt or 0
        ns.DB.pendingBagScanClaim = nil
    end
    P.currentCharacterKey = key
    return char, isNew
end
P.EnsureCurrentCharacter = EnsureCurrentCharacter

local function GetCurrentCharacter()
    local key = P.currentCharacterKey or GetCharacterKey()
    local char = Roster()[key]
    if not char then char = EnsureCurrentCharacter() end
    return EnsureSnapshots(char)
end
P.GetCurrentCharacter = GetCurrentCharacter

function P.GetCharacter(key) return Roster()[key] end

-- Characters sorted: current first, then by role order, then by name.
function P.GetCharacters()
    local list = {}
    for _, char in pairs(Roster()) do table.insert(list, char) end
    local current = P.currentCharacterKey
    local rank = {}
    for i, role in ipairs(ROLE_ORDER) do rank[role] = i end
    table.sort(list, function(a, b)
        if (a.key == current) ~= (b.key == current) then return a.key == current end
        local ra, rb = rank[a.role or "unassigned"], rank[b.role or "unassigned"]
        if ra ~= rb then return ra < rb end
        return (a.key or "") < (b.key or "")
    end)
    return list
end

-- ---------------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------------

local function GetRole(char)
    local role = char and char.role
    if role and ROLE_DEFS[role] then return role end
    return "unassigned"
end
P.GetRole = GetRole

function P.GetRoleLabel(role) return (ROLE_DEFS[role] or ROLE_DEFS.unassigned).label end

function P.RoleReceives(role, capability)
    local def = ROLE_DEFS[role or "unassigned"] or ROLE_DEFS.unassigned
    return def[capability] and true or false
end

local function SetRole(key, role)
    if not ROLE_DEFS[role] then return false end
    local char = Roster()[key]
    if not char then return false end
    char.role = role ~= "unassigned" and role or nil
    char.roleSetAt = Now()
    if Core.OnRosterChanged then Core.OnRosterChanged() end
    return true
end
P.SetCharacterRole = SetRole

function P.SetRoleForMany(keys, role)
    local changed = 0
    for _, key in ipairs(keys or {}) do
        if SetRole(key, role) then changed = changed + 1 end
    end
    return changed
end

-- Characters whose role has the capability ("receivesGear"/"receivesMaterials").
-- Unassigned characters are never included.
function P.CharactersWith(capability)
    local list = {}
    for _, char in pairs(Roster()) do
        local role = GetRole(char)
        if role ~= "unassigned" and P.RoleReceives(role, capability) then table.insert(list, char) end
    end
    table.sort(list, function(a, b) return (a.key or "") < (b.key or "") end)
    return list
end

function P.CountByRole()
    local counts = {}
    for _, role in ipairs(ROLE_ORDER) do counts[role] = 0 end
    for _, char in pairs(Roster()) do
        local role = GetRole(char)
        counts[role] = counts[role] + 1
    end
    return counts
end

-- ---------------------------------------------------------------------------
-- Role suggestions (onboarding O1)
-- ---------------------------------------------------------------------------

local function PrimaryProfessions(char)
    local names = {}
    for _, prof in ipairs(char.professions or {}) do
        if not prof.secondary then table.insert(names, prof.name) end
    end
    return names
end

local function IsMaxLevel(char)
    return (char.level or 0) >= MaxLevel()
end

local function GainedLevelsRecently(char)
    local history = char.levelHistory or {}
    if #history < 2 then return false end
    local last, previous = history[#history], history[#history - 1]
    return last.level > previous.level and (Now() - last.at) <= LEVELING_WINDOW_SECONDS
end

-- A coarse profile used to learn from the player's own choices.
local function Profile(char)
    local band = IsMaxLevel(char) and "max" or "below"
    local crafts = #PrimaryProfessions(char) > 0 and "crafts" or "nocrafts"
    return band .. ":" .. crafts
end

local function LearnedRoleFor(char)
    local profile = Profile(char)
    local tally, total = {}, 0
    for _, other in pairs(Roster()) do
        if other.key ~= char.key and other.role and Profile(other) == profile then
            tally[other.role] = (tally[other.role] or 0) + 1
            total = total + 1
        end
    end
    local bestRole, bestCount = nil, 0
    for role, count in pairs(tally) do
        if count > bestCount then bestRole, bestCount = role, count end
    end
    if bestRole and bestCount >= LEARNED_PATTERN_MIN and bestCount * 2 > total then
        return bestRole, bestCount
    end
    return nil
end

-- Returns role, reason. Suggestions are never applied without the player.
local function SuggestRole(char)
    if not char then return "unassigned", "" end
    local learned, count = LearnedRoleFor(char)
    if learned then
        return learned, "Matches " .. count .. " similar characters you set as " .. P.GetRoleLabel(learned)
    end
    local professions = PrimaryProfessions(char)
    if IsMaxLevel(char) then
        local counts = P.CountByRole()
        if counts.main == 0 then return "main", "Max level; looks like your main" end
        return "main", "Max level"
    end
    if GainedLevelsRecently(char) then
        return "leveling", "Gained levels recently"
    end
    if #professions > 0 then
        return "crafter", "Level " .. tostring(char.level or "?") .. " with " .. table.concat(professions, " and ")
    end
    return "utility", "Level " .. tostring(char.level or "?") .. " without professions"
end
P.SuggestRole = SuggestRole

-- The most recently configured other character, for "Same as <name>".
function P.LastConfiguredCharacter(exceptKey)
    local best
    for _, char in pairs(Roster()) do
        if char.key ~= exceptKey and char.role and char.roleSetAt then
            if not best or char.roleSetAt > best.roleSetAt then best = char end
        end
    end
    return best
end

-- Applies each character's suggestion. keys = nil means every Unassigned character.
function P.AcceptRoleSuggestions(keys)
    local targets = {}
    if keys then
        targets = keys
    else
        for key, char in pairs(Roster()) do
            if not char.role then table.insert(targets, key) end
        end
    end
    local changed = 0
    for _, key in ipairs(targets) do
        local role = SuggestRole(Roster()[key])
        if SetRole(key, role) then changed = changed + 1 end
    end
    return changed
end

-- ---------------------------------------------------------------------------
-- Inventory snapshots (W1)
-- ---------------------------------------------------------------------------

-- Scan lists for the current character: "bags" or "bank" (character bank
-- plus the account-wide Warband snapshot, as earlier versions stored them).
function P.GetScanList(scope)
    local char = GetCurrentCharacter()
    if scope == BAG_SCOPE then return char.scans.bags end
    local combined = {}
    for _, item in ipairs(char.scans.bank) do table.insert(combined, item) end
    for _, item in ipairs(Warband().items) do table.insert(combined, item) end
    return combined
end

function P.SetScanList(scope, items)
    local char = GetCurrentCharacter()
    if scope == BAG_SCOPE then
        char.scans.bags = items
    else
        char.scans.bank = items
    end
end

function P.SetWarbandItems(items)
    Warband().items = items
    Warband().scannedAt = Now()
end

-- When the current character last scanned bags/bank (0 = never).
function P.GetLastScan(scope)
    local char = GetCurrentCharacter()
    if scope == BAG_SCOPE then return char.lastScan.bags or 0 end
    return char.lastScan.bank or 0
end

function P.MarkScanned(scope)
    local char = GetCurrentCharacter()
    char.lastScan[scope == BAG_SCOPE and "bags" or "bank"] = Now()
end

-- Remove moved items (by location key) from every current snapshot list.
function P.RemoveFromSnapshots(movedKeys)
    local char = GetCurrentCharacter()
    local function filter(list)
        local kept = {}
        for _, item in ipairs(list or {}) do
            if not movedKeys[P.LocationKey(item)] then table.insert(kept, item) end
        end
        return kept
    end
    char.scans.bags = filter(char.scans.bags)
    char.scans.bank = filter(char.scans.bank)
    Warband().items = filter(Warband().items)
end

-- Every snapshot on the account: { character = char|nil, scope, items, scannedAt }.
function P.AllSnapshots()
    local list = {}
    for _, char in pairs(Roster()) do
        EnsureSnapshots(char)
        table.insert(list, { character = char, scope = BAG_SCOPE, items = char.scans.bags, scannedAt = char.lastScan.bags })
        table.insert(list, { character = char, scope = BANK_SCOPE, items = char.scans.bank, scannedAt = char.lastScan.bank })
    end
    local warband = Warband()
    table.insert(list, { character = nil, scope = "warband", items = warband.items, scannedAt = warband.scannedAt })
    return list
end

-- Decision fields added at runtime (Evaluator.BuildDecision). They are
-- recomputed on every use, and `rule` would duplicate rule tables into every
-- snapshot, so they are removed before the game writes saved variables.
local TRANSIENT_FIELDS = {
    "rule", "curated", "blockedReasons", "eligibleForBankMove", "eligibleForRecall",
    "ruleStatus", "bankTargetStorage", "reason", "key",
}

function P.CompactSnapshots()
    local function compact(list)
        for _, item in ipairs(list or {}) do
            for _, field in ipairs(TRANSIENT_FIELDS) do item[field] = nil end
        end
    end
    for _, char in pairs(Roster()) do
        if char.scans then
            compact(char.scans.bags)
            compact(char.scans.bank)
        end
    end
    compact(Warband().items)
    if ns.DB.unassignedBankScan then compact(ns.DB.unassignedBankScan.items) end
end