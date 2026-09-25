local T = ...
local F = require("fixtures")
local I = F.ITEMS

-- Fake BetterBags matching the verified plugin API (v0.5.11).
local function installBetterBags(w)
    local fake = { functions = {}, wiped = {}, reprocessed = 0 }
    local categories = {
        RegisterCategoryFunction = function(self, id, fn)
            assert(not fake.functions[id], "duplicate category function id")
            fake.functions[id] = fn
        end,
        WipeCategory = function(self, ctx, name) table.insert(fake.wiped, name) end,
        ReprocessAllItems = function(self, ctx) fake.reprocessed = fake.reprocessed + 1 end,
    }
    local contextModule = { New = function(self, name) return { name = name } end }
    local addon = { GetModule = function(self, name)
        if name == "Categories" then return categories end
        if name == "Context" then return contextModule end
    end }
    local ace = { GetAddon = function(self, name) if name == "BetterBags" then return addon end end }
    w.addonsLoaded.BetterBags = true
    rawset(w.env, "LibStub", setmetatable({ GetLibrary = function() return nil end }, {
        __call = function(_, name) if name == "AceAddon-3.0" then return ace end end,
    }))
    w.betterBags = fake
    return fake
end

local function game(populate)
    return T.game({ player = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" },
        setup = function(w) F.defineItems(w); F.addBank(w); installBetterBags(w); populate(w) end })
end

-- Call the registered category function like BetterBags would.
local function categoryOf(g, itemID)
    local fn = g.world.betterBags.functions.ICantEvenRightNow_categories
    local def = g.world.items[itemID]
    return fn({ itemInfo = { itemID = itemID, itemLink = g.world:itemLink(itemID), itemName = def.name,
        classID = def.classID, subclassID = def.subclassID, expacID = def.expansionID, itemQuality = def.quality,
        sellPrice = def.sellPrice, itemEquipLoc = def.equipLoc, itemLevel = def.itemLevel, bindType = def.bindType,
        isBound = false } })
end

T.test("BetterBags present: Home offers categories once; nothing registered until enabled", function()
    local g = game(function(w) end)
    g:P().SetCharacterRole("Main-R", "main")
    g:slash("")
    T.contains(g:UI().frame.panels.Home.notice.text:GetText(), "BetterBags detected")
    T.eq(next(g.world.betterBags.functions), nil, "off until enabled")
    local enable
    for _, b in ipairs(g:UI().frame.panels.Home.notice.buttons) do if b:GetText() == "Show categories" then enable = b end end
    g:click(enable)
    T.ok(g.world.betterBags.functions.ICantEvenRightNow_categories, "registered")
    T.notContains(g:UI().frame.panels.Home.notice.text:GetText() or "", "BetterBags detected", "asked only once")
end)

T.test("category function publishes per-item-ID decisions in priority order", function()
    local g = game(function(w) end)
    local P = g:P()
    P.SetCharacterRole("Main-R", "main")
    P.SetBetterBagsCategories(true)
    g:db().rules.items[I.OLD_POTION] = { protect = true }
    T.eq(categoryOf(g, I.OLD_POTION), "Protected", "protect wins")
    T.eq(categoryOf(g, I.JUNK), "Sell Candidates")
    T.eq(categoryOf(g, I.OLD_SWORD), "For the Warband", "BoE gear is shareable")
    T.eq(categoryOf(g, I.NEW_FLASK), nil, "current items get no category")
    g:db().rules.items[I.JUNK] = { neverSell = true }
    T.eq(categoryOf(g, I.JUNK), "Never Sell")
end)

T.test("rule changes wipe our categories and reprocess, deferred out of combat", function()
    local g = game(function(w) w:put(0, 1, I.JUNK, 2) end)
    local P = g:P()
    P.SetBetterBagsCategories(true)
    g:advance(2)
    local fake = g.world.betterBags
    local before = fake.reprocessed
    g.world.inCombat = true
    P.SetKeepReason(I.JUNK, "keepsake", "Broken Tusk")
    g:advance(2)
    T.eq(fake.reprocessed, before, "no refresh during combat")
    g.world.inCombat = false
    g.world:fire("PLAYER_REGEN_ENABLED")
    g:advance(2)
    T.eq(fake.reprocessed, before + 1, "refreshed after combat")
    local wipedProtected = false
    for _, name in ipairs(fake.wiped) do if name == "Protected" then wipedProtected = true end end
    T.ok(wipedProtected, "our categories are wiped before reprocessing")
end)

T.test("turning categories off returns nothing for every item", function()
    local g = game(function(w) end)
    local P = g:P()
    P.SetBetterBagsCategories(true)
    P.SetBetterBagsCategories(false)
    T.eq(categoryOf(g, I.JUNK), nil)
end)
