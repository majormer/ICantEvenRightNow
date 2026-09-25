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
        -- Mirrors v339 ValidateExtendedSearchTerms: string/number/boolean
        -- fields only, no ; or ^, no quote-wrapped strings. Records names in
        -- `searches` (like MultiSearchExact) and the full terms in `advanced`.
        MultiSearchAdvanced = function(caller, terms)
            verify(caller)
            if not w.ahOpen then error("Details: Auction house is not open") end
            local names = {}
            for i, term in ipairs(terms) do
                if type(term.searchString) ~= "string" then error("search term " .. i .. " must have searchString key") end
                for key, value in pairs(term) do
                    local t = type(value)
                    if type(key) ~= "string" or (t ~= "string" and t ~= "number" and t ~= "boolean") then error("Bad search term " .. i) end
                    if t == "string" and (value:match('^".*"$') or value:match("[;^]")) then error("Search term " .. i .. " contains ; or ^") end
                end
                table.insert(names, term.searchString)
            end
            fake.advanced = fake.advanced or {}
            table.insert(fake.advanced, terms)
            table.insert(fake.searches, names)
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
    -- Utilities.DBKeyFromLink mirrors v339: the callback runs at once only
    -- when the item's data is loaded (Item:ContinueOnItemLoad).
    local utilities = {
        DBKeyFromLink = function(link, callback)
            local id = w.parseItemID(link)
            local def = id and w.items[id]
            if def and def.cached then callback({ "g:" .. id .. ":" .. tostring(def.itemLevel), tostring(id) }) end
        end,
    }
    rawset(w.env, "Auctionator", { API = { v1 = api }, Utilities = utilities })
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
    -- ...but it mixes every item level, so it is not a value or a candidate.
    local sword = scanned(g, I.OLD_SWORD)
    T.eq((g:P().GetItemValue(sword)), (sword.sellPrice or 0) * (sword.count or 1))
    T.ok(not g:P().IsAuctionCandidate(sword))
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
T.test("opening the auction house shows a notice for Auction Candidates", function()
    local g = game(function(w) w:put(0, 1, I.VALUABLE_ORE, 20) end,
        { prices = { [I.VALUABLE_ORE] = 90000 }, ages = { [I.VALUABLE_ORE] = 1 } })
    g:P().SetCharacterRole("Main-R", "main")
    g:openAuctionHouse()
    local notice = g:UI().contextNoticeFrame
    T.ok(notice and notice:IsShown(), "notice at the AH")
    T.contains(notice.text:GetText(), "Auction Candidates: 1 in bags")
    g:closeAuctionHouse()
    T.no(notice:IsShown(), "hidden when the AH closes")
end)
T.test("at the AH the notice runs Check in Auctionator; bank-only tasks don't open a wrong route", function()
    local g = game(function(w)
        w:put(0, 1, I.VALUABLE_ORE, 20)
        w:put(6, 1, I.OLD_POTION, 5)
    end, { prices = { [I.VALUABLE_ORE] = 90000, [I.OLD_POTION] = 400000 },
           ages = { [I.VALUABLE_ORE] = 1, [I.OLD_POTION] = 1 } })
    g:openBank()
    g:closeBank()
    g:P().SetCharacterRole("Main-R", "main")
    g:openAuctionHouse()
    local notice = g:UI().contextNoticeFrame
    T.eq(notice.open:GetText(), "Check in Auctionator")
    g:click(notice.open)
    T.eq(#g.world.auctionator.searches, 1, "search started from the notice")
    -- Opening the bank-route task away from a bank stays on Home with a hint.
    local mark = g:logMark()
    T.no(g:P().OpenTask("Auction Candidates"))
    T.contains(g:printed(mark), "visit a bank to review these items")
    g:slash("")
    local widget
    for _, w in ipairs(g:UI().frame.panels.Home.cards) do
        if w:IsShown() and w.card and w.card.name == "Auction Candidates" then widget = w end
    end
    T.eq(widget.open:GetText(), "Visit a bank")
    T.no(widget.open:IsEnabled())
    T.ok(widget.secondary:IsShown() and widget.secondary:IsEnabled(), "Auctionator action still available")
end)
T.test("items whose link lookup fails are still named, classified, and searchable", function()
    local g = game(function(w)
        w:defineItem(8601, { name = "Stubborn Ore", classID = 7, subclassID = 7, maxStack = 200, sellPrice = 5,
            expansionID = 3, linkLookupFails = true })
        w:put(0, 1, 8601, 50)
    end, { prices = { [8601] = 80000 }, ages = { [8601] = 1 } })
    g:P().SetCharacterRole("Main-R", "main")
    local item = scanned(g, 8601)
    T.eq(item.name, "Stubborn Ore")
    T.eq(item.expansionID, 3, "data read by item ID")
    g:openAuctionHouse()
    T.ok(g:P().CheckCandidatesInAuctionator())
    T.same(g.world.auctionator.searches[1], { "Stubborn Ore" })
end)

T.test("items with unloaded data are never auction candidates", function()
    local g = game(function(w)
        w:defineItem(8701, { name = "Mystery Mat", classID = 7, maxStack = 20, sellPrice = 5, expansionID = 11,
            cached = false, neverLoads = true })
        w:put(0, 1, 8701, 10)
    end, { prices = { [8701] = 900000 }, ages = { [8701] = 1 } })
    g:Core().ScanInventory("bags", true)
    T.eq(#g:P().AuctionCandidateItems(), 0, "unknown data is not treated as sellable")
end)
T.test("gear is searched at its own item level, one term per level", function()
    local g = game(function(w)
        w:defineItem(8901, { name = "Tarnished Blade", classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON",
            itemLevel = 260, requiredLevel = 80, bindType = 2, sellPrice = 100, expansionID = 3 })
        w:put(0, 1, 8901, 1)
        w.equipped[16] = 305
    end, { prices = { [8901] = 5000000 }, ages = { [8901] = 1 } })
    g:P().SetCharacterRole("Main-R", "main")
    g:Core().ScanInventory("bags", true)
    g:openAuctionHouse()
    T.ok(g:P().CheckCandidatesInAuctionator())
    local terms = g.world.auctionator.advanced[1]
    T.eq(#terms, 1)
    T.eq(terms[1].searchString, "Tarnished Blade")
    T.eq(terms[1].minItemLevel, 260)
    T.eq(terms[1].maxItemLevel, 260)
    T.eq(terms[1].isExact, true)
end)
T.test("the auction house is not mistaken for a bank", function()
    local g = game(function(w) w:put(0, 1, I.VALUABLE_ORE, 20) end, {})
    g:openAuctionHouse()
    g:Core().UpdateContext()
    T.eq(g.ns.DB.context.bankOpen, false)
    T.eq(g.ns.DB.context.auctionHouseOpen, true)
end)
T.test("the notice's value updates when auction prices change", function()
    local prices = { [I.VALUABLE_ORE] = 900000 }
    local g = game(function(w) w:put(0, 1, I.VALUABLE_ORE, 20) end, { prices = prices, ages = { [I.VALUABLE_ORE] = 1 } })
    g:openAuctionHouse()
    local notice = g:UI().contextNoticeFrame
    T.ok(notice and notice:IsShown(), "notice shown at the AH")
    local before = notice.text:GetText()
    prices[I.VALUABLE_ORE] = 100000
    g.world:fire("COMMODITY_SEARCH_RESULTS_UPDATED", I.VALUABLE_ORE)
    g.world:advance(3)
    T.ok(notice.text:GetText() ~= before, "value text refreshed")
end)
T.test("gear is not priced until its item data is loaded", function()
    local g = game(function(w)
        w:defineItem(8902, { name = "Slow Blade", classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON",
            itemLevel = 260, requiredLevel = 80, bindType = 2, sellPrice = 100, expansionID = 3 })
        w:put(0, 1, 8902, 1)
        w.equipped[16] = 305
    end, { prices = { [8902] = 5000000 }, ages = { [8902] = 1 } })
    local blade = scanned(g, 8902)
    g.world.items[8902].cached = false
    T.eq(g:P().GetAuctionPrice(blade), nil, "no price while data is loading")
    g.world:advance(1)
    T.ok(g:P().GetAuctionPrice(blade), "priced once loaded")
end)
T.test("stale prices are not auction value, but still protect from vendoring", function()
    local g = game(function(w) w:put(0, 1, I.VALUABLE_ORE, 20) end,
        { prices = { [I.VALUABLE_ORE] = 900000 }, ages = { [I.VALUABLE_ORE] = 71 } })
    local ore = scanned(g, I.VALUABLE_ORE)
    T.eq(g:P().GetAuctionPrice(ore).fresh, false)
    T.ok(not g:P().IsAuctionCandidate(ore), "stale price: not a candidate")
    T.eq((g:P().GetItemValue(ore)), (ore.sellPrice or 0) * ore.count, "value falls back to vendor")
    T.ok(g:P().IsValueFlagged(ore, "Vendor"), "vendor protection still warns")
end)
T.test("the auction report explains gear it leaves out", function()
    local g = game(function(w)
        w:defineItem(8903, { name = "Unpriced Blade", classID = 2, subclassID = 7, equipLoc = "INVTYPE_WEAPON",
            itemLevel = 260, requiredLevel = 80, bindType = 2, sellPrice = 100, expansionID = 3 })
        w:put(0, 1, 8903, 1)
        w.equipped[16] = 305
    end, {})
    g:P().SetCharacterRole("Main-R", "main")
    g:Core().ScanInventory("bags", true)
    local text = table.concat(g:P().AuctionCandidateReport(), "\n")
    T.contains(text, "left out: Unpriced Blade [260]: no auction price")
end)
