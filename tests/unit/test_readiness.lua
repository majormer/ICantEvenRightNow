local T = ...
local F = require("fixtures")

-- Item data states (ItemData.lua) and getting ready (Readiness.lua).
local P_MAIN = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" }

-- A Strength plate helm in the bags; `def` overrides its definition.
local function game(def)
    return T.game({ player = P_MAIN, setup = function(w)
        F.defineItems(w)
        w:addBankTab(0, 6, "Main", 0, 20)
        local helm = { name = "Test Helm", classID = 4, subclassID = 4, equipLoc = "INVTYPE_HEAD",
            itemLevel = 100, requiredLevel = 60, bindType = 1, quality = 3, sellPrice = 100, expansionID = 11,
            stats = { ITEM_MOD_STRENGTH_SHORT = 10 } }
        for k, v in pairs(def or {}) do helm[k] = v end
        w:defineItem(8701, helm)
        w:put(0, 1, 8701, 1)
    end })
end

local function helm(g)
    g:slash("scan bags")
    for _, item in ipairs(g:P().GetScanList("bags")) do
        if item.itemID == 8701 then return item end
    end
end

T.test("item data: loading, then ready when the game answers", function()
    local g = game({ cached = false, loadDelay = 2 })
    local P = g:P()
    local item = { itemID = 8701, name = "Test Helm" }
    T.eq(P.ItemDataState(item), "loading")
    g:advance(3)
    T.eq(P.ItemDataState(item), "ready")
    local stats, state = P.ItemStats(item)
    T.eq(state, "ready")
    T.eq(stats.ITEM_MOD_STRENGTH_SHORT, 10)
end)

T.test("item data: gives up after the limit, and Rescan asks again", function()
    local g = game({ cached = false, neverLoads = true })
    local P = g:P()
    local item = { itemID = 8701, name = "Test Helm" }
    P.ItemDataState(item)
    g:advance(9)
    T.eq(P.ItemDataState(item), "failed")
    P.RetryFailedItemData()
    T.eq(P.ItemDataState(item), "loading", "asked again")
end)

T.test("item data: giving up on stats isn't permanent", function()
    local g = game({ statsAt = 1790000000 + 12 })
    g:P().SetCharacterRole("Main-R", "main")
    local P = g:P()
    local item = helm(g)
    T.eq(select(2, P.ItemStats(item)), "loading")
    g:advance(9)
    T.eq(select(2, P.ItemStats(item)), "failed")
    T.eq(P.ExplainScanned(item).primary.id, "details_unavailable", "no verdict without stats")
    g:advance(4)
    local stats, state = P.ItemStats(item)
    T.eq(state, "ready")
    T.eq(stats.ITEM_MOD_STRENGTH_SHORT, 10)
end)

T.test("item data: the game saying an item doesn't exist ends the wait", function()
    local g = game({ cached = false, neverLoads = true })
    local P = g:P()
    local item = { itemID = 8701, name = "Test Helm" }
    P.ItemDataState(item)
    g.world:fire("GET_ITEM_INFO_RECEIVED", 8701, nil)
    T.eq(P.ItemDataState(item), "missing")
end)

T.test("getting ready: the Transfer list shows no rows until the data is in", function()
    local g = game({ statsAt = 1790000000 + 3 })
    local P = g:P()
    P.SetCharacterRole("Main-R", "main")
    g:openVendor()
    g:Core().ShowHomeUI()
    P.OpenTask("Sell Items That Can Go")
    local panel = g:UI().frame.panels.Transfer
    T.eq(#(g:UI().transferRows or {}), 0, "no rows while getting ready")
    T.contains(panel.empty:GetText(), "Getting ready")
    T.ok(panel.empty:IsShown())
    T.notContains(panel.itemCount:GetText(), "matching")
    g:advance(9)   -- past the limit, whatever else is still loading
    T.notContains(panel.itemCount:GetText(), "Getting ready")
    T.contains(panel.itemCount:GetText(), "matching")
end)

T.test("getting ready: items that never load are named in the log", function()
    local g = game({ statsAt = 1790000000 + 60 })
    local P = g:P()
    P.SetCharacterRole("Main-R", "main")
    P.SetLogging(true)
    g:openVendor()
    g:advance(10)
    local found = false
    for _, line in ipairs(P.GetLogLines()) do
        if line:find("not checked: Test Helm", 1, true) then found = true end
    end
    T.ok(found, "the log names the item")
end)

T.test("item data: a read item stays ready when the cached flag flickers", function()
    local g = game({})
    local P = g:P()
    P.SetCharacterRole("Main-R", "main")
    local item = helm(g)
    T.eq(select(2, P.ItemStats(item)), "ready")
    g.world.items[8701].cached = false   -- the game briefly says "not cached"
    T.eq(P.ItemDataState(item), "ready")
    local stats, state = P.ItemStats(item)
    T.eq(state, "ready")
    T.eq(stats.ITEM_MOD_STRENGTH_SHORT, 10)
    T.ok(not P.GearDetailsPending(item), "no 'checking details' again")
end)
