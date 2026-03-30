if IsDuplicityVersion() then return end

Framework = {}

-- Auto-detect framework
if GetResourceState('qbx_core') == 'started' then
    Framework.name = 'qbx'
    Framework.isQBX = true
elseif GetResourceState('qb-core') == 'started' then
    Framework.name = 'qb'
    Framework.isQBX = false
else
    Framework = nil
    return
end

if Framework.isQBX then
    ---------------------------------------------------
    -- QBox (qbx_core) client implementations
    ---------------------------------------------------

    function Framework.SpawnVehicle(model, callback, coords, warp)
        local hash = type(model) == 'number' and model or GetHashKey(model)
        lib.requestModel(hash)

        local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, coords.w or 0.0, true, false)
        SetModelAsNoLongerNeeded(hash)

        if veh and veh ~= 0 then
            SetVehicleNeedsToBeHotwired(veh, false)
            SetVehRadioStation(veh, 'OFF')
            SetEntityAsMissionEntity(veh, true, true)

            if warp then
                TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
            end

            NetworkFadeInEntity(veh, true)
        end

        if callback then
            callback(veh)
        end
    end

    function Framework.SetVehicleProperties(vehicle, properties)
        if properties then
            lib.setVehicleProperties(vehicle, properties)
        end
    end

    function Framework.GetVehicleProperties(vehicle)
        return lib.getVehicleProperties(vehicle)
    end

    function Framework.GetPlate(vehicle)
        if vehicle and vehicle ~= 0 then
            return GetVehicleNumberPlateText(vehicle):gsub('^%s+', ''):gsub('%s+$', '')
        end
        return ''
    end

    function Framework.TriggerCallback(name, callback, ...)
        local args = { ... }
        CreateThread(function()
            local result = lib.callback(name, false, table.unpack(args))
            if callback then
                callback(result)
            end
        end)
    end

else
    ---------------------------------------------------
    -- QBCore (qb-core) client implementations
    ---------------------------------------------------

    local QBCore = exports['qb-core']:GetCoreObject()

    function Framework.SpawnVehicle(model, callback, coords, warp)
        QBCore.Functions.SpawnVehicle(model, callback, coords, warp)
    end

    function Framework.SetVehicleProperties(vehicle, properties)
        if properties then
            QBCore.Functions.SetVehicleProperties(vehicle, properties)
        end
    end

    function Framework.GetVehicleProperties(vehicle)
        if QBCore.Functions.GetVehicleProperties then
            return QBCore.Functions.GetVehicleProperties(vehicle)
        end
        return nil
    end

    function Framework.GetPlate(vehicle)
        return QBCore.Functions.GetPlate(vehicle)
    end

    function Framework.TriggerCallback(name, callback, ...)
        QBCore.Functions.TriggerCallback(name, callback, ...)
    end
end
