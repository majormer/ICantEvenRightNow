-- Simulated World of Warcraft client for offline tests.
-- Builds a fresh global environment per game with fake WoW APIs backed by a
-- small inventory simulation: containers, item definitions, cursor, locks,
-- bank/vendor/auction context, timers, events, and hardware-event gating.

local Frames = require("frames")

local World = {}
World.__index = World

-- Enum values verified 2026-09-25 against warcraft.wiki.gg (12.x client).
local ENUM = {
    BagIndex = {
        Accountbanktab = -3, Characterbanktab = -2, Keyring = -1,
        Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5,
        CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8,
        CharacterBankTab_4 = 9, CharacterBankTab_5 = 10, CharacterBankTab_6 = 11,
        AccountBankTab_1 = 12, AccountBankTab_2 = 13, AccountBankTab_3 = 14,
        AccountBankTab_4 = 15, AccountBankTab_5 = 16,
    },
    BankType = { Character = 0, Guild = 1, Account = 2 },
    ItemBind = {
        None = 0, OnAcquire = 1, OnEquip = 2, OnUse = 3, Quest = 4,
        Unused1 = 5, Unused2 = 6, ToWoWAccount = 7, ToBnetAccount = 8, ToBnetAccountUntilEquipped = 9,
    },
    BagSlotFlags = {
        DisableAutoSort = 0x1, ClassEquipment = 0x2, ClassConsumables = 0x4,
        ClassProfessionGoods = 0x8, ClassJunk = 0x10, ClassQuestItems = 0x20,
        ExcludeJunkSell = 0x40, ClassReagents = 0x80, ExpansionCurrent = 0x100, ExpansionLegacy = 0x200,
    },
    PlayerInteractionType = {
        Merchant = 5, Banker = 8, GuildBanker = 10, MailInfo = 17, Auctioneer = 21, AccountBanker = 68,
    },
    ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Artifact = 6, Heirloom = 7 },
    TooltipDataType = { Item = 0, Spell = 1, Unit = 2 },
}

local EXPANSIONS = {
    "CLASSIC", "BURNING_CRUSADE", "WRATH_OF_THE_LICH_KING", "CATACLYSM", "MISTS_OF_PANDARIA",
    "WARLORDS_OF_DRAENOR", "LEGION", "BATTLE_FOR_AZEROTH", "SHADOWLANDS", "DRAGONFLIGHT",
    "WAR_WITHIN", "MIDNIGHT",
}
local EXPANSION_NAMES = {
    "Classic", "The Burning Crusade", "Wrath of the Lich King", "Cataclysm", "Mists of Pandaria",
    "Warlords of Draenor", "Legion", "Battle for Azeroth", "Shadowlands", "Dragonflight",
    "The War Within", "Midnight",
}

local BANK_BAG_MIN, BANK_BAG_MAX = 6, 16
local MAX_BUYBACK = 12

local function deepcopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do copy[deepcopy(k, seen)] = deepcopy(v, seen) end
    return copy
end
World.deepcopy = deepcopy

-- Pure-Lua bit operations (WoW provides a `bit` library).
local function bitop(a, b, fn)
    a, b = math.floor(a or 0), math.floor(b or 0)
    local result, place = 0, 1
    while a > 0 or b > 0 do
        if fn(a % 2, b % 2) then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end
local function fold(fn)
    return function(a, b, ...)
        local r = bitop(a, b, fn)
        for i = 1, select("#", ...) do r = bitop(r, (select(i, ...)), fn) end
        return r
    end
end
local bitlib = {
    band = fold(function(x, y) return x == 1 and y == 1 end),
    bor = fold(function(x, y) return x == 1 or y == 1 end),
    bxor = fold(function(x, y) return x ~= y end),
    lshift = function(a, n) return math.floor(a) * 2 ^ n end,
    rshift = function(a, n) return math.floor(math.floor(a) / 2 ^ n) end,
}

-- ---------------------------------------------------------------------------
-- World construction
-- ---------------------------------------------------------------------------

function World.new(opts)
    opts = opts or {}
    local self = setmetatable({}, World)
    self.now = opts.now or 1790000000         -- seconds (roughly 2026)
    self.timers = {}
    self.timerSeq = 0
    self.eventFrames = {}
    self.log = {}
    self.items = {}
    self.containers = {}
    self.cursor = nil
    self.hardwareEvent = false
    self.inCombat = false
    self.bankOpen = false
    self.vendorOpen = false
    self.ahOpen = false
    self.interaction = nil
    self.money = 0
    self.buyback = {}
    self.lostToBuyback = {}
    self.sold = {}
    self.blockedActions = {}
    self.asyncMoves = opts.asyncMoves or false
    self.moveLatency = opts.moveLatency or 0.3
    self.pendingMoves = {}
    self.bankTabs = { [0] = {}, [2] = {} }
    self.equipped = {}
    self.quests = { completed = {}, active = {} }
    self.collections = { appearances = {}, toys = {}, mounts = {}, pets = {} }
    self.player = {
        name = "Tester", realm = "TestRealm", level = 80, className = "Warrior",
        classFile = "WARRIOR", classID = 1, professions = {},
    }
    if opts.player then for k, v in pairs(opts.player) do self.player[k] = v end end
    self.addonsLoaded = { ICantEvenRightNow = true }
    self.frames = Frames.new(self)
    -- Default containers: backpack 20 slots, four 16-slot bags, empty reagent bag.
    self:setContainer(0, 20)
    for bag = 1, 4 do self:setContainer(bag, opts.bagSize or 16) end
    self:setContainer(5, 0)
    self.env = self:_buildEnv()
    return self
end

function World:setContainer(bagID, size)
    self.containers[bagID] = { size = size, slots = self.containers[bagID] and self.containers[bagID].slots or {} }
end

-- Purchase character (bankType 0) or Warband (bankType 2) bank tabs.
function World:addBankTab(bankType, bagID, name, depositFlags, size)
    self:setContainer(bagID, size or 98)
    table.insert(self.bankTabs[bankType], {
        ID = bagID, bankType = bankType, name = name or "", icon = 0, depositFlags = depositFlags or 0,
    })
end

-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------

-- def fields: name, quality, itemLevel, requiredLevel, itemType, itemSubType,
-- maxStack, equipLoc, icon, sellPrice, classID, subclassID, bindType,
-- expansionID, cached (default true), questID, isQuestItem, appearanceSourceID
function World:defineItem(itemID, def)
    def = def or {}
    def.itemID = itemID
    def.name = def.name or ("Item " .. itemID)
    def.quality = def.quality or 1
    def.itemLevel = def.itemLevel or 1
    def.requiredLevel = def.requiredLevel or 0
    def.maxStack = def.maxStack or 1
    def.equipLoc = def.equipLoc or ""
    def.icon = def.icon or 134400
    def.sellPrice = def.sellPrice or 0
    def.classID = def.classID or 15
    def.subclassID = def.subclassID or 0
    def.bindType = def.bindType or 0
    if def.cached == nil then def.cached = true end
    self.items[itemID] = def
    return def
end

function World:itemLink(itemID)
    local def = self.items[itemID]
    return "|cffffffff|Hitem:" .. itemID .. "::::::::80:::::|h[" .. (def and def.name or "?") .. "]|h|r"
end

local function parseItemID(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then
        local id = value:match("item:(%d+)")
        if id then return tonumber(id) end
        return tonumber(value)
    end
    return nil
end
World.parseItemID = parseItemID

-- Put a stack into a slot. opts: bound, locked, warboundUntilEquipped
function World:put(bagID, slot, itemID, count, opts)
    opts = opts or {}
    assert(self.items[itemID], "undefined item " .. tostring(itemID))
    local container = assert(self.containers[bagID], "no container " .. tostring(bagID))
    assert(slot >= 1 and slot <= container.size, "slot out of range")
    container.slots[slot] = {
        itemID = itemID, count = count or 1, locked = opts.locked or false,
        bound = opts.bound or false, wue = opts.warboundUntilEquipped or false,
        questActive = opts.questActive,
    }
    return container.slots[slot]
end

function World:getStack(bagID, slot)
    local container = self.containers[bagID]
    return container and container.slots[slot] or nil
end

function World:isAccessible(bagID)
    if bagID >= BANK_BAG_MIN and bagID <= BANK_BAG_MAX then return self.bankOpen end
    return self.containers[bagID] ~= nil
end

-- Find every slot holding itemID (accessible or not).
function World:findItem(itemID)
    local found = {}
    for bagID, container in pairs(self.containers) do
        for slot, stack in pairs(container.slots) do
            if stack.itemID == itemID then table.insert(found, { bagID = bagID, slot = slot, stack = stack }) end
        end
    end
    table.sort(found, function(a, b)
        if a.bagID ~= b.bagID then return a.bagID < b.bagID end
        return a.slot < b.slot
    end)
    return found
end

function World:countItem(itemID)
    local n = 0
    for _, f in ipairs(self:findItem(itemID)) do n = n + f.stack.count end
    return n
end

-- ---------------------------------------------------------------------------
-- Cursor and item movement (PickupContainerItem semantics)
-- ---------------------------------------------------------------------------

function World:pickup(bagID, slot)
    if not self:isAccessible(bagID) then return end
    local container = self.containers[bagID]
    if not container or slot < 1 or slot > container.size then return end
    local target = container.slots[slot]

    if not self.cursor then
        if target and not target.locked then
            self.cursor = { stack = target, fromBag = bagID, fromSlot = slot }
            target.locked = true      -- WoW keeps the source locked while on cursor
        end
        return
    end

    local cursor = self.cursor
    local stack = cursor.stack
    if cursor.fromBag == bagID and cursor.fromSlot == slot then
        stack.locked = false
        self.cursor = nil
        return
    end
    if target and target.locked then return end   -- cannot drop onto a locked slot

    local def = self.items[stack.itemID]
    local function complete()
        local source = self.containers[cursor.fromBag]
        local current = container.slots[slot]
        if current == nil then
            source.slots[cursor.fromSlot] = nil
            container.slots[slot] = stack
        elseif current.itemID == stack.itemID and def.maxStack > 1 then
            local room = def.maxStack - current.count
            local moved = math.min(room, stack.count)
            current.count = current.count + moved
            stack.count = stack.count - moved
            if stack.count <= 0 then source.slots[cursor.fromSlot] = nil end
        else
            -- swap
            source.slots[cursor.fromSlot] = current
            container.slots[slot] = stack
        end
        stack.locked = false
    end

    self.cursor = nil
    if self.asyncMoves then
        table.insert(self.pendingMoves, { due = self.now + self.moveLatency, complete = complete })
    else
        complete()
    end
end

function World:clearCursor()
    if self.cursor then
        self.cursor.stack.locked = false
        self.cursor = nil
    end
end

-- ---------------------------------------------------------------------------
-- Time, timers, events
-- ---------------------------------------------------------------------------

function World:after(delay, fn)
    self.timerSeq = self.timerSeq + 1
    local timer = { due = self.now + (delay or 0), fn = fn, seq = self.timerSeq }
    table.insert(self.timers, timer)
    return timer
end

-- Advance the clock, running timers and completing pending moves in order.
function World:advance(seconds)
    local target = self.now + (seconds or 0)
    while true do
        local nextIndex, nextDue
        for i, t in ipairs(self.timers) do
            if not t.cancelled and t.due <= target and (not nextDue or t.due < nextDue
                or (t.due == nextDue and t.seq < self.timers[nextIndex].seq)) then
                nextIndex, nextDue = i, t.due
            end
        end
        local moveIndex, moveDue
        for i, m in ipairs(self.pendingMoves) do
            if m.due <= target and (not moveDue or m.due < moveDue) then moveIndex, moveDue = i, m.due end
        end
        if moveIndex and (not nextDue or moveDue <= nextDue) then
            local move = table.remove(self.pendingMoves, moveIndex)
            self.now = math.max(self.now, move.due)
            move.complete()
            self:fire("BAG_UPDATE_DELAYED")
        elseif nextIndex then
            local timer = table.remove(self.timers, nextIndex)
            self.now = math.max(self.now, timer.due)
            timer.fn()
        else
            break
        end
    end
    self.now = target
end

function World:_registerEventFrame(frame)
    for _, f in ipairs(self.eventFrames) do
        if f == frame then return end
    end
    table.insert(self.eventFrames, frame)
end

function World:fire(event, ...)
    for _, frame in ipairs(self.eventFrames) do
        if frame._events[event] then
            frame:_fire("OnEvent", event, ...)
        end
    end
end

-- Run fn as if inside a hardware event (a real mouse click).
function World:withHardwareEvent(fn, ...)
    local previous = self.hardwareEvent
    self.hardwareEvent = true
    local ok, err = pcall(fn, ...)
    self.hardwareEvent = previous
    if not ok then error(err, 0) end
end

-- ---------------------------------------------------------------------------
-- Selling (UseContainerItem at a merchant)
-- ---------------------------------------------------------------------------

function World:sell(bagID, slot)
    local stack = self:getStack(bagID, slot)
    if not stack or stack.locked then return end
    local def = self.items[stack.itemID]
    if (def.sellPrice or 0) <= 0 then
        table.insert(self.log, "UI_ERROR: That item cannot be sold.")
        return
    end
    self.containers[bagID].slots[slot] = nil
    self.money = self.money + def.sellPrice * stack.count
    local record = { itemID = stack.itemID, count = stack.count, price = def.sellPrice }
    table.insert(self.sold, record)
    table.insert(self.buyback, record)
    if #self.buyback > MAX_BUYBACK then
        table.insert(self.lostToBuyback, table.remove(self.buyback, 1))
    end
end

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

function World:_buildEnv()
    local world = self
    local frames = self.frames
    local G = {}
    local env = {}
    self.missingGlobals = {}

    -- Lua builtins
    for _, name in ipairs({
        "assert", "error", "ipairs", "next", "pairs", "pcall", "xpcall", "print", "rawequal",
        "rawget", "rawset", "select", "setmetatable", "getmetatable", "tonumber", "tostring",
        "type", "unpack", "loadstring", "setfenv", "getfenv", "collectgarbage", "string",
        "table", "math", "coroutine",
    }) do G[name] = _G[name] end
    G.debug = { traceback = debug.traceback, getinfo = debug.getinfo }
    G.bit = bitlib
    G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        table.insert(world.log, table.concat(parts, " "))
    end

    -- WoW Lua extensions
    G.format = string.format
    G.strlower, G.strupper, G.strlen, G.strsub, G.strfind, G.strmatch, G.gsub, G.strrep =
        string.lower, string.upper, string.len, string.sub, string.find, string.match, string.gsub, string.rep
    G.tinsert, G.tremove, G.sort = table.insert, table.remove, table.sort
    G.floor, G.ceil, G.abs, G.max, G.min, G.mod = math.floor, math.ceil, math.abs, math.max, math.min, math.fmod
    G.strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
    G.strsplit = function(delim, s, limit)
        local out = {}
        local pattern = "([^" .. delim:gsub("%p", "%%%0") .. "]*)"
        for part in (s .. delim):gmatch(pattern .. delim:gsub("%p", "%%%0")) do out[#out + 1] = part end
        return unpack(out)
    end
    G.strjoin = function(delim, ...) return table.concat({ ... }, delim) end
    G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    G.tContains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
    G.CopyTable = deepcopy
    G.Mixin = function(obj, ...)
        for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do obj[k] = v end end
        return obj
    end
    G.CreateFromMixins = function(...) return G.Mixin({}, ...) end
    G.time = function(t) if t then return os.time(t) end return math.floor(world.now) end
    G.date = function(fmt, t) return os.date(fmt, t or math.floor(world.now)) end
    G.GetTime = function() return world.now end
    G.GetServerTime = function() return math.floor(world.now) end
    G.GetMoney = function() return world.money end
    G.geterrorhandler = function() return world.errorHandler or function(msg) error(msg, 0) end end
    G.seterrorhandler = function(fn) world.errorHandler = fn end
    G.InCombatLockdown = function() return world.inCombat end
    G.IsShiftKeyDown = function() return world.shiftDown or false end
    G.IsControlKeyDown = function() return world.controlDown or false end
    G.IsAltKeyDown = function() return world.altDown or false end
    G.PlaySound = function() end
    G.SOUNDKIT = setmetatable({}, { __index = function() return 0 end })
    G.hooksecurefunc = function(tbl, name, fn)
        if type(tbl) == "string" then tbl, name, fn = env, tbl, name end
        local original = tbl[name]
        tbl[name] = function(...)
            local r = { original(...) }
            fn(...)
            return unpack(r)
        end
    end
    G.SlashCmdList = {}
    G.hash_SlashCmdList = {}
    G.UISpecialFrames = {}
    G.StaticPopupDialogs = {}
    G.StaticPopup_Show = function(name) world.lastPopup = name end
    G.StaticPopup_Hide = function() end
    G.UIErrorsFrame = { AddMessage = function(_, msg) table.insert(world.log, "UI_ERROR: " .. tostring(msg)) end }
    G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(world.log, tostring(msg)) end }
    G.NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
    G.HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }
    G.RED_FONT_COLOR = { r = 1, g = 0.1, b = 0.1 }
    G.GREEN_FONT_COLOR = { r = 0.1, g = 1, b = 0.1 }
    G.GRAY_FONT_COLOR = { r = 0.5, g = 0.5, b = 0.5 }
    G.ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, hex = "|cffffffff" } end })

    -- Expansions
    for i, key in ipairs(EXPANSIONS) do
        G["LE_EXPANSION_" .. key] = i - 1
        G["EXPANSION_NAME" .. (i - 1)] = EXPANSION_NAMES[i]
    end
    G.LE_EXPANSION_LEVEL_CURRENT = #EXPANSIONS - 1
    G.GetExpansionLevel = function() return #EXPANSIONS - 1 end
    G.GetMaxLevelForPlayerExpansion = function() return world.maxLevel or 90 end
    G.GetMaxLevelForLatestExpansion = G.GetMaxLevelForPlayerExpansion

    G.Enum = deepcopy(ENUM)

    -- Frames
    G.CreateFrame = frames.CreateFrame
    G.EnumerateFrames = frames.EnumerateFrames
    G.UIParent = frames.CreateFrame("Frame", "UIParent")
    G.Minimap = frames.CreateFrame("Frame", "Minimap", G.UIParent)
    G.GameTooltip = frames.CreateFrame("GameTooltip", "GameTooltip", G.UIParent)
    G.GameTooltip:Hide()
    local tooltip = G.GameTooltip
    tooltip._lines = {}
    tooltip.SetOwner = function(t) t._lines = {} end
    tooltip.ClearLines = function(t) t._lines = {} end
    tooltip.AddLine = function(t, text) table.insert(t._lines, tostring(text)) end
    tooltip.AddDoubleLine = function(t, a, b) table.insert(t._lines, tostring(a) .. " " .. tostring(b)) end
    tooltip.SetText = function(t, text) t._lines = { tostring(text) } end
    tooltip.SetHyperlink = function(t, link) table.insert(t._lines, tostring(link)) end
    tooltip.SetBagItem = function(t, bag, slot)
        local stack = world:getStack(bag, slot)
        if stack then table.insert(t._lines, world.items[stack.itemID].name) end
    end
    tooltip.NumLines = function(t) return #t._lines end
    G.FauxScrollFrame_Update = function(frame, numItems, numToDisplay, buttonHeight)
        frame._faux = { numItems = numItems, numToDisplay = numToDisplay, buttonHeight = buttonHeight }
        local maxOffset = math.max(0, (numItems or 0) - (numToDisplay or 0))
        if (frame._offset or 0) > maxOffset then frame._offset = maxOffset end
        return numItems > numToDisplay
    end
    G.FauxScrollFrame_GetOffset = function(frame) return frame._offset or 0 end
    G.FauxScrollFrame_SetOffset = function(frame, offset) frame._offset = offset end
    G.FauxScrollFrame_OnVerticalScroll = function(frame, value, itemHeight, updateFn)
        frame._offset = math.floor(value / itemHeight + 0.5)
        if updateFn then updateFn(frame) end
    end
    G.GetCursorPosition = function() return 0, 0 end

    -- Addons
    G.C_AddOns = {
        IsAddOnLoaded = function(name) return world.addonsLoaded[name] and true or false end,
        GetAddOnMetadata = function(_, field) if field == "Version" then return "0.6.0" end end,
        LoadAddOn = function() return false end,
    }
    G.IsAddOnLoaded = G.C_AddOns.IsAddOnLoaded
    G.LibStub = nil

    -- Player
    G.UnitName = function(unit) if unit == "player" then return world.player.name end end
    G.UnitFullName = function(unit) if unit == "player" then return world.player.name, world.player.realm end end
    G.GetRealmName = function() return world.player.realm end
    G.GetNormalizedRealmName = function() return (world.player.realm:gsub("[%s%-]", "")) end
    G.UnitLevel = function(unit) if unit == "player" then return world.player.level end end
    G.UnitClass = function(unit)
        if unit == "player" then return world.player.className, world.player.classFile, world.player.classID end
    end
    G.UnitClassBase = function(unit) if unit == "player" then return world.player.classFile, world.player.classID end end
    G.UnitGUID = function(unit) if unit == "player" then return "Player-0000-" .. world.player.name end end
    G.UnitXP = function() return world.player.xp or 0 end
    G.UnitXPMax = function() return 1000 end
    G.GetZoneText = function() return world.zone or "Dornogal" end
    G.GetRealZoneText = G.GetZoneText
    G.GetProfessions = function()
        local p = world.player.professions
        return p[1] and 1 or nil, p[2] and 2 or nil, nil, nil, p.cooking and 5 or nil
    end
    G.GetProfessionInfo = function(index)
        local prof = index == 5 and world.player.professions.cooking or world.player.professions[index]
        if not prof then return nil end
        return prof.name, 0, prof.skill or 1, prof.maxSkill or 100, 0, 0, prof.skillLine
    end

    -- Containers
    local function stackInfo(bagID, slot)
        if not world:isAccessible(bagID) then return nil end
        local stack = world:getStack(bagID, slot)
        if not stack then return nil end
        local def = world.items[stack.itemID]
        return {
            iconFileID = def.icon, stackCount = stack.count, isLocked = stack.locked,
            quality = def.quality, isReadable = false, hasLoot = false,
            hyperlink = world:itemLink(stack.itemID), isFiltered = false,
            hasNoValue = (def.sellPrice or 0) <= 0, itemID = stack.itemID, isBound = stack.bound,
        }
    end
    G.C_Container = {
        GetContainerNumSlots = function(bagID)
            if not world:isAccessible(bagID) then return 0 end
            local c = world.containers[bagID]
            return c and c.size or 0
        end,
        GetContainerNumFreeSlots = function(bagID)
            if not world:isAccessible(bagID) then return nil end
            local c = world.containers[bagID]
            if not c then return 0 end
            local used = 0
            for _ in pairs(c.slots) do used = used + 1 end
            return c.size - used, 0
        end,
        GetContainerItemInfo = stackInfo,
        GetContainerItemID = function(bagID, slot)
            if not world:isAccessible(bagID) then return nil end
            local stack = world:getStack(bagID, slot)
            return stack and stack.itemID or nil
        end,
        GetContainerItemLink = function(bagID, slot)
            local info = stackInfo(bagID, slot)
            return info and info.hyperlink or nil
        end,
        GetContainerItemQuestInfo = function(bagID, slot)
            local stack = world:isAccessible(bagID) and world:getStack(bagID, slot)
            if not stack then return { isQuestItem = false, questID = nil, isActive = false } end
            local def = world.items[stack.itemID]
            local questID = def.questID
            return {
                isQuestItem = def.isQuestItem and true or false,
                questID = questID,
                isActive = questID and world.quests.active[questID] and true or false,
            }
        end,
        PickupContainerItem = function(bagID, slot) world:pickup(bagID, slot) end,
        UseContainerItem = function(bagID, slot)
            if not world.hardwareEvent then
                table.insert(world.blockedActions, "UseContainerItem")
                error("ADDON_ACTION_BLOCKED: UseContainerItem requires a hardware event", 2)
            end
            if world.vendorOpen then world:sell(bagID, slot) end
        end,
        SplitContainerItem = function() end,
        SortBags = function() world.sortedBags = true end,
        GetBagName = function(bagID) return "Bag " .. bagID end,
    }
    G.GetCursorInfo = function()
        if world.cursor then return "item", world.cursor.stack.itemID, world:itemLink(world.cursor.stack.itemID) end
        return nil
    end
    G.ClearCursor = function() world:clearCursor() end
    G.CursorHasItem = function() return world.cursor ~= nil end

    -- Items
    G.ItemLocation = {
        CreateFromBagAndSlot = function(_, bagID, slot)
            return {
                bagID = bagID, slotIndex = slot,
                IsValid = function() return world:isAccessible(bagID) and world:getStack(bagID, slot) ~= nil end,
                IsBagAndSlot = function() return true end,
                GetBagAndSlot = function() return bagID, slot end,
            }
        end,
        CreateFromEquipmentSlot = function(_, slotID)
            return {
                equipmentSlotIndex = slotID,
                IsValid = function() return world.equipped[slotID] ~= nil end,
                IsEquipmentSlot = function() return true end,
                IsBagAndSlot = function() return false end,
            }
        end,
    }
    local function stackFor(location)
        if location and location.bagID then return world:getStack(location.bagID, location.slotIndex) end
        return nil
    end
    local function getItemInfo(value)
        local itemID = parseItemID(value)
        local def = itemID and world.items[itemID]
        if not def or not def.cached then return nil end
        return def.name, world:itemLink(itemID), def.quality, def.itemLevel, def.requiredLevel,
            def.itemType or "Miscellaneous", def.itemSubType or "Other", def.maxStack, def.equipLoc,
            def.icon, def.sellPrice, def.classID, def.subclassID, def.bindType, def.expansionID,
            nil, def.isCraftingReagent or false
    end
    G.GetItemInfo = getItemInfo
    G.C_Item = {
        GetItemInfo = getItemInfo,
        GetItemInfoInstant = function(value)
            local itemID = parseItemID(value)
            local def = itemID and world.items[itemID]
            if not def then return nil end
            return itemID, def.itemType, def.itemSubType, def.equipLoc, def.icon, def.classID, def.subclassID
        end,
        IsItemDataCachedByID = function(itemID)
            local def = world.items[itemID]
            return def and def.cached or false
        end,
        RequestLoadItemDataByID = function(itemID)
            local def = world.items[itemID]
            if def and not def.cached and not def.neverLoads then
                world:after(0.5, function() def.cached = true end)
            end
        end,
        IsBound = function(location)
            local stack = stackFor(location)
            return stack and stack.bound or false
        end,
        IsBoundToAccountUntilEquip = function(location)
            local stack = stackFor(location)
            return stack and stack.wue or false
        end,
        GetCurrentItemLevel = function(location)
            if location and location.equipmentSlotIndex then return world.equipped[location.equipmentSlotIndex] end
            local stack = stackFor(location)
            return stack and world.items[stack.itemID].itemLevel or nil
        end,
        GetItemID = function(location)
            local stack = stackFor(location)
            return stack and stack.itemID or nil
        end,
        DoesItemExist = function(location) return stackFor(location) ~= nil end,
        GetItemQuality = function(location)
            local stack = stackFor(location)
            return stack and world.items[stack.itemID].quality or nil
        end,
        GetItemNameByID = function(itemID) local def = world.items[itemID] return def and def.name end,
        GetItemIconByID = function(itemID) local def = world.items[itemID] return def and def.icon end,
    }

    -- Bank
    G.C_Bank = {
        FetchPurchasedBankTabData = function(bankType)
            if not world.bankOpen then return nil end
            local tabs = world.bankTabs[bankType]
            return tabs and deepcopy(tabs) or nil
        end,
        FetchPurchasedBankTabIDs = function(bankType)
            if not world.bankOpen then return nil end
            local ids = {}
            for _, tab in ipairs(world.bankTabs[bankType] or {}) do ids[#ids + 1] = tab.ID end
            return ids
        end,
        FetchNumPurchasedBankTabs = function(bankType) return #(world.bankTabs[bankType] or {}) end,
        IsItemAllowedInBankType = function(bankType, location)
            local stack = stackFor(location)
            if not stack then return false end
            if bankType ~= ENUM.BankType.Account then return true end
            local def = world.items[stack.itemID]
            if def.accountBankAllowed ~= nil then return def.accountBankAllowed end
            local warbound = def.bindType == ENUM.ItemBind.ToWoWAccount or def.bindType == ENUM.ItemBind.ToBnetAccount
                or def.bindType == ENUM.ItemBind.ToBnetAccountUntilEquipped or stack.wue
            return warbound or not stack.bound
        end,
        AreAnyBankTypesViewable = function() return world.bankOpen end,
        CanViewBank = function() return world.bankOpen end,
        CanUseBank = function() return world.bankOpen end,
        AutoDepositItemsIntoBank = function() world.autoDepositCalled = true end,
    }
    G.C_PlayerInteractionManager = {
        IsInteractingWithNpcOfType = function(interactionType) return world.interaction == interactionType end,
    }

    -- Quests
    G.C_QuestLog = {
        IsQuestFlaggedCompleted = function(questID) return world.quests.completed[questID] and true or false end,
        IsOnQuest = function(questID) return world.quests.active[questID] and true or false end,
        GetTitleForQuestID = function(questID) return "Quest " .. tostring(questID) end,
        IsQuestFlaggedCompletedOnAccount = function(questID)
            return world.quests.completedOnAccount and world.quests.completedOnAccount[questID] or false
        end,
    }

    -- Collections
    G.C_TransmogCollection = {
        GetItemInfo = function(value)
            local itemID = parseItemID(value)
            local def = itemID and world.items[itemID]
            if not def or not def.appearanceSourceID then return nil end
            return def.appearanceID or def.appearanceSourceID, def.appearanceSourceID
        end,
        PlayerHasTransmogItemModifiedAppearance = function(sourceID)
            return world.collections.appearances[sourceID] and true or false
        end,
        PlayerHasTransmogByItemInfo = function(value)
            local itemID = parseItemID(value)
            local def = itemID and world.items[itemID]
            return def and def.appearanceSourceID and world.collections.appearances[def.appearanceSourceID] and true or false
        end,
    }
    G.PlayerHasToy = function(itemID) return world.collections.toys[itemID] and true or false end
    G.C_ToyBox = {
        GetToyInfo = function(itemID)
            local def = world.items[itemID]
            if def and def.isToy then return itemID, def.name, def.icon end
            return nil
        end,
    }
    G.C_MountJournal = {
        GetMountFromItem = function(itemID)
            local def = world.items[itemID]
            return def and def.mountID or nil
        end,
        GetMountInfoByID = function(mountID)
            return "Mount " .. mountID, 0, 0, false, true, 0, false, false, 0, false,
                world.collections.mounts[mountID] and true or false, mountID
        end,
    }
    G.C_PetJournal = {
        GetPetInfoByItemID = function(itemID)
            local def = world.items[itemID]
            if not def or not def.petSpeciesID then return nil end
            return def.name, 0, 0, 0, "", "", false, false, "", "", 0, 0, def.petSpeciesID
        end,
        GetNumCollectedInfo = function(speciesID)
            return world.collections.pets[speciesID] or 0, 3
        end,
    }

    -- Auction house (minimal; price lookups are faked per test)
    G.C_AuctionHouse = {
        IsThrottledMessageSystemReady = function() return true end,
        IsSellItemValid = function(location)
            local stack = stackFor(location)
            if not stack then return false end
            local def = world.items[stack.itemID]
            return not stack.bound and not def.questID and (def.bindType ~= ENUM.ItemBind.OnAcquire)
        end,
        MakeItemKey = function(itemID) return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end,
        SendSearchQuery = function(itemKey)
            world.ahQueries = (world.ahQueries or 0) + 1
            local price = world.ahPrices and world.ahPrices[itemKey.itemID]
            world:after(0.1, function()
                world.lastAhResult = { itemID = itemKey.itemID, price = price }
                local def = world.items[itemKey.itemID]
                if def and def.maxStack > 1 then
                    world:fire("COMMODITY_SEARCH_RESULTS_UPDATED", itemKey.itemID)
                else
                    world:fire("ITEM_SEARCH_RESULTS_UPDATED", itemKey)
                end
            end)
        end,
        GetNumCommoditySearchResults = function(itemID)
            return (world.ahPrices and world.ahPrices[itemID]) and 1 or 0
        end,
        GetCommoditySearchResultInfo = function(itemID, index)
            local price = world.ahPrices and world.ahPrices[itemID]
            if not price or index ~= 1 then return nil end
            return { itemID = itemID, quantity = 10, unitPrice = price }
        end,
        GetNumItemSearchResults = function(itemKey)
            return (world.ahPrices and world.ahPrices[itemKey.itemID]) and 1 or 0
        end,
        GetItemSearchResultInfo = function(itemKey, index)
            local price = world.ahPrices and world.ahPrices[itemKey.itemID]
            if not price or index ~= 1 then return nil end
            return { itemKey = itemKey, buyoutAmount = price, quantity = 1 }
        end,
    }

    -- Timers
    G.C_Timer = {
        After = function(delay, fn) world:after(delay, fn) end,
        NewTimer = function(delay, fn)
            local handle = {}
            local timer = world:after(delay, function() fn(handle) end)
            handle.Cancel = function() timer.cancelled = true end
            handle.IsCancelled = function() return timer.cancelled and true or false end
            return handle
        end,
        NewTicker = function(interval, fn, iterations)
            local handle = { remaining = iterations }
            local function schedule()
                local timer = world:after(interval, function()
                    if handle.cancelled then return end
                    fn(handle)
                    if handle.remaining then
                        handle.remaining = handle.remaining - 1
                        if handle.remaining <= 0 then return end
                    end
                    schedule()
                end)
                handle.timer = timer
            end
            handle.Cancel = function() handle.cancelled = true; if handle.timer then handle.timer.cancelled = true end end
            handle.IsCancelled = function() return handle.cancelled and true or false end
            schedule()
            return handle
        end,
    }

    -- Tooltip post-calls: tests fire them with world:showItemTooltip(itemID).
    world.tooltipPostCalls = {}
    G.TooltipDataProcessor = {
        AddTooltipPostCall = function(dataType, fn)
            world.tooltipPostCalls[dataType] = world.tooltipPostCalls[dataType] or {}
            table.insert(world.tooltipPostCalls[dataType], fn)
        end,
    }

    -- Secret values do not exist unless a test installs them.
    G.issecretvalue = nil

    env._G = env
    setmetatable(env, {
        __index = function(_, key)
            local value = G[key]
            if value == nil and type(key) == "string" then world.missingGlobals[key] = true end
            return value
        end,
    })
    self.G = G
    return env
end

-- Simulate hovering an item anywhere in the game; returns the added lines.
function World:showItemTooltip(itemID)
    local tooltip = self.env.GameTooltip
    tooltip._lines = {}
    for _, fn in ipairs(self.tooltipPostCalls[ENUM.TooltipDataType.Item] or {}) do
        fn(tooltip, { id = itemID, type = ENUM.TooltipDataType.Item })
    end
    return tooltip._lines
end

-- Open/close contexts, firing the events the real client fires.
function World:openBank()
    self.bankOpen = true
    self.interaction = ENUM.PlayerInteractionType.Banker
    self:fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", ENUM.PlayerInteractionType.Banker)
    self:fire("BANKFRAME_OPENED")
end

function World:closeBank()
    self.bankOpen = false
    self.interaction = nil
    self:fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", ENUM.PlayerInteractionType.Banker)
    self:fire("BANKFRAME_CLOSED")
end

function World:openVendor()
    self.vendorOpen = true
    self.interaction = ENUM.PlayerInteractionType.Merchant
    self:fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", ENUM.PlayerInteractionType.Merchant)
    self:fire("MERCHANT_SHOW")
end

function World:closeVendor()
    self.vendorOpen = false
    self.interaction = nil
    self:fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", ENUM.PlayerInteractionType.Merchant)
    self:fire("MERCHANT_CLOSED")
end

function World:openAuctionHouse()
    self.ahOpen = true
    self.interaction = ENUM.PlayerInteractionType.Auctioneer
    self:fire("AUCTION_HOUSE_SHOW")
end

function World:closeAuctionHouse()
    self.ahOpen = false
    self.interaction = nil
    self:fire("AUCTION_HOUSE_CLOSED")
end

World.ENUM = ENUM
World.MAX_BUYBACK = MAX_BUYBACK
return World
