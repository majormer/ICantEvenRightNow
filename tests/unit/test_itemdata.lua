local T = ...
local F = require("fixtures")

-- Item data that loads slowly or not at all must not strip what a scan knows.

local PLAYER = { name = "Main", realm = "R", level = 90, classFile = "WARRIOR" }

local function defineOre(w, extra)
    local def = { name = "Stubborn Ore", classID = 7, subclassID = 7, maxStack = 200, sellPrice = 5, expansionID = 11 }
    for k, v in pairs(extra or {}) do def[k] = v end
    w:defineItem(8801, def)
    w:put(0, 1, 8801, 20)
end

local function bagItem(g, itemID)
    for _, item in ipairs(g:P().GetScanList("bags")) do
        if item.itemID == itemID then return item end
    end
end

T.test("slow item data is picked up when it arrives, after the timed retries", function()
    local g = T.game({ player = PLAYER, setup = function(w)
        F.defineItems(w); defineOre(w, { cached = false, loadDelay = 10 })
    end })
    g:Core().ScanInventory("bags", true)
    T.eq(bagItem(g, 8801).expansionID, nil, "not loaded yet")
    g.world:advance(15)
    local item = bagItem(g, 8801)
    T.eq(item.name, "Stubborn Ore")
    T.eq(item.expansionID, 11, "rescanned when the data arrived")
end)

T.test("a scan keeps details from earlier scans when the client has no data", function()
    local g = T.game({ player = PLAYER, setup = function(w) F.defineItems(w); defineOre(w) end })
    g:Core().ScanInventory("bags", true)
    g:logout()
    local saved = g.env.ICantEvenRightNowDB

    local g2 = T.game({ player = PLAYER, savedVariables = saved, setup = function(w)
        F.defineItems(w); defineOre(w, { cached = false, neverLoads = true })
    end })
    g2:Core().ScanInventory("bags", true)
    local item = bagItem(g2, 8801)
    T.eq(item.name, "Stubborn Ore", "name from the saved scan")
    T.eq(item.expansionID, 11, "expansion from the saved scan")
    T.eq(item.classID, 7)
end)
