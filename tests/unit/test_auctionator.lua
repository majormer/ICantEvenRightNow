local T = ...
local F = require("fixtures")
local I = F.ITEMS

-- Fake Auctionator mirroring the installed v339 API (Source/API/v1).
local function installAuctionator(w, opts)
    opts = opts or {}
    local fake = { searches = {}, lists = {} }
    local function verify(callerID)
        if type(callerID) ~= "string" or callerID == "" then error("Invalid callerID. Use the name of your add-on.") end
    end
    local api = {
        GetAuctionPriceByItemLink = function(caller, link) verify(caller) return (opts.prices or {})[w.parseItemID(link)] end,
        GetAuctionPriceByItemID = function(caller, id) verify(caller) return (opts.prices or {})[id] end,
        GetAuctionAgeByItemLink = function(caller, link) verify(caller) return (opts.ages or {})[w.parseItemID(link)] end,
        GetAuctionAgeByItemID = function(caller, id) verify(caller) return (opts.ages or {})[id] end,
        IsAuctionDataExactByItemLink = function(caller, link)
            verify(caller)
            local exact = (opts.exact or {})[w.parseItemID(link)]
            if exact == nil then return true end
            return exact
        end,
        MultiSearchExact = function(caller, terms)
            verify(caller)
            if not w.ahOpen then error("Contact the maintainer of " .. caller .. " to resolve this problem. Details: Auction house is not open") end
            for _, term in ipairs(terms) do
                if term:match("[;^]") then error("Search term contains ; or ^") end
            end
            table.insert(fake.searches, terms)
        end,
        ConvertToSearchString = function(caller, term)
            verify(caller)
            return term.isExact and ('"' .. term.searchString .. '"') or term.searchString
        end,
        CreateShoppingList = function(caller, name, strings)
            verify(caller)
            fake.lists[name] = strings
        end,
    }
    rawset(w.env, "Auctionator", { API = { v1 = api } })
    w.addonsLoaded.Auctionator = true
    w.auctionator = fake
    return fake
end

local function game(populate, opts)
    return T.game({ player = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" },
        setup = function(w) F.defineItems(w); F.addBank(w); installAuctionator(w, opts); populate(w) end })
end

local function scanned(g, itemID)
    g:Core().ScanInventory("bags", true)
    for _, item in ipairs(g:P().GetScanList("bags")) do
        if item.itemID == itemID then return item end
    end
end

local function homeWidget(g, name)
    for _, widget in ipairs(g:UI().frame.panels.Home.cards) do
        if widget:IsShown() and widget.card and widget.card.name == name then return widget end
    end
end

T.test("gear priced from the base item is labelled approximate", function()
    local g = game(function(w) w:put(0, 1, I.OLD_SWORD, 1) end,
        { prices = { [I.OLD_SWORD] = 2500000 }, ages = { [I.OLD_SWORD] = 1 }, exact = { [I.OLD_SWORD] = false } })
    local price = g:P().GetAuctionPrice(scanned(g, I.OLD_SWORD))
    T.eq(price.exact, false)
    T.contains(g:P().FormatPriceSource(price), "approximate")
    -- Vendor protection still applies: better to warn than lose value.
    T.ok(g:P().IsValueFlagged(scanned(g, I.OLD_SWORD), "Vendor"))
end)

T.test("exact prices and non-gear are not labelled approximate", function()
    local g = game(function(w) w:put(0, 1, I.VALUABLE_ORE, 20) end,
        { prices = { [I.VALUABLE_ORE] = 90000 }, ages = { [I.VALUABLE_ORE] = 1 } })
    local price = g:P().GetAuctionPrice(scanned(g, I.VALUABLE_ORE))
    T.notContains(g:P().FormatPriceSource(price), "approximate")
end)

T.test("Auction Candidates: 'Check in Auctionator' searches every candidate at the AH", function()
    local g = game(function(w)
        w:put(0, 1, I.VALUABLE_ORE, 20)
        w:put(6, 1, I.OLD_SWORD, 1)
    end, { prices = { [I.VALUABLE_ORE] = 90000, [I.OLD_SWORD] = 2500000 }, ages = { [I.VALUABLE_ORE] = 1, [I.OLD_SWORD] = 1 } })
    g:openBank()
    g:closeBank()
    g:openAuctionHouse()
    g:P().SetCharacterRole("Main-R", "main")
    g:slash("")
    local widget = homeWidget(g, "Auction Candidates")
    T.ok(widget and widget.secondary:IsShown(), "secondary action shown")
    T.eq(widget.secondary:GetText(), "Check in Auctionator")
    g:click(widget.secondary)
    local searched = g.world.auctionator.searches[1]
    -- The BoE broadsword is wearable by this Main, so it is kept, not suggested.
    T.same(searched, { "Obsidium Ore" }, "candidates by exact name; items a played character uses are excluded")
    T.contains(g:printed(), "Searching 1 item in Auctionator's Shopping tab")
end)

T.test("away from the AH, candidates are saved as an Auctionator shopping list", function()
    local g = game(function(w) w:put(0, 1, I.VALUABLE_ORE, 20) end,
        { prices = { [I.VALUABLE_ORE] = 90000 }, ages = { [I.VALUABLE_ORE] = 1 } })
    g:P().SetCharacterRole("Main-R", "main")
    g:slash("")
    local widget = homeWidget(g, "Auction Candidates")
    T.eq(widget.secondary:GetText(), "Save to Auctionator")
    g:click(widget.secondary)
    T.same(g.world.auctionator.lists["I Can't Even: Auction Candidates"], { '"Obsidium Ore"' })
    T.eq(#g.world.auctionator.searches, 0, "no search attempted away from the AH")
end)

T.test("with Auctionator, price checks go to Auctionator instead of the own lookup", function()
    local g = game(function(w)
        w:put(0, 1, I.VALUABLE_ORE, 20)
        w:put(0, 2, I.OLD_SWORD, 1)
        w:put(0, 3, I.BOUND_HELM, 1, { bound = true })
    end)
    g:Core().ScanInventory("bags", true)
    g:openAuctionHouse()
    local names = {}
    for _, c in ipairs(g:P().GetTaskCards()) do names[c.name] = c end
    T.eq(names["Price My Items"], nil, "own lookup hidden")
    T.eq(names["Check Prices in Auctionator"].ready, 2, "only tradeable items without a price")
    g.world:withHardwareEvent(function() g:P().OpenTask("Check Prices in Auctionator") end)
    T.same(g.world.auctionator.searches[1], { "Cataclysm Broadsword", "Obsidium Ore" })
    T.eq(g.world.ahQueries, nil, "the addon's own AH queries were not used")
    T.eq(g:UI().activeTab, "Home", "stays on Home")
end)

T.test("names Auctionator would reject are cleaned", function()
    local g = game(function(w)
        w:defineItem(8201, { name = 'Odd;Name^"', classID = 7, subclassID = 7, maxStack = 20, sellPrice = 1, expansionID = 3 })
        w:put(0, 1, 8201, 5)
    end, { prices = { [8201] = 900000 }, ages = { [8201] = 1 } })
    g:Core().ScanInventory("bags", true)
    g:openAuctionHouse()
    T.ok(g:P().CheckCandidatesInAuctionator())
    T.same(g.world.auctionator.searches[1], { "OddName" })
end)

T.test("current-expansion and in-use items are never auction candidates", function()
    local g = game(function(w)
        w:defineItem(8301, { name = "Void-Touched Drums", classID = 0, subclassID = 8, maxStack = 20,
            sellPrice = 100, expansionID = 11 })
        w:put(0, 1, 8301, 39)                -- current expansion: keep
        w:put(0, 2, I.VALUABLE_ORE, 20)      -- old, unused: candidate
        w:put(0, 3, I.LINEN, 200)            -- old, but a crafter uses it: keep
    end, { prices = { [8301] = 500000, [I.VALUABLE_ORE] = 90000, [I.LINEN] = 60000 },
           ages = { [8301] = 1, [I.VALUABLE_ORE] = 1, [I.LINEN] = 1 } })
    local P = g:P()
    P.SetCharacterRole("Main-R", "main")
    g:db().characters["Main-R"].professions = { { name = "Tailoring", skillLine = 197 } }
    g:Core().ScanInventory("bags", true)
    local ids = {}
    for _, item in ipairs(P.AuctionCandidateItems()) do ids[item.itemID] = true end
    T.no(ids[8301], "current-expansion drums are not suggested for auction")
    T.no(ids[I.LINEN], "linen your tailor uses is kept")
    T.ok(ids[I.VALUABLE_ORE], "old unused ore is a candidate")
end)

T.test("Auction Candidates card shows the auction value, not the vendor value", function()
    local g = game(function(w) w:put(6, 1, I.VALUABLE_ORE, 20) end,
        { prices = { [I.VALUABLE_ORE] = 90000 }, ages = { [I.VALUABLE_ORE] = 1 } })
    g:openBank()
    g:P().SetCharacterRole("Main-R", "main")
    local card
    for _, c in ipairs(g:P().GetTaskCards()) do if c.name == "Auction Candidates" then card = c end end
    T.eq(g:P().CardSummary(card), "1 in the bank (~171g 0s at auction)")
end)

T.test("items whose data hasn't loaded still get a readable name", function()
    local g = game(function(w)
        w:defineItem(8401, { name = "Slowly Loading Gem", classID = 7, maxStack = 20, cached = false, neverLoads = true })
        w:put(0, 1, 8401, 3)
    end)
    local item = scanned(g, 8401)
    T.eq(item.name, "Slowly Loading Gem", "name taken from the item link")
    T.eq(g:P().ItemDisplayName("", nil, 42), "Item 42")
    T.eq(g:P().ItemDisplayName(nil, "|cff|Hitem:1|h[]|h|r", 7), "Item 7")
end)
T.test("setting: include current-expansion items in Auction Candidates (off by default)", function()
    local g = game(function(w)
        w:defineItem(8501, { name = "Fresh Ore", classID = 7, subclassID = 7, maxStack = 200, sellPrice = 10, expansionID = 11 })
        w:defineItem(8502, { name = "Fresh Cloth", classID = 7, subclassID = 5, maxStack = 200, sellPrice = 10, expansionID = 11 })
        w:put(0, 1, 8501, 100)
        w:put(0, 2, 8502, 100)
    end, { prices = { [8501] = 50000, [8502] = 50000 }, ages = { [8501] = 1, [8502] = 1 } })
    local P = g:P()
    P.SetCharacterRole("Main-R", "main")
    g:db().characters["Main-R"].professions = { { name = "Tailoring", skillLine = 197 } }
    g:Core().ScanInventory("bags", true)
    local function candidates()
        local ids = {}
        for _, item in ipairs(P.AuctionCandidateItems()) do ids[item.itemID] = true end
        return ids
    end
    T.eq(g:db().ui.auctionIncludeCurrent, false, "off by default")
    T.no(candidates()[8501], "current ore excluded by default")
    g:db().ui.auctionIncludeCurrent = true
    local ids = candidates()
    T.ok(ids[8501], "current ore included when enabled")
    T.no(ids[8502], "cloth your tailor uses is still kept")
end)
T.test("Auction Candidates counts candidates in bags and in the bank", function()
    local g = game(function(w)
        w:put(0, 1, I.VALUABLE_ORE, 20)
        w:put(6, 1, I.OLD_POTION, 5)
    end, { prices = { [I.VALUABLE_ORE] = 90000, [I.OLD_POTION] = 400000 },
           ages = { [I.VALUABLE_ORE] = 1, [I.OLD_POTION] = 1 } })
    g:openBank()
    g:P().SetCharacterRole("Main-R", "main")
    local card
    for _, c in ipairs(g:P().GetTaskCards()) do if c.name == "Auction Candidates" then card = c end end
    T.eq(card.ready, 2)
    T.contains(g:P().CardSummary(card), "1 in bags, 1 in the bank")
end)