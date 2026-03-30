if not IsDuplicityVersion() then return end

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

-- Cache for shared data
local sharedCache = {}

if Framework.isQBX then
    ---------------------------------------------------
    -- QBox (qbx_core) implementations
    ---------------------------------------------------

    function Framework.GetPlayer(source)
        return exports.qbx_core:GetPlayer(source)
    end

    function Framework.GetPlayerByCitizenId(citizenid)
        return exports.qbx_core:GetPlayerByCitizenId(citizenid)
    end

    function Framework.GetAllPlayers()
        return exports.qbx_core:GetQBPlayers() or {}
    end

    function Framework.GetOfflinePlayer(citizenid)
        return exports.qbx_core:GetOfflinePlayer(citizenid)
    end

    function Framework.SetMetaData(identifier, key, value)
        exports.qbx_core:SetMetadata(identifier, key, value)
    end

    function Framework.GetMetaData(identifier, key)
        return exports.qbx_core:GetMetadata(identifier, key)
    end

    function Framework.GetItemByName(player, itemName)
        if GetResourceState('ox_inventory') == 'started' then
            local src = player.PlayerData and player.PlayerData.source or player.source
            if src then
                local ok, result = pcall(function()
                    return exports.ox_inventory:GetSlotWithItem(src, itemName)
                end)
                if ok then return result end
            end
        end
        -- Fallback: iterate player items
        if player.PlayerData and player.PlayerData.items then
            for _, item in pairs(player.PlayerData.items) do
                if item.name == itemName then
                    return item
                end
            end
        end
        return nil
    end

    function Framework.GetSharedJobs()
        if not sharedCache.jobs then
            sharedCache.jobs = exports.qbx_core:GetJobs() or {}
        end
        return sharedCache.jobs
    end

    function Framework.GetSharedVehicles()
        if not sharedCache.vehicles then
            sharedCache.vehicles = exports.qbx_core:GetVehiclesByName() or {}
        end
        return sharedCache.vehicles
    end

    function Framework.GetSharedWeapons()
        if not sharedCache.weapons then
            sharedCache.weapons = exports.qbx_core:GetWeapons() or {}
        end
        return sharedCache.weapons
    end

    function Framework.GetSharedItems()
        if not sharedCache.items then
            if GetResourceState('ox_inventory') == 'started' then
                local ok, items = pcall(function()
                    return exports.ox_inventory:Items()
                end)
                if ok and items then
                    sharedCache.items = items
                end
            end
            sharedCache.items = sharedCache.items or {}
        end
        return sharedCache.items
    end

    function Framework.GetVehicleByModel(model)
        local vehicles = Framework.GetSharedVehicles()
        return vehicles[model]
    end

    function Framework.GetWeaponByHash(hash)
        local weapons = Framework.GetSharedWeapons()
        return weapons[hash]
    end

    function Framework.GetGroupMembers(group, groupType)
        return exports.qbx_core:GetGroupMembers(group, groupType) or {}
    end

else
    ---------------------------------------------------
    -- QBCore (qb-core) implementations
    ---------------------------------------------------

    local QBCore = exports['qb-core']:GetCoreObject()

    function Framework.GetPlayer(source)
        return QBCore.Functions.GetPlayer(source)
    end

    function Framework.GetPlayerByCitizenId(citizenid)
        return QBCore.Functions.GetPlayerByCitizenId(citizenid)
    end

    function Framework.GetAllPlayers()
        return QBCore.Functions.GetQBPlayers() or {}
    end

    function Framework.GetOfflinePlayer(citizenid)
        -- QBCore does not have a native GetOfflinePlayer
        if QBCore.Functions.GetOfflinePlayerByCitizenId then
            return QBCore.Functions.GetOfflinePlayerByCitizenId(citizenid)
        end
        return nil
    end

    function Framework.SetMetaData(source, key, value)
        local player = QBCore.Functions.GetPlayer(source)
        if player then
            player.Functions.SetMetaData(key, value)
        end
    end

    function Framework.GetMetaData(source, key)
        local player = QBCore.Functions.GetPlayer(source)
        if player and player.PlayerData and player.PlayerData.metadata then
            return player.PlayerData.metadata[key]
        end
        return nil
    end

    function Framework.GetItemByName(player, itemName)
        if player.Functions and player.Functions.GetItemByName then
            return player.Functions.GetItemByName(itemName)
        end
        return nil
    end

    function Framework.GetSharedJobs()
        return QBCore.Shared.Jobs or {}
    end

    function Framework.GetSharedVehicles()
        return QBCore.Shared.Vehicles or {}
    end

    function Framework.GetSharedWeapons()
        return QBCore.Shared.Weapons or {}
    end

    function Framework.GetSharedItems()
        return QBCore.Shared.Items or {}
    end

    function Framework.GetVehicleByModel(model)
        local vehicles = QBCore.Shared.Vehicles
        return vehicles and vehicles[model] or nil
    end

    function Framework.GetWeaponByHash(hash)
        local weapons = QBCore.Shared.Weapons
        return weapons and weapons[hash] or nil
    end

    function Framework.GetGroupMembers(group, groupType)
        -- QBCore does not have GetGroupMembers natively
        return {}
    end
end
