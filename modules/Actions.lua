local _, ns = ...
local Core = ns.Core
local Data = ns.Data
local UI = ns.UI

function Core.SetExpansionFilterFromText(text)
    text = (text or ""):lower()
    local function SetMoveExpansionFilter(value)
        SetFilterInclude("Move", "expansion", value)
    end
    if text == "" or text == "all" or text == "old" then
        SetMoveExpansionFilter(EXPANSION_FILTER_ALL)
        return
    elseif text == "unknown" or text == "unknown expansion" then
        SetMoveExpansionFilter(EXPANSION_FILTER_UNKNOWN)
        return
    elseif text == "not current" or text == "notcurrent" then
        SetMoveExpansionFilter(EXPANSION_FILTER_NOT_CURRENT)
        return
    end
    for expansionID, expansion in pairs(Data.Expansions) do
        if expansion.name:lower():find(text, 1, true) then
            SetMoveExpansionFilter(expansionID)
            return
        end
    end
    Print("Unknown expansion filter: " .. text)
end

function Core.SelectRecommended()
    UI.selected = {}
    local startIndex = (UI.page - 1) * UI.pageSize + 1
    local endIndex = math.min(#UI.visible, startIndex + UI.pageSize - 1)
    for index = startIndex, endIndex do
        local item = UI.visible[index]
        local isRecommended = (ns.DB.ui.mode == "Dump to Bank" and item.recommendedAction == Data.Actions.BANK)
            or (ns.DB.ui.mode == "Recall from Bank" and item.recommendedAction == Data.Actions.RECALL)
        if isRecommended and IsMoveEligibleForCurrentMode(item) and not GetMoveBlockReason(item) then
            UI.selected[item.key] = true
        end
    end
    Core.RefreshUI()
end

function Core.SelectVisible()
    UI.selected = {}
    local startIndex = (UI.page - 1) * UI.pageSize + 1
    local endIndex = math.min(#UI.visible, startIndex + UI.pageSize - 1)
    for index = startIndex, endIndex do
        local item = UI.visible[index]
        if IsMoveEligibleForCurrentMode(item) and not GetMoveBlockReason(item) then
            UI.selected[item.key] = true
        end
    end
    Core.RefreshUI()
end

function Core.SelectOrganizerMovable()
    UI.organizeSelected = {}
    local startIndex = (UI.page - 1) * ORGANIZE_PAGE_SIZE + 1
    local endIndex = math.min(#UI.organizeVisible, startIndex + ORGANIZE_PAGE_SIZE - 1)
    for index = startIndex, endIndex do
        local plan = UI.organizeVisible[index]
        if plan.movable then
            UI.organizeSelected[plan.key] = true
        end
    end
    Core.RefreshUI()
end

function Core.SelectVendorReady()
    UI.vendorSelected = {}
    local startIndex = (UI.page - 1) * VENDOR_PAGE_SIZE + 1
    local endIndex = math.min(#UI.vendorVisible, startIndex + VENDOR_PAGE_SIZE - 1)
    for index = startIndex, endIndex do
        local plan = UI.vendorVisible[index]
        if plan.movable then
            UI.vendorSelected[plan.key] = true
        end
    end
    Core.RefreshUI()
end

local function RemoveMovedItemsFromScan(movedKeys)
    for _, scope in ipairs({ BAG_SCOPE, BANK_SCOPE }) do
        local kept = {}
        for _, item in ipairs(ns.DB.scans[scope] or {}) do
            if not movedKeys[LocationKey(item)] then
                table.insert(kept, item)
            end
        end
        ns.DB.scans[scope] = kept
    end
end

function Core.MoveOneItem(item)
    Core.UpdateContext()
    local blockReason = GetMoveBlockReason(item)
    local canMove = IsMoveEligibleForCurrentMode(item) and not blockReason
    local verb = ns.DB.ui.mode == "Recall from Bank" and "recall" or "bank"
    if not canMove then
        Print("Cannot " .. verb .. " " .. (item.name or ("Item " .. item.itemID)) .. ": " .. (blockReason or "not eligible for this mode"))
        return
    end

    local moved, moveError
    if ns.DB.ui.mode == "Recall from Bank" then
        moved, moveError = MoveBankItemToNormalBag(item)
    else
        moved, moveError = MoveItemToBankTarget(item)
    end
    if not moved then
        Print("Cannot " .. verb .. " " .. (item.name or ("Item " .. item.itemID)) .. ": " .. (moveError or "move failed"))
        return
    end
    UI.selected[item.key] = nil
    RemoveMovedItemsFromScan({ [item.key] = true })
    Core.RefreshUI()
    Print("Move run complete: 1 moved, 0 blocked.")
    Core.ScheduleRescanAfterMove()
end

function Core.MoveSelected()
    Core.UpdateContext()
    if ns.DB.context.inCombat then
        Print("Cannot move items in combat.")
        return
    end
    if not ns.DB.context.bankOpen then
        Print("Open the bank before moving items.")
        return
    end

    local moved, blocked = 0, 0
    local movedKeys = {}
    local takenSlots = {}
    local blockedDetails = {}
    for _, item in ipairs(GetAllDecisions() or {}) do
        if UI.selected[item.key] then
            local blockReason = GetMoveBlockReason(item)
            local canMove = IsMoveEligibleForCurrentMode(item) and not blockReason
            local didMove, moveError = false, nil
            if canMove then
                if ns.DB.ui.mode == "Dump to Bank" then
                    didMove, moveError = MoveItemToBankTarget(item, takenSlots)
                else
                    didMove, moveError = MoveBankItemToNormalBag(item, takenSlots)
                end
            end
            if didMove then
                movedKeys[item.key] = true
                moved = moved + 1
            else
                blocked = blocked + 1
                if #blockedDetails < 3 then
                    table.insert(blockedDetails, (item.name or ("Item " .. item.itemID)) .. ": " .. (blockReason or moveError or "not eligible for this mode"))
                end
            end
        end
    end
    UI.selected = {}
    RemoveMovedItemsFromScan(movedKeys)
    Core.RefreshUI()
    Print("Move run complete: " .. moved .. " moved, " .. blocked .. " blocked.")
    if #blockedDetails > 0 then
        Print("Blocked details: " .. table.concat(blockedDetails, "; "))
    end
    Core.ScheduleRescanAfterMove()
end

function Core.MoveOrganizerSelected()
    Core.UpdateContext()
    if ns.DB.context.inCombat then
        Print("Cannot move items in combat.")
        return
    end
    if not ns.DB.context.bankOpen then
        Print("Open the bank before organizing bank storage.")
        return
    end

    local moved, blocked = 0, 0
    local movedKeys = {}
    local takenSlots = {}
    local blockedDetails = {}
    for _, plan in ipairs(GetOrganizationPlans(true)) do
        if UI.organizeSelected[plan.key] then
            local item = plan.item
            local didMove, moveError = false, nil
            if plan.movable then
                didMove, moveError = MoveBankItemToStorageTarget(item, plan.targetStorage, takenSlots)
            else
                moveError = plan.blockedReason or "not movable"
            end
            if didMove then
                movedKeys[item.key] = true
                moved = moved + 1
            else
                blocked = blocked + 1
                if #blockedDetails < 3 then
                    table.insert(blockedDetails, (item.name or ("Item " .. item.itemID)) .. ": " .. (moveError or "move failed"))
                end
            end
        end
    end

    UI.organizeSelected = {}
    RemoveMovedItemsFromScan(movedKeys)
    Core.RefreshUI()
    Print("Organizer run complete: " .. moved .. " moved, " .. blocked .. " blocked.")
    if #blockedDetails > 0 then
        Print("Blocked details: " .. table.concat(blockedDetails, "; "))
    end
    Core.ScheduleRescanAfterMove()
end

function Core.ProcessVendorSelected()
    Core.UpdateContext()
    if ns.DB.context.inCombat then
        Print("Cannot process vendor items in combat.")
        return
    end
    if not ns.DB.context.bankOpen and not ns.DB.context.vendorOpen then
        Print("Open the bank to recall candidates, or a vendor to sell bag candidates.")
        return
    end

    local moved, blocked, sold, recalled = 0, 0, 0, 0
    local movedKeys = {}
    for _, plan in ipairs(GetVendorPlans(true)) do
        if UI.vendorSelected[plan.key] then
            local item = plan.item
            if plan.movable then
                local didMove = false
                if plan.action == VENDOR_ACTION_RECALL then
                    didMove = MoveBankItemToNormalBag(item)
                elseif CContainer.UseContainerItem then
                    CContainer.UseContainerItem(item.bagID, item.slot)
                    didMove = true
                end
                if not didMove then
                    blocked = blocked + 1
                else
                    movedKeys[item.key] = true
                    moved = moved + 1
                    if plan.action == VENDOR_ACTION_SELL then
                        sold = sold + 1
                    else
                        recalled = recalled + 1
                    end
                end
            else
                blocked = blocked + 1
            end
        end
    end

    UI.vendorSelected = {}
    RemoveMovedItemsFromScan(movedKeys)
    Core.RefreshUI()
    Print("Vendor run complete: " .. sold .. " sold, " .. recalled .. " recalled, " .. blocked .. " blocked.")
    if moved > 0 then
        Core.ScheduleRescanAfterMove()
    end
end

