-- Dispatch Functions --

-- Get Recent Dispatch Calls
function GetRecentDispatch()
    local resourceName = tostring(GetCurrentResourceName())
    local ok, result = pcall(function()
        return Bridge.callback(resourceName .. ':server:getRecentDispatches')
    end)
    if ok and result then
        return result
    end
    return {}
end

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    local check = Bridge.callback('ps-mdt:hasProfile')
end)